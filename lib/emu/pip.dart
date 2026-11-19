import 'dart:io';
import 'dart:typed_data';

import 'package:jp_pip/jp_pip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hình trong hình (PiP) cho giả lập: đẩy khung hình của giả lập đang chọn vào cửa sổ PiP của iOS.
class Pip {
  static bool enabled = false;
  static String target = '';
  static int _last = 0;
  static bool _ready = false;

  static bool wants(String id) => enabled && Platform.isIOS && id == target;

  static Future<void> load() async {
    if (!Platform.isIOS) return;
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('pip') ?? false;
  }

  /// Bật/tắt. Trả về false nếu thiết bị không hỗ trợ.
  static Future<bool> set(bool v, String id) async {
    if (!Platform.isIOS) return false;
    if (v) {
      final ok = await JpPip.setup(auto: true);
      if (!ok) return false;
      _ready = true;
      target = id;
    } else {
      _ready = false;
      await JpPip.stop();
      await JpPip.dispose();
    }
    enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('pip', v);
    return true;
  }

  /// Đặt giả lập mà PiP sẽ hiển thị (giả lập vừa mở).
  static Future<void> focus(String id) async {
    target = id;
    if (enabled && !_ready) _ready = await JpPip.setup(auto: true);
  }

  static void send(Uint8List rgba, int w, int h) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_ready || now - _last < 66) return;
    _last = now;
    JpPip.frame(rgba, w, h);
  }

  static Future<bool> startNow() => JpPip.start();
}
