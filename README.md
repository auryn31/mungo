![mungo](https://raw.githubusercontent.com/massivefermion/mungo/main/banner.png)

[![Package Version](https://img.shields.io/hexpm/v/mungo)](https://hex.pm/packages/mungo)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/mungo/)

# mungo (formerly gleam_mongo)
> mungo: a felted fabric made from the shredded fibre of repurposed woollen cloth
---


A mongodb driver for gleam

## <img width=32 src=https://raw.githubusercontent.com/massivefermion/mungo/main/icon.png> Quick start

```sh
gleam shell # Run an Erlang shell
```

## <img width=32 src=https://raw.githubusercontent.com/massivefermion/mungo/main/icon.png> Installation

```sh
gleam add mungo
```

## <img width=32 src=https://raw.githubusercontent.com/massivefermion/mungo/main/icon.png> Roadmap

- [x] support basic mongodb commands
- [x] support aggregation
- [x] support connection strings
- [x] support authentication
- [x] support mongodb cursors
- [ ] support connection pooling
   - The plan is to use [puddle](https://github.com/massivefermion/puddle), but there are still unresolved issues with that package!
- [ ] support bulk operations
- [ ] support clusters
- [ ] support tls
- [ ] support transactions
- [ ] support change streams
- [ ] support other mongodb commands

## <img width=32 src=https://raw.githubusercontent.com/massivefermion/mungo/main/icon.png> Usage

### Connecting to MongoDB

```gleam
import mungo

pub fn main() {
  // Connect with authentication
  let assert Ok(client) =
    mungo.start(
      "mongodb://app-dev:passwd@localhost/app-db?authSource=admin",
      512,
    )

  // Connect without authentication
  let assert Ok(client) =
    mungo.start("mongodb://localhost/mydb", 512)

  // Connect to a specific host and port
  let assert Ok(client) =
    mungo.start("mongodb://db.example.com:27017/mydb", 512)
}
```

### Inserting Documents

```gleam
import mungo
import bison/bson

pub fn insert_example(client) {
  let users = mungo.collection(client, "users")

  // Insert a single document
  let assert Ok(_id) =
    users
    |> mungo.insert_one(
      [
        #("name", bson.String("Alice")),
        #("email", bson.String("alice@example.com")),
        #("age", bson.Int32(30)),
      ],
      512,
    )

  // Insert multiple documents at once
  let assert Ok(result) =
    users
    |> mungo.insert_many(
      [
        [
          #("name", bson.String("Bob")),
          #("email", bson.String("bob@example.com")),
          #("age", bson.Int32(25)),
        ],
        [
          #("name", bson.String("Charlie")),
          #("email", bson.String("charlie@example.com")),
          #("age", bson.Int32(35)),
        ],
      ],
      512,
    )

  // result.inserted contains the count of inserted documents
  // result.inserted_ids contains the generated ObjectIds
  let inserted_count = result.inserted
}
```

### Finding Documents

```gleam
import mungo
import mungo/crud.{Sort, Limit, Skip, Projection}
import bison/bson
import gleam/option

pub fn find_example(client) {
  let users = mungo.collection(client, "users")

  // Find a single document by filter
  let assert Ok(user) =
    mungo.find_one(
      users,
      [#("email", bson.String("alice@example.com"))],
      [],
      512,
    )

  // Find a document by its ObjectId
  let assert Ok(user) =
    mungo.find_by_id(users, "507f1f77bcf86cd799439011", 512)

  // Find all documents (no filter)
  let assert Ok(cursor) =
    mungo.find_all(users, [], 512)
  let all_users = mungo.to_list(cursor, 512)

  // Find with filter, sort, and limit
  let assert Ok(cursor) =
    mungo.find_many(
      users,
      [#("age", bson.Document(dict.from_list([#("$gt", bson.Int32(18))]))],
      [
        Sort([#("age", bson.Int32(1))]),
        Limit(10),
        Skip(5),
      ],
      512,
    )

  // Iterate with a cursor
  let assert #(option.Some(first_user), cursor) =
    mungo.next(cursor, 512)
  let assert #(option.Second(second_user), cursor) =
    mungo.next(cursor, 512)

  // Count documents
  let assert Ok(count) = mungo.count_all(users, 512)
  let assert Ok(filtered_count) =
    mungo.count(
      users,
      [#("age", bson.Document(dict.from_list([#("$gte", bson.Int32(21))]))],
      512,
    )
}
```

### Updating Documents

```gleam
import mungo
import mungo/crud.{Upsert}
import bison/bson

pub fn update_example(client) {
  let users = mungo.collection(client, "users")

  // Update a single document
  let assert Ok(result) =
    mungo.update_one(
      users,
      [#("email", bson.String("alice@example.com"))],
      [#("$set", bson.Document(dict.from_list([
        #("email", bson.String("alice_new@example.com")),
      ])))],
      [],
      512,
    )
  // result.matched - number of documents matched
  // result.modified - number of documents modified

  // Update with upsert (inserts if no match found)
  let assert Ok(result) =
    mungo.update_one(
      users,
      [#("email", bson.String("new@example.com"))],
      [
        #("$set", bson.Document(dict.from_list([
          #("name", bson.String("New User")),
          #("email", bson.String("new@example.com")),
        ]))),
      ],
      [Upsert],
      512,
    )
  // result.upserted contains the IDs of upserted documents

  // Update multiple documents
  let assert Ok(result) =
    mungo.update_many(
      users,
      [#("role", bson.String("admin"))],
      [#("$set", bson.Document(dict.from_list([
        #("active", bson.Boolean(True)),
      ])))],
      [],
      512,
    )
}
```

### Deleting Documents

```gleam
import mungo
import bison/bson

pub fn delete_example(client) {
  let users = mungo.collection(client, "users")

  // Delete a single document
  let assert Ok(deleted_count) =
    mungo.delete_one(
      users,
      [#("email", bson.String("bob@example.com"))],
      512,
    )

  // Delete multiple documents
  let assert Ok(deleted_count) =
    mungo.delete_many(
      users,
      [#("inactive", bson.Boolean(True))],
      512,
    )
}
```

### Aggregation Pipelines

```gleam
import mungo
import mungo/aggregation.{
  Let, aggregate, match, lookup, unwind, project, sort, group, skip, limit,
  to_cursor,
}
import bison/bson

pub fn aggregation_example(client) {
  let orders = mungo.collection(client, "orders")

  // Simple aggregation: group by status and count
  let assert Ok(cursor) =
    orders
    |> aggregate([], 512)
    |> group([
      #("_id", bson.String("$status")),
      #("count", bson.Document(dict.from_list([#("$sum", bson.Int32(1))]))),
    ])
    |> sort([#("count", bson.Int32(-1))])
    |> to_cursor

  // Pipeline with $lookup (join with another collection)
  let assert Ok(cursor) =
    orders
    |> aggregate([], 512)
    |> match([#("status", bson.String("completed"))])
    |> lookup(
      from: "customers",
      local_field: "customer_id",
      foreign_field: "_id",
      alias: "customer",
    )
    |> unwind("$customer", False)
    |> project([
      #("_id", bson.Int32(0)),
      #("total", bson.Int32(1)),
      #("customer_name", bson.String("$customer.name")),
    ])
    |> to_cursor

  // Pipeline with $let and $addFields
  let assert Ok(cursor) =
    products
    |> aggregate([Let([#("tax_rate", bson.Double(0.08))])], 512)
    |> match([
      #(
        "$expr",
        bson.Document(dict.from_list([
          #(
            "$gt",
            bson.Array([bson.String("$price"), bson.Int32(100)]),
          ),
        ])),
      ),
    ])
    |> mungo/aggregation.add_fields([
      #(
        "price_with_tax",
        bson.Document(dict.from_list([
          #(
            "$multiply",
            bson.Array([
              bson.String("$price"),
              bson.Document(dict.from_list([#("$add", bson.Array([
                bson.Int32(1),
                bson.String("$$tax_rate"),
              ]))])),
            ]),
          ),
        ])),
      ),
    ])
    |> skip(10)
    |> limit(5)
    |> to_cursor
}
```

### Handling Errors

```gleam
import mungo
import mungo/error
import bison/bson

pub fn error_handling_example(client) {
  let users = mungo.collection(client, "users")

  case mungo.insert_one(
    users,
    [#("email", bson.String("duplicate@example.com"))],
    512,
  ) {
    Ok(id) -> io.debug(id)
    Error(error.WriteErrors(errors)) ->
      // Handle write errors (e.g., duplicate key)
      errors |> list.each(fn(err) {
        io.debug(err.1)  // error message
      })
    Error(error.ServerError(server_error)) ->
      // Handle MongoDB server errors
      case error.is_retriable_error(server_error) {
        True -> io.println("Retriable error, should retry")
        False -> io.println("Non-retriable server error")
      }
    Error(error.TCPError(tcp_error)) ->
      io.println("TCP connection error")
    Error(error.AuthenticationError) ->
      io.println("Authentication failed")
    Error(error.ConnectionStringError) ->
      io.println("Invalid connection string")
    Error(error.ActorError) ->
      io.println("Actor communication error")
    Error(error.StructureError) ->
      io.println("Unexpected response structure")
  }
}
```

### Full Example: CRUD + Aggregation

```gleam
import gleam/option
import mungo
import mungo/crud.{Sort, Upsert}
import mungo/aggregation.{
  Let, add_fields, aggregate, match, pipelined_lookup, to_cursor, unwind,
}
import bison/bson

pub fn main() {
  let assert Ok(client) =
    mungo.start(
      "mongodb://app-dev:passwd@localhost/app-db?authSource=admin",
      512,
    )

  let users =
    client
    |> mungo.collection("users")

  let _ =
    users
    |> mungo.insert_many(
      [
        [
          #("username", bson.String("jmorrow")),
          #("name", bson.String("vincent freeman")),
          #("email", bson.String("jmorrow@gattaca.eu")),
          #("age", bson.Int32(32)),
        ],
        [
          #("username", bson.String("real-jerome")),
          #("name", bson.String("jerome eugene morrow")),
          #("email", bson.String("real-jerome@running.at")),
          #("age", bson.Int32(32)),
        ],
      ],
      128,
    )

  let _ =
    users
    |> mungo.update_one(
      [#("username", bson.String("real-jerome"))],
      [
        #(
          "$set",
          bson.Document([
            #("username", bson.String("eugene")),
            #("email", bson.String("eugene@running.at")),
          ]),
        ),
      ],
      [Upsert],
      128,
    )

  let assert Ok(yahoo_cursor) =
    users
    |> mungo.find_many(
      [#("email", bson.Regex(#("yahoo", "")))],
      [Sort([#("username", bson.Int32(-1))])],
      128,
    )
  let _yahoo_users = mungo.to_list(yahoo_cursor, 128)

  let assert Ok(underage_lindsey_cursor) =
    users
    |> aggregate([Let([#("minimum_age", bson.Int32(21))])], 128)
    |> match([
      #(
        "$expr",
        bson.Document([
          #(
            "$lt",
            bson.Array([bson.String("$age"), bson.String("$$minimum_age")]),
          ),
        ]),
      ),
    ])
    |> add_fields([
      #(
        "first_name",
        bson.Document([
          #(
            "$arrayElemAt",
            bson.Array([
              bson.Document([
                #(
                  "$split",
                  bson.Array([bson.String("$name"), bson.String(" ")]),
                ),
              ]),
              bson.Int32(0),
            ]),
          ),
        ]),
      ),
    ])
    |> match([#("first_name", bson.String("lindsey"))])
    |> pipelined_lookup(
      from: "profiles",
      define: [#("user", bson.String("$username"))],
      pipeline: [
        [
          #(
            "$match",
            bson.Document([
              #(
                "$expr",
                bson.Document([
                  #(
                    "$eq",
                    bson.Array([bson.String("$username"), bson.String("$$user")]),
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ],
      alias: "profile",
    )
    |> unwind("$profile", False)
    |> to_cursor

  let assert #(option.Some(_underage_lindsey), underage_lindsey_cursor) =
    underage_lindsey_cursor
    |> mungo.next(128)

  let assert #(option.None, _) =
    underage_lindsey_cursor
    |> mungo.next(128)
}
```
