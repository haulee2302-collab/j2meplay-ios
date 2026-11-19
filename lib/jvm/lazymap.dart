import 'dart:collection';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Bản đồ tên → nội dung, chỉ giải nén một mục khi có người đọc (JAR lớn có hàng nghìn mục,
/// phần lớn không bao giờ dùng tới; giải nén hết lúc mở làm game khởi động rất lâu).
class LazyJarMap extends MapBase<String, Uint8List> {
  final Map<String, Uint8List> _done = {};
  final Map<String, ArchiveFile> _lazy = {};

  void addLazy(String name, ArchiveFile f) => _lazy[name] = f;

  @override
  Uint8List? operator [](Object? key) {
    final d = _done[key];
    if (d != null) return d;
    final f = _lazy.remove(key);
    if (f == null) return null;
    final b = Uint8List.fromList(f.content as List<int>);
    _done[key as String] = b;
    return b;
  }

  @override
  void operator []=(String key, Uint8List value) {
    _lazy.remove(key);
    _done[key] = value;
  }

  @override
  void clear() {
    _done.clear();
    _lazy.clear();
  }

  @override
  Iterable<String> get keys => [..._done.keys, ..._lazy.keys];

  @override
  Uint8List? remove(Object? key) {
    final v = this[key];
    _done.remove(key);
    return v;
  }

  @override
  bool containsKey(Object? key) => _done.containsKey(key) || _lazy.containsKey(key);
}
