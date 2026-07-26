import gleam/dict
import gleam/list
import gleam/result

import mungo/client
import mungo/error

import bison/bson

pub type BulkOperation {
  InsertOne(List(#(String, bson.Value)))
  UpdateOne(
    filter: List(#(String, bson.Value)),
    update: List(#(String, bson.Value)),
    upsert: Bool,
  )
  UpdateMany(
    filter: List(#(String, bson.Value)),
    update: List(#(String, bson.Value)),
    upsert: Bool,
  )
  DeleteOne(filter: List(#(String, bson.Value)))
  DeleteMany(filter: List(#(String, bson.Value)))
  ReplaceOne(
    filter: List(#(String, bson.Value)),
    replacement: List(#(String, bson.Value)),
    upsert: Bool,
  )
}

pub type BulkWriteResult {
  BulkWriteResult(
    inserted: Int,
    matched: Int,
    modified: Int,
    deleted: Int,
    upserted: List(bson.Value),
  )
}

pub fn bulk_write(
  collection: client.Collection,
  operations: List(BulkOperation),
  ordered: Bool,
  timeout: Int,
) -> Result(BulkWriteResult, error.Error) {
  let ops =
    list.map(operations, fn(op) {
      case op {
        InsertOne(doc) ->
          bson.Document(dict.from_list([
            #("insertOne", bson.Document(dict.from_list([
              #("document", bson.Document(dict.from_list(doc))),
            ]))),
          ]))
        UpdateOne(filter:, update:, upsert:) ->
          bson.Document(dict.from_list([
            #(
              "updateOne",
              bson.Document(dict.from_list([
                #("filter", bson.Document(dict.from_list(filter))),
                #("update", bson.Document(dict.from_list(update))),
                #("upsert", bson.Boolean(upsert)),
              ])),
            ),
          ]))
        UpdateMany(filter:, update:, upsert:) ->
          bson.Document(dict.from_list([
            #(
              "updateMany",
              bson.Document(dict.from_list([
                #("filter", bson.Document(dict.from_list(filter))),
                #("update", bson.Document(dict.from_list(update))),
                #("upsert", bson.Boolean(upsert)),
              ])),
            ),
          ]))
        DeleteOne(filter:) ->
          bson.Document(dict.from_list([
            #(
              "deleteOne",
              bson.Document(dict.from_list([
                #("filter", bson.Document(dict.from_list(filter))),
              ])),
            ),
          ]))
        DeleteMany(filter:) ->
          bson.Document(dict.from_list([
            #(
              "deleteMany",
              bson.Document(dict.from_list([
                #("filter", bson.Document(dict.from_list(filter))),
              ])),
            ),
          ]))
        ReplaceOne(filter:, replacement:, upsert:) ->
          bson.Document(dict.from_list([
            #(
              "replaceOne",
              bson.Document(dict.from_list([
                #("filter", bson.Document(dict.from_list(filter))),
                #("replacement", bson.Document(dict.from_list(replacement))),
                #("upsert", bson.Boolean(upsert)),
              ])),
            ),
          ]))
      }
    })

  let cmd = [
    #("bulkWrite", bson.String(collection.name)),
    #("ops", bson.Array(ops)),
    #("ordered", bson.Boolean(ordered)),
  ]

  client.execute_command(collection, cmd, timeout)
  |> result.map(fn(reply) {
    let inserted = case dict.get(reply, "nInserted") {
      Ok(bson.Int32(n)) -> n
      _ -> 0
    }
    let matched = case dict.get(reply, "nMatched") {
      Ok(bson.Int32(n)) -> n
      _ -> 0
    }
    let modified = case dict.get(reply, "nModified") {
      Ok(bson.Int32(n)) -> n
      _ -> 0
    }
    let deleted = case dict.get(reply, "nDeleted") {
      Ok(bson.Int32(n)) -> n
      _ -> 0
    }
    let upserted = case dict.get(reply, "upserted") {
      Ok(bson.Array(ids)) -> ids
      _ -> []
    }

    case dict.get(reply, "writeErrors") {
      Ok(bson.Array(errors)) ->
        Error(error.WriteErrors(
          errors
          |> list.map(fn(err) {
            let assert bson.Document(fields) = err
            let assert Ok(bson.Int32(code)) = dict.get(fields, "code")
            let assert Ok(bson.String(msg)) = dict.get(fields, "errmsg")
            let source = case dict.get(fields, "op") {
              Ok(v) -> v
              Error(Nil) -> bson.Int32(0)
            }
            error.WriteError(code, msg, source)
          }),
        ))
      _ ->
        Ok(BulkWriteResult(
          inserted:,
          matched:,
          modified:,
          deleted:,
          upserted:,
        ))
    }
  })
  |> result.flatten
}
