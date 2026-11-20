import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cầu nối tới lõi JVM viết bằng C (native/jvmcore). Chỉ có trong bản iOS có biên dịch lõi C.
/// Không có lõi (hoặc lỗi nạp) thì [JvmCore.get] trả về null và app dùng bộ thông dịch Dart như cũ.
class JvmCore {
  static JvmCore? _i;
  static bool _tried = false;
  static const prefKey = 'emu_core';
  static bool enabled = false;
  static String lastError = '';

  static Future<void> load() async {
    try {
      enabled = (await SharedPreferences.getInstance()).getBool(prefKey) ?? false;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v) async {
    enabled = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(prefKey, v);
    } catch (_) {}
  }

  static JvmCore? get() {
    if (_tried) return _i;
    _tried = true;
    if (!Platform.isIOS) {
      lastError = 'không phải iOS';
      return null;
    }
    try {
      DynamicLibrary lib;
      final errs = <String>[];
      try {
        lib = DynamicLibrary.process();
        lib.lookup('jvmcore_status');
      } catch (e) {
        errs.add('process: $e');
        lib = DynamicLibrary.open('jvmcore.framework/jvmcore');
        lib.lookup('jvmcore_status');
      }
      _i = JvmCore._(lib);
    } catch (e) {
      lastError = '$e';
      if (kDebugMode) debugPrint('[core] không nạp được lõi C: $e');
      _i = null;
    }
    return _i;
  }

  final int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, int) _start;
  final int Function(Pointer<Uint8>, int) _poll;
  final void Function(int, int) _key;
  final void Function(int, int, int) _ptr;
  final int Function() _status;
  final Pointer<Utf8> Function() _error;
  final void Function() _stop, _refresh;
  final Pointer<Utf8> Function() _log;
  final int Function(Pointer<Uint8>, int) _uiPoll;
  final void Function(Pointer<Utf8>) _uiAct;
  final int Function(Pointer<Uint8>, int) _netPoll;
  final void Function(int, int, Pointer<Uint8>, int, Pointer<Uint8>, int) _netDone;
  Pointer<Uint8> _nbuf = malloc<Uint8>(1 << 16);
  int _ncap = 1 << 16;
  Pointer<Uint8> _ubuf = malloc<Uint8>(1 << 16);
  int _ucap = 1 << 16;
  Pointer<Uint8> _buf = malloc<Uint8>(1 << 20);
  int _cap = 1 << 20;

  JvmCore._(DynamicLibrary l)
      : _start = l.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32, Int32), int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, int)>('jvmcore_start'),
        _poll = l.lookupFunction<Int32 Function(Pointer<Uint8>, Int32), int Function(Pointer<Uint8>, int)>('jvmcore_poll'),
        _key = l.lookupFunction<Void Function(Int32, Int32), void Function(int, int)>('jvmcore_key'),
        _ptr = l.lookupFunction<Void Function(Int32, Int32, Int32), void Function(int, int, int)>('jvmcore_pointer'),
        _status = l.lookupFunction<Int32 Function(), int Function()>('jvmcore_status'),
        _error = l.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('jvmcore_error'),
        _stop = l.lookupFunction<Void Function(), void Function()>('jvmcore_stop'),
        _refresh = l.lookupFunction<Void Function(), void Function()>('jvmcore_refresh'),
        _log = l.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('jvmcore_log'),
        _uiPoll = l.lookupFunction<Int32 Function(Pointer<Uint8>, Int32), int Function(Pointer<Uint8>, int)>('jvmcore_ui_poll'),
        _uiAct = l.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('jvmcore_ui_action'),
        _netPoll = l.lookupFunction<Int32 Function(Pointer<Uint8>, Int32), int Function(Pointer<Uint8>, int)>('jvmcore_net_poll'),
        _netDone = l.lookupFunction<Void Function(Int32, Int32, Pointer<Uint8>, Int32, Pointer<Uint8>, Int32), void Function(int, int, Pointer<Uint8>, int, Pointer<Uint8>, int)>('jvmcore_net_done');

  /// 0 chưa chạy · 1 đang chạy · 2 đã thoát · -1 lỗi
  int get status => _status();
  String get error => _error().toDartString();
  bool get busy => _status() == 1;

  /// Các dòng lỗi đầu tiên của lõi (ngoại lệ chưa bắt, API chưa cài...).
  String get log => _log().toDartString();

  /// 0 = chạy; -1 = lõi đang bận với một giả lập khác.
  int start(String dir, String midlet, String rms, int w, int h) {
    final d = dir.toNativeUtf8(), m = midlet.toNativeUtf8(), r = rms.toNativeUtf8();
    try {
      return _start(d, m, r, w, h);
    } finally {
      malloc.free(d);
      malloc.free(m);
      malloc.free(r);
    }
  }

  /// Lấy khung kế tiếp (null nếu chưa có). Dữ liệu chỉ hợp lệ tới lần gọi poll sau: dùng xong (kể cả await) rồi mới gọi lại.
  Uint8List? poll() {
    var n = _poll(_buf, _cap);
    if (n == 0) return null;
    if (n < 0) {
      malloc.free(_buf);
      _cap = -n + 1024;
      _buf = malloc<Uint8>(_cap);
      n = _poll(_buf, _cap);
      if (n <= 0) return null;
    }
    return _buf.asTypedList(n);
  }

  /// Mô tả JSON của màn hình List/Form/TextBox/Alert đang hiện (null nếu không đổi).
  String? uiPoll() {
    var n = _uiPoll(_ubuf, _ucap);
    if (n == 0) return null;
    if (n < 0) {
      malloc.free(_ubuf);
      _ucap = -n + 1024;
      _ubuf = malloc<Uint8>(_ucap);
      n = _uiPoll(_ubuf, _ucap);
      if (n <= 0) return null;
    }
    return utf8.decode(_ubuf.asTypedList(n), allowMalformed: true);
  }

  /// Gửi thao tác của người dùng trên màn hình đó: K<lệnh> · L<mục> · M<bits> · E<chữ> · T<mục>:<chữ> · S<mục>:<bits> · G<mục>:<giá trị> · D (đóng Alert).
  void uiAction(String s) {
    final p = s.toNativeUtf8();
    try {
      _uiAct(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Yêu cầu HTTP do game phát ra (null nếu chưa có): "id\nPHƯƠNG THỨC\nURL\nKhóa: giá trị\n...\n\n" rồi tới thân yêu cầu.
  Uint8List? netPoll() {
    var n = _netPoll(_nbuf, _ncap);
    if (n == 0) return null;
    if (n < 0) {
      malloc.free(_nbuf);
      _ncap = -n + 1024;
      _nbuf = malloc<Uint8>(_ncap);
      n = _netPoll(_nbuf, _ncap);
      if (n <= 0) return null;
    }
    return Uint8List.fromList(_nbuf.asTypedList(n));
  }

  /// Trả kết quả HTTP về lõi (status <= 0 = lỗi kết nối).
  void netDone(int id, int status, Uint8List headers, Uint8List body) {
    final h = malloc<Uint8>(headers.length + 1), b = malloc<Uint8>(body.length + 1);
    try {
      h.asTypedList(headers.length).setAll(0, headers);
      b.asTypedList(body.length).setAll(0, body);
      _netDone(id, status, h, headers.length, b, body.length);
    } finally {
      malloc.free(h);
      malloc.free(b);
    }
  }

  void key(int type, int code) => _key(type, code);
  void pointer(int type, int x, int y) => _ptr(type, x, y);
  void stop() => _stop();
  void refresh() => _refresh();
}

/// Giải nén JAR ra thư mục (một lần cho mỗi JAR) để lõi C nạp lớp và tài nguyên trực tiếp từ tệp.
Future<({String dir, String midlet})?> prepareJar(Uint8List bytes, String root, String stamp) async {
  final dir = Directory(root);
  final mark = File('$root/.ok');
  if (!(await mark.exists()) || (await mark.readAsString()) != stamp) {
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await compute(_extract, [bytes, root]);
    await mark.writeAsString(stamp);
  }
  final mf = File('$root/META-INF/MANIFEST.MF');
  if (!await mf.exists()) return null;
  final cls = midletOf(await mf.readAsString());
  if (cls == null) return null;
  return (dir: root, midlet: cls);
}

void _extract(List<dynamic> a) {
  final bytes = a[0] as Uint8List;
  final root = a[1] as String;
  final ar = ZipDecoder().decodeBytes(bytes);
  for (final f in ar) {
    final name = f.name;
    if (name.contains('..')) continue;
    if (f.isFile) {
      final o = File('$root/$name');
      o.parent.createSync(recursive: true);
      o.writeAsBytesSync(f.content as List<int>);
    }
  }
}

/// Lớp MIDlet đầu tiên trong MANIFEST (MIDlet-1: Tên, biểu tượng, lớp), dạng 'a/b/C'.
String? midletOf(String manifest) {
  final lines = <String>[];
  for (final raw in const LineSplitter().convert(manifest)) {
    if (raw.startsWith(' ') && lines.isNotEmpty) {
      lines[lines.length - 1] += raw.substring(1);
    } else {
      lines.add(raw);
    }
  }
  for (final l in lines) {
    if (l.toLowerCase().startsWith('midlet-1:')) {
      final parts = l.substring(9).split(',');
      if (parts.length >= 3) return parts[2].trim().replaceAll('.', '/');
    }
  }
  return null;
}
