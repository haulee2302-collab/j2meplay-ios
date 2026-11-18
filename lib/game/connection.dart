import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

import '../api.dart';
import 'jpc.dart';

/// Thông tin truy cập máy chủ J2ME của phiên (dùng cho chọn / tải JAR).
class Access {
  final String origin, sessionId, ticket, viewKey;
  Access(this.origin, this.sessionId, this.ticket, this.viewKey);
}

class _Frame {
  final IOWebSocketChannel ws;
  final Uint8List data;
  final int seq;
  final int arrivedAt;
  _Frame(this.ws, this.data, this.seq, this.arrivedAt);
}

int _now() => DateTime.now().millisecondsSinceEpoch;

/// Một phiên xem màn hình J2ME (bản Dart của GameConnection.kt):
/// vé VIEW (web) → thông tin xem (máy chủ J2ME) → websocket JPC1 → giải nén → hàng đợi → vẽ → ack.
class GameConnection extends ChangeNotifier {
  final String rentalId;
  GameConnection(this.rentalId);

  // ---- trạng thái cho giao diện ----
  String statusText = 'Xin chờ';
  bool statusError = false;
  bool loading = true;
  bool ready = false; // máy chủ cho phép gửi thao tác
  bool noGame = false;
  bool jarBlocked = false;
  bool firstFrame = false;
  int frameW = 0, frameH = 0;
  Map<String, dynamic>? runtime;
  ui.Image? image;
  Access? access;

  final Api _api = Api.instance;
  final JpcRenderer _renderer = JpcRenderer();

  int _gen = 0;
  IOWebSocketChannel? _socket;
  StreamSubscription? _sub;
  bool _stopped = false;
  bool _paused = false;
  bool _needKeyFrame = true;
  bool _keyFrameRequested = false;
  int _attempt = 0;
  Timer? _retry;
  final List<_Frame> _queue = [];
  bool _draining = false;
  int _lastPresentAt = 0;
  final Map<String, Completer<Map<String, dynamic>?>> _pending = {};
  int _reqSeq = 0;
  final _rnd = math.Random.secure();

  void _notify() {
    if (!_stopped) notifyListeners();
  }

  void _status(String text, {bool error = false, bool? isLoading}) {
    statusText = text;
    statusError = error;
    loading = isLoading ?? !error;
    if (error && RegExp('JAR ghép', caseSensitive: false).hasMatch(text)) jarBlocked = true;
    _notify();
  }

  void _setReady(bool v) {
    if (ready == v) return;
    ready = v;
    _notify();
  }

  // ---------------- vòng đời ----------------
  void start() {
    _stopped = false;
    _paused = false;
    _connect();
  }

  @override
  void dispose() {
    _stopped = true;
    _gen++;
    _retry?.cancel();
    _closeSocket();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    _queue.clear();
    _renderer.close();
    image?.dispose();
    image = null;
    super.dispose();
  }

  void pause() {
    _paused = true;
    _closeSocket();
  }

  void resume() {
    if (_stopped) return;
    if (_paused) {
      _paused = false;
      _attempt = 0;
      _connect();
    }
  }

  void reload() {
    if (_stopped) return;
    _attempt = 0;
    _paused = false;
    noGame = false;
    _closeSocket();
    _connect();
  }

  void _closeSocket() {
    final s = _socket;
    _socket = null;
    _sub?.cancel();
    _sub = null;
    _setReady(false);
    try { s?.sink.close(1000, 'Closed'); } catch (_) {}
  }

  void _scheduleReconnect([int? delayMs]) {
    if (_stopped || _paused) return;
    final a = ++_attempt;
    final wait = delayMs ?? math.min(20000, (500 * math.pow(1.7, math.min(a - 1, 8))).round());
    _status('Xin chờ');
    final myGen = _gen;
    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: wait), () {
      if (_gen == myGen) _connect();
    });
  }

  // ---------------- vé + thông tin xem ----------------
  String _b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  String _newViewKey() => _b64url(List<int>.generate(32, (_) => _rnd.nextInt(256)));
  String _hash(String key) => _b64url(sha256.convert(utf8.encode(key)).bytes);

  void _connect() {
    if (_stopped) return;
    final myGen = ++_gen;
    _closeSocket();
    _retry?.cancel();
    _connectFlow(myGen).catchError((Object e) {
      if (_gen == myGen && !_stopped) {
        _status(e.toString(), isLoading: false);
        _scheduleReconnect();
      }
    });
  }

  Future<void> _connectFlow(int myGen) async {
    _status('Xin chờ');
    final viewKey = _newViewKey();
    final (code, json, _) = await _api.rawPost('/api/site/rentals/${Uri.encodeComponent(rentalId)}/ticket', {'viewKeyHash': _hash(viewKey)});
    if (_gen != myGen) return;
    if (code == 202 || json?['recovering'] == true) {
      final m = '${json?['message'] ?? ''}';
      _status(m.isEmpty ? 'Xin chờ' : m);
      _scheduleReconnect(1500);
      return;
    }
    final acc = json?['access'];
    if (code < 200 || code >= 300 || acc is! Map) {
      final m = '${json?['error'] ?? ''}';
      final msg = m.isEmpty ? 'Không kết nối được màn hình (mã $code)' : m;
      if (code == 401 || code == 403 || code == 404) {
        _status(msg, error: true, isLoading: false);
      } else if (code == 409) {
        _status(msg, isLoading: false);
        _scheduleReconnect(5000);
      } else {
        _status(msg, isLoading: false);
        _scheduleReconnect();
      }
      return;
    }
    final serverUrl = '${acc['serverUrl'] ?? ''}'.isNotEmpty ? '${acc['serverUrl']}' : '${acc['url'] ?? ''}';
    String origin = '';
    try {
      final u = Uri.parse(serverUrl);
      origin = '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
    } catch (_) {}
    if (origin.isEmpty || !origin.contains('://') || origin.startsWith('://')) {
      _status('Địa chỉ máy chủ không hợp lệ.', error: true, isLoading: false);
      return;
    }
    final a = Access(origin, '${acc['sessionId'] ?? ''}', '${acc['ticket'] ?? ''}', viewKey);
    access = a;

    final deadline = _now() + 45000;
    var pause = 300;
    Map<String, dynamic> meta;
    final notReady = RegExp('runner.*sẵn sàng|chưa sẵn sàng|đang được khôi phục', caseSensitive: false);
    while (true) {
      final (mc, mj) = await sessionRequest(a, 'GET', '/api/public-session?id=${Uri.encodeQueryComponent(a.sessionId)}');
      if (_gen != myGen) return;
      if (mc < 200 || mc >= 300 || mj == null) {
        final err = '${mj?['error'] ?? ''}';
        if (notReady.hasMatch(err) && _now() < deadline) {
          await Future.delayed(Duration(milliseconds: pause));
          pause = math.min(2000, pause * 3 ~/ 2);
          continue;
        }
        _status(err.isEmpty ? 'Không tải được thông tin màn hình.' : err, isLoading: false);
        _scheduleReconnect();
        return;
      }
      meta = mj;
      final rt = mj['runtime'];
      if (rt is Map<String, dynamic>) {
        final w = (rt['width'] as num?)?.toInt() ?? 0, h = (rt['height'] as num?)?.toInt() ?? 0;
        if (w > 0 && h > 0) {
          frameW = w;
          frameH = h;
        }
        _applyRuntime(rt);
      }
      final session = mj['session'];
      if (session is Map && session['jarBlocked'] == true) {
        jarBlocked = true;
        _status('JAR ghép đã bị chặn', error: true, isLoading: false);
        return;
      }
      if (session is Map && session['hasGame'] == false) {
        noGame = true;
        _status('Phiên chưa chạy game nào. Hãy chọn JAR để bắt đầu.', isLoading: false);
        return;
      }
      noGame = false;
      if ('${mj['workerSocketUrl'] ?? ''}'.isNotEmpty && '${mj['workerSocketProtocol'] ?? ''}'.isNotEmpty) break;
      if (_now() > deadline) {
        _status('Màn hình đang khởi động.');
        _scheduleReconnect(1000);
        return;
      }
      _status('Đang mở giao diện J2ME…');
      await Future.delayed(Duration(milliseconds: pause));
      pause = math.min(2000, pause * 3 ~/ 2);
    }
    _openSocket(myGen, '${meta['workerSocketUrl']}', '${meta['workerSocketProtocol']}', a);
  }

  String get _webOrigin {
    try {
      final u = Uri.parse(_api.base);
      return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
    } catch (_) {
      return _api.base;
    }
  }

  /// Gọi API máy chủ J2ME của phiên (kèm vé + khóa VIEW).
  Future<(int, Map<String, dynamic>?)> sessionRequest(Access a, String method, String pathAndQuery,
      {List<int>? body, String contentType = 'application/json', int timeoutMs = 15000}) async {
    try {
      final req = http.Request(method, Uri.parse(a.origin + pathAndQuery));
      req.headers['Authorization'] = 'Bearer ${a.ticket}';
      req.headers['X-View-Key'] = a.viewKey;
      req.headers['Origin'] = _webOrigin;
      req.headers['Accept'] = 'application/json';
      if (body != null) {
        req.headers['Content-Type'] = contentType;
        req.bodyBytes = body;
      }
      final res = await http.Response.fromStream(await req.send().timeout(Duration(milliseconds: timeoutMs)));
      Map<String, dynamic>? j;
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map<String, dynamic>) j = d;
      } catch (_) {}
      return (res.statusCode, j);
    } catch (e) {
      return (0, <String, dynamic>{'error': 'Lỗi kết nối máy chủ J2ME'});
    }
  }

  void _applyRuntime(Map<String, dynamic> rt) {
    runtime = rt;
    _notify();
  }

  // ---------------- websocket ----------------
  void _openSocket(int myGen, String url, String protocol, Access a) {
    String socketUrl = url;
    try {
      final t = Uri.parse(url), o = Uri.parse(a.origin);
      socketUrl = Uri(scheme: o.scheme == 'https' ? 'wss' : 'ws', host: o.host, port: o.hasPort ? o.port : null, path: t.path, query: t.hasQuery ? t.query : null).toString();
    } catch (_) {}
    final inflater = JpcStreamInflater();
    var seq = 0;
    var helloSeen = false;
    var revoked = '';
    _needKeyFrame = true;
    _keyFrameRequested = false;
    firstFrame = false;
    _queue.clear();

    final IOWebSocketChannel ch;
    try {
      ch = IOWebSocketChannel.connect(Uri.parse(socketUrl), protocols: [protocol, 'jarplay-key.${a.viewKey}'], headers: {'Origin': _webOrigin});
    } catch (e) {
      _status('Không mở được websocket', isLoading: false);
      _scheduleReconnect();
      return;
    }
    _socket = ch;

    void ended(int? code) {
      inflater.close();
      if (_socket != ch) return;
      _socket = null;
      _sub = null;
      _setReady(false);
      if (revoked.isNotEmpty || code == 4001) {
        _status(revoked.isEmpty ? 'Quyền xem màn hình đã bị thu hồi.' : revoked, error: true, isLoading: false);
        return;
      }
      if (_stopped || _paused) return;
      if (_gen == myGen) _scheduleReconnect(helloSeen ? 300 : null);
    }

    ch.ready.then((_) {
      if (_socket != ch) return;
      _attempt = 0;
      ch.sink.add(jsonEncode({
        'type': 'video-capabilities', 'protocol': 'jpc1', 'jpcVersion': 4,
        'frameAck': true, 'ackSeq': true, 'rendererReady': true, 'compression': 'deflate-stream',
      }));
    }).catchError((_) {});

    _sub = ch.stream.listen((msg) {
      if (_socket != ch) return;
      if (msg is String) {
        Map<String, dynamic> m;
        try {
          m = jsonDecode(msg) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        switch ('${m['type']}') {
          case 'hello':
            helloSeen = true;
            _setReady(m['input'] == true);
            break;
          case 'runtime':
            final rt = m['runtime'];
            if (rt is Map<String, dynamic>) _applyRuntime(rt);
            break;
          case 'rental_state':
            revoked = '${m['message'] ?? ''}'.isEmpty ? 'Quyền VIEW đã bị thu hồi.' : '${m['message']}';
            _status(revoked, error: true, isLoading: false);
            try { ch.sink.close(4001, 'View revoked'); } catch (_) {}
            break;
          case 'status':
            final t = '${m['message'] ?? ''}';
            if ('${m['state']}' == 'ended') {
              _status(t.isEmpty ? 'Màn hình J2ME đã dừng.' : t, error: true, isLoading: false);
            } else if (!firstFrame) {
              _status('${m['state']}' == 'waiting' ? 'Đang mở giao diện J2ME…' : 'Xin chờ');
            }
            break;
          case 'input-result':
            if (m.containsKey('browserEditor') || m.containsKey('browserForm') || m.containsKey('browserList')) _applyRuntime(m);
            final id = '${m['requestId'] ?? ''}';
            if (id.isNotEmpty) {
              final c = _pending.remove(id);
              if (c != null && !c.isCompleted) c.complete(m['ok'] == true ? m : null);
            }
            break;
        }
        return;
      }
      if (msg is List<int>) {
        final frameSeq = ++seq;
        Uint8List frame;
        try {
          frame = inflater.inflate(msg is Uint8List ? msg : Uint8List.fromList(msg));
        } catch (_) {
          _closeSocket();
          _scheduleReconnect(300);
          return;
        }
        _queueFrame(ch, frame, frameSeq);
      }
    }, onDone: () => ended(ch.closeCode), onError: (_) => ended(0), cancelOnError: true);
  }

  void _send(IOWebSocketChannel ws, Map<String, dynamic> m) {
    try { ws.sink.add(jsonEncode(m)); } catch (_) {}
  }

  void _ack(IOWebSocketChannel ws, int clientMs, int seq) {
    if (ws != _socket) return;
    _send(ws, {'type': 'frame-presented', if (clientMs >= 0) 'clientMs': clientMs, if (seq > 0) 'seq': seq});
  }

  void _requestKeyFrame(IOWebSocketChannel ws) {
    if (ws != _socket || _keyFrameRequested) return;
    _keyFrameRequested = true;
    _send(ws, {'type': 'request-keyframe'});
  }

  void _queueFrame(IOWebSocketChannel ws, Uint8List data, int seq) {
    if (_needKeyFrame) {
      if (!jpcIsKeyFrame(data)) {
        _ack(ws, -1, seq);
        _requestKeyFrame(ws);
        return;
      }
      _needKeyFrame = false;
      _keyFrameRequested = false;
    }
    if (_queue.length >= 300) {
      final now = _now();
      for (final f in _queue) { _ack(f.ws, now - f.arrivedAt, f.seq); }
      _queue.clear();
      _renderer.reset();
      if (!jpcIsKeyFrame(data)) {
        _needKeyFrame = true;
        _ack(ws, -1, seq);
        _requestKeyFrame(ws);
        return;
      }
    }
    _queue.add(_Frame(ws, data, seq, _now()));
    _drain();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_stopped) {
        final item = _queue.removeAt(0);
        if (item.ws != _socket) continue;
        final later = [for (final f in _queue) if (f.ws == item.ws) f.data];
        var skip = later.isNotEmpty && jpcCoveredLater(item.data, later);
        if (!skip && later.isNotEmpty && _now() - item.arrivedAt > jpcLagLimitMs && jpcRedrawnLater(item.data, later)) skip = true;
        try {
          final r = await _renderer.renderFrame(item.data, skip);
          if (r.width != frameW || r.height != frameH) {
            frameW = r.width;
            frameH = r.height;
            _notify();
          }
          if (!r.skipped) {
            final now = _now();
            if (_queue.isEmpty || now - _lastPresentAt >= 33) await _present();
            if (!firstFrame) {
              firstFrame = true;
              _notify();
            }
          }
        } catch (_) {
          _renderer.reset();
          _needKeyFrame = true;
          _queue.clear();
          _requestKeyFrame(item.ws);
        }
        _ack(item.ws, _now() - item.arrivedAt, item.seq);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _present() async {
    final img = await _renderer.snapshot();
    if (img == null) return;
    if (_stopped) {
      img.dispose();
      return;
    }
    final old = image;
    image = img;
    _lastPresentAt = _now();
    notifyListeners();
    // ui.Image cũ vẫn có thể đang được vẽ trong khung hiện tại: giải phóng sau.
    if (old != null) Future.delayed(const Duration(milliseconds: 200), old.dispose);
  }

  // ---------------- thao tác ----------------
  String _newRequestId() => 'app-${_now().toRadixString(36)}-${(++_reqSeq).toRadixString(36)}';

  /// Gửi thao tác và chờ kết quả (form / danh sách / ô chữ). null = thất bại.
  Future<Map<String, dynamic>?> sendInput(Map<String, dynamic> payload) async {
    final ws = _socket;
    if (!ready || ws == null) return null;
    final id = _newRequestId();
    final c = Completer<Map<String, dynamic>?>();
    _pending[id] = c;
    _send(ws, {'type': 'input', 'requestId': id, 'payload': payload});
    final r = await c.future.timeout(const Duration(seconds: 7), onTimeout: () => null);
    _pending.remove(id);
    return r;
  }

  /// Gửi thao tác không chờ (phím giữ / chạm).
  bool sendInputNow(Map<String, dynamic> payload) {
    final ws = _socket;
    if (ws == null || !ready) return false;
    _send(ws, {'type': 'input', 'requestId': _newRequestId(), 'payload': payload});
    return true;
  }

  bool key(String key, String phase) => sendInputNow({'type': 'key', 'key': key, 'phase': phase});
  bool touch(String phase, double x, double y) => sendInputNow({'type': 'touch', 'phase': phase, 'x': x, 'y': y});
  Future<bool> keyTap(String key) async => (await sendInput({'type': 'key', 'key': key, 'phase': 'tap'})) != null;
  Future<bool> text(String text) async => (await sendInput({'type': 'text', 'text': text})) != null;

  /// Hỏi lại runtime (khi game báo đang ở form nhưng chưa gửi nội dung form).
  Future<void> probeRuntime() async {
    final a = access;
    if (a == null) return;
    for (final d in const [50, 140, 320, 700, 1400, 2500, 4000]) {
      await Future.delayed(Duration(milliseconds: d));
      if (_stopped) return;
      final (c, j) = await sessionRequest(a, 'GET', '/api/public-session?id=${Uri.encodeQueryComponent(a.sessionId)}');
      final rt = j?['runtime'];
      if (rt is Map<String, dynamic> && c >= 200 && c < 300 && (rt.containsKey('browserEditor') || rt.containsKey('browserForm') || rt.containsKey('browserList'))) {
        _applyRuntime(rt);
        return;
      }
    }
  }
}
