-module(persistent_term_ffi).
-export([get/1, set/2]).

get(Key) ->
    try {ok, persistent_term:get(Key)}
    catch error:badarg -> {error, nil}
    end.

set(Key, Value) ->
    persistent_term:put(Key, Value),
    ok.
