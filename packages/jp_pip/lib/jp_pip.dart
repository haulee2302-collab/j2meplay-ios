import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Cầu nối tới AVPictureInPictureController (iOS 15+).
class JpPip {
  static const MethodChannel _ch = MethodChannel('jp_pip');

  static Future<bool> supported() async {
    try {
      return (await _ch.invokeMethod<bool>('supported')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// [auto]: tự vào hình-trong-hình khi người dùng rời app.
  static Future<bool> setup({bool auto = true}) async {
    try {
      return (await _ch.invokeMethod<bool>('setup', {'auto': auto})) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> frame(Uint8List rgba, int w, int h) async {
    try {
      await _ch.invokeMethod('frame', {'data': rgba, 'w': w, 'h': h});
    } catch (_) {}
  }

  static Future<bool> start() async {
    try {
      return (await _ch.invokeMethod<bool>('start')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  static Future<void> dispose() async {
    try {
      await _ch.invokeMethod('dispose');
    } catch (_) {}
  }

  /// Giữ app chạy nền bằng định vị độ chính xác thấp (hiện biểu tượng định vị ở thanh trạng thái).
  static Future<void> locStart() async {
    try {
      await _ch.invokeMethod('locStart');
    } catch (_) {}
  }

  static Future<void> locStop() async {
    try {
      await _ch.invokeMethod('locStop');
    } catch (_) {}
  }
}
