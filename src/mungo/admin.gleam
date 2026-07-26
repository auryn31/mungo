import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/result

import mungo/client
import mungo/error

import bison/bson

pub type DatabaseInfo {
  DatabaseInfo(
    name: String,
    size_on_disk: Int,
    empty: Bool,
    namespaces: Int,
  )
}

pub fn list_databases(
  client_subj: process.Subject(client.Message),
  timeout: Int,
) -> Result(List(DatabaseInfo), error.Error) {
  let collection = client.Collection("admin", "admin", client_subj)
  let cmd = [#("listDatabases", bson.Int32(1))]

  client.execute_command(collection, cmd, timeout)
  |> result.map(fn(reply) {
    case dict.get(reply, "databases") {
      Ok(bson.Array(dbs)) ->
        Ok(
          list.filter_map(dbs, fn(db) {
            case db {
              bson.Document(fields) -> {
                let name = case dict.get(fields, "name") {
                  Ok(bson.String(n)) -> n
                  _ -> ""
                }
                let size_on_disk = case dict.get(fields, "sizeOnDisk") {
                  Ok(bson.Int64(s)) -> s
                  Ok(bson.Int32(s)) -> s
                  _ -> 0
                }
                let empty = case dict.get(fields, "empty") {
                  Ok(bson.Boolean(e)) -> e
                  _ -> False
                }
                Ok(DatabaseInfo(name, size_on_disk, empty, 0))
              }
              _ -> Error(Nil)
            }
          }),
        )
      _ -> Error(error.StructureError)
    }
  })
  |> result.flatten
}

pub fn list_collections(
  collection: client.Collection,
  timeout: Int,
) -> Result(List(String), error.Error) {
  let cmd = [#("listCollections", bson.Int32(1))]

  client.execute_command(collection, cmd, timeout)
  |> result.map(fn(reply) {
    case dict.get(reply, "cursor") {
      Ok(bson.Document(cursor_doc)) ->
        case dict.get(cursor_doc, "firstBatch") {
          Ok(bson.Array(collections)) ->
            Ok(
              list.filter_map(collections, fn(col) {
                case col {
                  bson.Document(fields) ->
                    case dict.get(fields, "name") {
                      Ok(bson.String(n)) -> Ok(n)
                      _ -> Error(Nil)
                    }
                  _ -> Error(Nil)
                }
              }),
            )
          _ -> Error(error.StructureError)
        }
      _ -> Error(error.StructureError)
    }
  })
  |> result.flatten
}

pub fn drop_database(
  collection: client.Collection,
  timeout: Int,
) -> Result(Nil, error.Error) {
  let cmd = [#("dropDatabase", bson.Int32(1))]

  client.execute_command(collection, cmd, timeout)
  |> result.replace(Nil)
}
