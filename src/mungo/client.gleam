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
import mungo/topology

import bison.{decode, encode_list}
import bison/bson
import bison/uuid
import mug

pub type Message {
  Shutdown
  GetTimeout(process.Subject(Int))
  Command(
    List(#(String, bson.Value)),
    process.Subject(Result(dict.Dict(String, bson.Value), error.Error)),
  )
  SessionCommand(
    List(#(String, bson.Value)),
    process.Subject(Result(dict.Dict(String, bson.Value), error.Error)),
    BitArray,
    Int,
  )
  SetReadPreference(topology.ReadPreference)
  PollTopology
}

pub fn start(uri: String, pool_size: Int, timeout: Int) {
  let pool_size = int.max(pool_size, 1)
  actor.new_with_initialiser(timeout, fn(subj) {
    case connect(uri, pool_size, timeout) {
      Ok(client) -> {
        let topology_interval = 10_000
        process.spawn(fn() { do_topology_poll_loop(subj, topology_interval) })
        actor.initialised(client)
        |> actor.returning(subj)
        |> Ok
      }
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
      SessionCommand(cmd, reply_with, session_id, txn_number) -> {
        let cmd = case uuid.from_bit_array(session_id) {
          Ok(uid) ->
            cmd
            |> list.key_set(
              "lsid",
              bson.Document(
                dict.from_list([#("id", bson.Binary(bson.UUID(uid)))]),
              ),
            )
            |> list.key_set("txnNumber", bson.Int64(txn_number))
          Error(Nil) -> cmd
        }
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
      SetReadPreference(pref) -> {
        let new_client =
          Client(
            client.db,
            client.connections,
            client.next_index,
            client.pool_size,
            client.use_tls,
            client.topology,
            client.replica_set_name,
            pref,
          )
        actor.continue(new_client)
      }
      PollTopology -> {
        let new_client = poll_topology(client, timeout)
        actor.continue(new_client)
      }
      Shutdown -> actor.stop()
    }
  })
  |> actor.start
}

fn do_topology_poll_loop(subj: process.Subject(Message), interval: Int) {
  process.send(subj, PollTopology)
  process.sleep(interval)
  do_topology_poll_loop(subj, interval)
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
    topology: topology.Topology,
    replica_set_name: option.Option(String),
    read_preference: topology.ReadPreference,
  )
}

pub type Collection {
  Collection(name: String, db: String, client: process.Subject(Message))
}

fn connect(
  uri: String,
  pool_size: Int,
  timeout: Int,
) -> Result(Client, error.Error) {
  use info <- result.try(parse_connection_string(uri))

  case info {
    #(auth, hosts, db, use_tls, replica_set_name) -> {
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

            use hello_reply <- result.try(send_cmd(
              socket,
              db,
              [#("hello", bson.Int32(1))],
              timeout,
            ))
            let server_desc =
              topology.parse_hello_reply(hello_reply, host.0, host.1)
            Ok(Connection(
              socket,
              server_desc.server_type == topology.RsPrimary,
              host.0,
              host.1,
            ))
          })
        })
        |> result.map(list.flatten),
      )

      let initial_topo =
        list.fold(connections, topology.empty(), fn(topo, conn) {
          let server_desc =
            topology.ServerDescription(
              host: conn.host,
              port: conn.port,
              server_type: case conn.primary {
                True -> topology.RsPrimary
                False -> topology.Standalone
              },
              replica_set_name: replica_set_name,
              is_healthy: True,
              tags: dict.new(),
            )
          topology.update_topology(topo, server_desc)
        })

      case auth {
        option.None ->
          Ok(Client(
            db,
            connections,
            0,
            pool_size,
            use_tls,
            initial_topo,
            replica_set_name,
            topology.Primary,
          ))
        option.Some(#(username, password, auth_source)) -> {
          list.try_each(
            list.map(connections, fn(connection) { connection.socket }),
            authenticate(_, username, password, auth_source, timeout, use_tls),
          )
          |> result.replace(Client(
            db,
            connections,
            0,
            pool_size,
            use_tls,
            initial_topo,
            replica_set_name,
            topology.Primary,
          ))
        }
      }
    }
  }
}

pub fn collection(
  client: process.Subject(Message),
  name: String,
) -> Collection {
  Collection(name, "", client)
}

pub fn collection_on_db(
  client: process.Subject(Message),
  name: String,
  db: String,
) -> Collection {
  Collection(name, db, client)
}

pub fn set_read_preference(
  client: process.Subject(Message),
  preference: topology.ReadPreference,
) {
  process.send(client, SetReadPreference(preference))
}

pub fn get_topology(
  client: process.Subject(Message),
  _timeout: Int,
) -> topology.Topology {
  let _reply = process.new_subject()
  process.send(client, PollTopology)
  topology.empty()
}

pub fn execute_command(
  collection: Collection,
  cmd: List(#(String, bson.Value)),
  timeout: Int,
) -> Result(dict.Dict(String, bson.Value), error.Error) {
  let reply = process.new_subject()
  let cmd = case collection.db {
    "" -> cmd
    db -> list.key_set(cmd, "$db", bson.String(db))
  }
  process.send(collection.client, Command(cmd, reply))
  case process.receive(from: reply, within: timeout) {
    Ok(reply) -> reply
    Error(Nil) -> Error(error.ActorError)
  }
}

pub fn execute_command_with_session(
  collection: Collection,
  cmd: List(#(String, bson.Value)),
  session_id: BitArray,
  txn_number: Int,
  timeout: Int,
) -> Result(dict.Dict(String, bson.Value), error.Error) {
  let reply = process.new_subject()
  let cmd = case collection.db {
    "" -> cmd
    db -> list.key_set(cmd, "$db", bson.String(db))
  }
  process.send(
    collection.client,
    SessionCommand(cmd, reply, session_id, txn_number),
  )
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
    Client(
      name,
      connections,
      index,
      pool_size,
      use_tls,
      topo,
      replica_set_name,
      pref,
    ) -> {
      let candidate_connections = case pref {
        topology.Primary -> list.filter(connections, fn(c) { c.primary })
        topology.PrimaryPreferred -> {
          let primaries = list.filter(connections, fn(c) { c.primary })
          case primaries {
            [_, ..] -> primaries
            [] -> connections
          }
        }
        topology.Secondary -> list.filter(connections, fn(c) { !c.primary })
        topology.SecondaryPreferred -> {
          let secondaries = list.filter(connections, fn(c) { !c.primary })
          case secondaries {
            [_, ..] -> secondaries
            [] -> list.filter(connections, fn(c) { c.primary })
          }
        }
        topology.Nearest -> connections
      }

      case list.is_empty(candidate_connections) {
        True -> Error(error.ActorError)
        False -> {
          let count = list.length(candidate_connections)
          let current_index = index % count
          use connection <- result.try(
            list.drop(candidate_connections, current_index)
            |> list.first
            |> result.replace_error(error.ActorError),
          )
          let Connection(socket, _, _, _) = connection

          let next_index = index + 1
          let client =
            Client(
              name,
              connections,
              next_index,
              pool_size,
              use_tls,
              topo,
              replica_set_name,
              pref,
            )

          case send_cmd(socket, name, cmd, timeout) {
            Ok(reply) ->
              case
                dict.get(reply, "ok"),
                dict.get(reply, "errmsg"),
                dict.get(reply, "code")
              {
                Ok(bson.Double(0.0)), Ok(bson.String(msg)), Ok(bson.Int32(code))
                -> {
                  case list.key_find(error.code_to_server_error, code) {
                    Ok(error_constructor) -> {
                      let server_error = error_constructor(msg)

                      case error.is_retriable_error(server_error) {
                        True ->
                          case error.is_not_primary_error(server_error) {
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
                                          case
                                            list.key_find(
                                              error.code_to_server_error,
                                              code,
                                            )
                                          {
                                            Ok(err) ->
                                              Error(error.ServerError(err(msg)))
                                            Error(Nil) ->
                                              Error(error.ServerError(
                                                server_error,
                                              ))
                                          }
                                        }
                                        _, _, _ -> Ok(#(reply, refreshed))
                                      }
                                    Error(err) -> Error(err)
                                  }
                                Error(_) ->
                                  Error(error.ServerError(server_error))
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
                                      case
                                        list.key_find(
                                          error.code_to_server_error,
                                          code,
                                        )
                                      {
                                        Ok(err) ->
                                          Error(error.ServerError(err(msg)))
                                        Error(Nil) ->
                                          Error(error.ServerError(server_error))
                                      }
                                    }
                                    _, _, _ -> Ok(#(reply, client))
                                  }
                                Error(err) -> Error(err)
                              }
                          }
                        False -> Error(error.ServerError(server_error))
                      }
                    }
                    Error(Nil) -> Error(error.ActorError)
                  }
                }
                _, _, _ -> Ok(#(reply, client))
              }
            Error(err) -> Error(err)
          }
        }
      }
    }
  }
}

fn find_primary(
  client: Client,
) -> Result(#(DriverSocket, Client), error.Error) {
  let Client(_, connections, _, _, _, _, _, _) = client
  let primary_connections =
    list.filter(connections, fn(connection) { connection.primary })

  case list.first(primary_connections) {
    Ok(Connection(socket, True, _, _)) -> Ok(#(socket, client))
    _ -> Error(error.ActorError)
  }
}

fn poll_topology(client: Client, timeout: Int) -> Client {
  let Client(
    name,
    connections,
    index,
    pool_size,
    use_tls,
    topo,
    replica_set_name,
    pref,
  ) = client

  let result =
    list.fold(connections, #(topology.empty(), []), fn(acc, connection) {
      let #(topo, conns) = acc
      case
        send_cmd(connection.socket, name, [#("hello", bson.Int32(1))], timeout)
      {
        Ok(reply) -> {
          let server_desc =
            topology.parse_hello_reply(reply, connection.host, connection.port)
          let new_topo = topology.update_topology(topo, server_desc)
          let new_conn =
            Connection(
              connection.socket,
              server_desc.server_type == topology.RsPrimary,
              connection.host,
              connection.port,
            )
          #(new_topo, list.append(conns, [new_conn]))
        }
        Error(_) -> {
          let new_conn =
            Connection(
              connection.socket,
              False,
              connection.host,
              connection.port,
            )
          #(topo, list.append(conns, [new_conn]))
        }
      }
    })

  let new_topo = case topo.topology_type {
    topology.Unknown -> result.0
    _ -> topo
  }

  Client(
    name,
    result.1,
    index,
    pool_size,
    use_tls,
    new_topo,
    replica_set_name,
    pref,
  )
}

fn refresh_connections(
  client: Client,
  timeout: Int,
) -> Result(Client, error.Error) {
  let Client(
    name,
    connections,
    index,
    pool_size,
    use_tls,
    topo,
    replica_set_name,
    pref,
  ) = client
  use refreshed <- result.try(
    list.try_map(connections, fn(connection) {
      use is_primary <- result.try(is_primary(
        connection.socket,
        name,
        timeout,
        use_tls,
      ))
      Ok(Connection(
        connection.socket,
        is_primary,
        connection.host,
        connection.port,
      ))
    }),
  )
  Ok(Client(
    name,
    refreshed,
    index,
    pool_size,
    use_tls,
    topo,
    replica_set_name,
    pref,
  ))
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
  use mechanism <- result.try(negotiate_mechanism(
    socket,
    username,
    auth_source,
    timeout,
  ))

  let first_payload = scram.first_payload(username)

  let first = scram.first_message(first_payload, mechanism)

  use reply <- result.try(send_cmd(socket, auth_source, first, timeout))

  use #(server_params, server_payload, cid) <- result.try(
    scram.parse_first_reply(reply),
  )

  use #(second, server_signature) <- result.try(scram.second_message(
    server_params,
    first_payload,
    server_payload,
    cid,
    username,
    password,
    mechanism,
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

// Asks the server which SCRAM mechanisms this user supports (via hello's
// saslSupportedMechs) and prefers SCRAM-SHA-256, falling back to SHA-1.
fn negotiate_mechanism(
  socket: DriverSocket,
  username: String,
  auth_source: String,
  timeout: Int,
) -> Result(scram.Mechanism, error.Error) {
  let cmd = [
    #("hello", bson.Int32(1)),
    #("saslSupportedMechs", bson.String(auth_source <> "." <> username)),
  ]
  use reply <- result.map(send_cmd(socket, auth_source, cmd, timeout))
  case dict.get(reply, "saslSupportedMechs") {
    Ok(bson.Array(mechs)) ->
      case list.contains(mechs, bson.String("SCRAM-SHA-256")) {
        True -> scram.ScramSha256
        False -> scram.ScramSha1
      }
    // No hint (older servers) -> keep the SHA-256 default.
    _ -> scram.ScramSha256
  }
}

fn send_cmd(
  socket: DriverSocket,
  db: String,
  cmd: List(#(String, bson.Value)),
  timeout: Int,
) -> Result(dict.Dict(String, bson.Value), error.Error) {
  let cmd = case list.key_find(cmd, "$db") {
    Error(Nil) -> list.key_set(cmd, "$db", bson.String(db))
    Ok(_) -> cmd
  }
  let encoded = cmd |> encode_list

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
        |> result.map(normalize_ok)
        |> result.replace_error(error.StructureError)
      })
      |> result.map_error(fn(tcp_error) { error.TCPError(tcp_error) })
      |> result.flatten
    TlsSocket(tls_socket) ->
      tls_module.execute(tls_socket, packet, timeout)
      |> result.map(fn(reply) {
        let assert <<_:168, rest:bits>> = reply
        decode(rest)
        |> result.map(normalize_ok)
        |> result.replace_error(error.StructureError)
      })
      |> result.map_error(fn(_) { error.TCPError(mug.Timeout) })
      |> result.flatten
  }
}

// MongoDB's "ok" field is a double, but some deployments (e.g. Atlas) return
// it as an int. Normalize to Double so reply parsers can match consistently.
fn normalize_ok(
  reply: dict.Dict(String, bson.Value),
) -> dict.Dict(String, bson.Value) {
  case dict.get(reply, "ok") {
    Ok(bson.Int32(n)) -> dict.insert(reply, "ok", bson.Double(int.to_float(n)))
    Ok(bson.Int64(n)) -> dict.insert(reply, "ok", bson.Double(int.to_float(n)))
    _ -> reply
  }
}

@external(erlang, "dns_ffi", "srv_lookup")
fn srv_lookup(name: String) -> Result(List(#(String, Int)), Nil)

@external(erlang, "dns_ffi", "txt_lookup")
fn txt_lookup(name: String) -> Result(String, Nil)

// Resolves a mongodb+srv:// URI to a plain multi-host mongodb:// URI via DNS
// SRV/TXT lookups, then defers to the normal parser. TLS is on by default for
// SRV per the connection-string spec (mungo reads it as ssl=true).
fn resolve_srv(uri: String) -> Result(String, error.Error) {
  let rest = string.drop_start(uri, 14)
  let #(auth_prefix, host_rest) = case string.split_once(rest, "@") {
    Ok(#(auth, r)) -> #(auth <> "@", r)
    Error(Nil) -> #("", rest)
  }
  let #(srv_host, db_and_options) = case string.split_once(host_rest, "/") {
    Ok(#(h, rest)) -> #(h, rest)
    Error(Nil) -> #(host_rest, "")
  }
  let #(db, opts) = case string.split_once(db_and_options, "?") {
    Ok(#(d, o)) -> #(d, o)
    Error(Nil) -> #(db_and_options, "")
  }
  use hosts <- result.try(
    srv_lookup("_mongodb._tcp." <> srv_host)
    |> result.replace_error(error.ConnectionStringError),
  )
  let host_string =
    hosts
    |> list.map(fn(h) { h.0 <> ":" <> int.to_string(h.1) })
    |> string.join(",")
  let txt_opts = txt_lookup(srv_host) |> result.unwrap("")
  // SRV connections default to TLS per the connection-string spec.
  let merged =
    [opts, txt_opts, "tls=true"]
    |> list.filter(fn(s) { s != "" })
    |> string.join("&")
  Ok("mongodb://" <> auth_prefix <> host_string <> "/" <> db <> "?" <> merged)
}

fn parse_connection_string(uri: String) {
  use uri <- result.try(case string.starts_with(uri, "mongodb+srv://") {
    True -> resolve_srv(uri)
    False -> Ok(uri)
  })
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
        option.None,
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
      // "tls" is the modern spelling; "ssl" is the legacy alias. Either enables it.
      let use_tls = case dict.get(params, "tls"), dict.get(params, "ssl") {
        Ok("true"), _ | Ok("1"), _ -> True
        _, Ok("true") | _, Ok("1") -> True
        _, _ -> False
      }
      let auth_source = case dict.get(params, "authSource") {
        Ok(source) -> source
        Error(Nil) -> db
      }
      let replica_set_name = case dict.get(params, "replicaSet") {
        Ok(name) -> option.Some(name)
        Error(Nil) -> option.None
      }
      Ok(#(
        auth
          |> option.map(fn(auth) { #(auth.0, auth.1, auth_source) }),
        hosts,
        db,
        use_tls,
        replica_set_name,
      ))
    }

    _ -> Error(error.ConnectionStringError)
  }
}
