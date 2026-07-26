import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string

import mungo/error

import bison/bson
import bison/generic

pub fn first_payload(username: String) {
  let nonce =
    crypto.strong_random_bytes(24)
    |> bit_array.base64_encode(True)

  ["n=", clean_username(username), ",r=", nonce]
  |> string.concat
}

// SCRAM mechanism the server supports for a user. Chosen by negotiation.
pub type Mechanism {
  ScramSha1
  ScramSha256
}

fn mechanism_name(mechanism: Mechanism) -> String {
  case mechanism {
    ScramSha1 -> "SCRAM-SHA-1"
    ScramSha256 -> "SCRAM-SHA-256"
  }
}

fn mechanism_alg(mechanism: Mechanism) -> crypto.HashAlgorithm {
  case mechanism {
    ScramSha1 -> crypto.Sha1
    ScramSha256 -> crypto.Sha256
  }
}

fn mechanism_key_len(mechanism: Mechanism) -> Int {
  case mechanism {
    ScramSha1 -> 20
    ScramSha256 -> 32
  }
}

pub fn first_message(payload, mechanism: Mechanism) {
  let payload =
    ["n,,", payload]
    |> string.concat
    |> generic.from_string

  [
    #("saslStart", bson.Boolean(True)),
    #("mechanism", bson.String(mechanism_name(mechanism))),
    #("payload", bson.Binary(bson.Generic(payload))),
    #("autoAuthorize", bson.Boolean(True)),
    #(
      "options",
      bson.Document(
        dict.from_list([#("skipEmptyExchange", bson.Boolean(True))]),
      ),
    ),
  ]
}

pub fn parse_first_reply(reply: dict.Dict(String, bson.Value)) {
  case
    dict.get(reply, "ok"),
    dict.get(reply, "done"),
    dict.get(reply, "conversationId"),
    dict.get(reply, "payload"),
    dict.get(reply, "errmsg")
  {
    Ok(bson.Double(0.0)), _, _, _, Ok(bson.String(msg)) ->
      Error(error.ServerError(error.AuthenticationFailed(msg)))

    Ok(bson.Double(1.0)),
      Ok(bson.Boolean(False)),
      Ok(bson.Int32(cid)),
      Ok(bson.Binary(bson.Generic(data))),
      _
    -> {
      use data <- result.try(
        generic.to_string(data)
        |> result.replace_error(
          error.ServerError(error.AuthenticationFailed(
            "First payload is not a string",
          )),
        ),
      )

      case parse_payload(data) {
        Ok([#("r", rnonce), #("s", salt), #("i", i)]) ->
          case int.parse(i) {
            Ok(iterations) ->
              case iterations >= 4096 {
                True -> Ok(#(#(rnonce, salt, iterations), data, cid))
                False ->
                  Error(
                    error.ServerError(error.AuthenticationFailed(
                      "Iterations should be an integer",
                    )),
                  )
              }
            Error(Nil) ->
              Error(
                error.ServerError(error.AuthenticationFailed(
                  "Iterations was not found",
                )),
              )
          }
        _ ->
          Error(
            error.ServerError(error.AuthenticationFailed(
              "Invalid first payload",
            )),
          )
      }
    }
    _, _, _, _, _ ->
      Error(
        error.ServerError(error.AuthenticationFailed("Invalid first reply")),
      )
  }
}

// MongoDB's SCRAM-SHA-1 feeds the hex MD5 of "username:mongo:password" (a
// MONGODB-CR legacy quirk) into Hi(), not the raw password. SCRAM-SHA-256
// uses the raw password.
fn scram_secret(
  username: String,
  password: String,
  mechanism: Mechanism,
) -> String {
  case mechanism {
    ScramSha256 -> password
    ScramSha1 ->
      crypto.hash(
        crypto.Md5,
        bit_array.from_string(username <> ":mongo:" <> password),
      )
      |> bit_array.base16_encode
      |> string.lowercase
  }
}

pub fn second_message(
  server_params,
  first_payload,
  server_payload,
  cid,
  username,
  password,
  mechanism: Mechanism,
) {
  let #(rnonce, salt, iterations) = server_params
  let alg = mechanism_alg(mechanism)
  let secret = scram_secret(username, password, mechanism)

  use salt <- result.try(
    bit_array.base64_decode(salt)
    |> result.replace_error(
      error.ServerError(error.AuthenticationFailed(
        "Salt is not base64 encoded string",
      )),
    ),
  )

  let salted_password = hi(secret, salt, iterations, mechanism)

  let client_key =
    crypto.hmac(bit_array.from_string("Client Key"), alg, salted_password)

  let server_key =
    crypto.hmac(bit_array.from_string("Server Key"), alg, salted_password)

  let stored_key = crypto.hash(alg, client_key)

  let auth_message =
    [first_payload, ",", server_payload, ",c=biws,r=", rnonce]
    |> string.concat
    |> generic.from_string

  let client_signature =
    crypto.hmac(generic.to_bit_array(auth_message), alg, stored_key)

  let second_payload =
    [
      "c=biws,r=",
      rnonce,
      ",p=",
      xor(client_key, client_signature, <<>>)
        |> bit_array.base64_encode(True),
    ]
    |> string.concat
    |> generic.from_string

  let server_signature =
    crypto.hmac(generic.to_bit_array(auth_message), alg, server_key)

  #(
    [
      #("saslContinue", bson.Boolean(True)),
      #("conversationId", bson.Int32(cid)),
      #("payload", bson.Binary(bson.Generic(second_payload))),
    ],
    server_signature,
  )
  |> Ok
}

pub fn parse_second_reply(
  reply: dict.Dict(String, bson.Value),
  server_signature: BitArray,
) {
  case
    dict.get(reply, "ok"),
    dict.get(reply, "done"),
    dict.get(reply, "payload")
  {
    Ok(bson.Double(0.0)), _, _ ->
      Error(error.ServerError(error.AuthenticationFailed("")))

    Ok(bson.Double(1.0)),
      Ok(bson.Boolean(True)),
      Ok(bson.Binary(bson.Generic(data)))
    -> {
      use data <- result.try(
        generic.to_string(data)
        |> result.replace_error(
          error.ServerError(error.AuthenticationFailed("")),
        ),
      )

      case parse_payload(data) {
        Ok([#("v", data)]) -> {
          use received_signature <- result.try(
            bit_array.base64_decode(data)
            |> result.replace_error(
              error.ServerError(error.AuthenticationFailed("")),
            ),
          )

          case
            bit_array.byte_size(server_signature)
            == bit_array.byte_size(received_signature)
            && crypto.secure_compare(server_signature, received_signature)
          {
            True -> Ok(Nil)
            False -> Error(error.ServerError(error.AuthenticationFailed("")))
          }
        }
        _ -> Error(error.ServerError(error.AuthenticationFailed("")))
      }
    }
    _, _, _ -> Error(error.ServerError(error.AuthenticationFailed("")))
  }
}

fn parse_payload(payload: String) {
  payload
  |> string.split(",")
  |> list.try_map(fn(item) { string.split_once(item, "=") })
  |> result.replace_error(error.ServerError(error.AuthenticationFailed("")))
}

fn clean_username(username: String) {
  username
  |> string.replace("=", "=3D")
  |> string.replace(",", "=2C")
}

// erlang crypto:pbkdf2_hmac digest atoms differ from gleam_crypto's:
// SHA-1 is the atom `sha`, not `sha1`. These constructors compile to the
// atoms erlang expects.
type Digest {
  Sha
  Sha256
}

fn mechanism_digest(mechanism: Mechanism) -> Digest {
  case mechanism {
    ScramSha1 -> Sha
    ScramSha256 -> Sha256
  }
}

pub fn hi(password, salt, iterations, mechanism: Mechanism) {
  // TODO: should cache with unique key constructed from params
  pbkdf2(
    mechanism_digest(mechanism),
    password,
    salt,
    iterations,
    mechanism_key_len(mechanism),
  )
}

@external(erlang, "crypto", "pbkdf2_hmac")
fn pbkdf2(
  alg: Digest,
  password: String,
  salt: BitArray,
  iterations: Int,
  key_len: Int,
) -> BitArray

fn xor(a: BitArray, b: BitArray, storage: BitArray) -> BitArray {
  let assert <<fa, ra:bits>> = a
  let assert <<fb, rb:bits>> = b

  let new_storage =
    [storage, <<int.bitwise_exclusive_or(fa, fb)>>]
    |> bit_array.concat

  case ra, rb {
    <<>>, <<>> -> new_storage
    _, _ -> xor(ra, rb, new_storage)
  }
}
