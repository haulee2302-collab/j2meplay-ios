import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../jvm/midp.dart';
import '../jvm/vm.dart';
import 'proxy.dart';

/// Kết nối mạng một MIDlet: socket:// (TCP, có proxy SOCKS5/HTTP) và http(s)://.
class NetConn {
  final String url;
  final StreamIn input = StreamIn(Uint8List(0))..live = true;
  final StreamOut output = StreamOut();
  Socket? sock;
  bool connected = false, failed = false, closed = false;
  String? err;
  bool isHttp = false;
  // HTTP
  String method = 'GET';
  final Map<String, String> reqHeaders = {};
  final Map<String, String> respHeaders = {};
  int code = 0;
  String message = '';
  bool httpStarted = false, httpDone = false;
  int length = -1;
  String? type;
  NetConn(this.url);

  // ---- bộ đệm bắt tay proxy ----
  final BytesBuilder _hs = BytesBuilder();
  Completer<void>? _wait;
  bool _handshaking = true;

  void _onData(Uint8List d) {
    if (_handshaking) {
      _hs.add(d);
      final w = _wait;
      if (w != null && !w.isCompleted) w.complete();
    } else {
      input.add(d);
    }
  }

  Future<Uint8List> _take(int n) async {
    while (_hs.length < n) {
      _wait = Completer<void>();
      await _wait!.future.timeout(const Duration(seconds: 20));
    }
    final all = _hs.takeBytes();
    if (all.length > n) _hs.add(all.sublist(n));
    return Uint8List.sublistView(all, 0, n);
  }

  Future<void> connect(String host, int port, LocalProxy? px) async {
    try {
      final s = await Socket.connect(px?.host ?? host, px?.port ?? port, timeout: const Duration(seconds: 20));
      s.setOption(SocketOption.tcpNoDelay, true);
      sock = s;
      s.listen(_onData, onDone: () {
        input.closed = true;
        closed = true;
      }, onError: (e) {
        input.error = '$e';
        input.closed = true;
        closed = true;
      }, cancelOnError: true);
      if (px != null) {
        if (px.type == 'socks5') {
          final hasAuth = px.user.isNotEmpty;
          s.add(hasAuth ? [5, 2, 0, 2] : [5, 1, 0]);
          final r = await _take(2);
          if (r[1] == 2) {
            final u = utf8.encode(px.user), p = utf8.encode(px.pass);
            s.add([1, u.length, ...u, p.length, ...p]);
            final a = await _take(2);
            if (a[1] != 0) throw 'Proxy từ chối tài khoản';
          } else if (r[1] != 0) {
            throw 'Proxy không hỗ trợ xác thực';
          }
          final h = utf8.encode(host);
          s.add([5, 1, 0, 3, h.length, ...h, port >> 8, port & 255]);
          final hd = await _take(4);
          if (hd[1] != 0) throw 'Proxy không kết nối được (mã ${hd[1]})';
          if (hd[3] == 1) {
            await _take(6);
          } else if (hd[3] == 3) {
            final l = (await _take(1))[0];
            await _take(l + 2);
          } else {
            await _take(18);
          }
        } else {
          final auth = px.user.isEmpty ? '' : 'Proxy-Authorization: Basic ${base64Encode(utf8.encode('${px.user}:${px.pass}'))}\r\n';
          s.add(utf8.encode('CONNECT $host:$port HTTP/1.1\r\nHost: $host:$port\r\n$auth\r\n'));
          final buf = <int>[];
          while (true) {
            buf.addAll(await _take(1));
            if (buf.length >= 4 && buf[buf.length - 1] == 10 && buf[buf.length - 2] == 13 && buf[buf.length - 3] == 10 && buf[buf.length - 4] == 13) break;
            if (buf.length > 8192) throw 'Phản hồi proxy không hợp lệ';
          }
          final line = String.fromCharCodes(buf).split('\r\n').first;
          if (!line.contains(' 200')) throw 'Proxy HTTP: $line';
        }
      }
      _handshaking = false;
      final rest = _hs.takeBytes();
      if (rest.isNotEmpty) input.add(rest);
      connected = true;
      output.sink = (d) {
        if (!closed) s.add(d);
      };
    } catch (e) {
      failed = true;
      err = '$e';
      input.closed = true;
      closed = true;
      try { sock?.destroy(); } catch (_) {}
    }
  }

  Future<void> runHttp(LocalProxy? px) async {
    httpStarted = true;
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      if (px != null && px.type == 'http') {
        c.findProxy = (_) => 'PROXY ${px.host}:${px.port}';
        if (px.user.isNotEmpty) c.addProxyCredentials(px.host, px.port, '', HttpClientBasicCredentials(px.user, px.pass));
      }
      final req = await c.openUrl(method, Uri.parse(url));
      reqHeaders.forEach((k, v) => req.headers.set(k, v));
      final body = output.b.takeBytes();
      if (body.isNotEmpty) req.add(body);
      final resp = await req.close().timeout(const Duration(seconds: 40));
      code = resp.statusCode;
      message = resp.reasonPhrase;
      resp.headers.forEach((k, v) => respHeaders[k.toLowerCase()] = v.join(','));
      length = resp.contentLength;
      type = resp.headers.contentType?.toString();
      final data = await resp.fold<BytesBuilder>(BytesBuilder(), (b, d) { b.add(d); return b; });
      input.add(data.takeBytes());
      input.closed = true;
      c.close();
    } catch (e) {
      failed = true;
      err = '$e';
      input.closed = true;
    }
    httpDone = true;
  }

  void close() {
    closed = true;
    input.closed = true;
    try { sock?.destroy(); } catch (_) {}
  }
}

/// Kiểm tra proxy thật: mở kết nối TCP tới api.ipify.org:80 qua proxy rồi đọc địa chỉ IP trả về.
Future<String> testProxy(LocalProxy px) async {
  final c = NetConn('test');
  await c.connect('api.ipify.org', 80, px);
  if (c.failed) return 'Lỗi: ${c.err}';
  c.output.sink?.call(utf8.encode('GET / HTTP/1.0\r\nHost: api.ipify.org\r\nConnection: close\r\n\r\n'));
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end) && !c.input.closed) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  final text = String.fromCharCodes(c.input.b.sublist(c.input.p));
  c.close();
  final i = text.indexOf('\r\n\r\n');
  final body = (i >= 0 ? text.substring(i + 4) : text).trim();
  if (!text.startsWith('HTTP/')) return 'Không nhận được phản hồi từ máy chủ kiểm tra';
  return 'Proxy hoạt động. IP ra ngoài: $body';
}

void installNet(Midp midp, LocalProxy? proxy) {
  final vm = midp.vm;
  const obj = 'java/lang/Object';
  const C = 'javax/microedition/io/\$Conn';
  const ifs = [
    'javax/microedition/io/Connection', 'javax/microedition/io/InputConnection', 'javax/microedition/io/OutputConnection',
    'javax/microedition/io/StreamConnection', 'javax/microedition/io/ContentConnection', 'javax/microedition/io/HttpConnection',
    'javax/microedition/io/SocketConnection',
  ];
  for (final n in ifs) {
    vm.defClass(n, null, isInterface: true);
  }
  vm.defClass(C, obj, ifaces: ifs);
  vm.defClass('javax/microedition/io/HttpsConnection', null, isInterface: true);

  int i(List a, int k) => a[k] as int;
  JObject s(String v) => vm.str(v);
  String ss(dynamic o) {
    if (o == null) throw vm.ex('java/lang/NullPointerException');
    return (o as JObject).native as String;
  }
  NetConn nc(dynamic o) => (o as JObject).native as NetConn;
  void all(String name, String desc, NativeFn f) {
    vm.reg(C, name, desc, f);
    for (final n in ifs) {
      vm.reg(n, name, desc, f);
    }
  }

  JObject streamObj(String cls, Object native) {
    final o = JObject(vm.loadClass(cls));
    o.native = native;
    return o;
  }

  dynamic open(JThread t, String url) {
    final m = RegExp(r'^(\w+):(?://)?([^:/;]*)(?::(\d+))?(.*)$').firstMatch(url);
    if (m == null) throw vm.ex('javax/microedition/io/ConnectionNotFoundException', url);
    final scheme = m.group(1)!.toLowerCase();
    final c = NetConn(url);
    final o = JObject(vm.loadClass(C))..native = c;
    if (scheme == 'socket') {
      final host = m.group(2)!;
      final port = int.tryParse(m.group(3) ?? '') ?? 0;
      if (host.isEmpty || port == 0) throw vm.ex('java/lang/IllegalArgumentException', url);
      vm.onLog?.call('Kết nối socket $host:$port${proxy != null ? ' qua proxy ${proxy.label}' : ''}');
      unawaited(c.connect(host, port, proxy));
      return vm.block(t, () => c.connected || c.failed, () {
        if (c.failed) {
          vm.onLog?.call('Kết nối thất bại: ${c.err}');
          throw vm.ex('java/io/IOException', c.err ?? 'Không kết nối được');
        }
        return o;
      }, placeholder: o);
    }
    if (scheme == 'http' || scheme == 'https') {
      c.isHttp = true;
      return o;
    }
    throw vm.ex('javax/microedition/io/ConnectionNotFoundException', 'Chưa hỗ trợ $scheme://');
  }

  const K = 'javax/microedition/io/Connector';
  vm.reg(K, 'open', '(Ljava/lang/String;)Ljavax/microedition/io/Connection;', (v, t, a) => open(t, ss(a[0])), isStatic: true);
  vm.reg(K, 'open', '(Ljava/lang/String;I)Ljavax/microedition/io/Connection;', (v, t, a) => open(t, ss(a[0])), isStatic: true);
  vm.reg(K, 'open', '(Ljava/lang/String;IZ)Ljavax/microedition/io/Connection;', (v, t, a) => open(t, ss(a[0])), isStatic: true);

  // HTTP: chạy yêu cầu khi cần kết quả
  dynamic http(JThread t, NetConn c, dynamic Function() f, {int slots = 1}) {
    if (!c.isHttp) return f();
    if (!c.httpStarted) unawaited(c.runHttp(proxy));
    return vm.block(t, () => c.httpDone, f, slots: slots);
  }

  all('setRequestMethod', '(Ljava/lang/String;)V', (v, t, a) { nc(a[0]).method = ss(a[1]); return null; });
  all('setRequestProperty', '(Ljava/lang/String;Ljava/lang/String;)V', (v, t, a) { nc(a[0]).reqHeaders[ss(a[1])] = ss(a[2]); return null; });
  all('getRequestMethod', '()Ljava/lang/String;', (v, t, a) => s(nc(a[0]).method));
  all('getResponseCode', '()I', (v, t, a) {
    final c = nc(a[0]);
    return http(t, c, () {
      if (c.failed) throw v.ex('java/io/IOException', c.err);
      return c.code;
    });
  });
  all('getResponseMessage', '()Ljava/lang/String;', (v, t, a) {
    final c = nc(a[0]);
    return http(t, c, () => s(c.message));
  });
  all('getHeaderField', '(Ljava/lang/String;)Ljava/lang/String;', (v, t, a) {
    final c = nc(a[0]);
    return http(t, c, () {
      final r = c.respHeaders[ss(a[1]).toLowerCase()];
      return r == null ? null : s(r);
    });
  });
  all('getLength', '()J', (v, t, a) {
    final c = nc(a[0]);
    return http(t, c, () => c.length, slots: 2);
  });
  all('getType', '()Ljava/lang/String;', (v, t, a) {
    final c = nc(a[0]);
    return http(t, c, () => c.type == null ? null : s(c.type!));
  });
  all('getURL', '()Ljava/lang/String;', (v, t, a) => s(nc(a[0]).url));
  all('getEncoding', '()Ljava/lang/String;', (v, t, a) => null);
  all('openInputStream', '()Ljava/io/InputStream;', (v, t, a) {
    final c = nc(a[0]);
    return http(t, c, () {
      if (c.failed && c.isHttp) throw v.ex('java/io/IOException', c.err);
      return streamObj('java/io/DataInputStream', c.input);
    });
  });
  all('openDataInputStream', '()Ljava/io/DataInputStream;', (v, t, a) {
    final c = nc(a[0]);
    return http(t, c, () {
      if (c.failed && c.isHttp) throw v.ex('java/io/IOException', c.err);
      return streamObj('java/io/DataInputStream', c.input);
    });
  });
  all('openOutputStream', '()Ljava/io/OutputStream;', (v, t, a) => streamObj('java/io/DataOutputStream', nc(a[0]).output));
  all('openDataOutputStream', '()Ljava/io/DataOutputStream;', (v, t, a) => streamObj('java/io/DataOutputStream', nc(a[0]).output));
  all('close', '()V', (v, t, a) { nc(a[0]).close(); return null; });
  all('setSocketOption', '(BI)V', (v, t, a) => null);
  all('getSocketOption', '(B)I', (v, t, a) => 0);
  all('getAddress', '()Ljava/lang/String;', (v, t, a) => s(nc(a[0]).sock?.remoteAddress.address ?? ''));
  all('getLocalAddress', '()Ljava/lang/String;', (v, t, a) => s('127.0.0.1'));
  all('getPort', '()I', (v, t, a) => nc(a[0]).sock?.remotePort ?? 0);
  all('getLocalPort', '()I', (v, t, a) => nc(a[0]).sock?.port ?? 0);

  vm.reg(K, 'openInputStream', '(Ljava/lang/String;)Ljava/io/InputStream;', (v, t, a) {
    final c = open(t, ss(a[0]));
    return v.callVirtual(c, 'openInputStream', '()Ljava/io/InputStream;', const []);
  }, isStatic: true);
  vm.reg(K, 'openDataInputStream', '(Ljava/lang/String;)Ljava/io/DataInputStream;', (v, t, a) {
    final c = open(t, ss(a[0]));
    return v.callVirtual(c, 'openDataInputStream', '()Ljava/io/DataInputStream;', const []);
  }, isStatic: true);
  vm.reg(K, 'openOutputStream', '(Ljava/lang/String;)Ljava/io/OutputStream;', (v, t, a) {
    final c = open(t, ss(a[0]));
    return v.callVirtual(c, 'openOutputStream', '()Ljava/io/OutputStream;', const []);
  }, isStatic: true);
  vm.reg(K, 'openDataOutputStream', '(Ljava/lang/String;)Ljava/io/DataOutputStream;', (v, t, a) {
    final c = open(t, ss(a[0]));
    return v.callVirtual(c, 'openDataOutputStream', '()Ljava/io/DataOutputStream;', const []);
  }, isStatic: true);
  // java.net.Socket
  const SK = 'java/net/Socket';
  vm.defClass(SK, obj);
  vm.reg(SK, '<init>', '(Ljava/lang/String;I)V', (v, t, a) {
    final host = ss(a[1]);
    final port = i(a, 2);
    final c = NetConn('socket://$host:$port');
    (a[0] as JObject).native = c;
    vm.onLog?.call('Socket $host:$port${proxy != null ? ' qua proxy ${proxy.label}' : ''}');
    unawaited(c.connect(host, port, proxy));
    return vm.block(t, () => c.connected || c.failed, () {
      if (c.failed) throw v.ex('java/io/IOException', c.err ?? 'Không kết nối được');
      return null;
    });
  });
  vm.reg(SK, 'getInputStream', '()Ljava/io/InputStream;', (v, t, a) => streamObj('java/io/DataInputStream', nc(a[0]).input));
  vm.reg(SK, 'getOutputStream', '()Ljava/io/OutputStream;', (v, t, a) => streamObj('java/io/DataOutputStream', nc(a[0]).output));
  vm.reg(SK, 'close', '()V', (v, t, a) { nc(a[0]).close(); return null; });
  vm.reg(SK, 'setSoTimeout', '(I)V', (v, t, a) => null);
  vm.reg(SK, 'setTcpNoDelay', '(Z)V', (v, t, a) => null);
  vm.reg(SK, 'setKeepAlive', '(Z)V', (v, t, a) => null);
  vm.reg(SK, 'isClosed', '()Z', (v, t, a) => 0);
  vm.reg(SK, 'isConnected', '()Z', (v, t, a) => 1);

  // đảm bảo i() không bị báo thừa
  assert(i(const [0], 0) == 0);
}
