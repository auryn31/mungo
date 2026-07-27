import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/result
import gleam/yielder

import mungo/client
import mungo/error

import bison/bson

pub opaque type ChangeStream {
  ChangeStream(
    collection: client.Collection,
    id: Int,
    batch_size: Int,
    yielder: yielder.Yielder(bson.Value),
    resume_token: option.Option(bson.Value),
  )
}

pub type ChangeEvent {
  ChangeEvent(
    operation_type: String,
    document_key: option.Option(bson.Value),
    full_document: option.Option(bson.Value),
    ns: option.Option(String),
    update_description: option.Option(bson.Value),
    cluster_time: option.Option(bson.Value),
  )
}

pub fn new(
  collection: client.Collection,
  id: Int,
  batch: List(bson.Value),
) -> ChangeStream {
  let resume_token = extract_resume_token(batch)
  ChangeStream(
    collection: collection,
    id: id,
    batch_size: list.length(batch),
    yielder: yielder.from_list(batch),
    resume_token: resume_token,
  )
}

pub fn watch(
  collection: client.Collection,
  pipeline: List(#(String, bson.Value)),
  options: List(WatchOption),
  timeout: Int,
) -> Result(ChangeStream, error.Error) {
  let body =
    list.fold(
      options,
      [
        #("watch", bson.String(collection.name)),
        #(
          "pipeline",
          bson.Array(
            list.map(pipeline, fn(p) { bson.Document(dict.from_list([p])) }),
          ),
        ),
      ],
      fn(acc, opt) {
        case opt {
          ResumeAfter(token) -> list.key_set(acc, "resumeAfter", token)
          StartAfter(token) -> list.key_set(acc, "startAfter", token)
          FullDocument(mode) ->
            list.key_set(acc, "fullDocument", bson.String(mode))
          BatchSize(size) -> list.key_set(acc, "batchSize", bson.Int32(size))
          MaxAwaitTimeMS(ms) ->
            list.key_set(acc, "maxAwaitTimeMS", bson.Int64(ms))
        }
      },
    )

  client.execute_command(collection, body, timeout)
  |> result.map(fn(reply) {
    case dict.get(reply, "cursor") {
      Ok(bson.Document(cursor_doc)) ->
        case dict.get(cursor_doc, "id"), dict.get(cursor_doc, "firstBatch") {
          Ok(bson.Int64(id)), Ok(bson.Array(batch)) ->
            new(collection, id, batch) |> Ok
          _, _ -> Error(error.StructureError)
        }
      _ -> Error(error.StructureError)
    }
  })
  |> result.flatten
}

pub fn next(stream: ChangeStream, timeout: Int) {
  case yielder.step(stream.yielder) {
    yielder.Next(doc, rest) -> {
      let token = extract_resume_token_from_doc(doc)
      #(
        option.Some(doc),
        ChangeStream(
          stream.collection,
          stream.id,
          stream.batch_size,
          rest,
          option.or(token, stream.resume_token),
        ),
      )
    }
    yielder.Done ->
      case stream.id {
        0 -> #(
          option.None,
          ChangeStream(
            stream.collection,
            0,
            stream.batch_size,
            yielder.empty(),
            stream.resume_token,
          ),
        )
        _ -> {
          case get_more(stream, timeout) {
            Ok(new_stream) ->
              case yielder.step(new_stream.yielder) {
                yielder.Next(doc, rest) -> {
                  let token = extract_resume_token_from_doc(doc)
                  #(
                    option.Some(doc),
                    ChangeStream(
                      stream.collection,
                      new_stream.id,
                      new_stream.batch_size,
                      rest,
                      option.or(token, stream.resume_token),
                    ),
                  )
                }
                yielder.Done -> #(
                  option.None,
                  ChangeStream(
                    stream.collection,
                    new_stream.id,
                    new_stream.batch_size,
                    yielder.empty(),
                    stream.resume_token,
                  ),
                )
              }
            Error(_) -> #(
              option.None,
              ChangeStream(
                stream.collection,
                stream.id,
                stream.batch_size,
                yielder.empty(),
                stream.resume_token,
              ),
            )
          }
        }
      }
  }
}

pub fn to_list(stream: ChangeStream, timeout: Int) {
  to_list_internal(stream, [], timeout)
}

fn to_list_internal(stream, storage, timeout) {
  case next(stream, timeout) {
    #(option.Some(next), new_stream) ->
      to_list_internal(new_stream, list.append(storage, [next]), timeout)
    #(option.None, _) -> storage
  }
}

fn get_more(
  stream: ChangeStream,
  timeout: Int,
) -> Result(ChangeStream, error.Error) {
  let cmd = [
    #("getMore", bson.Int64(stream.id)),
    #("collection", bson.String(stream.collection.name)),
    #("batchSize", bson.Int32(stream.batch_size)),
  ]

  process.call(
    stream.collection.client,
    waiting: timeout,
    sending: client.Command(cmd, _),
  )
  |> result.map(fn(reply) {
    case dict.get(reply, "cursor") {
      Ok(bson.Document(cursor_doc)) ->
        case dict.get(cursor_doc, "id"), dict.get(cursor_doc, "nextBatch") {
          Ok(bson.Int64(id)), Ok(bson.Array(batch)) -> {
            let token = extract_resume_token(batch)
            Ok(ChangeStream(
              stream.collection,
              id,
              list.length(batch),
              yielder.from_list(batch),
              option.or(token, stream.resume_token),
            ))
          }
          _, _ -> Error(error.StructureError)
        }
      _ -> Error(error.StructureError)
    }
  })
  |> result.flatten
}

fn extract_resume_token(batch: List(bson.Value)) -> option.Option(bson.Value) {
  case batch {
    [bson.Document(doc), ..] ->
      case dict.get(doc, "_id") {
        Ok(token) -> option.Some(token)
        Error(Nil) -> option.None
      }
    _ -> option.None
  }
}

fn extract_resume_token_from_doc(doc: bson.Value) -> option.Option(bson.Value) {
  case doc {
    bson.Document(doc) ->
      case dict.get(doc, "_id") {
        Ok(token) -> option.Some(token)
        Error(Nil) -> option.None
      }
    _ -> option.None
  }
}

pub type WatchOption {
  ResumeAfter(bson.Value)
  StartAfter(bson.Value)
  FullDocument(String)
  BatchSize(Int)
  MaxAwaitTimeMS(Int)
}
