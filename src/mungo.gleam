import mungo/client
import mungo/crud
import mungo/cursor
import mungo/bulk
import mungo/admin
import mungo/session
import mungo/change_stream
import mungo/topology

pub type Message =
  client.Message

pub type ReadPreference =
  topology.ReadPreference

pub const primary = topology.Primary

pub const primary_preferred = topology.PrimaryPreferred

pub const secondary = topology.Secondary

pub const secondary_preferred = topology.SecondaryPreferred

pub const nearest = topology.Nearest

/// The connection uri must specify the database
pub fn start(uri, pool_size, timeout) {
  client.start(uri, pool_size, timeout)
}

pub fn next(cursor, timeout) {
  cursor.next(cursor, timeout)
}

pub fn to_list(cursor, timeout) {
  cursor.to_list(cursor, timeout)
}

pub fn collection(db, name) {
  db
  |> client.collection(name)
}

pub fn count_all(collection, timeout) {
  collection
  |> crud.count_all(timeout)
}

pub fn count(collection, filter, timeout) {
  collection
  |> crud.count(filter, timeout)
}

pub fn find_by_id(collection, id, timeout) {
  collection
  |> crud.find_by_id(id, timeout)
}

pub fn insert_one(collection, doc, timeout) {
  collection
  |> crud.insert_one(doc, timeout)
}

pub fn insert_many(collection, docs, timeout) {
  collection
  |> crud.insert_many(docs, timeout)
}

pub fn find_all(collection, options, timeout) {
  collection
  |> crud.find_all(options, timeout)
}

pub fn delete_one(collection, filter, timeout) {
  collection
  |> crud.delete_one(filter, timeout)
}

pub fn delete_many(collection, filter, timeout) {
  collection
  |> crud.delete_many(filter, timeout)
}

pub fn find_many(collection, filter, options, timeout) {
  collection
  |> crud.find_many(filter, options, timeout)
}

pub fn find_one(collection, filter, projection, timeout) {
  collection
  |> crud.find_one(filter, projection, timeout)
}

pub fn update_one(collection, filter, change, options, timeout) {
  collection
  |> crud.update_one(filter, change, options, timeout)
}

pub fn update_many(collection, filter, change, options, timeout) {
  collection
  |> crud.update_many(filter, change, options, timeout)
}

pub fn bulk_write(collection, operations, ordered, timeout) {
  collection
  |> bulk.bulk_write(operations, ordered, timeout)
}

pub fn distinct(collection, field, filter, timeout) {
  collection
  |> crud.distinct(field, filter, timeout)
}

pub fn find_and_modify(
  collection,
  filter,
  update,
  replacement,
  sort,
  remove,
  upsert,
  new,
  timeout,
) {
  collection
  |> crud.find_and_modify(
    filter,
    update,
    replacement,
    sort,
    remove,
    upsert,
    new,
    timeout,
  )
}

pub fn drop(collection, timeout) {
  collection
  |> crud.drop(timeout)
}

pub fn create_index(collection, keys, name, unique, timeout) {
  collection
  |> crud.create_index(keys, name, unique, timeout)
}

pub fn drop_index(collection, index_name, timeout) {
  collection
  |> crud.drop_index(index_name, timeout)
}

pub fn list_databases(client, timeout) {
  admin.list_databases(client, timeout)
}

pub fn list_collections(collection, timeout) {
  admin.list_collections(collection, timeout)
}

pub fn drop_database(collection, timeout) {
  admin.drop_database(collection, timeout)
}

pub type Session =
  session.Session

pub fn start_session(client, timeout) {
  session.start(client, timeout)
}

pub fn start_transaction(session) {
  session.start_transaction(session)
}

pub fn commit_transaction(session, timeout) {
  session.commit_transaction(session, timeout)
}

pub fn abort_transaction(session, timeout) {
  session.abort_transaction(session, timeout)
}

pub fn end_session(session, timeout) {
  session.end(session, timeout)
}

pub fn execute_command_with_session(
  collection,
  cmd,
  session_id,
  txn_number,
  timeout,
) {
  client.execute_command_with_session(
    collection,
    cmd,
    session_id,
    txn_number,
    timeout,
  )
}

pub type ChangeStream =
  change_stream.ChangeStream

pub type ChangeEvent =
  change_stream.ChangeEvent

pub type WatchOption =
  change_stream.WatchOption

pub fn watch(collection, pipeline, options, timeout) {
  change_stream.watch(collection, pipeline, options, timeout)
}

pub fn change_stream_next(stream, timeout) {
  change_stream.next(stream, timeout)
}

pub fn change_stream_to_list(stream, timeout) {
  change_stream.to_list(stream, timeout)
}

pub fn set_read_preference(client, preference) {
  client.set_read_preference(client, preference)
}
