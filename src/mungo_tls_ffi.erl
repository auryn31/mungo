-module(mungo_tls_ffi).
-export([
    connect/2,
    connect/3,
    send/2,
    set_active_once/1,
    receive_packet/2,
    close/1
]).

connect(Host, Port) ->
    connect(Host, Port, 5000).

connect(Host, Port, Timeout) ->
    ssl:start(),
    HostList = case is_binary(Host) of
        true -> binary_to_list(Host);
        false -> Host
    end,
    ssl:connect(HostList, Port, [
        {active, false},
        {packet, raw},
        binary,
        {verify, verify_peer},
        {cacerts, public_key:cacerts_get()},
        {server_name_indication, HostList},
        {customize_hostname_check,
            [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}
    ], Timeout).

send(Socket, Packet) ->
    case ssl:send(Socket, Packet) of
        ok -> {ok, nil};
        Err -> Err
    end.

set_active_once(Socket) ->
    ssl:setopts(Socket, [{active, once}]).

receive_packet(Socket, Timeout) ->
    receive
        {ssl, Socket, Data} ->
            {ok, Data};
        {ssl_closed, Socket} ->
            {error, closed};
        {ssl_error, Socket, Reason} ->
            {error, Reason}
    after Timeout ->
        {error, timeout}
    end.

close(Socket) ->
    ssl:close(Socket).
