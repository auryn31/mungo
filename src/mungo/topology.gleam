import gleam/dict
import gleam/float
import gleam/list
import gleam/option
import gleam/order

import bison/bson

pub type TopologyType {
  Single
  ReplicaSetNoPrimary
  ReplicaSetWithPrimary
  Sharded
  Unknown
}

pub type ServerRole {
  RsPrimary
  RsSecondary
  RsArbiter
  RsOther
  RsGhost
  Standalone
  Mongos
  Router
}

pub type ServerDescription {
  ServerDescription(
    host: String,
    port: Int,
    server_type: ServerRole,
    replica_set_name: option.Option(String),
    is_healthy: Bool,
    tags: dict.Dict(String, String),
  )
}

pub type Topology {
  Topology(
    topology_type: TopologyType,
    set_name: option.Option(String),
    servers: List(ServerDescription),
    max_election_id: option.Option(bson.Value),
    max_set_version: option.Option(Int),
  )
}

pub type ReadPreference {
  Primary
  PrimaryPreferred
  Secondary
  SecondaryPreferred
  Nearest
}

pub fn empty() -> Topology {
  Topology(
    topology_type: Unknown,
    set_name: option.None,
    servers: [],
    max_election_id: option.None,
    max_set_version: option.None,
  )
}

pub fn parse_hello_reply(
  reply: dict.Dict(String, bson.Value),
  host: String,
  port: Int,
) -> ServerDescription {
  let is_writable_primary = case dict.get(reply, "isWritablePrimary") {
    Ok(bson.Boolean(v)) -> v
    _ -> False
  }
  let is_secondary = case dict.get(reply, "isSecondary") {
    Ok(bson.Boolean(v)) -> v
    _ -> False
  }
  let is_arbiter = case dict.get(reply, "isArbiter") {
    Ok(bson.Boolean(v)) -> v
    _ -> False
  }
  let is_replica_set_member = case dict.get(reply, "isreplicaset") {
    Ok(bson.Boolean(v)) -> v
    _ -> False
  }
  let ok = case dict.get(reply, "ok") {
    Ok(bson.Double(v)) -> float.compare(v, 0.0) == order.Gt
    _ -> False
  }

  let server_type = case
    ok, is_writable_primary, is_secondary, is_arbiter, is_replica_set_member
  {
    False, _, _, _, _ -> Standalone
    True, True, _, _, _ -> RsPrimary
    True, _, True, _, _ -> RsSecondary
    True, _, _, True, _ -> RsArbiter
    True, _, _, _, True -> RsOther
    True, _, _, _, _ -> Standalone
  }

  let replica_set_name = case dict.get(reply, "setName") {
    Ok(bson.String(name)) -> option.Some(name)
    _ -> option.None
  }

  let tags = case dict.get(reply, "tags") {
    Ok(bson.Document(fields)) ->
      dict.map_values(fields, fn(_key, val) {
        case val {
          bson.String(s) -> s
          _ -> ""
        }
      })
    _ -> dict.new()
  }

  ServerDescription(
    host:,
    port:,
    server_type:,
    replica_set_name:,
    is_healthy: ok,
    tags:,
  )
}

pub fn update_topology(
  topology: Topology,
  server: ServerDescription,
) -> Topology {
  let servers =
    list.filter(topology.servers, fn(s) {
      s.host != server.host || s.port != server.port
    })
  let servers = list.append(servers, [server])

  let topology_type = case server.replica_set_name, server.server_type {
    option.Some(name), RsPrimary -> {
      let _ = name
      ReplicaSetWithPrimary
    }
    option.Some(name), RsSecondary -> {
      let _ = name
      ReplicaSetNoPrimary
    }
    option.Some(_), _ -> ReplicaSetNoPrimary
    option.None, Mongos -> Sharded
    option.None, Standalone -> Single
    _, _ -> Unknown
  }

  let set_name = case topology.set_name {
    option.None -> server.replica_set_name
    other -> other
  }

  Topology(
    topology_type:,
    set_name:,
    servers:,
    max_election_id: topology.max_election_id,
    max_set_version: topology.max_set_version,
  )
}

pub fn find_server(
  topology: Topology,
  host: String,
  port: Int,
) -> option.Option(ServerDescription) {
  list.find(topology.servers, fn(s) { s.host == host && s.port == port })
  |> result_to_option
}

fn result_to_option(result: Result(a, Nil)) -> option.Option(a) {
  case result {
    Ok(value) -> option.Some(value)
    Error(Nil) -> option.None
  }
}

pub fn select_server(
  topology: Topology,
  preference: ReadPreference,
) -> option.Option(ServerDescription) {
  let candidates = case preference {
    Primary ->
      list.filter(topology.servers, fn(s) {
        s.is_healthy && s.server_type == RsPrimary
      })
    Secondary ->
      list.filter(topology.servers, fn(s) {
        s.is_healthy && s.server_type == RsSecondary
      })
    PrimaryPreferred -> {
      let primaries =
        list.filter(topology.servers, fn(s) {
          s.is_healthy && s.server_type == RsPrimary
        })
      case primaries {
        [p, ..] -> [p]
        [] ->
          list.filter(topology.servers, fn(s) {
            s.is_healthy && s.server_type == RsSecondary
          })
      }
    }
    SecondaryPreferred -> {
      let secondaries =
        list.filter(topology.servers, fn(s) {
          s.is_healthy && s.server_type == RsSecondary
        })
      case secondaries {
        [s, ..] -> [s]
        [] ->
          list.filter(topology.servers, fn(s) {
            s.is_healthy && s.server_type == RsPrimary
          })
      }
    }
    Nearest ->
      list.filter(topology.servers, fn(s) { s.is_healthy })
  }

  list.first(candidates) |> result_to_option
}
