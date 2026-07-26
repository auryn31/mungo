import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri

import mungo/error
import mungo/scram
import mungo/tcp
import mungo/tls as tls_module

import bison.{decode, encode_list}
import bison/bson
import mug

pub type Message {
  Shutdown
  GetTimeout(process.Subject(Int))
  Command(
    List(#(String, bson.Value)),
    process.Subject(Result(dict.Dict(String, bson.Value), error.Error)),
  )
}

pub fn start(uri: String, pool_size: Int, timeout: Int) {
  let pool_size = int.max(pool_size, 1)
  actor.new_with_initialiser(timeout, fn(subj) {
    case connect(uri, pool_size, timeout) {
      Ok(client) ->
        actor.initialised(client)
        |> actor.returning(subj)
        |> Ok
      Error(err) ->
        case err {
          error.ConnectionStringError -> Error("Invalid connection string")
          error.TCPError(_) -> Error("TCP connection error")
          error.ServerError(error.AuthenticationFailed(msg)) -> Error(msg)
          _ -> Error("Unknown error")
        }
    }
  })
  |> actor.on_message(fn(client, msg) {
    case msg {
      Command(cmd, reply_with) -> {
        case execute(client, cmd, timeout) {
          Ok(#(reply, client)) -> {
            actor.send(reply_with, Ok(reply))
            actor.continue(client)
          }
          Error(err) -> {
            actor.send(reply_with, Error(err))
            actor.continue(client)
          }
        }
      }
      GetTimeout(reply_with) -> {
        actor.send(reply_with, timeout)
        actor.continue(client)
      }
      Shutdown -> actor.stop()
    }
  })
  |> actor.start
}

pub type DriverSocket {
  TcpSocket(mug.Socket)
  TlsSocket(tls_module.TlsSocket)
}

pub opaque type Connection {
  Connection(socket: DriverSocket, primary: Bool, host: String, port: Int)
}

pub opaque type Client {
  Client(
    db: String,
    connections: List(Connection),
    next_index: Int,
    pool_size: Int,
    use_tls: Bool,
  )
}

pub type Collection {
  Collection(name: String, client: process.Subject(Message))
}

fn connect(uri: String, pool_size: Int, timeout: Int) -> Result(Client, error.Error) {
  use info <- result.try(parse_connection_string(uri))

  case info {
    #(auth, hosts, db, use_tls) -> {
      use connections <- result.try(
        list.try_map(hosts, fn(host) {
          list.repeat(Nil, pool_size)
          |> list.index_map(fn(_, i) { i })
          |> list.try_map(fn(_) {
            use socket <- result.try(case use_tls {
              True ->
                tls_module.connect(host.0, host.1, timeout)
                |> result.map(fn(s) { TlsSocket(s) })
                |> result.map_error(fn(_) { error.TCPError(mug.Timeout) })
              False ->
                tcp.connect(host.0, host.1, timeout)
                |> result.map(fn(s) { TcpSocket(s) })
                |> result.map_error(fn(err) {
                  error.TCPError(connect_error_to_error(err))
                })
            })

            use is_primary <- result.try(is_primary(socket, db, timeout, use_tls))
            Ok(Connection(socket, is_primary, host.0, host.1))
          })
        })
        |> result.map(list.flatten),
      )

      case auth {
        option.None -> Ok(Client(db, connections, 0, pool_size, use_tls))
        option.Some(#(username, password, auth_source)) -> {
          list.try_each(
            list.map(connections, fn(connection) { connection.socket }),
            authenticate(_, username, password, auth_source, timeout, use_tls),
          )
          |> result.replace(Client(db, connections, 0, pool_size, use_tls))
        }
      }
    }
  }
}

pub fn collection(client: process.Subject(Message), name: String) -> Collection {
  Collection(name, client)
}

pub fn execute_command(
  collection: Collection,
  cmd: List(#(String, bson.Value)),
  timeout: Int,
) -> Result(dict.Dict(String, bson.Value), error.Error) {
  let reply = process.new_subject()
  process.send(collection.client, Command(cmd, reply))
  case process.receive(from: reply, within: timeout) {
    Ok(reply) -> reply
    Error(Nil) -> Error(error.ActorError)
  }
}

fn execute(
  client: Client,
  cmd: List(#(String, bson.Value)),
  timeout: Int,
) -> Result(#(dict.Dict(String, bson.Value), Client), error.Error) {
  case client {
    Client(name, connections, index, pool_size, use_tls) -> {
      let primary_connections =
        list.filter(connections, fn(connection) { connection.primary })

      case list.is_empty(primary_connections) {
        True -> Error(error.ActorError)
        False -> {
          let count = list.length(primary_connections)
          let current_index = case count > 0 {
            True -> index % count
            False -> 0
          }
          let assert Ok(Connection(socket, True, _, _)) =
            list.drop(primary_connections, current_index)
            |> list.first

          let next_index = index + 1
          let client = Client(name, connections, next_index, pool_size, use_tls)

          case send_cmd(socket, name, cmd, timeout) {
            Ok(reply) ->
              case
                dict.get(reply, "ok"),
                dict.get(reply, "errmsg"),
                dict.get(reply, "code")
              {
                Ok(bson.Double(0.0)), Ok(bson.String(msg)), Ok(bson.Int32(code)) -> {
                  let assert Ok(error) =
                    list.key_find(error.code_to_server_error, code)
                  let error = error(msg)

                  case error.is_retriable_error(error) {
                    True ->
                      case error.is_not_primary_error(error) {
                        True -> {
                          use refreshed <- result.try(refresh_connections(
                            client,
                            timeout,
                          ))
                          case find_primary(refreshed) {
                            Ok(#(socket, refreshed)) ->
                              case send_cmd(socket, name, cmd, timeout) {
                                Ok(reply) ->
                                  case
                                    dict.get(reply, "ok"),
                                    dict.get(reply, "errmsg"),
                                    dict.get(reply, "code")
                                  {
                                    Ok(bson.Double(0.0)),
                                    Ok(bson.String(msg)),
                                    Ok(bson.Int32(code))
                                    -> {
                                      let assert Ok(err) =
                                        list.key_find(
                                          error.code_to_server_error,
                                          code,
                                        )
                                      Error(error.ServerError(err(msg)))
                                    }
                                    _, _, _ -> Ok(#(reply, refreshed))
                                  }
                                Error(error) -> Error(error)
                              }
                            Error(_) -> Error(error.ServerError(error))
                          }
                        }

                        False ->
                          case send_cmd(socket, name, cmd, timeout) {
                            Ok(reply) ->
                              case
                                dict.get(reply, "ok"),
                                dict.get(reply, "errmsg"),
                                dict.get(reply, "code")
                              {
                                Ok(bson.Double(0.0)),
                                Ok(bson.String(msg)),
                                Ok(bson.Int32(code))
                                -> {
                                  let assert Ok(err) =
                                    list.key_find(
                                      error.code_to_server_error,
                                      code,
                                    )
                                  Error(error.ServerError(err(msg)))
                                }
                                _, _, _ -> Ok(#(reply, client))
                              }
                            Error(error) -> Error(error)
                          }
                      }
                    False -> Error(error.ServerError(error))
                  }
                }
                _, _, _ -> Ok(#(reply, client))
              }
            Error(error) -> Error(error)
          }
        }
      }
    }
  }
}

fn find_primary(client: Client) -> Result(#(DriverSocket, Client), error.Error) {
  let Client(_, connections, _, _, _) = client
  let primary_connections =
    list.filter(connections, fn(connection) { connection.primary })

  case list.first(primary_connections) {
    Ok(Connection(socket, True, _, _)) -> Ok(#(socket, client))
    _ -> Error(error.ActorError)
  }
}

fn refresh_connections(
  client: Client,
  timeout: Int,
) -> Result(Client, error.Error) {
  let Client(name, connections, index, pool_size, use_tls) = client
  use refreshed <- result.try(
    list.try_map(connections, fn(connection) {
      use is_primary <- result.try(is_primary(
        connection.socket,
        name,
        timeout,
        use_tls,
      ))
      Ok(Connection(connection.socket, is_primary, connection.host, connection.port))
    }),
  )
  Ok(Client(name, refreshed, index, pool_size, use_tls))
}

fn connect_error_to_error(err: mug.ConnectError) -> mug.Error {
  case err {
    mug.ConnectFailedIpv4(e) -> e
    mug.ConnectFailedIpv6(e) -> e
    mug.ConnectFailedBoth(e, _) -> e
  }
}

fn is_primary(socket: DriverSocket, db: String, timeout: Int, _use_tls: Bool) {
  send_cmd(socket, db, [#("hello", bson.Int32(1))], timeout)
  |> result.map(fn(reply) {
    case dict.get(reply, "isWritablePrimary") {
      Ok(bson.Boolean(True)) -> True
      _ -> False
    }
  })
}

fn authenticate(
  socket: DriverSocket,
  username: String,
  password: String,
  auth_source: String,
  timeout: Int,
  _use_tls: Bool,
) {
  let first_payload = scram.first_payload(username)

  let first = scram.first_message(first_payload)

  use reply <- result.try(send_cmd(socket, auth_source, first, timeout))

  use #(server_params, server_payload, cid) <- result.try(
    scram.parse_first_reply(reply),
  )

  use #(second, server_signature) <- result.try(scram.second_message(
    server_params,
    first_payload,
    server_payload,
    cid,
    password,
  ))

  use reply <- result.try(send_cmd(socket, auth_source, second, timeout))

  case dict.get(reply, "ok") {
    Ok(bson.Double(0.0)) ->
      Error(
        error.ServerError(error.AuthenticationFailed("Authentication not ok")),
      )
    _ -> scram.parse_second_reply(reply, server_signature)
  }
}

fn send_cmd(
  socket: DriverSocket,
  db: String,
  cmd: List(#(String, bson.Value)),
  timeout: Int,
) -> Result(dict.Dict(String, bson.Value), error.Error) {
  let encoded =
    cmd
    |> list.key_set("$db", bson.String(db))
    |> encode_list

  let size = bit_array.byte_size(encoded) + 21

  let packet =
    [<<size:32-little, 0:32, 0:32, 2013:32-little, 0:32, 0>>, encoded]
    |> bit_array.concat

  case socket {
    TcpSocket(tcp_socket) ->
      tcp.execute(tcp_socket, packet, timeout)
      |> result.map(fn(reply) {
        let assert <<_:168, rest:bits>> = reply
        decode(rest)
        |> result.replace_error(error.StructureError)
      })
      |> result.map_error(fn(tcp_error) { error.TCPError(tcp_error) })
      |> result.flatten
    TlsSocket(tls_socket) ->
      tls_module.execute(tls_socket, packet, timeout)
      |> result.map(fn(reply) {
        let assert <<_:168, rest:bits>> = reply
        decode(rest)
        |> result.replace_error(error.StructureError)
      })
      |> result.map_error(fn(_) { error.TCPError(mug.Timeout) })
      |> result.flatten
  }
}

fn parse_connection_string(uri: String) {
  use <- bool.guard(
    !string.starts_with(uri, "mongodb://"),
    Error(error.ConnectionStringError),
  )
  let uri = string.drop_start(uri, 10)

  use #(auth, rest) <- result.try(case string.split_once(uri, "@") {
    Ok(#(auth, rest)) ->
      case string.split_once(auth, ":") {
        Ok(#(username, password)) if username != "" && password != "" ->
          case
            [username, password]
            |> list.map(uri.percent_decode)
          {
            [Ok(username), Ok(password)] ->
              Ok(#(option.Some(#(username, password)), rest))
            _ -> Error(error.ConnectionStringError)
          }
        _ -> Error(error.ConnectionStringError)
      }
    Error(Nil) -> Ok(#(option.None, uri))
  })

  use #(hosts, db_and_options) <- result.try(
    string.split_once(rest, "/")
    |> result.replace_error(error.ConnectionStringError),
  )
  use hosts <- result.try(
    hosts
    |> string.split(",")
    |> list.map(fn(host) {
      case string.starts_with(host, ":") {
        True -> Error(error.ConnectionStringError)
        False -> Ok(host)
      }
    })
    |> list.try_map(fn(host) {
      host
      |> result.map(fn(host) {
        case string.split_once(host, ":") {
          Ok(#(host, port)) -> {
            use port <- result.try(
              int.parse(port)
              |> result.replace_error(error.ConnectionStringError),
            )
            Ok(#(host, port))
          }
          Error(Nil) -> Ok(#(host, 27_017))
        }
      })
      |> result.flatten
    }),
  )

  case string.split(db_and_options, "?") {
    [db] if db != "" -> {
      use db <- result.try(
        uri.percent_decode(db)
        |> result.replace_error(error.ConnectionStringError),
      )
      Ok(#(
        auth
          |> option.map(fn(auth) { #(auth.0, auth.1, db) }),
        hosts,
        db,
        False,
      ))
    }

    [db, query_string] if db != "" -> {
      use db <- result.try(
        uri.percent_decode(db)
        |> result.replace_error(error.ConnectionStringError),
      )
      let params =
        query_string
        |> string.split("&")
        |> list.fold(dict.new(), fn(acc, param) {
          case string.split_once(param, "=") {
            Ok(#(key, value)) -> dict.insert(acc, key, value)
            Error(Nil) -> acc
          }
        })
      let use_tls = case dict.get(params, "ssl") {
        Ok("true") -> True
        Ok("1") -> True
        _ -> False
      }
      let auth_source = case dict.get(params, "authSource") {
        Ok(source) -> source
        Error(Nil) -> db
      }
      Ok(#(
        auth
          |> option.map(fn(auth) { #(auth.0, auth.1, auth_source) }),
        hosts,
        db,
        use_tls,
      ))
    }

    _ -> Error(error.ConnectionStringError)
  }
}
