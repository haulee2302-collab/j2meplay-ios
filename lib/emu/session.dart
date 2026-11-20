import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/connection.dart';
import '../game/jpc.dart';
import '../jvm/jar.dart';
import '../jvm/midp.dart';
import '../jvm/vm.dart';
import 'core.dart';
import 'glyphs.dart';
import 'net.dart';
import 'keepalive.dart';
import 'pip.dart';
import 'store.dart';

/// Phím ảo gửi vào game local (nối với Canvas MIDP ở giai đoạn sau).
class EmuKeys implements KeyTarget {
  final void Function(String key, String phase)? onKey;
  EmuKeys([this.onKey]);
  @override
  bool key(String key, String phase) {
    onKey?.call(key, phase);
    return true;
  }

  @override
  bool sendInputNow(Map<String, dynamic> payload) => true;
}

/// Một giả lập đang chạy: VM + MIDP + khung hình. Giữ trong [EmuRuntime] nên vẫn chạy khi thoát màn hình game ("chạy ẩn").
class EmuSession extends ChangeNotifier {
  final LocalInstance inst;
  Vm? vm;
  Midp? midp;
  Timer? _timer, _rmsT;
  String status = 'Xin chờ';
  bool error = false, ready = false, foreground = true, _busy = false;
  /// Chế độ "vẽ giả": game vẫn chạy logic nhưng không dựng hình (tiết kiệm máy cho game tự đánh, treo máy).
  bool noDraw = false;
  /// Lõi C chỉ dựng hình khi đang xem game. Chạy ẩn (thoát màn hình / app xuống nền) thì tự "vẽ giả".
  void syncDraw() {
    final hidden = !foreground || !BgKeep.active;
    _core?.setDraw(!(noDraw || (hidden && !Pip.wants(inst.id))));
  }

  void setNoDraw(bool v) {
    noDraw = v;
    syncDraw();
    if (!v && ready) resume();
    notifyListeners();
  }

  final List<String> log = [];
  final ValueNotifier<ui.Image?> frame = ValueNotifier(null);
  // Màn hình List/Form/TextBox/Alert do lõi C mô tả (null = đang ở màn hình vẽ bằng khung hình).
  final ValueNotifier<Map<String, dynamic>?> screen = ValueNotifier(null);
  /// Lệnh (Command) của Canvas, hiện thành thanh phím mềm.
  final ValueNotifier<List<dynamic>?> softkeys = ValueNotifier(null);
  /// Danh sách MIDlet cần người dùng chọn (JAR có nhiều MIDlet).
  final ValueNotifier<List<(String, String)>?> choices = ValueNotifier(null);
  Completer<String>? _choose;
  void chooseMidlet(String cls) {
    choices.value = null;
    _choose?.complete(cls);
    _choose = null;
  }
  String get _midletPref => 'midlet_${inst.jarId}';
  bool _uiSeen = false;
  void uiAct(String s) => _core?.uiAction(s);
  // Lõi C (thử nghiệm): khung hình JPC1 do native/jvmcore phát, vẽ bằng JpcRenderer của phiên thuê.
  JvmCore? _core;
  JpcRenderer? _rend;
  bool _coreMode = false, _pumping = false, _dirtyC = false, _coreEnded = false;
  bool get coreMode => _coreMode;
  String coreNote = '';
  late final EmuKeys keys = EmuKeys((k, ph) {
    if (_coreMode) {
      _coreKey(k, ph);
    } else {
      midp?.key(k, ph);
    }
  });
  EmuSession(this.inst);

  void _set(String s, {bool err = false}) {
    status = s;
    error = err;
    notifyListeners();
  }

  void _log(String s) {
    log.add(s);
    if (log.length > 300) log.removeAt(0);
    if (kDebugMode) debugPrint('[emu] $s');
  }

  Future<File> _rmsFile() async => File('${(await EmuStore.instanceDir(inst.id)).path}/rms_${inst.jarId}.json');

  Timer? _watch;

  Future<void> start({bool forceDart = false}) async {
    try {
      _set('Đang chuẩn bị game…');
      final jars = await EmuStore.listJars();
      final jar = jars.where((j) => j.id == inst.jarId).toList();
      if (jar.isEmpty) {
        _set('Chưa chọn file JAR. Hãy mở Kho JAR để chọn game.', err: true);
        return;
      }
      final Uint8List bytes = await (await EmuStore.jarFile(jar.first.id)).readAsBytes();
      if (!forceDart && JvmCore.enabled && await _startCore(jar.first.id, bytes)) return;
      await Glyphs.build();
      final v = createVm(onLog: _log);
      v.props['microedition.platform'] = 'J2ME Play';
      v.props['microedition.encoding'] = 'UTF-8';
      v.props['microedition.configuration'] = 'CLDC-1.1';
      v.props['microedition.profiles'] = 'MIDP-2.0';
      v.mainThread = v.uiThread;
      vm = v;
      final info = loadJar(v, bytes);
      if (info.midletClass == null) {
        _set('JAR không khai báo MIDlet-1 trong MANIFEST.', err: true);
        return;
      }
      final m = Midp(v, inst.width, inst.height, info.attrs);
      m.glyphProvider = Glyphs.get;
      m.install();
      m.onExit = () => _set('Game đã thoát');
      m.onScreen = notifyListeners;
      installNet(m, inst.proxy);
      m.onFrame = _publish;
      try {
        final f = await _rmsFile();
        if (await f.exists()) m.rmsImport(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
      m.onRmsChanged = () {
        _rmsT?.cancel();
        _rmsT = Timer(const Duration(milliseconds: 800), () async {
          try {
            await (await _rmsFile()).writeAsString(jsonEncode(m.rmsExport()));
          } catch (_) {}
        });
      };
      midp = m;
      _set('Đang khởi động ${info.midletName ?? 'game'}…');
      try {
        final mid = v.newInstance(info.midletClass!);
        unawaited(v.runScheduler());
        m.start(mid);
      } on JavaThrow catch (e) {
        _set('Không khởi động được game: ${v.jtoString(e.obj)}', err: true);
        return;
      }
      final ms = inst.fps <= 0 ? 16 : (1000 ~/ inst.fps).clamp(8, 100);
      _timer = Timer.periodic(Duration(milliseconds: ms), (_) => m.tick());
      ready = true;
      _set('Đang chạy');
    } catch (e) {
      _set('Không mở được game: $e', err: true);
    }
  }

  // ---------------- lõi C ----------------
  Future<bool> _startCore(String jarId, Uint8List bytes) async {
    final core = JvmCore.get();
    if (core == null) {
      coreNote = 'Lõi C không nạp được: ${JvmCore.lastError}';
      _log(coreNote);
      return false;
    }
    try {
      _set('Đang giải nén JAR…');
      final base = (await EmuStore.instanceDir(inst.id)).path;
      final prep = await prepareJar(bytes, '$base/core_$jarId', '${bytes.length}');
      if (prep == null) {
        coreNote = 'Lõi C: không đọc được MIDlet-1 trong MANIFEST';
        _log(coreNote);
        return false;
      }
      final rms = '$base/rms_core_$jarId';
      var midlet = prep.midlet;
      if (prep.all.length > 1) {
        final sp = await SharedPreferences.getInstance();
        final saved = sp.getString(_midletPref);
        if (saved != null && prep.all.any((e) => e.$2 == saved)) {
          midlet = saved;
        } else {
          _choose = Completer<String>();
          choices.value = prep.all;
          _set('Chọn MIDlet để chạy');
          midlet = await _choose!.future;
          await sp.setString(_midletPref, midlet);
        }
      }
      final rc = core.start(prep.dir, midlet, rms, inst.width, inst.height);
      if (rc != 0) {
        coreNote = 'Lõi C đang bận (mã $rc)';
        _log(coreNote);
        return false;
      }
      _core = core;
      JvmCore.markRunning(true);
      syncDraw();
      _rend = JpcRenderer();
      _coreMode = true;
      _coreEnded = false;
      final ms = inst.fps <= 0 ? 16 : (1000 ~/ inst.fps).clamp(8, 100);
      _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _pumpCore());
      ready = true;
      _set('Đang chạy (lõi C)');
      _watch = Timer(const Duration(seconds: 8), _coreWatchdog);
      return true;
    } catch (e) {
      coreNote = 'Lõi C lỗi: $e';
      _log(coreNote);
      _coreMode = false;
      return false;
    }
  }

  /// Sau 8 giây lõi C vẫn chưa ra khung hình nào: lấy log, dừng lõi và chạy lại bằng bộ thông dịch Dart.
  Future<void> _coreWatchdog() async {
    if (!_coreMode || frame.value != null || _uiSeen) return;
    final core = _core;
    var lg = '';
    try {
      lg = (core?.log ?? '').trim();
    } catch (_) {}
    final first = lg.split('\n').where((l) => l.trim().isNotEmpty).take(4).join(' | ');
    coreNote = 'Lõi C không ra hình: ${first.isEmpty ? 'không có lỗi nào được ghi' : first}. Đã chuyển sang bộ thông dịch Dart';
    _log(coreNote);
    _timer?.cancel();
    _core?.stop();
    _core = null;
    _rend?.close();
    _rend = null;
    _coreMode = false;
    JvmCore.markRunning(false);
    notifyListeners();
    await start(forceDart: true);
  }

  Future<void> _pumpCore() async {
    final core = _core, r = _rend;
    if (core == null || r == null || _pumping) return;
    _pumping = true;
    try {
      final show = !noDraw && ((BgKeep.active && foreground) || Pip.wants(inst.id));
      var any = false;
      for (var i = 0; i < 48; i++) {
        final d = core.poll();
        if (d == null) break;
        if (!show) continue; // nền: bỏ khung; khi quay lại sẽ yêu cầu vẽ lại toàn bộ
        try {
          await r.renderFrame(d, false);
          any = true;
        } catch (e) {
          _log('JPC lỗi: $e');
          core.refresh();
        }
      }
      if (any) _presentCore();
      final nq = core.netPoll();
      if (nq != null) unawaited(_netRequest(core, nq));
      final uj = core.uiPoll();
      if (uj != null) {
        try {
          final m = jsonDecode(uj) as Map<String, dynamic>;
          if (m['kind'] == 'none') {
            screen.value = null;
            softkeys.value = null;
            core.refresh();
          } else if (m['kind'] == 'softkeys') {
            if (screen.value != null) core.refresh();
            screen.value = null;
            softkeys.value = m['commands'] as List<dynamic>;
          } else {
            softkeys.value = null;
            _uiSeen = true;
            screen.value = m;
          }
        } catch (_) {}
      }
      final st = core.status;
      if ((st == -1 || st == 2) && frame.value == null && !_uiSeen && !_coreEnded) {
        _coreEnded = true;
        await _coreWatchdog();
        return;
      }
      if (st == -1 && !_coreEnded) {
        _coreEnded = true;
        coreNote = 'Lõi C dừng: ${core.error}';
        _set('Lõi C dừng: ${core.error}', err: true);
      } else if (st == 2 && !_coreEnded) {
        _coreEnded = true;
        _set('Game đã thoát');
      }
    } finally {
      _pumping = false;
    }
  }

  /// Thực hiện một yêu cầu HTTP/HTTPS do lõi C nhờ làm (lõi chờ kết quả, tối đa 30 giây).
  Future<void> _netRequest(JvmCore core, Uint8List d) async {
    var id = 0;
    try {
      final sep = _indexOf(d, const [10, 10]);
      final head = utf8.decode(d.sublist(0, sep < 0 ? d.length : sep), allowMalformed: true).split('\n');
      final body = sep < 0 ? Uint8List(0) : d.sublist(sep + 2);
      id = int.parse(head[0]);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await client.openUrl(head[1], Uri.parse(head[2]));
        var ua = false;
        for (var i = 3; i < head.length; i++) {
          final c = head[i].indexOf(':');
          if (c <= 0) continue;
          final k = head[i].substring(0, c).trim(), v = head[i].substring(c + 1).trim();
          if (k.toLowerCase() == 'user-agent') ua = true;
          req.headers.set(k, v);
        }
        if (!ua) req.headers.set('User-Agent', 'Profile/MIDP-2.0 Configuration/CLDC-1.1');
        if (body.isNotEmpty) req.add(body);
        final res = await req.close().timeout(const Duration(seconds: 12));
        final bb = BytesBuilder(copy: false);
        await for (final ch in res) {
          bb.add(ch);
          if (bb.length > 16 * 1024 * 1024) break;
        }
        final hb = StringBuffer();
        res.headers.forEach((k, v) => hb.write('$k: ${v.join(', ')}\n'));
        core.netDone(id, res.statusCode, Uint8List.fromList(utf8.encode(hb.toString())), bb.takeBytes());
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _log('HTTP lỗi: $e');
      if (id != 0) core.netDone(id, 0, Uint8List(0), Uint8List(0));
    }
  }

  static int _indexOf(Uint8List d, List<int> pat) {
    for (var i = 0; i + pat.length <= d.length; i++) {
      var ok = true;
      for (var k = 0; k < pat.length; k++) {
        if (d[i + k] != pat[k]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  Future<void> _presentCore() async {
    final r = _rend;
    if (r == null) return;
    if (_busy) {
      _dirtyC = true;
      return;
    }
    _busy = true;
    try {
      final fb = r.fb;
      if (fb != null && Pip.wants(inst.id)) Pip.send(Uint8List.fromList(fb.buffer.asUint8List()), r.width, r.height);
      if (noDraw || !BgKeep.active || !foreground) return;
      final img = await r.snapshot();
      if (img == null) return;
      final old = frame.value;
      frame.value = img;
      if (old != null) Future.delayed(const Duration(milliseconds: 250), old.dispose);
    } finally {
      _busy = false;
      if (_dirtyC && _coreMode) {
        _dirtyC = false;
        _presentCore();
      }
    }
  }

  void _coreKey(String k, String phase) {
    final code = Midp.keyCodeOf(k);
    if (code == 0) return;
    if (phase == 'press') {
      _core?.key(0, code);
      _core?.key(1, code);
    } else {
      _core?.key(phase == 'down' ? 0 : 1, code);
    }
  }

  void _publish() {
    final m = midp;
    if (m == null || _busy) return;
    if (noDraw) return;
    final pip = Pip.wants(inst.id);
    if (!BgKeep.active && !pip) return;
    final w = m.width, h = m.height, px = m.screen.px;
    final out = Uint8List(w * h * 4);
    final o32 = out.buffer.asUint32List();
    // ARGB → RGBA (little-endian: byte0=R ... byte3=A), một lần ghi mỗi điểm ảnh.
    for (var i = 0; i < px.length; i++) {
      final c = px[i];
      o32[i] = 0xFF000000 | ((c & 255) << 16) | (c & 0xFF00) | ((c >> 16) & 255);
    }
    if (pip) Pip.send(out, w, h);
    if (!BgKeep.active) return;
    _busy = true;
    ui.decodeImageFromPixels(out, w, h, ui.PixelFormat.rgba8888, (img) {
      _busy = false;
      final old = frame.value;
      frame.value = img;
      // Ảnh cũ có thể còn đang được vẽ ở khung hiện tại: giải phóng trễ để không bị nháy/mất hình.
      if (old != null) Future.delayed(const Duration(milliseconds: 250), old.dispose);
    });
  }

  bool get usesCore => _coreMode;

  /// Quên MIDlet đã chọn để chọn lại khi khởi động lần sau.
  Future<void> forgetMidlet() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_midletPref);
    } catch (_) {}
  }

  void resume() {
    if (_coreMode) {
      _core?.refresh();
      return;
    }
    _publish();
  }

  void pointer(String phase, int x, int y) {
    if (_coreMode) {
      _core?.pointer(phase == 'down' ? 0 : (phase == 'up' ? 1 : 2), x, y);
      return;
    }
    midp?.pointer(phase, x, y);
  }

  void typeChar(String ch) {
    if (_coreMode) {
      if (ch.isEmpty) return;
      final c = ch.codeUnitAt(0);
      _core?.key(0, c);
      _core?.key(1, c);
      return;
    }
    midp?.typeChar(ch);
  }

  Future<void> saveShot() async {
    final img = frame.value;
    if (img == null) return;
    try {
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd != null) { await (await EmuStore.shot(inst.id)).writeAsBytes(bd.buffer.asUint8List()); EmuRuntime.changed.value++; }
    } catch (_) {}
  }

  void stop() {
    _timer?.cancel();
    _watch?.cancel();
    screen.value = null;
    softkeys.value = null;
    if (_coreMode) {
      _coreMode = false;
      _core?.stop();
      _core = null;
      _rend?.close();
      _rend = null;
      JvmCore.markRunning(false);
    }
    midp?.destroy();
    vm?.stop();
    vm = null;
    midp = null;
    ready = false;
    status = 'Đã dừng';
    notifyListeners();
  }
}

/// Danh sách giả lập đang chạy (theo id).
class EmuRuntime {
  static final Map<String, EmuSession> sessions = {};
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static EmuSession open(LocalInstance inst) {
    var s = sessions[inst.id];
    if (s == null) {
      s = EmuSession(inst);
      sessions[inst.id] = s;
      s.start();
      changed.value++;
    }
    final wasHidden = !s.foreground;
    s.foreground = true;
    s.syncDraw();
    if (wasHidden && s.ready) s.resume(); // quay lại game đang chạy ẩn: vẽ lại toàn bộ khung
    return s;
  }

  static void close(String id) {
    sessions.remove(id)?.stop();
    changed.value++;
  }

  static String modeOf(String id) {
    final s = sessions[id];
    if (s == null) return '';
    return s.foreground ? 'foreground' : 'hidden';
  }
}
