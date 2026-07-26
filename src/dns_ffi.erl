-module(dns_ffi).
-export([srv_lookup/1, txt_lookup/1]).

%% Returns {ok, [{Host, Port}, ...]} sorted by priority, or {error, nil}.
srv_lookup(Name) ->
    case inet_res:lookup(binary_to_list(Name), in, srv) of
        [] -> {error, nil};
        Records ->
            Sorted = lists:sort(fun({P1, _, _, _}, {P2, _, _, _}) -> P1 =< P2 end, Records),
            Hosts = [{list_to_binary(strip_dot(Target)), Port} || {_Prio, _Weight, Port, Target} <- Sorted],
            {ok, Hosts}
    end.

%% Returns {ok, Options} joining all TXT chunks, or {error, nil} if none.
txt_lookup(Name) ->
    case inet_res:lookup(binary_to_list(Name), in, txt) of
        [] -> {error, nil};
        Records ->
            Joined = lists:flatten([lists:concat(Chunks) || Chunks <- Records]),
            {ok, list_to_binary(Joined)}
    end.

strip_dot(Str) ->
    case lists:reverse(Str) of
        [$. | Rest] -> lists:reverse(Rest);
        _ -> Str
    end.
