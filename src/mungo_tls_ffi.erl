-module(mungo_tls_ffi).
-export([
    connect/2,
    connect/3,
    send/2,
    receive_packet/2,
    close/1
]).

connect(Host, Port) ->
    connect(Host, Port, 5000).

connect(Host, Port, Timeout) ->
    application:ensure_all_started(ssl),
    HostList = case is_binary(Host) of
        true -> binary_to_list(Host);
        false -> Host
    end,
    Result = ssl:connect(HostList, Port, [
        {active, false},
        {packet, raw},
        binary,
        {verify, verify_peer},
        {cacerts, public_key:cacerts_get()},
        {server_name_indication, HostList},
        {customize_hostname_check,
            [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}
    ], Timeout),
    case Result of
        {ok, Socket} -> {ok, Socket};
        {error, Reason} -> {error, format_error(Reason)}
    end.

send(Socket, Packet) ->
    case ssl:send(Socket, Packet) of
        ok -> {ok, nil};
        {error, Reason} -> {error, format_error(Reason)}
    end.

%% Reads exactly one MongoDB wire-protocol message. The first 4 bytes are the
%% little-endian total messageLength (including those 4 bytes), so we frame on
%% it instead of assuming a reply fits in a single TLS record.
receive_packet(Socket, Timeout) ->
    case ssl:recv(Socket, 4, Timeout) of
        {ok, <<Size:32/little-unsigned>> = Header} when Size >= 4 ->
            case Size - 4 of
                0 -> {ok, Header};
                Rest ->
                    case ssl:recv(Socket, Rest, Timeout) of
                        {ok, Body} -> {ok, <<Header/binary, Body/binary>>};
                        {error, Reason} -> {error, format_error(Reason)}
                    end
            end;
        {ok, _} -> {error, <<"Invalid message length">>};
        {error, Reason} -> {error, format_error(Reason)}
    end.

close(Socket) ->
    ssl:close(Socket).

format_error(Reason) when is_binary(Reason) -> Reason;
format_error(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).
