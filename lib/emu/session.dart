import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../game/connection.dart';
import '../jvm/jar.dart';
import '../jvm/vm.dart';
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

/// Một giả lập đang chạy: VM + trạng thái. Giữ trong [EmuRuntime] nên vẫn chạy khi thoát màn hình game ("chạy ẩn").
class EmuSession extends ChangeNotifier {
  final LocalInstance inst;
  Vm? vm;
  String status = 'Xin chờ';
  bool error = false, ready = false, foreground = true;
  final List<String> log = [];
  late final EmuKeys keys = EmuKeys();
  EmuSession(this.inst);

  void _set(String s, {bool err = false}) {
    status = s;
    error = err;
    notifyListeners();
  }

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
      final v = createVm(onLog: (s) {
        log.add(s);
        if (log.length > 300) log.removeAt(0);
      });
      v.props['microedition.platform'] = 'J2ME Play';
      v.props['microedition.encoding'] = 'UTF-8';
      v.props['microedition.configuration'] = 'CLDC-1.1';
      v.props['microedition.profiles'] = 'MIDP-2.0';
      vm = v;
      final info = loadJar(v, bytes);
      if (info.midletClass == null) {
        _set('JAR không khai báo MIDlet-1 trong MANIFEST.', err: true);
        return;
      }
      _set('Đang khởi động ${info.midletName ?? 'game'}…');
      try {
        v.loadClass(info.midletClass!);
      } on JavaThrow catch (e) {
        _set('Lõi MIDP chưa đủ để chạy game này: ${e.obj.cls.name} ${v.jstr(e.obj.f['message']) ?? ''}', err: true);
        return;
      }
      _set('Lõi MIDP (Canvas/Graphics) đang được hoàn thiện — game chưa chạy được.', err: true);
    } catch (e) {
      _set('Không mở được game: $e', err: true);
    }
  }

  void stop() {
    vm?.stop();
    vm = null;
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
