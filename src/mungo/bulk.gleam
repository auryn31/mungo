import gleam/dict
import gleam/list
import gleam/result

import mungo/client
import mungo/error

import bison/bson
import bison/object_id

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

fn empty_result() -> BulkWriteResult {
  BulkWriteResult(inserted: 0, matched: 0, modified: 0, deleted: 0, upserted: [])
}

fn merge_results(a: BulkWriteResult, b: BulkWriteResult) -> BulkWriteResult {
  BulkWriteResult(
    inserted: a.inserted + b.inserted,
    matched: a.matched + b.matched,
    modified: a.modified + b.modified,
    deleted: a.deleted + b.deleted,
    upserted: list.append(a.upserted, b.upserted),
  )
}

pub fn bulk_write(
  collection: client.Collection,
  operations: List(BulkOperation),
  _ordered: Bool,
  timeout: Int,
) -> Result(BulkWriteResult, error.Error) {
  let batches = group_by_type(operations)
  execute_batches(collection, batches, timeout, empty_result())
}

type Batch {
  InsertBatch(docs: List(bson.Value))
  UpdateBatch(specs: List(bson.Value))
  DeleteBatch(specs: List(bson.Value))
}

fn group_by_type(operations: List(BulkOperation)) -> List(Batch) {
  do_group_by_type(operations, [], [])
}

fn do_group_by_type(
  remaining: List(BulkOperation),
  current: List(BulkOperation),
  batches: List(Batch),
) -> List(Batch) {
  case remaining {
    [] -> {
      case flush_batch(current) {
        option.None -> batches
        option.Some(batch) -> list.append(batches, [batch])
      }
    }
    [op, ..rest] -> {
      let same_type = case current, op {
        [], InsertOne(_) -> True
        [InsertOne(_), ..], InsertOne(_) -> True
        [], UpdateOne(..) -> True
        [UpdateOne(..), ..], UpdateOne(..) -> True
        [], UpdateMany(..) -> True
        [UpdateMany(..), ..], UpdateMany(..) -> True
        [], ReplaceOne(..) -> True
        [ReplaceOne(..), ..], ReplaceOne(..) -> True
        [], DeleteOne(..) -> True
        [DeleteOne(..), ..], DeleteOne(_) -> True
        [], DeleteMany(..) -> True
        [DeleteMany(..), ..], DeleteMany(_) -> True
        _, _ -> False
      }
      case same_type {
        True -> do_group_by_type(rest, [op, ..current], batches)
        False -> {
          let batches = case flush_batch(current) {
            option.None -> batches
            option.Some(batch) -> list.append(batches, [batch])
          }
          do_group_by_type(rest, [op], batches)
        }
      }
    }
  }
}

import gleam/option

fn flush_batch(batch: List(BulkOperation)) -> option.Option(Batch) {
  case batch {
    [] -> option.None
    [InsertOne(_), ..] -> option.Some(InsertBatch(docs: collect_inserts(batch)))
    [UpdateOne(..), ..] | [UpdateMany(..), ..] | [ReplaceOne(..), ..] ->
      option.Some(UpdateBatch(specs: collect_updates(batch)))
    [DeleteOne(..), ..] | [DeleteMany(..), ..] ->
      option.Some(DeleteBatch(specs: collect_deletes(batch)))
  }
}

fn collect_inserts(ops: List(BulkOperation)) -> List(bson.Value) {
  list.reverse(ops)
  |> list.map(fn(op) {
    case op {
      InsertOne(doc) -> {
        let has_id =
          list.any(doc, fn(kv) { kv.0 == "_id" })
        case has_id {
          True -> bson.Document(dict.from_list(doc))
          False -> {
            let id = object_id.new()
            bson.Document(dict.from_list([#("_id", bson.ObjectId(id)), ..doc]))
          }
        }
      }
      _ -> bson.Document(dict.new())
    }
  })
}

fn collect_updates(ops: List(BulkOperation)) -> List(bson.Value) {
  list.reverse(ops)
  |> list.map(fn(op) {
    case op {
      UpdateOne(filter:, update:, upsert:) ->
        bson.Document(dict.from_list([
          #("q", bson.Document(dict.from_list(filter))),
          #("u", bson.Document(dict.from_list(update))),
          #("multi", bson.Boolean(False)),
          #("upsert", bson.Boolean(upsert)),
        ]))
      UpdateMany(filter:, update:, upsert:) ->
        bson.Document(dict.from_list([
          #("q", bson.Document(dict.from_list(filter))),
          #("u", bson.Document(dict.from_list(update))),
          #("multi", bson.Boolean(True)),
          #("upsert", bson.Boolean(upsert)),
        ]))
      ReplaceOne(filter:, replacement:, upsert:) ->
        bson.Document(dict.from_list([
          #("q", bson.Document(dict.from_list(filter))),
          #("u", bson.Document(dict.from_list(replacement))),
          #("multi", bson.Boolean(False)),
          #("upsert", bson.Boolean(upsert)),
        ]))
      _ -> bson.Document(dict.new())
    }
  })
}

fn collect_deletes(ops: List(BulkOperation)) -> List(bson.Value) {
  list.reverse(ops)
  |> list.map(fn(op) {
    case op {
      DeleteOne(filter:) ->
        bson.Document(dict.from_list([
          #("q", bson.Document(dict.from_list(filter))),
          #("limit", bson.Int32(1)),
        ]))
      DeleteMany(filter:) ->
        bson.Document(dict.from_list([
          #("q", bson.Document(dict.from_list(filter))),
          #("limit", bson.Int32(0)),
        ]))
      _ -> bson.Document(dict.new())
    }
  })
}

fn execute_batches(
  collection: client.Collection,
  batches: List(Batch),
  timeout: Int,
  acc: BulkWriteResult,
) -> Result(BulkWriteResult, error.Error) {
  case batches {
    [] -> Ok(acc)
    [batch, ..rest] -> {
      let result = execute_batch(collection, batch, timeout)
      case result {
        Ok(batch_result) -> {
          let merged = merge_results(acc, batch_result)
          execute_batches(collection, rest, timeout, merged)
        }
        Error(err) -> Error(err)
      }
    }
  }
}

fn execute_batch(
  collection: client.Collection,
  batch: Batch,
  timeout: Int,
) -> Result(BulkWriteResult, error.Error) {
  case batch {
    InsertBatch(docs:) -> execute_insert_batch(collection, docs, timeout)
    UpdateBatch(specs:) -> execute_update_batch(collection, specs, timeout)
    DeleteBatch(specs:) -> execute_delete_batch(collection, specs, timeout)
  }
}

fn execute_insert_batch(
  collection: client.Collection,
  docs: List(bson.Value),
  timeout: Int,
) -> Result(BulkWriteResult, error.Error) {
  let cmd = [
    #("insert", bson.String(collection.name)),
    #("documents", bson.Array(docs)),
  ]

  client.execute_command(collection, cmd, timeout)
  |> result.map(fn(reply) {
    case dict.get(reply, "writeErrors") {
      Ok(bson.Array(errors)) ->
        Error(error.WriteErrors(
          errors
          |> list.map(fn(err) {
            let assert bson.Document(fields) = err
            let assert Ok(bson.Int32(code)) = dict.get(fields, "code")
            let assert Ok(bson.String(msg)) = dict.get(fields, "errmsg")
            let source = case dict.get(fields, "keyValue") {
              Ok(v) -> v
              Error(Nil) -> bson.Int32(0)
            }
            error.WriteError(code, msg, source)
          }),
        ))
      _ -> {
        let inserted = case dict.get(reply, "n") {
          Ok(bson.Int32(n)) -> n
          _ -> 0
        }
        Ok(BulkWriteResult(
          inserted:,
          matched: 0,
          modified: 0,
          deleted: 0,
          upserted: [],
        ))
      }
    }
  })
  |> result.flatten
}

fn execute_update_batch(
  collection: client.Collection,
  specs: List(bson.Value),
  timeout: Int,
) -> Result(BulkWriteResult, error.Error) {
  let cmd = [
    #("update", bson.String(collection.name)),
    #("updates", bson.Array(specs)),
  ]

  client.execute_command(collection, cmd, timeout)
  |> result.map(fn(reply) {
    case dict.get(reply, "writeErrors") {
      Ok(bson.Array(errors)) ->
        Error(error.WriteErrors(
          errors
          |> list.map(fn(err) {
            let assert bson.Document(fields) = err
            let assert Ok(bson.Int32(code)) = dict.get(fields, "code")
            let assert Ok(bson.String(msg)) = dict.get(fields, "errmsg")
            let source = case dict.get(fields, "keyValue") {
              Ok(v) -> v
              Error(Nil) -> bson.Int32(0)
            }
            error.WriteError(code, msg, source)
          }),
        ))
      _ -> {
        let matched = case dict.get(reply, "n") {
          Ok(bson.Int32(n)) -> n
          _ -> 0
        }
        let modified = case dict.get(reply, "nModified") {
          Ok(bson.Int32(n)) -> n
          _ -> 0
        }
        let upserted = case dict.get(reply, "upserted") {
          Ok(bson.Array(ids)) -> ids
          _ -> []
        }
        Ok(BulkWriteResult(
          inserted: 0,
          matched:,
          modified:,
          deleted: 0,
          upserted:,
        ))
      }
    }
  })
  |> result.flatten
}

fn execute_delete_batch(
  collection: client.Collection,
  specs: List(bson.Value),
  timeout: Int,
) -> Result(BulkWriteResult, error.Error) {
  let cmd = [
    #("delete", bson.String(collection.name)),
    #("deletes", bson.Array(specs)),
  ]

  client.execute_command(collection, cmd, timeout)
  |> result.map(fn(reply) {
    case dict.get(reply, "writeErrors") {
      Ok(bson.Array(errors)) ->
        Error(error.WriteErrors(
          errors
          |> list.map(fn(err) {
            let assert bson.Document(fields) = err
            let assert Ok(bson.Int32(code)) = dict.get(fields, "code")
            let assert Ok(bson.String(msg)) = dict.get(fields, "errmsg")
            let source = case dict.get(fields, "keyValue") {
              Ok(v) -> v
              Error(Nil) -> bson.Int32(0)
            }
            error.WriteError(code, msg, source)
          }),
        ))
      _ -> {
        let deleted = case dict.get(reply, "n") {
          Ok(bson.Int32(n)) -> n
          _ -> 0
        }
        Ok(BulkWriteResult(
          inserted: 0,
          matched: 0,
          modified: 0,
          deleted:,
          upserted: [],
        ))
      }
    }
  })
  |> result.flatten
}
