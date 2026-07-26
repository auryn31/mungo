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
    ssl:connect(Host, Port, [
        {active, false},
        {packet, raw},
        binary,
        {timeout, Timeout}
    ], Timeout).

send(Socket, Packet) ->
    ssl:send(Socket, Packet).

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
