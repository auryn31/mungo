import bison/bson
import gleam/dict
import gleam/list
import gleam/option
import gleeunit
import gleeunit/should
import mungo/error
import mungo/topology

pub fn main() {
  gleeunit.main()
}

// ---- Error module tests ----

pub fn is_retriable_error_returns_true_for_host_unreachable_test() {
  error.is_retriable_error(error.HostUnreachable("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_host_not_found_test() {
  error.is_retriable_error(error.HostNotFound("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_network_timeout_test() {
  error.is_retriable_error(error.NetworkTimeout("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_shutdown_in_progress_test() {
  error.is_retriable_error(error.ShutdownInProgress("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_primary_stepped_down_test() {
  error.is_retriable_error(error.PrimarySteppedDown("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_exceeded_time_limit_test() {
  error.is_retriable_error(error.ExceededTimeLimit("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_connection_pool_expired_test() {
  error.is_retriable_error(error.ConnectionPoolExpired("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_socket_exception_test() {
  error.is_retriable_error(error.SocketException("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_not_writable_primary_test() {
  error.is_retriable_error(error.NotWritablePrimary("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_interrupted_at_shutdown_test() {
  error.is_retriable_error(error.InterruptedAtShutdown("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_interrupted_due_to_repl_state_change_test() {
  error.is_retriable_error(error.InterruptedDueToReplStateChange("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_not_primary_no_secondary_ok_test() {
  error.is_retriable_error(error.NotPrimaryNoSecondaryOk("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_true_for_not_primary_or_secondary_test() {
  error.is_retriable_error(error.NotPrimaryOrSecondary("test"))
  |> should.be_true
}

pub fn is_retriable_error_returns_false_for_ok_test() {
  error.is_retriable_error(error.OK("test"))
  |> should.be_false
}

pub fn is_retriable_error_returns_false_for_internal_error_test() {
  error.is_retriable_error(error.InternalError("test"))
  |> should.be_false
}

pub fn is_retriable_error_returns_false_for_authentication_failed_test() {
  error.is_retriable_error(error.AuthenticationFailed("test"))
  |> should.be_false
}

pub fn is_retriable_error_returns_false_for_duplicate_key_test() {
  error.is_retriable_error(error.DuplicateKey("test"))
  |> should.be_false
}

pub fn is_retriable_error_returns_false_for_bad_value_test() {
  error.is_retriable_error(error.BadValue("test"))
  |> should.be_false
}

pub fn is_retriable_error_returns_false_for_namespace_not_found_test() {
  error.is_retriable_error(error.NamespaceNotFound("test"))
  |> should.be_false
}

pub fn is_retriable_error_returns_false_for_command_not_supported_test() {
  error.is_retriable_error(error.CommandNotSupported("test"))
  |> should.be_false
}

// ---- is_not_primary_error tests ----

pub fn is_not_primary_error_returns_true_for_primary_stepped_down_test() {
  error.is_not_primary_error(error.PrimarySteppedDown("test"))
  |> should.be_true
}

pub fn is_not_primary_error_returns_true_for_not_writable_primary_test() {
  error.is_not_primary_error(error.NotWritablePrimary("test"))
  |> should.be_true
}

pub fn is_not_primary_error_returns_true_for_interrupted_due_to_repl_state_change_test() {
  error.is_not_primary_error(error.InterruptedDueToReplStateChange("test"))
  |> should.be_true
}

pub fn is_not_primary_error_returns_true_for_not_primary_no_secondary_ok_test() {
  error.is_not_primary_error(error.NotPrimaryNoSecondaryOk("test"))
  |> should.be_true
}

pub fn is_not_primary_error_returns_true_for_not_primary_or_secondary_test() {
  error.is_not_primary_error(error.NotPrimaryOrSecondary("test"))
  |> should.be_true
}

pub fn is_not_primary_error_returns_false_for_ok_test() {
  error.is_not_primary_error(error.OK("test"))
  |> should.be_false
}

pub fn is_not_primary_error_returns_false_for_network_timeout_test() {
  error.is_not_primary_error(error.NetworkTimeout("test"))
  |> should.be_false
}

pub fn is_not_primary_error_returns_false_for_shutdown_in_progress_test() {
  error.is_not_primary_error(error.ShutdownInProgress("test"))
  |> should.be_false
}

pub fn is_not_primary_error_returns_false_for_socket_exception_test() {
  error.is_not_primary_error(error.SocketException("test"))
  |> should.be_false
}

pub fn is_not_primary_error_returns_false_for_host_unreachable_test() {
  error.is_not_primary_error(error.HostUnreachable("test"))
  |> should.be_false
}

pub fn is_not_primary_error_returns_false_for_duplicate_key_test() {
  error.is_not_primary_error(error.DuplicateKey("test"))
  |> should.be_false
}

pub fn is_not_primary_error_returns_false_for_authentication_failed_test() {
  error.is_not_primary_error(error.AuthenticationFailed("test"))
  |> should.be_false
}

// ---- code_to_server_error mapping tests ----

pub fn code_to_server_error_maps_code_0_to_ok_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 0)
  constructor("msg")
  |> should.equal(error.OK("msg"))
}

pub fn code_to_server_error_maps_code_1_to_internal_error_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 1)
  constructor("msg")
  |> should.equal(error.InternalError("msg"))
}

pub fn code_to_server_error_maps_code_18_to_authentication_failed_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 18)
  constructor("msg")
  |> should.equal(error.AuthenticationFailed("msg"))
}

pub fn code_to_server_error_maps_code_11000_to_duplicate_key_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 11_000)
  constructor("msg")
  |> should.equal(error.DuplicateKey("msg"))
}

pub fn code_to_server_error_maps_code_26_to_namespace_not_found_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 26)
  constructor("msg")
  |> should.equal(error.NamespaceNotFound("msg"))
}

pub fn code_to_server_error_maps_code_59_to_command_not_found_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 59)
  constructor("msg")
  |> should.equal(error.CommandNotFound("msg"))
}

pub fn code_to_server_error_maps_code_11600_to_interrupted_at_shutdown_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 11_600)
  constructor("msg")
  |> should.equal(error.InterruptedAtShutdown("msg"))
}

pub fn code_to_server_error_maps_code_9001_to_socket_exception_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 9001)
  constructor("msg")
  |> should.equal(error.SocketException("msg"))
}

pub fn code_to_server_error_maps_code_10107_to_not_writable_primary_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 10_107)
  constructor("msg")
  |> should.equal(error.NotWritablePrimary("msg"))
}

pub fn code_to_server_error_maps_code_13435_to_not_primary_no_secondary_ok_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 13_435)
  constructor("msg")
  |> should.equal(error.NotPrimaryNoSecondaryOk("msg"))
}

pub fn code_to_server_error_maps_code_13436_to_not_primary_or_secondary_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 13_436)
  constructor("msg")
  |> should.equal(error.NotPrimaryOrSecondary("msg"))
}

pub fn code_to_server_error_maps_code_189_to_primary_stepped_down_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 189)
  constructor("msg")
  |> should.equal(error.PrimarySteppedDown("msg"))
}

pub fn code_to_server_error_maps_code_89_to_network_timeout_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 89)
  constructor("msg")
  |> should.equal(error.NetworkTimeout("msg"))
}

pub fn code_to_server_error_maps_code_91_to_shutdown_in_progress_test() {
  let assert Ok(constructor) = list.key_find(error.code_to_server_error, 91)
  constructor("msg")
  |> should.equal(error.ShutdownInProgress("msg"))
}

pub fn code_to_server_error_returns_error_for_unknown_code_test() {
  list.key_find(error.code_to_server_error, 99_999)
  |> should.be_error
}

// ---- Error type tests ----

pub fn error_type_has_correct_variants_test() {
  // Verify error types can be constructed and match their expected variant
  error.StructureError
  |> should.equal(error.StructureError)
  error.AuthenticationError
  |> should.equal(error.AuthenticationError)
  error.ActorError
  |> should.equal(error.ActorError)
  error.ConnectionStringError
  |> should.equal(error.ConnectionStringError)
}

pub fn write_error_type_test() {
  let error.WriteError(code, msg, _) =
    error.WriteError(11_000, "duplicate key", bson.String("test"))
  should.equal(code, 11_000)
  should.equal(msg, "duplicate key")
}

pub fn server_error_type_test() {
  let err = error.ServerError(error.DuplicateKey("dup key"))
  case err {
    error.ServerError(error.DuplicateKey(msg)) -> should.equal(msg, "dup key")
    _ -> panic as "expected ServerError(DuplicateKey)"
  }
}

// ---- Comprehensive retriable/non-retriable classification tests ----

pub fn all_retriable_errors_are_retriable_test() {
  let retriable_errors = [
    error.HostUnreachable(""),
    error.HostNotFound(""),
    error.NetworkTimeout(""),
    error.ShutdownInProgress(""),
    error.PrimarySteppedDown(""),
    error.ExceededTimeLimit(""),
    error.ConnectionPoolExpired(""),
    error.SocketException(""),
    error.NotWritablePrimary(""),
    error.InterruptedAtShutdown(""),
    error.InterruptedDueToReplStateChange(""),
    error.NotPrimaryNoSecondaryOk(""),
    error.NotPrimaryOrSecondary(""),
  ]

  retriable_errors
  |> list.each(fn(err) {
    error.is_retriable_error(err)
    |> should.be_true
  })
}

pub fn all_not_primary_errors_are_retriable_test() {
  let not_primary_errors = [
    error.PrimarySteppedDown(""),
    error.NotWritablePrimary(""),
    error.InterruptedDueToReplStateChange(""),
    error.NotPrimaryNoSecondaryOk(""),
    error.NotPrimaryOrSecondary(""),
  ]

  not_primary_errors
  |> list.each(fn(err) {
    error.is_retriable_error(err)
    |> should.be_true
    error.is_not_primary_error(err)
    |> should.be_true
  })
}

// ---- Topology tests ----

pub fn topology_empty_test() {
  let t = topology.empty()
  should.equal(t.topology_type, topology.Unknown)
  should.equal(t.servers, [])
}

pub fn parse_hello_reply_primary_test() {
  let reply = dict.from_list([
    #("ok", bson.Double(1.0)),
    #("isWritablePrimary", bson.Boolean(True)),
    #("setName", bson.String("rs0")),
  ])
  let desc = topology.parse_hello_reply(reply, "host1", 27017)
  should.equal(desc.server_type, topology.RsPrimary)
  should.equal(desc.is_healthy, True)
  should.equal(desc.host, "host1")
  should.equal(desc.port, 27017)
  should.equal(desc.replica_set_name, option.Some("rs0"))
}

pub fn parse_hello_reply_secondary_test() {
  let reply = dict.from_list([
    #("ok", bson.Double(1.0)),
    #("isWritablePrimary", bson.Boolean(False)),
    #("isSecondary", bson.Boolean(True)),
    #("setName", bson.String("rs0")),
  ])
  let desc = topology.parse_hello_reply(reply, "host2", 27018)
  should.equal(desc.server_type, topology.RsSecondary)
  should.equal(desc.is_healthy, True)
}

pub fn parse_hello_reply_standalone_test() {
  let reply = dict.from_list([
    #("ok", bson.Double(1.0)),
    #("isWritablePrimary", bson.Boolean(True)),
  ])
  let desc = topology.parse_hello_reply(reply, "localhost", 27017)
  should.equal(desc.server_type, topology.RsPrimary)
}

pub fn parse_hello_reply_unhealthy_test() {
  let reply = dict.from_list([
    #("ok", bson.Double(0.0)),
    #("isWritablePrimary", bson.Boolean(False)),
  ])
  let desc = topology.parse_hello_reply(reply, "host1", 27017)
  should.equal(desc.is_healthy, False)
}

pub fn update_topology_adds_server_test() {
  let t = topology.empty()
  let desc = topology.ServerDescription(
    host: "host1",
    port: 27017,
    server_type: topology.RsPrimary,
    replica_set_name: option.Some("rs0"),
    is_healthy: True,
    tags: dict.new(),
  )
  let t = topology.update_topology(t, desc)
  should.equal(list.length(t.servers), 1)
  should.equal(t.topology_type, topology.ReplicaSetWithPrimary)
  should.equal(t.set_name, option.Some("rs0"))
}

pub fn update_topology_replaces_server_test() {
  let t = topology.empty()
  let desc1 = topology.ServerDescription(
    host: "host1",
    port: 27017,
    server_type: topology.RsPrimary,
    replica_set_name: option.Some("rs0"),
    is_healthy: True,
    tags: dict.new(),
  )
  let t = topology.update_topology(t, desc1)
  let desc2 = topology.ServerDescription(
    host: "host1",
    port: 27017,
    server_type: topology.RsSecondary,
    replica_set_name: option.Some("rs0"),
    is_healthy: True,
    tags: dict.new(),
  )
  let t = topology.update_topology(t, desc2)
  should.equal(list.length(t.servers), 1)
}

pub fn select_server_primary_test() {
  let t = topology.empty()
  let primary = topology.ServerDescription(
    host: "host1",
    port: 27017,
    server_type: topology.RsPrimary,
    replica_set_name: option.Some("rs0"),
    is_healthy: True,
    tags: dict.new(),
  )
  let secondary = topology.ServerDescription(
    host: "host2",
    port: 27018,
    server_type: topology.RsSecondary,
    replica_set_name: option.Some("rs0"),
    is_healthy: True,
    tags: dict.new(),
  )
  let t = topology.update_topology(t, primary)
  let t = topology.update_topology(t, secondary)

  let selected = topology.select_server(t, topology.Primary)
  case selected {
    option.Some(s) -> should.equal(s.host, "host1")
    option.None -> panic as "Expected a server"
  }
}

pub fn select_server_secondary_test() {
  let t = topology.empty()
  let primary = topology.ServerDescription(
    host: "host1",
    port: 27017,
    server_type: topology.RsPrimary,
    replica_set_name: option.Some("rs0"),
    is_healthy: True,
    tags: dict.new(),
  )
  let secondary = topology.ServerDescription(
    host: "host2",
    port: 27018,
    server_type: topology.RsSecondary,
    replica_set_name: option.Some("rs0"),
    is_healthy: True,
    tags: dict.new(),
  )
  let t = topology.update_topology(t, primary)
  let t = topology.update_topology(t, secondary)

  let selected = topology.select_server(t, topology.Secondary)
  case selected {
    option.Some(s) -> should.equal(s.host, "host2")
    option.None -> panic as "Expected a server"
  }
}

pub fn select_server_primary_preferred_fallback_test() {
  let t = topology.empty()
  let secondary = topology.ServerDescription(
    host: "host2",
    port: 27018,
    server_type: topology.RsSecondary,
    replica_set_name: option.Some("rs0"),
    is_healthy: True,
    tags: dict.new(),
  )
  let t = topology.update_topology(t, secondary)

  let selected = topology.select_server(t, topology.PrimaryPreferred)
  case selected {
    option.Some(s) -> should.equal(s.host, "host2")
    option.None -> panic as "Expected a server"
  }
}

pub fn parse_hello_reply_with_tags_test() {
  let tags = dict.from_list([#("dc", "us-east"), #("rack", "1")])
  let tags_bson = dict.map_values(tags, fn(_k, v) { bson.String(v) })
  let reply = dict.from_list([
    #("ok", bson.Double(1.0)),
    #("isWritablePrimary", bson.Boolean(True)),
    #("setName", bson.String("rs0")),
    #("tags", bson.Document(tags_bson)),
  ])
  let desc = topology.parse_hello_reply(reply, "host1", 27017)
  should.equal(dict.get(desc.tags, "dc"), Ok("us-east"))
  should.equal(dict.get(desc.tags, "rack"), Ok("1"))
}
