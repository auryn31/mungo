import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import birl
import bison/bson
import bison/generic
import bison/md5
import bison/object_id
import bison/uuid
import gleeunit/should
import mungo/aggregation
import mungo/client
import mungo/crud
import mungo/cursor
import mungo/session
import mungo/bulk
import mungo/admin
import testcontainer
import testcontainer/container
import testcontainer/error as tc_error
import testcontainer/formula
import testcontainer/port
import testcontainer_formulas/mongo

const timeout = 5000

const container_key = "mungo_test_url"

@external(erlang, "persistent_term_ffi", "get")
fn persistent_get(key: String) -> Result(String, Nil)

@external(erlang, "persistent_term_ffi", "set")
fn persistent_set(key: String, value: String) -> Nil

fn get_or_start_container() -> String {
  case persistent_get(container_key) {
    Ok(url) -> url
    Error(Nil) -> {
      let f =
        mongo.new()
        |> mongo.with_database("mungo_test")
        |> mongo.formula()
      let assert Ok(c) = testcontainer.start(formula.spec(f))
      let host = container.host(c)
      let assert Ok(p) = container.host_port(c, port.tcp(27_017))
      let url =
        "mongodb://root:root@"
        <> host
        <> ":"
        <> int.to_string(p)
        <> "/mungo_test?authSource=admin"
      persistent_set(container_key, url)
      url
    }
  }
}

fn with_mongo(
  name: String,
  f: fn(client.Collection) -> Result(a, tc_error.Error),
) -> Result(a, tc_error.Error) {
  let url = get_or_start_container()
  let assert Ok(started) = client.start(url, 1, timeout)
  let coll = client.collection(started.data, name)
  f(coll)
}

fn make_range(from: Int, to: Int) -> List(Int) {
  list.repeat(Nil, to - from + 1)
  |> list.index_map(fn(_, i) { from + i })
}

fn find_doc(
  coll: client.Collection,
  filter: List(#(String, bson.Value)),
) -> dict.Dict(String, bson.Value) {
  let assert Ok(option.Some(bson.Document(fields))) =
    crud.find_one(coll, filter, [], timeout)
  fields
}

// ---------------------------------------------------------------------------
// BSON Data Types
// ---------------------------------------------------------------------------

pub fn bson_string_test() {
  with_mongo("t_string", fn(coll) {
    let doc = [#("val", bson.String("hello world"))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.String("hello world")))
    Ok(Nil)
  })
}

pub fn bson_empty_string_test() {
  with_mongo("t_empty_str", fn(coll) {
    let doc = [#("val", bson.String(""))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.String("")))
    Ok(Nil)
  })
}

pub fn bson_unicode_string_test() {
  with_mongo("t_unicode", fn(coll) {
    let doc = [#("val", bson.String("日本語テスト"))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.String("日本語テスト")))
    Ok(Nil)
  })
}

pub fn bson_special_chars_test() {
  with_mongo("t_special_chars", fn(coll) {
    let doc = [#("val", bson.String("line1\nline2\ttab"))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "val"),
      Ok(bson.String("line1\nline2\ttab")),
    )
    Ok(Nil)
  })
}

pub fn bson_int32_test() {
  with_mongo("t_int32", fn(coll) {
    let doc = [#("val", bson.Int32(42))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Int32(42)))
    Ok(Nil)
  })
}

pub fn bson_int32_negative_test() {
  with_mongo("t_int32_neg", fn(coll) {
    let doc = [#("val", bson.Int32(-1))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Int32(-1)))
    Ok(Nil)
  })
}

pub fn bson_int32_zero_test() {
  with_mongo("t_int32_zero", fn(coll) {
    let doc = [#("val", bson.Int32(0))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Int32(0)))
    Ok(Nil)
  })
}

pub fn bson_int32_max_test() {
  with_mongo("t_int32_max", fn(coll) {
    let doc = [#("val", bson.Int32(2_147_483_647))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Int32(2_147_483_647)))
    Ok(Nil)
  })
}

pub fn bson_int32_min_test() {
  with_mongo("t_int32_min", fn(coll) {
    let doc = [#("val", bson.Int32(-2_147_483_648))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Int32(-2_147_483_648)))
    Ok(Nil)
  })
}

pub fn bson_int64_test() {
  with_mongo("t_int64", fn(coll) {
    let doc = [#("val", bson.Int64(9_007_199_254_740_993))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "val"),
      Ok(bson.Int64(9_007_199_254_740_993)),
    )
    Ok(Nil)
  })
}

pub fn bson_double_test() {
  with_mongo("t_double", fn(coll) {
    let doc = [#("val", bson.Double(3.14159))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Double(3.14159)))
    Ok(Nil)
  })
}

pub fn bson_double_negative_test() {
  with_mongo("t_double_neg", fn(coll) {
    let doc = [#("val", bson.Double(-0.001))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Double(-0.001)))
    Ok(Nil)
  })
}

pub fn bson_double_zero_test() {
  with_mongo("t_double_zero", fn(coll) {
    let doc = [#("val", bson.Double(0.0))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Double(0.0)))
    Ok(Nil)
  })
}

pub fn bson_boolean_true_test() {
  with_mongo("t_bool_true", fn(coll) {
    let doc = [#("val", bson.Boolean(True))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Boolean(True)))
    Ok(Nil)
  })
}

pub fn bson_boolean_false_test() {
  with_mongo("t_bool_false", fn(coll) {
    let doc = [#("val", bson.Boolean(False))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Boolean(False)))
    Ok(Nil)
  })
}

pub fn bson_null_test() {
  with_mongo("t_null", fn(coll) {
    let doc = [#("val", bson.Null)]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Null))
    Ok(Nil)
  })
}

pub fn bson_array_test() {
  with_mongo("t_array", fn(coll) {
    let doc = [
      #(
        "val",
        bson.Array([
          bson.Int32(1),
          bson.String("two"),
          bson.Double(3.0),
          bson.Boolean(True),
          bson.Null,
        ]),
      ),
    ]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "val"),
      Ok(bson.Array([
        bson.Int32(1),
        bson.String("two"),
        bson.Double(3.0),
        bson.Boolean(True),
        bson.Null,
      ])),
    )
    Ok(Nil)
  })
}

pub fn bson_empty_array_test() {
  with_mongo("t_empty_arr", fn(coll) {
    let doc = [#("val", bson.Array([]))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Array([])))
    Ok(Nil)
  })
}

pub fn bson_nested_array_test() {
  with_mongo("t_nested_arr", fn(coll) {
    let doc = [
      #(
        "val",
        bson.Array([
          bson.Array([bson.Int32(1), bson.Int32(2)]),
          bson.Array([bson.Int32(3), bson.Int32(4)]),
        ]),
      ),
    ]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "val"),
      Ok(bson.Array([
        bson.Array([bson.Int32(1), bson.Int32(2)]),
        bson.Array([bson.Int32(3), bson.Int32(4)]),
      ])),
    )
    Ok(Nil)
  })
}

pub fn bson_document_test() {
  with_mongo("t_document", fn(coll) {
    let inner =
      dict.from_list([#("a", bson.Int32(1)), #("b", bson.String("two"))])
    let doc = [#("val", bson.Document(inner))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Document(inner_found)) = dict.get(fields, "val")
    should.equal(dict.get(inner_found, "a"), Ok(bson.Int32(1)))
    should.equal(dict.get(inner_found, "b"), Ok(bson.String("two")))
    Ok(Nil)
  })
}

pub fn bson_empty_document_test() {
  with_mongo("t_empty_doc", fn(coll) {
    let doc = [#("val", bson.Document(dict.new()))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Document(dict.new())))
    Ok(Nil)
  })
}

pub fn bson_deeply_nested_document_test() {
  with_mongo("t_deep_nested", fn(coll) {
    let level3 = dict.from_list([#("deep", bson.String("value"))])
    let level2 = dict.from_list([#("level3", bson.Document(level3))])
    let level1 = dict.from_list([#("level2", bson.Document(level2))])
    let doc = [#("val", bson.Document(level1))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Document(l1)) = dict.get(fields, "val")
    let assert Ok(bson.Document(l2)) = dict.get(l1, "level2")
    let assert Ok(bson.Document(l3)) = dict.get(l2, "level3")
    should.equal(dict.get(l3, "deep"), Ok(bson.String("value")))
    Ok(Nil)
  })
}

pub fn bson_object_id_test() {
  with_mongo("t_objectid", fn(coll) {
    let id = object_id.new()
    let doc = [#("_id", bson.ObjectId(id)), #("val", bson.String("test"))]
    let assert Ok(_) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", bson.ObjectId(id))])
    should.equal(dict.get(fields, "val"), Ok(bson.String("test")))
    Ok(Nil)
  })
}

pub fn bson_datetime_test() {
  with_mongo("t_datetime", fn(coll) {
    let now = birl.utc_now()
    let doc = [#("val", bson.DateTime(now))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.DateTime(_)) = dict.get(fields, "val")
    Ok(Nil)
  })
}

pub fn bson_regex_test() {
  with_mongo("t_regex", fn(coll) {
    let doc = [#("val", bson.Regex("^test$", "i"))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Regex(pattern, options)) = dict.get(fields, "val")
    should.equal(pattern, "^test$")
    should.equal(options, "i")
    Ok(Nil)
  })
}

pub fn bson_timestamp_test() {
  with_mongo("t_timestamp", fn(coll) {
    let doc = [#("val", bson.Timestamp(1000, 1))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Timestamp(1000, 1)))
    Ok(Nil)
  })
}

pub fn bson_binary_generic_test() {
  with_mongo("t_binary_gen", fn(coll) {
    let data = generic.from_string("hello binary")
    let doc = [#("val", bson.Binary(bson.Generic(data)))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Binary(bson.Generic(returned))) =
      dict.get(fields, "val")
    should.equal(generic.to_string(returned), Ok("hello binary"))
    Ok(Nil)
  })
}

pub fn bson_binary_uuid_test() {
  with_mongo("t_binary_uuid", fn(coll) {
    let assert Ok(id_val) =
      uuid.from_string("550e8400-e29b-41d4-a716-446655440000")
    let doc = [#("val", bson.Binary(bson.UUID(id_val)))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Binary(bson.UUID(returned))) =
      dict.get(fields, "val")
    should.equal(
      uuid.to_string(returned),
      "550e8400-e29b-41d4-a716-446655440000",
    )
    Ok(Nil)
  })
}

pub fn bson_binary_md5_test() {
  with_mongo("t_binary_md5", fn(coll) {
    let assert Ok(md5_val) =
      md5.from_string("d41d8cd98f00b204e9800998ecf8427e")
    let doc = [#("val", bson.Binary(bson.MD5(md5_val)))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Binary(bson.MD5(returned))) =
      dict.get(fields, "val")
    should.equal(
      md5.to_string(returned),
      "d41d8cd98f00b204e9800998ecf8427e",
    )
    Ok(Nil)
  })
}

// ---------------------------------------------------------------------------
// Edge Cases
// ---------------------------------------------------------------------------

pub fn insert_empty_document_test() {
  with_mongo("e_empty_doc", fn(coll) {
    let doc: List(#(String, bson.Value)) = []
    let assert Ok(_) = crud.insert_one(coll, doc, timeout)
    let assert Ok(count) = crud.count_all(coll, timeout)
    should.equal(count, 1)
    Ok(Nil)
  })
}

pub fn find_nonexistent_id_test() {
  with_mongo("e_nonexist_id", fn(coll) {
    let fake_id = "000000000000000000000000"
    let assert Ok(option.None) = crud.find_by_id(coll, fake_id, timeout)
    Ok(Nil)
  })
}

pub fn find_nonexistent_filter_test() {
  with_mongo("e_nonexist_filt", fn(coll) {
    let doc = [#("name", bson.String("Alice"))]
    let assert Ok(_) = crud.insert_one(coll, doc, timeout)
    let assert Ok(option.None) =
      crud.find_one(
        coll,
        [#("name", bson.String("DoesNotExist"))],
        [],
        timeout,
      )
    Ok(Nil)
  })
}

pub fn delete_nonexistent_test() {
  with_mongo("e_del_nonexist", fn(coll) {
    let assert Ok(deleted) =
      crud.delete_one(coll, [#("name", bson.String("Nobody"))], timeout)
    should.equal(deleted, 0)
    Ok(Nil)
  })
}

pub fn update_nonexistent_without_upsert_test() {
  with_mongo("e_upd_no_upsert", fn(coll) {
    let assert Ok(res) =
      crud.update_one(
        coll,
        [#("name", bson.String("Ghost"))],
        [#("$set", bson.Document(dict.from_list([#("x", bson.Int32(1))])))],
        [],
        timeout,
      )
    should.equal(res.matched, 0)
    should.equal(res.modified, 0)
    should.equal(res.upserted, [])
    Ok(Nil)
  })
}

pub fn update_with_upsert_creates_doc_test() {
  with_mongo("e_upsert_create", fn(coll) {
    let assert Ok(res) =
      crud.update_one(
        coll,
        [#("name", bson.String("New"))],
        [
          #(
            "$set",
            bson.Document(dict.from_list([#("score", bson.Int32(100))])),
          ),
        ],
        [crud.Upsert],
        timeout,
      )
    should.equal(list.length(res.upserted), 1)

    let fields = find_doc(coll, [#("name", bson.String("New"))])
    should.equal(dict.get(fields, "score"), Ok(bson.Int32(100)))
    Ok(Nil)
  })
}

pub fn large_array_test() {
  with_mongo("e_large_array", fn(coll) {
    let items =
      make_range(0, 99) |> list.map(fn(i) { bson.Int32(i) })
    let doc = [#("items", bson.Array(items))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Array(arr)) = dict.get(fields, "items")
    should.equal(list.length(arr), 100)
    Ok(Nil)
  })
}

pub fn many_fields_document_test() {
  with_mongo("e_many_fields", fn(coll) {
    let fields =
      make_range(0, 49)
      |> list.map(fn(i) { #("field_" <> int.to_string(i), bson.Int32(i)) })
    let assert Ok(id) = crud.insert_one(coll, fields, timeout)
    let assert Ok(option.Some(bson.Document(found))) =
      crud.find_one(coll, [#("_id", id)], [], timeout)
    should.equal(dict.size(found), 51)
    should.equal(dict.get(found, "field_0"), Ok(bson.Int32(0)))
    should.equal(dict.get(found, "field_49"), Ok(bson.Int32(49)))
    Ok(Nil)
  })
}

pub fn mixed_types_in_array_test() {
  with_mongo("e_mixed_array", fn(coll) {
    let doc = [
      #(
        "mixed",
        bson.Array([
          bson.String("text"),
          bson.Int32(42),
          bson.Double(3.14),
          bson.Boolean(True),
          bson.Null,
          bson.Array([bson.Int32(1)]),
          bson.Document(dict.from_list([#("key", bson.String("val"))])),
        ]),
      ),
    ]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)
    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Array(items)) = dict.get(fields, "mixed")
    should.equal(list.length(items), 7)
    let assert [s, i, d, b, n, a, doc_val] = items
    should.equal(s, bson.String("text"))
    should.equal(i, bson.Int32(42))
    should.equal(d, bson.Double(3.14))
    should.equal(b, bson.Boolean(True))
    should.equal(n, bson.Null)
    should.equal(a, bson.Array([bson.Int32(1)]))
    should.equal(
      doc_val,
      bson.Document(dict.from_list([#("key", bson.String("val"))])),
    )
    Ok(Nil)
  })
}

pub fn find_by_id_invalid_string_test() {
  with_mongo("e_invalid_id", fn(coll) {
    let assert Error(_) = crud.find_by_id(coll, "not-a-valid-id", timeout)
    Ok(Nil)
  })
}

pub fn find_by_id_wrong_length_test() {
  with_mongo("e_wrong_len_id", fn(coll) {
    let assert Error(_) = crud.find_by_id(coll, "12345", timeout)
    Ok(Nil)
  })
}

pub fn find_empty_collection_test() {
  with_mongo("e_find_empty", fn(coll) {
    let assert Ok(c) = crud.find_many(coll, [], [], timeout)
    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 0)
    Ok(Nil)
  })
}

pub fn count_empty_collection_test() {
  with_mongo("e_count_empty", fn(coll) {
    let assert Ok(count) = crud.count_all(coll, timeout)
    should.equal(count, 0)
    Ok(Nil)
  })
}

pub fn count_with_no_match_test() {
  with_mongo("e_count_nomatch", fn(coll) {
    let assert Ok(_) = crud.insert_one(coll, [#("x", bson.Int32(1))], timeout)
    let assert Ok(count) =
      crud.count(coll, [#("x", bson.Int32(999))], timeout)
    should.equal(count, 0)
    Ok(Nil)
  })
}

// ---------------------------------------------------------------------------
// Comparison Operators
// ---------------------------------------------------------------------------

pub fn find_comparison_operators_test() {
  with_mongo("ops_comparison", fn(coll) {
    let docs = [
      [#("v", bson.Int32(10))],
      [#("v", bson.Int32(20))],
      [#("v", bson.Int32(30))],
      [#("v", bson.Int32(40))],
      [#("v", bson.Int32(50))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c1) =
      crud.find_many(
        coll,
        [#("v", bson.Document(dict.from_list([#("$gt", bson.Int32(30))])))],
        [],
        timeout,
      )
    should.equal(list.length(cursor.to_list(c1, timeout)), 2)

    let assert Ok(c2) =
      crud.find_many(
        coll,
        [#("v", bson.Document(dict.from_list([#("$gte", bson.Int32(30))])))],
        [],
        timeout,
      )
    should.equal(list.length(cursor.to_list(c2, timeout)), 3)

    let assert Ok(c3) =
      crud.find_many(
        coll,
        [#("v", bson.Document(dict.from_list([#("$lt", bson.Int32(30))])))],
        [],
        timeout,
      )
    should.equal(list.length(cursor.to_list(c3, timeout)), 2)

    let assert Ok(c4) =
      crud.find_many(
        coll,
        [#("v", bson.Document(dict.from_list([#("$lte", bson.Int32(30))])))],
        [],
        timeout,
      )
    should.equal(list.length(cursor.to_list(c4, timeout)), 3)

    let assert Ok(c5) =
      crud.find_many(
        coll,
        [#("v", bson.Document(dict.from_list([#("$ne", bson.Int32(30))])))],
        [],
        timeout,
      )
    should.equal(list.length(cursor.to_list(c5, timeout)), 4)

    let assert Ok(c6) =
      crud.find_many(
        coll,
        [
          #(
            "v",
            bson.Document(dict.from_list([
              #("$in", bson.Array([bson.Int32(10), bson.Int32(50)])),
            ])),
          ),
        ],
        [],
        timeout,
      )
    should.equal(list.length(cursor.to_list(c6, timeout)), 2)

    let assert Ok(c7) =
      crud.find_many(
        coll,
        [
          #(
            "v",
            bson.Document(dict.from_list([
              #("$nin", bson.Array([bson.Int32(10), bson.Int32(50)])),
            ])),
          ),
        ],
        [],
        timeout,
      )
    should.equal(list.length(cursor.to_list(c7, timeout)), 3)

    Ok(Nil)
  })
}

pub fn find_logical_operators_test() {
  with_mongo("ops_logical", fn(coll) {
    let docs = [
      [#("a", bson.Int32(1)), #("b", bson.Int32(10))],
      [#("a", bson.Int32(2)), #("b", bson.Int32(20))],
      [#("a", bson.Int32(3)), #("b", bson.Int32(30))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      crud.find_many(
        coll,
        [
          #(
            "$or",
            bson.Array([
              bson.Document(dict.from_list([#("a", bson.Int32(1))])),
              bson.Document(dict.from_list([#("b", bson.Int32(30))])),
            ]),
          ),
        ],
        [],
        timeout,
      )
    should.equal(list.length(cursor.to_list(c, timeout)), 2)
    Ok(Nil)
  })
}

// ---------------------------------------------------------------------------
// Find Options
// ---------------------------------------------------------------------------

pub fn find_with_sort_test() {
  with_mongo("opts_sort", fn(coll) {
    let docs = [
      [#("name", bson.String("C")), #("order", bson.Int32(3))],
      [#("name", bson.String("A")), #("order", bson.Int32(1))],
      [#("name", bson.String("B")), #("order", bson.Int32(2))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      crud.find_many(
        coll,
        [],
        [crud.Sort([#("order", bson.Int32(1))])],
        timeout,
      )
    let results = cursor.to_list(c, timeout)
    let assert [first, second, third] = results
    let assert bson.Document(f) = first
    let assert bson.Document(s) = second
    let assert bson.Document(t) = third
    should.equal(dict.get(f, "name"), Ok(bson.String("A")))
    should.equal(dict.get(s, "name"), Ok(bson.String("B")))
    should.equal(dict.get(t, "name"), Ok(bson.String("C")))
    Ok(Nil)
  })
}

pub fn find_with_sort_descending_test() {
  with_mongo("opts_sort_desc", fn(coll) {
    let docs = [
      [#("name", bson.String("A")), #("score", bson.Int32(10))],
      [#("name", bson.String("B")), #("score", bson.Int32(20))],
      [#("name", bson.String("C")), #("score", bson.Int32(30))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      crud.find_many(
        coll,
        [],
        [crud.Sort([#("score", bson.Int32(-1))])],
        timeout,
      )
    let results = cursor.to_list(c, timeout)
    let assert [first, ..] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "name"), Ok(bson.String("C")))
    Ok(Nil)
  })
}

pub fn find_with_skip_test() {
  with_mongo("opts_skip", fn(coll) {
    let docs = [
      [#("name", bson.String("A"))],
      [#("name", bson.String("B"))],
      [#("name", bson.String("C"))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      crud.find_many(
        coll,
        [],
        [crud.Skip(1), crud.Sort([#("name", bson.Int32(1))])],
        timeout,
      )
    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 2)
    let assert [first, ..] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "name"), Ok(bson.String("B")))
    Ok(Nil)
  })
}

pub fn find_with_limit_test() {
  with_mongo("opts_limit", fn(coll) {
    let docs =
      make_range(1, 5) |> list.map(fn(i) { [#("name", bson.String(int.to_string(i)))] })
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      crud.find_many(
        coll,
        [],
        [crud.Limit(2), crud.Sort([#("name", bson.Int32(1))])],
        timeout,
      )
    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 2)
    Ok(Nil)
  })
}

pub fn find_with_projection_test() {
  with_mongo("opts_proj", fn(coll) {
    let doc = [
      #("name", bson.String("Alice")),
      #("age", bson.Int32(30)),
      #("secret", bson.String("hidden")),
    ]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(option.Some(bson.Document(fields))) =
      crud.find_one(
        coll,
        [#("_id", id)],
        [#("name", bson.Int32(1)), #("age", bson.Int32(1))],
        timeout,
      )
    should.equal(dict.get(fields, "name"), Ok(bson.String("Alice")))
    should.equal(dict.get(fields, "age"), Ok(bson.Int32(30)))
    should.equal(dict.get(fields, "secret"), Error(Nil))
    Ok(Nil)
  })
}

pub fn find_with_skip_and_limit_test() {
  with_mongo("opts_skip_lim", fn(coll) {
    let docs =
      make_range(1, 10) |> list.map(fn(i) { [#("n", bson.Int32(i))] })
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      crud.find_many(
        coll,
        [],
        [
          crud.Skip(2),
          crud.Limit(3),
          crud.Sort([#("n", bson.Int32(1))]),
        ],
        timeout,
      )
    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 3)
    let assert [first, ..] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "n"), Ok(bson.Int32(3)))
    Ok(Nil)
  })
}

// ---------------------------------------------------------------------------
// Update Operators
// ---------------------------------------------------------------------------

pub fn update_unset_test() {
  with_mongo("upd_unset", fn(coll) {
    let doc = [
      #("name", bson.String("Alice")),
      #("temp", bson.Int32(99)),
    ]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$unset",
            bson.Document(dict.from_list([#("temp", bson.String(""))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "temp"), Error(Nil))
    should.equal(dict.get(fields, "name"), Ok(bson.String("Alice")))
    Ok(Nil)
  })
}

pub fn update_inc_test() {
  with_mongo("upd_inc", fn(coll) {
    let doc = [#("counter", bson.Int32(10))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$inc",
            bson.Document(dict.from_list([#("counter", bson.Int32(5))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "counter"), Ok(bson.Int32(15)))
    Ok(Nil)
  })
}

pub fn update_inc_negative_test() {
  with_mongo("upd_inc_neg", fn(coll) {
    let doc = [#("counter", bson.Int32(10))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$inc",
            bson.Document(dict.from_list([#("counter", bson.Int32(-3))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "counter"), Ok(bson.Int32(7)))
    Ok(Nil)
  })
}

pub fn update_min_test() {
  with_mongo("upd_min", fn(coll) {
    let doc = [#("val", bson.Int32(10))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$min",
            bson.Document(dict.from_list([#("val", bson.Int32(5))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Int32(5)))
    Ok(Nil)
  })
}

pub fn update_min_no_change_test() {
  with_mongo("upd_min_no", fn(coll) {
    let doc = [#("val", bson.Int32(10))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(res) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$min",
            bson.Document(dict.from_list([#("val", bson.Int32(20))])),
          ),
        ],
        [],
        timeout,
      )
    should.equal(res.modified, 0)
    Ok(Nil)
  })
}

pub fn update_max_test() {
  with_mongo("upd_max", fn(coll) {
    let doc = [#("val", bson.Int32(10))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$max",
            bson.Document(dict.from_list([#("val", bson.Int32(20))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "val"), Ok(bson.Int32(20)))
    Ok(Nil)
  })
}

pub fn update_rename_test() {
  with_mongo("upd_rename", fn(coll) {
    let doc = [#("old_name", bson.String("value"))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$rename",
            bson.Document(dict.from_list([
              #("old_name", bson.String("new_name")),
            ])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "new_name"), Ok(bson.String("value")))
    should.equal(dict.get(fields, "old_name"), Error(Nil))
    Ok(Nil)
  })
}

pub fn update_push_array_test() {
  with_mongo("upd_push", fn(coll) {
    let doc = [#("tags", bson.Array([bson.String("a"), bson.String("b")]))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$push",
            bson.Document(dict.from_list([#("tags", bson.String("c"))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "tags"),
      Ok(bson.Array([bson.String("a"), bson.String("b"), bson.String("c")])),
    )
    Ok(Nil)
  })
}

pub fn update_push_each_test() {
  with_mongo("upd_push_each", fn(coll) {
    let doc = [#("tags", bson.Array([bson.String("a")]))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$push",
            bson.Document(dict.from_list([
              #(
                "tags",
                bson.Document(dict.from_list([
                  #(
                    "$each",
                    bson.Array([bson.String("b"), bson.String("c")]),
                  ),
                ])),
              ),
            ])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "tags"),
      Ok(bson.Array([
        bson.String("a"),
        bson.String("b"),
        bson.String("c"),
      ])),
    )
    Ok(Nil)
  })
}

pub fn update_pull_array_test() {
  with_mongo("upd_pull", fn(coll) {
    let doc = [
      #(
        "tags",
        bson.Array([bson.String("a"), bson.String("b"), bson.String("c")]),
      ),
    ]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$pull",
            bson.Document(dict.from_list([#("tags", bson.String("b"))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "tags"),
      Ok(bson.Array([bson.String("a"), bson.String("c")])),
    )
    Ok(Nil)
  })
}

pub fn update_add_to_set_test() {
  with_mongo("upd_addtoset", fn(coll) {
    let doc = [#("tags", bson.Array([bson.String("a"), bson.String("b")]))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$addToSet",
            bson.Document(dict.from_list([#("tags", bson.String("b"))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "tags"),
      Ok(bson.Array([bson.String("a"), bson.String("b")])),
    )

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$addToSet",
            bson.Document(dict.from_list([#("tags", bson.String("c"))])),
          ),
        ],
        [],
        timeout,
      )

    let fields2 = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields2, "tags"),
      Ok(bson.Array([bson.String("a"), bson.String("b"), bson.String("c")])),
    )
    Ok(Nil)
  })
}

pub fn update_set_multiple_fields_test() {
  with_mongo("upd_multi_set", fn(coll) {
    let doc = [
      #("a", bson.Int32(1)),
      #("b", bson.String("old")),
    ]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$set",
            bson.Document(dict.from_list([
              #("a", bson.Int32(99)),
              #("b", bson.String("new")),
              #("c", bson.Boolean(True)),
            ])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "a"), Ok(bson.Int32(99)))
    should.equal(dict.get(fields, "b"), Ok(bson.String("new")))
    should.equal(dict.get(fields, "c"), Ok(bson.Boolean(True)))
    Ok(Nil)
  })
}

pub fn update_insert_new_field_test() {
  with_mongo("upd_new_field", fn(coll) {
    let doc = [#("name", bson.String("Alice"))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$set",
            bson.Document(dict.from_list([#("age", bson.Int32(30))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(dict.get(fields, "name"), Ok(bson.String("Alice")))
    should.equal(dict.get(fields, "age"), Ok(bson.Int32(30)))
    Ok(Nil)
  })
}

pub fn update_many_with_inc_test() {
  with_mongo("upd_many_inc", fn(coll) {
    let docs = [
      [#("name", bson.String("A")), #("score", bson.Int32(10))],
      [#("name", bson.String("B")), #("score", bson.Int32(20))],
      [#("name", bson.String("C")), #("score", bson.Int32(30))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(res) =
      crud.update_many(
        coll,
        [],
        [#("$inc", bson.Document(dict.from_list([#("score", bson.Int32(5))])))],
        [],
        timeout,
      )
    should.equal(res.matched, 3)
    should.equal(res.modified, 3)
    Ok(Nil)
  })
}

pub fn update_push_to_nonexistent_array_test() {
  with_mongo("upd_push_new", fn(coll) {
    let doc = [#("name", bson.String("Alice"))]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let assert Ok(_) =
      crud.update_one(
        coll,
        [#("_id", id)],
        [
          #(
            "$push",
            bson.Document(dict.from_list([#("tags", bson.String("new"))])),
          ),
        ],
        [],
        timeout,
      )

    let fields = find_doc(coll, [#("_id", id)])
    should.equal(
      dict.get(fields, "tags"),
      Ok(bson.Array([bson.String("new")])),
    )
    Ok(Nil)
  })
}

// ---------------------------------------------------------------------------
// Index Operations
// ---------------------------------------------------------------------------

pub fn create_index_test() {
  with_mongo("idx_create", fn(coll) {
    let cmd = [
      #("createIndexes", bson.String(coll.name)),
      #(
        "indexes",
        bson.Array([
          bson.Document(dict.from_list([
            #("key", bson.Document(dict.from_list([#("email", bson.Int32(1))]))),
            #("name", bson.String("email_idx")),
          ])),
        ]),
      ),
    ]
    let assert Ok(_) = client.execute_command(coll, cmd, timeout)

    let list_cmd = [#("listIndexes", bson.String(coll.name))]
    let assert Ok(reply) = client.execute_command(coll, list_cmd, timeout)
    let assert Ok(bson.Document(cursor_doc)) = dict.get(reply, "cursor")
    let assert Ok(bson.Array(indexes)) = dict.get(cursor_doc, "firstBatch")
    should.equal(list.length(indexes) >= 2, True)
    Ok(Nil)
  })
}

pub fn create_unique_index_test() {
  with_mongo("idx_unique", fn(coll) {
    let cmd = [
      #("createIndexes", bson.String(coll.name)),
      #(
        "indexes",
        bson.Array([
          bson.Document(dict.from_list([
            #("key", bson.Document(dict.from_list([#("code", bson.Int32(1))]))),
            #("name", bson.String("code_unique")),
            #("unique", bson.Boolean(True)),
          ])),
        ]),
      ),
    ]
    let assert Ok(_) = client.execute_command(coll, cmd, timeout)

    let assert Ok(_) =
      crud.insert_one(coll, [#("code", bson.String("ABC"))], timeout)
    let assert Error(_) =
      crud.insert_one(coll, [#("code", bson.String("ABC"))], timeout)
    let assert Ok(_) =
      crud.insert_one(coll, [#("code", bson.String("DEF"))], timeout)
    Ok(Nil)
  })
}

pub fn create_compound_index_test() {
  with_mongo("idx_compound", fn(coll) {
    let cmd = [
      #("createIndexes", bson.String(coll.name)),
      #(
        "indexes",
        bson.Array([
          bson.Document(dict.from_list([
            #(
              "key",
              bson.Document(dict.from_list([
                #("last_name", bson.Int32(1)),
                #("first_name", bson.Int32(1)),
              ])),
            ),
            #("name", bson.String("name_idx")),
          ])),
        ]),
      ),
    ]
    let assert Ok(_) = client.execute_command(coll, cmd, timeout)

    let docs = [
      [
        #("last_name", bson.String("Smith")),
        #("first_name", bson.String("John")),
      ],
      [
        #("last_name", bson.String("Smith")),
        #("first_name", bson.String("Jane")),
      ],
      [
        #("last_name", bson.String("Jones")),
        #("first_name", bson.String("Bob")),
      ],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      crud.find_many(
        coll,
        [#("last_name", bson.String("Smith"))],
        [crud.Sort([#("first_name", bson.Int32(1))])],
        timeout,
      )
    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 2)
    Ok(Nil)
  })
}

pub fn drop_index_test() {
  with_mongo("idx_drop", fn(coll) {
    let create_cmd = [
      #("createIndexes", bson.String(coll.name)),
      #(
        "indexes",
        bson.Array([
          bson.Document(dict.from_list([
            #("key", bson.Document(dict.from_list([#("temp", bson.Int32(1))]))),
            #("name", bson.String("temp_idx")),
          ])),
        ]),
      ),
    ]
    let assert Ok(_) = client.execute_command(coll, create_cmd, timeout)

    let drop_cmd = [
      #("dropIndexes", bson.String(coll.name)),
      #("index", bson.String("temp_idx")),
    ]
    let assert Ok(_) = client.execute_command(coll, drop_cmd, timeout)

    let list_cmd = [#("listIndexes", bson.String(coll.name))]
    let assert Ok(reply) = client.execute_command(coll, list_cmd, timeout)
    let assert Ok(bson.Document(cursor_doc)) = dict.get(reply, "cursor")
    let assert Ok(bson.Array(indexes)) = dict.get(cursor_doc, "firstBatch")
    let has_temp_idx =
      list.any(indexes, fn(idx) {
        case idx {
          bson.Document(fields) ->
            dict.get(fields, "name") == Ok(bson.String("temp_idx"))
          _ -> False
        }
      })
    should.equal(has_temp_idx, False)
    Ok(Nil)
  })
}

// ---------------------------------------------------------------------------
// Aggregation Pipeline (extended)
// ---------------------------------------------------------------------------

pub fn aggregation_group_sum_test() {
  with_mongo("agg_group_sum", fn(coll) {
    let docs = [
      [#("dept", bson.String("eng")), #("salary", bson.Int32(100))],
      [#("dept", bson.String("eng")), #("salary", bson.Int32(120))],
      [#("dept", bson.String("sales")), #("salary", bson.Int32(90))],
      [#("dept", bson.String("sales")), #("salary", bson.Int32(110))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.group([
        #(
          "_id",
          bson.Document(dict.from_list([#("dept", bson.String("$dept"))])),
        ),
        #(
          "total",
          bson.Document(dict.from_list([#("$sum", bson.String("$salary"))])),
        ),
      ])
      |> aggregation.sort([#("_id", bson.Int32(1))])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 2)
    let assert [first, second] = results
    let assert bson.Document(f1) = first
    let assert bson.Document(f2) = second

    let assert Ok(bson.Document(id1)) = dict.get(f1, "_id")
    should.equal(dict.get(id1, "dept"), Ok(bson.String("eng")))
    should.equal(dict.get(f1, "total"), Ok(bson.Int32(220)))

    let assert Ok(bson.Document(id2)) = dict.get(f2, "_id")
    should.equal(dict.get(id2, "dept"), Ok(bson.String("sales")))
    should.equal(dict.get(f2, "total"), Ok(bson.Int32(200)))
    Ok(Nil)
  })
}

pub fn aggregation_group_avg_test() {
  with_mongo("agg_group_avg", fn(coll) {
    let docs = [
      [#("category", bson.String("a")), #("val", bson.Int32(10))],
      [#("category", bson.String("a")), #("val", bson.Int32(20))],
      [#("category", bson.String("a")), #("val", bson.Int32(30))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.group([
        #(
          "_id",
          bson.Document(dict.from_list([
            #("category", bson.String("$category")),
          ])),
        ),
        #(
          "avg_val",
          bson.Document(dict.from_list([#("$avg", bson.String("$val"))])),
        ),
      ])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    let assert [first] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "avg_val"), Ok(bson.Double(20.0)))
    Ok(Nil)
  })
}

pub fn aggregation_group_first_last_test() {
  with_mongo("agg_group_fstlst", fn(coll) {
    let docs = [
      [#("grp", bson.String("x")), #("order", bson.Int32(1)), #("val", bson.String("first"))],
      [#("grp", bson.String("x")), #("order", bson.Int32(2)), #("val", bson.String("mid"))],
      [#("grp", bson.String("x")), #("order", bson.Int32(3)), #("val", bson.String("last"))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.sort([#("order", bson.Int32(1))])
      |> aggregation.group([
        #(
          "_id",
          bson.Document(dict.from_list([#("grp", bson.String("$grp"))])),
        ),
        #(
          "first_val",
          bson.Document(dict.from_list([#("$first", bson.String("$val"))])),
        ),
        #(
          "last_val",
          bson.Document(dict.from_list([#("$last", bson.String("$val"))])),
        ),
      ])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    let assert [first] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "first_val"), Ok(bson.String("first")))
    should.equal(dict.get(f, "last_val"), Ok(bson.String("last")))
    Ok(Nil)
  })
}

pub fn aggregation_group_min_max_test() {
  with_mongo("agg_group_minmax", fn(coll) {
    let docs = [
      [#("grp", bson.String("a")), #("v", bson.Int32(5))],
      [#("grp", bson.String("a")), #("v", bson.Int32(15))],
      [#("grp", bson.String("b")), #("v", bson.Int32(3))],
      [#("grp", bson.String("b")), #("v", bson.Int32(99))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.group([
        #(
          "_id",
          bson.Document(dict.from_list([#("grp", bson.String("$grp"))])),
        ),
        #(
          "min_v",
          bson.Document(dict.from_list([#("$min", bson.String("$v"))])),
        ),
        #(
          "max_v",
          bson.Document(dict.from_list([#("$max", bson.String("$v"))])),
        ),
      ])
      |> aggregation.sort([#("_id", bson.Int32(1))])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    let assert [first, second] = results
    let assert bson.Document(f1) = first
    let assert bson.Document(f2) = second
    should.equal(dict.get(f1, "min_v"), Ok(bson.Int32(5)))
    should.equal(dict.get(f1, "max_v"), Ok(bson.Int32(15)))
    should.equal(dict.get(f2, "min_v"), Ok(bson.Int32(3)))
    should.equal(dict.get(f2, "max_v"), Ok(bson.Int32(99)))
    Ok(Nil)
  })
}

pub fn aggregation_project_test() {
  with_mongo("agg_project", fn(coll) {
    let doc = [
      #("first_name", bson.String("John")),
      #("last_name", bson.String("Doe")),
      #("age", bson.Int32(30)),
    ]
    let assert Ok(_) = crud.insert_one(coll, doc, timeout)

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.add_fields([
        #(
          "full_name",
          bson.Document(dict.from_list([
            #(
              "$concat",
              bson.Array([
                bson.String("$first_name"),
                bson.String(" "),
                bson.String("$last_name"),
              ]),
            ),
          ])),
        ),
      ])
      |> aggregation.project([
        #("full_name", bson.Int32(1)),
        #("age", bson.Int32(1)),
        #("_id", bson.Int32(0)),
      ])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    let assert [first] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "full_name"), Ok(bson.String("John Doe")))
    should.equal(dict.get(f, "age"), Ok(bson.Int32(30)))
    should.equal(dict.get(f, "first_name"), Error(Nil))
    Ok(Nil)
  })
}

pub fn aggregation_unwind_test() {
  with_mongo("agg_unwind", fn(coll) {
    let doc = [
      #("name", bson.String("Alice")),
      #("tags", bson.Array([bson.String("go"), bson.String("rust")])),
    ]
    let assert Ok(_) = crud.insert_one(coll, doc, timeout)

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.unwind("$tags", False)
      |> aggregation.sort([#("tags", bson.Int32(1))])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 2)
    let assert [first, second] = results
    let assert bson.Document(f1) = first
    let assert bson.Document(f2) = second
    should.equal(dict.get(f1, "tags"), Ok(bson.String("go")))
    should.equal(dict.get(f2, "tags"), Ok(bson.String("rust")))
    Ok(Nil)
  })
}

pub fn aggregation_unwind_preserve_null_test() {
  with_mongo("agg_unwind_null", fn(coll) {
    let assert Ok(_) =
      crud.insert_one(
        coll,
        [
          #("name", bson.String("Alice")),
          #("tags", bson.Array([bson.String("a")])),
        ],
        timeout,
      )
    let assert Ok(_) =
      crud.insert_one(
        coll,
        [
          #("name", bson.String("Bob")),
          #("tags", bson.Array([])),
        ],
        timeout,
      )
    let assert Ok(_) =
      crud.insert_one(
        coll,
        [#("name", bson.String("Charlie"))],
        timeout,
      )

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.unwind("$tags", True)
      |> aggregation.sort([#("name", bson.Int32(1))])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 3)
    Ok(Nil)
  })
}

pub fn aggregation_skip_limit_test() {
  with_mongo("agg_skip_lim", fn(coll) {
    let docs =
      make_range(1, 10) |> list.map(fn(i) { [#("n", bson.Int32(i))] })
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.sort([#("n", bson.Int32(1))])
      |> aggregation.skip(2)
      |> aggregation.limit(3)
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 3)
    let assert [first, ..] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "n"), Ok(bson.Int32(3)))
    Ok(Nil)
  })
}

pub fn aggregation_group_count_test() {
  with_mongo("agg_group_count", fn(coll) {
    let docs = [
      [#("type", bson.String("a"))],
      [#("type", bson.String("a"))],
      [#("type", bson.String("b"))],
    ]
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.group([
        #("_id", bson.Null),
        #(
          "count",
          bson.Document(dict.from_list([#("$sum", bson.Int32(1))])),
        ),
      ])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    let assert [first] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "count"), Ok(bson.Int32(3)))
    Ok(Nil)
  })
}

pub fn aggregation_lookup_test() {
  with_mongo("agg_lookup", fn(coll) {
    let authors = client.collection(coll.client, coll.name <> "_authors")
    let assert Ok(_) =
      crud.insert_one(
        authors,
        [#("_id", bson.Int32(1)), #("name", bson.String("Alice"))],
        timeout,
      )

    let assert Ok(_) =
      crud.insert_one(
        coll,
        [
          #("title", bson.String("Post 1")),
          #("author_id", bson.Int32(1)),
        ],
        timeout,
      )

    let assert Ok(_) =
      crud.insert_one(
        coll,
        [
          #("title", bson.String("Post 2")),
          #("author_id", bson.Int32(1)),
        ],
        timeout,
      )

    let assert Ok(c) =
      aggregation.aggregate(coll, [], timeout)
      |> aggregation.lookup(
        from: coll.name <> "_authors",
        local_field: "author_id",
        foreign_field: "_id",
        alias: "author",
      )
      |> aggregation.unwind("$author", False)
      |> aggregation.add_fields([
        #("author_name", bson.String("$author.name")),
      ])
      |> aggregation.project([
        #("title", bson.Int32(1)),
        #("author_name", bson.Int32(1)),
        #("_id", bson.Int32(0)),
      ])
      |> aggregation.to_cursor

    let results = cursor.to_list(c, timeout)
    should.equal(list.length(results), 2)
    let assert [first, ..] = results
    let assert bson.Document(f) = first
    should.equal(dict.get(f, "author_name"), Ok(bson.String("Alice")))
    Ok(Nil)
  })
}

// ---------------------------------------------------------------------------
// Write Edge Cases
// ---------------------------------------------------------------------------

pub fn insert_many_with_custom_ids_test() {
  with_mongo("w_custom_ids", fn(coll) {
    let docs = [
      [#("_id", bson.Int32(100)), #("name", bson.String("A"))],
      [#("_id", bson.Int32(200)), #("name", bson.String("B"))],
    ]
    let assert Ok(crud.InsertResult(inserted: 2, inserted_ids: ids)) =
      crud.insert_many(coll, docs, timeout)
    should.equal(ids, [bson.Int32(100), bson.Int32(200)])

    let fields = find_doc(coll, [#("_id", bson.Int32(100))])
    should.equal(dict.get(fields, "name"), Ok(bson.String("A")))
    Ok(Nil)
  })
}

pub fn update_upsert_nonexistent_test() {
  with_mongo("w_upsert_new", fn(coll) {
    let assert Ok(res) =
      crud.update_one(
        coll,
        [#("email", bson.String("new@test.com"))],
        [
          #(
            "$set",
            bson.Document(dict.from_list([#("name", bson.String("New User"))])),
          ),
        ],
        [crud.Upsert],
        timeout,
      )
    should.equal(list.length(res.upserted), 1)

    let fields = find_doc(coll, [#("email", bson.String("new@test.com"))])
    should.equal(dict.get(fields, "name"), Ok(bson.String("New User")))
    Ok(Nil)
  })
}

pub fn delete_many_no_match_test() {
  with_mongo("w_delmany_no", fn(coll) {
    let assert Ok(_) = crud.insert_one(coll, [#("x", bson.Int32(1))], timeout)
    let assert Ok(deleted) =
      crud.delete_many(coll, [#("x", bson.Int32(999))], timeout)
    should.equal(deleted, 0)
    let assert Ok(count) = crud.count_all(coll, timeout)
    should.equal(count, 1)
    Ok(Nil)
  })
}

pub fn insert_delete_all_test() {
  with_mongo("w_ins_delall", fn(coll) {
    let docs =
      make_range(1, 3) |> list.map(fn(i) { [#("a", bson.Int32(i))] })
    let assert Ok(_) = crud.insert_many(coll, docs, timeout)
    let assert Ok(count) = crud.count_all(coll, timeout)
    should.equal(count, 3)

    let assert Ok(deleted) = crud.delete_many(coll, [], timeout)
    should.equal(deleted, 3)

    let assert Ok(count2) = crud.count_all(coll, timeout)
    should.equal(count2, 0)
    Ok(Nil)
  })
}

pub fn nested_array_filter_test() {
  with_mongo("w_nested_filter", fn(coll) {
    let doc = [
      #(
        "matrix",
        bson.Array([
          bson.Array([bson.Int32(1), bson.Int32(2)]),
          bson.Array([bson.Int32(3), bson.Int32(4)]),
        ]),
      ),
    ]
    let assert Ok(id) = crud.insert_one(coll, doc, timeout)

    let fields = find_doc(coll, [#("_id", id)])
    let assert Ok(bson.Array(matrix)) = dict.get(fields, "matrix")
    should.equal(list.length(matrix), 2)
    let assert [bson.Array(row1), _] = matrix
    should.equal(list.length(row1), 2)
    Ok(Nil)
  })
}

pub fn session_start_test() {
  with_mongo("w_session", fn(coll) {
    let assert Ok(sess) = session.start(coll.client, timeout)
    let sid = session.session_id(sess)
    should.be_true(bit_array.byte_size(sid) > 0)
    should.equal(session.is_active(sess), False)
    let sess2 = session.start_transaction(sess)
    should.equal(session.is_active(sess2), True)
    should.equal(session.txn_number(sess2), 1)
    let _ = session.end(sess2, timeout)
    Ok(Nil)
  })
}

pub fn bulk_insert_test() {
  with_mongo("w_bulk_insert", fn(coll) {
    let ops = [
      bulk.InsertOne([#("x", bson.Int32(1))]),
      bulk.InsertOne([#("x", bson.Int32(2))]),
      bulk.InsertOne([#("x", bson.Int32(3))]),
    ]
    let assert Ok(result) = bulk.bulk_write(coll, ops, True, timeout)
    should.equal(result.inserted, 3)
    let assert Ok(count) = crud.count_all(coll, timeout)
    should.equal(count, 3)
    Ok(Nil)
  })
}

pub fn bulk_mixed_ops_test() {
  with_mongo("w_bulk_mixed", fn(coll) {
    let assert Ok(_) = crud.insert_one(coll, [#("x", bson.Int32(1))], timeout)
    let ops = [
      bulk.InsertOne([#("x", bson.Int32(2))]),
      bulk.UpdateOne(
        filter: [#("x", bson.Int32(1))],
        update: [#("$set", bson.Document(dict.from_list([#("x", bson.Int32(10))])))],
        upsert: False,
      ),
      bulk.DeleteOne(filter: [#("x", bson.Int32(2))]),
    ]
    let assert Ok(result) = bulk.bulk_write(coll, ops, True, timeout)
    should.equal(result.inserted, 1)
    should.equal(result.matched, 1)
    should.equal(result.deleted, 1)
    let assert Ok(count) = crud.count_all(coll, timeout)
    should.equal(count, 1)
    Ok(Nil)
  })
}

pub fn list_databases_test() {
  with_mongo("w_listdb", fn(coll) {
    let assert Ok(dbs) = admin.list_databases(coll.client, timeout)
    should.be_true(dbs != [])
    let db_names = list.map(dbs, fn(db) { db.name })
    should.be_true(list.contains(db_names, "admin"))
    Ok(Nil)
  })
}

pub fn list_collections_test() {
  with_mongo("w_listcol", fn(coll) {
    let assert Ok(_) = crud.insert_one(coll, [#("a", bson.Int32(1))], timeout)
    let db_coll = client.Collection("mungo_test", "mungo_test", coll.client)
    let assert Ok(cols) = admin.list_collections(db_coll, timeout)
    should.be_true(cols != [])
    should.be_true(list.contains(cols, "w_listcol"))
    Ok(Nil)
  })
}

pub fn distinct_test() {
  with_mongo("w_distinct", fn(coll) {
    let assert Ok(_) = crud.insert_one(coll, [#("color", bson.String("red"))], timeout)
    let assert Ok(_) = crud.insert_one(coll, [#("color", bson.String("blue"))], timeout)
    let assert Ok(_) = crud.insert_one(coll, [#("color", bson.String("red"))], timeout)
    let assert Ok(values) = crud.distinct(coll, "color", [], timeout)
    should.equal(list.length(values), 2)
    Ok(Nil)
  })
}

pub fn find_and_modify_test() {
  with_mongo("w_fam", fn(coll) {
    let assert Ok(_) = crud.insert_one(coll, [
      #("x", bson.Int32(1)),
      #("y", bson.Int32(10)),
    ], timeout)
    let assert Ok(result) = crud.find_and_modify(
      coll,
      [#("x", bson.Int32(1))],
      option.Some([#("$set", bson.Document(dict.from_list([#("y", bson.Int32(99))])))]),
      option.None,
      [],
      False,
      False,
      True,
      timeout,
    )
    case result {
      option.Some(bson.Document(fields)) -> {
        let assert Ok(bson.Int32(y)) = dict.get(fields, "y")
        should.equal(y, 99)
      }
      _ -> panic as "Expected document"
    }
    Ok(Nil)
  })
}
