pub type TlsSocket

pub fn connect(host: String, port: Int, timeout: Int) -> Result(TlsSocket, String) {
  tls_connect(host, port, timeout)
}

pub fn execute(
  socket: TlsSocket,
  packet: BitArray,
  timeout: Int,
) -> Result(BitArray, String) {
  case tls_send(socket, packet) {
    Ok(Nil) -> {
      tls_set_active_once(socket)
      tls_receive(socket, timeout)
    }
    Error(err) -> Error(err)
  }
}

@external(erlang, "mungo_tls_ffi", "connect")
fn tls_connect(host: String, port: Int, timeout: Int) -> Result(TlsSocket, String)

@external(erlang, "mungo_tls_ffi", "send")
fn tls_send(socket: TlsSocket, packet: BitArray) -> Result(Nil, String)

@external(erlang, "mungo_tls_ffi", "set_active_once")
fn tls_set_active_once(socket: TlsSocket) -> Nil

@external(erlang, "mungo_tls_ffi", "receive_packet")
fn tls_receive(socket: TlsSocket, timeout: Int) -> Result(BitArray, String)

@external(erlang, "mungo_tls_ffi", "close")
pub fn close(socket: TlsSocket) -> Nil
