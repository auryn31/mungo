import gleam/dict
import gleam/erlang/process
import gleam/result

import mungo/client
import mungo/error

import bison/bson
import bison/uuid as bison_uuid

pub opaque type Session {
  Session(
    client: process.Subject(client.Message),
    session_id: BitArray,
    txn_number: Int,
    active: Bool,
  )
}

fn execute_command(
  collection: client.Collection,
  cmd: List(#(String, bson.Value)),
  timeout: Int,
) -> Result(dict.Dict(String, bson.Value), error.Error) {
  let reply = process.new_subject()
  process.send(
    collection.client,
    client.Command(cmd, reply),
  )
  case process.receive(from: reply, within: timeout) {
    Ok(reply) -> reply
    Error(Nil) -> Error(error.ActorError)
  }
}

pub fn start(
  client_subj: process.Subject(client.Message),
  timeout: Int,
) -> Result(Session, error.Error) {
  let cmd = [#("startSession", bson.Int32(1))]
  let collection = client.Collection("admin", "admin", client_subj)

  use reply <- result.try(execute_command(collection, cmd, timeout))

  use id <- result.try(
    case dict.get(reply, "id") {
      Ok(bson.Document(id_doc)) ->
        case dict.get(id_doc, "id") {
          Ok(bson.Binary(bson.UUID(uid))) -> Ok(bison_uuid.to_bit_array(uid))
          _ -> Error(error.StructureError)
        }
      _ -> Error(error.StructureError)
    },
  )

  Ok(Session(client: client_subj, session_id: id, txn_number: 0, active: False))
}

pub fn start_transaction(session: Session) -> Session {
  Session(
    client: session.client,
    session_id: session.session_id,
    txn_number: session.txn_number + 1,
    active: True,
  )
}

fn lsid_dict(session_id: BitArray) {
  case bison_uuid.from_bit_array(session_id) {
    Ok(uid) ->
      bson.Document(dict.from_list([
        #("id", bson.Binary(bson.UUID(uid))),
      ]))
    Error(Nil) -> bson.Document(dict.new())
  }
}

pub fn commit_transaction(
  session: Session,
  timeout: Int,
) -> Result(Nil, error.Error) {
  let collection = client.Collection("admin", "admin", session.client)
  let cmd = [
    #("commitTransaction", bson.Int32(1)),
    #("lsid", lsid_dict(session.session_id)),
    #("txnNumber", bson.Int64(session.txn_number)),
    #("autocommit", bson.Boolean(False)),
    #("readConcern", bson.Document(dict.from_list([#("level", bson.String("snapshot"))]))),
  ]

  client.execute_command(collection, cmd, timeout)
  |> result.replace(Nil)
}

pub fn abort_transaction(
  session: Session,
  timeout: Int,
) -> Result(Nil, error.Error) {
  let collection = client.Collection("admin", "admin", session.client)
  let cmd = [
    #("abortTransaction", bson.Int32(1)),
    #("lsid", lsid_dict(session.session_id)),
    #("txnNumber", bson.Int64(session.txn_number)),
  ]

  client.execute_command(collection, cmd, timeout)
  |> result.replace(Nil)
}

pub fn end(session: Session, timeout: Int) -> Result(Nil, error.Error) {
  let collection = client.Collection("admin", "admin", session.client)

  case bison_uuid.from_bit_array(session.session_id) {
    Error(Nil) -> Error(error.StructureError)
    Ok(uid) -> {
      let cmd = [
        #("endSessions", bson.Int32(1)),
        #("id", bson.Binary(bson.UUID(uid))),
      ]

      client.execute_command(collection, cmd, timeout)
      |> result.replace(Nil)
    }
  }
}

pub fn execute_with_session(
  collection: client.Collection,
  cmd: List(#(String, bson.Value)),
  session: Session,
  timeout: Int,
) -> Result(dict.Dict(String, bson.Value), error.Error) {
  client.execute_command_with_session(
    collection,
    cmd,
    session.session_id,
    session.txn_number,
    timeout,
  )
}

pub fn session_id(session: Session) -> BitArray {
  session.session_id
}

pub fn txn_number(session: Session) -> Int {
  session.txn_number
}

pub fn is_active(session: Session) -> Bool {
  session.active
}
