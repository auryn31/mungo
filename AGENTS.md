# Mungo Project Memory

## Project Overview
- **What**: MongoDB driver for Gleam (formerly gleam_mongo)
- **Path**: `/Users/aurynengel/coding/mungo`
- **Target**: Erlang OTP
- **Bison fork**: `/Users/aurynengel/coding/bison` (user's fork at `github.com/auryn31/bison`)

## Architecture
```
src/
  mungo.gleam              # Public API facade - delegates to client, crud, bulk, admin
  mungo/client.gleam       # Actor-based client: Connection pooling, auth, TLS/TCP dispatch
  mungo/tcp.gleam          # Plain TCP via mug
  mungo/tls.gleam          # TLS via Erlang ssl FFI
  mungo/crud.gleam         # CRUD ops: find, insert, update, delete, distinct, findAndModify, index ops
  mungo/cursor.gleam       # Server-side cursors with getMore
  mungo/aggregation.gleam  # Pipeline aggregation (match, group, lookup, project, etc.)
  mungo/bulk.gleam         # Bulk write operations (insertOne, updateOne, deleteOne, etc.)
  mungo/admin.gleam        # DB admin: listDatabases, listCollections, dropDatabase
  mungo/error.gleam        # Error types + MongoDB error code mapping
  mungo/scram.gleam        # SCRAM-SHA-256 authentication
  mungo_tls_ffi.erl        # Erlang FFI for SSL/TLS connections
```

## Dependency Versions (current)
- `gleam_stdlib` 1.0.3, `gleam_erlang` 1.3.0, `gleam_otp` 1.2.0, `gleam_crypto` 1.6.0
- `mug` 3.1.0, `gleam_json` 3.1.0, `bison` 1.7.0 (git)
- `testcontainer` 1.0.2, `testcontainer_formulas` 1.0.0 (dev)
- `birl` 1.9.0 (transitive via bison)

## Key API Pattern
```gleam
// start takes: uri, pool_size, timeout
// All CRUD/aggregate functions take: collection, args..., timeout
// Client is an OTP actor (Subject), Collection holds (name, client_subject)
let assert Ok(started) = client.start(db.connection_url, pool_size, timeout)
let users = mungo.collection(started, "users")
```

## Important Learnings

### Erlang FFI File Placement
- **Rule**: FFI `.erl` files MUST be at `src/` root level, NOT in subdirectories
- `src/mungo/tls_ffi.erl` → WRONG (Erlang compiler can't handle `@` in module names)
- `src/mungo_tls_ffi.erl` → CORRECT
- FFI files in `src/<package>/` get compiled as module `<package>@<filename>` which Erlang rejects
- Do NOT include `-module()` declaration in FFI files when using Gleam's compilation
- Reference with `@external(erlang, "mungo_tls_ffi", "function_name")`

### gleam_stdlib 1.x Breaking Changes
- `result.then` → `result.try`
- `dynamic.from`, `dynamic.element`, `dynamic.field`, `dynamic.any` removed (use `decode` API)
- `dynamic.DecodeError` → `decode.DecodeError`
- `list.range` does NOT exist → use `list.repeat(Nil, n) |> list.index_map(fn(_, i) { i })`
- `option.Some(...)` is correct (not `option(Some(...))`)
- `result.unwrap(or:)` is the label (not `with:`)

### gleam_json 3.x Breaking Changes
- `decode`, `decode_bits`, `to_string_builder` removed

### gleam_otp 1.x Actor API
- `start_spec`/`Spec`/`Ready`/`Failed` removed
- Replaced with `new_with_initialiser`/`on_message`/`start` builder pattern
- `Failed` → `InitFailed`
- Init returns `Result(Initialised(...), String)`
- `on_message` handler signature: `fn(state, message)` NOT `fn(message, state)`
- `process.try_call` removed → use `process.call` or `send`+`receive` pattern

### gleam_erlang 1.x Changes
- `process.select(timeout)` → `process.selector_receive(within:)`
- `mug.select_tcp_messages` still works as before

### mug 3.x Breaking Changes
- `ConnectionOptions` now takes 4 args (added `ip_version_preference`)
- `selecting_tcp_messages` → `select_tcp_messages`
- `mug.connect` returns `Result(Socket, ConnectError)` not `Result(Socket, Error)`
- `mug.ConnectError` variants: `ConnectFailedIpv4`, `ConnectFailedIpv6`, `ConnectFailedBoth`
- Need `connect_error_to_error` helper to convert `ConnectError` to `Error`

### MongoDB Wire Protocol
- OpMsg format: `<<size:32-little, 0:32, 0:32, 2013:32-little, 0:32, 0>>, encoded`
- Response: skip 168 bits (21 bytes header), then decode BSON
- Commands use `#("command", bson.Value)` pairs, `encode_list` from bison
- `$db` field must be set on every command
- `listIndexes` response has `cursor.firstBatch` (NOT `indexBatch`)
- `listCollections` response has `cursor.firstBatch`
- `update_one` with upsert: `matched` is 1 even for newly created doc
- Auto-generated `_id` means document size is 1 more than explicit fields
- `$addFields` must come BEFORE `$project` (can't reference excluded fields)
- `$concat` returns Null if referenced fields are not in the document

### Bison Fork (auryn31/bison)
- Removed `juno` dependency entirely
- `bson.ObjectId(id)` → converted to bit_array for dynamic conversion
- `bson.DateTime(t)` → `birl.to_unix(t) * 1000` for millisecond int
- `bison/ejson/decoder.gleam` rewritten: `decode.field` API for stdlib 1.x
- Time bug fixed: `duration.Duration(ms)` → `duration.accurate_new([#(ms, duration.MilliSecond)])`
- `bison_ffi.erl` needs `-compile({no_auto_import,[element/2]})` for Erlang 27 compat
- `generic.from_string` returns opaque type; wrap with `bson.Generic(data)`

### Test Architecture
- **Unit tests**: `test/mungo_test.gleam` — error module tests (52 tests)
- **Integration tests**: `test/integration_test.gleam` — testcontainers with real MongoDB
- `testcontainer_formulas` provides `formula.mongo("7.0")` with `connection_url`, `host`, `port`
- `testcontainer.start(formula)` returns a container; `formula.connection_url(container)` gets the URL
- `with_mongo(name, fn(collection))` helper cleans up collection before/after each test
- `find_doc(coll, filter)` helper finds first doc as dict for assertion
- 137 total tests passing

### BSON Types
- `bson.Generic`, `bson.UUID`, `bson.MD5` are constructors of `bson.Binary` type
- `generic.from_string`, `uuid.from_string`, `md5.from_string` return opaque types
- Wrap with `bson.Generic(data)`, `bson.UUID(data)`, `bson.MD5(data)`
- `crud.Upsert`, `crud.Sort`, `crud.Skip`, `crud.Limit` need module prefix

### Connection Pooling
- `Client` holds: `db`, `connections`, `next_index`, `pool_size`, `use_tls`, `topology`, `replica_set_name`, `read_preference`
- `Connection` holds: `socket: DriverSocket`, `primary: Bool`, `host: String`, `port: Int`
- `DriverSocket` = `TcpSocket(mug.Socket) | TlsSocket(tls_module.TlsSocket)`
- Round-robin selection: `index % list.length(candidate_connections)`
- `refresh_connections` rechecks `isPrimary` on all connections during failover

### TLS Support
- `src/mungo_tls_ffi.erl` uses Erlang `ssl` module
- Connection string: `mongodb://host/db?ssl=true` enables TLS
- Query parameter parsing: `?ssl=true`, `?ssl=1`, `?authSource=admin&ssl=true`
- `tls.gleam` module mirrors `tcp.gleam` but uses SSL FFI

### Cluster/Replica Set Support
- `mungo/topology.gleam`: TopologyType, ServerDescription, Topology, ReadPreference
- `topology.hello` command: `#("hello", bson.Int32(1))` returns `isWritablePrimary`, `isSecondary`, `setName`, `tags`
- Connection string: `?replicaSet=rsName` parsed and stored in Client
- Topology monitoring: 10s interval polling via `process.spawn` + `process.sleep`
- Read preferences: Primary, PrimaryPreferred, Secondary, SecondaryPreferred, Nearest
- `execute` function routes based on read_preference: filters connections by primary/secondary status
- `poll_topology` updates connection `primary` flag based on hello responses
- `set_read_preference(client, pref)` sends message to actor to change routing

### Bulk Operations (Client-Side Batching)
- `bulkWrite` server command is MongoDB 8.0+ only
- Implemented client-side batching: groups consecutive same-type operations
- Inserts use `insert` command with documents array
- Updates use `update` command with updates array (q, u, multi, upsert)
- Deletes use `delete` command with deletes array (q, limit)
- Batch order matters: `[op, ..current]` prepends (reverses order), so `list.reverse` in collectors is needed
- `group_by_type` returns batches in flush order — do NOT reverse at the end

### Git / Dependencies
- Bison is a git dependency: `{ git = "https://github.com/auryn31/bison.git", ref = "main" }`
- `manifest.toml` is auto-generated by `gleam build` — never edit manually
- `birl` is transitive (via bison) — importing it shows a warning but works
- `gleam build` auto-regenerates manifest when deps change

## Current Work State
### Completed
- All deps bumped to latest versions
- README fully rewritten with 7 sections
- bison fork migrated to stdlib 1.x (all tests pass)
- mungo builds clean, all 155 tests pass
- Connection pooling implemented (pool_size param, round-robin)
- Bulk operations module created (`mungo/bulk.gleam`) — client-side batching
- Admin module created (`mungo/admin.gleam` — listDatabases, listCollections, dropDatabase)
- CRUD extended: distinct, findAndModify, drop, createIndex, dropIndex
- TLS support: FFI + module + connection string parsing
- Bison switched from local path to git dependency
- Transactions (session support, lsid + txnNumber in commands)
- Change streams (watch command, cursor-based)
- Cluster/replica set support (topology monitoring, read preferences)
- 155 tests passing (52 unit + 103 integration)

### Not Started
- Integration tests for transactions/change streams (need replica set container)

## Commands
```sh
gleam build          # Compile (check for errors)
gleam test           # Run all tests (needs Docker for integration)
gleam format         # Format source
gleam deps download  # Fetch dependencies
```
