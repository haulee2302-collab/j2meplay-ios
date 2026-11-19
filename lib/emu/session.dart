import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../game/connection.dart';
import '../jvm/jar.dart';
import '../jvm/midp.dart';
import '../jvm/vm.dart';
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
  final List<String> log = [];
  final ValueNotifier<ui.Image?> frame = ValueNotifier(null);
  late final EmuKeys keys = EmuKeys((k, ph) => midp?.key(k, ph));
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

  Future<void> start() async {
    try {
      _set('Đang chuẩn bị game…');
      final jars = await EmuStore.listJars();
      final jar = jars.where((j) => j.id == inst.jarId).toList();
      if (jar.isEmpty) {
        _set('Chưa chọn file JAR. Hãy mở Kho JAR để chọn game.', err: true);
        return;
      }
      final Uint8List bytes = await (await EmuStore.jarFile(jar.first.id)).readAsBytes();
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

  void _publish() {
    final m = midp;
    if (m == null || _busy) return;
    final pip = Pip.wants(inst.id);
    if (!BgKeep.active && !pip) return;
    final w = m.width, h = m.height, px = m.screen.px;
    final out = Uint8List(w * h * 4);
    for (var i = 0, o = 0; i < px.length; i++, o += 4) {
      final c = px[i];
      out[o] = (c >> 16) & 255;
      out[o + 1] = (c >> 8) & 255;
      out[o + 2] = c & 255;
      out[o + 3] = 255;
    }
    if (pip) Pip.send(out, w, h);
    if (!BgKeep.active) return;
    _busy = true;
    ui.decodeImageFromPixels(out, w, h, ui.PixelFormat.rgba8888, (img) {
      _busy = false;
      final old = frame.value;
      frame.value = img;
      old?.dispose();
    });
  }

  void resume() => _publish();

  void pointer(String phase, int x, int y) => midp?.pointer(phase, x, y);
  void typeChar(String ch) => midp?.typeChar(ch);

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
    s.foreground = true;
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
