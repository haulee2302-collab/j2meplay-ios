import 'dart:typed_data';

/// Phân tích tệp .class (Java 1.x / CLDC 1.1): hằng số, trường, phương thức, mã byte, bảng ngoại lệ.
class CpRef {
  final int tag, a, b;
  const CpRef(this.tag, this.a, this.b);
}

class ExHandler {
  final int start, end, handler;
  final String? type; // null = catch-all (finally)
  const ExHandler(this.start, this.end, this.handler, this.type);
}

class FieldInfo {
  final int access;
  final String name, desc;
  final dynamic constValue;
  FieldInfo(this.access, this.name, this.desc, this.constValue);
  bool get isStatic => (access & 8) != 0;
}

class MethodInfo {
  final int access;
  final String name, desc;
  Uint8List? code;
  int maxStack = 0, maxLocals = 0;
  List<ExHandler> handlers = const [];
  MethodInfo(this.access, this.name, this.desc);
  bool get isStatic => (access & 8) != 0;
  bool get isNative => (access & 0x100) != 0;
  bool get isAbstract => (access & 0x400) != 0;
  bool get isSynchronized => (access & 0x20) != 0;
}

class ClassFile {
  late final List<dynamic> cp; // String | int | double | CpRef | null
  late final int access;
  late final String name;
  late final String? superName;
  late final List<String> interfaces;
  final List<FieldInfo> fields = [];
  final List<MethodInfo> methods = [];
  final Map<int, String> _classNames = {};

  ClassFile(Uint8List data) {
    final b = ByteData.sublistView(data);
    var p = 0;
    int u1() => b.getUint8(p++);
    int u2() { final v = b.getUint16(p); p += 2; return v; }
    int u4() { final v = b.getUint32(p); p += 4; return v; }
    if (u4() != 0xCAFEBABE) throw FormatException('Không phải tệp class');
    u2(); u2();
    final n = u2();
    cp = List<dynamic>.filled(n, null);
    for (var i = 1; i < n; i++) {
      final tag = u1();
      switch (tag) {
        case 1:
          final len = u2();
          cp[i] = _mutf8(data, p, len);
          p += len;
          break;
        case 3:
          cp[i] = b.getInt32(p);
          p += 4;
          break;
        case 4:
          cp[i] = b.getFloat32(p);
          p += 4;
          break;
        case 5:
          cp[i] = b.getInt64(p);
          p += 8;
          i++;
          break;
        case 6:
          cp[i] = b.getFloat64(p);
          p += 8;
          i++;
          break;
        case 7:
        case 8:
          cp[i] = CpRef(tag, u2(), 0);
          break;
        case 9:
        case 10:
        case 11:
        case 12:
          cp[i] = CpRef(tag, u2(), u2());
          break;
        default:
          throw FormatException('Hằng số lớp không hỗ trợ: $tag');
      }
    }
    access = u2();
    name = className(u2());
    final sup = u2();
    superName = sup == 0 ? null : className(sup);
    final ic = u2();
    interfaces = [for (var i = 0; i < ic; i++) className(u2())];
    final fc = u2();
    for (var i = 0; i < fc; i++) {
      final acc = u2(), nm = cp[u2()] as String, ds = cp[u2()] as String;
      dynamic cv;
      final ac = u2();
      for (var k = 0; k < ac; k++) {
        final an = cp[u2()] as String;
        final len = u4();
        if (an == 'ConstantValue') {
          final idx = b.getUint16(p);
          final v = cp[idx];
          cv = v is CpRef ? ('S:' + (cp[v.a] as String)) : v;
        }
        p += len;
      }
      fields.add(FieldInfo(acc, nm, ds, cv));
    }
    final mc = u2();
    for (var i = 0; i < mc; i++) {
      final m = MethodInfo(u2(), cp[u2()] as String, cp[u2()] as String);
      final ac = u2();
      for (var k = 0; k < ac; k++) {
        final an = cp[u2()] as String;
        final len = u4();
        final end = p + len;
        if (an == 'Code') {
          m.maxStack = u2();
          m.maxLocals = u2();
          final cl = u4();
          m.code = Uint8List.sublistView(data, p, p + cl);
          p += cl;
          final el = u2();
          final hs = <ExHandler>[];
          for (var e = 0; e < el; e++) {
            final s = u2(), en = u2(), h = u2(), t = u2();
            hs.add(ExHandler(s, en, h, t == 0 ? null : className(t)));
          }
          m.handlers = hs;
        }
        p = end;
      }
      methods.add(m);
    }
  }

  String className(int idx) {
    return _classNames[idx] ??= cp[(cp[idx] as CpRef).a] as String;
  }

  String utf(int i) => cp[i] as String;
}

String _mutf8(Uint8List d, int off, int len) {
  final out = <int>[];
  var i = off;
  final end = off + len;
  while (i < end) {
    final c = d[i++];
    if (c < 0x80) {
      out.add(c);
    } else if ((c & 0xE0) == 0xC0) {
      out.add(((c & 0x1F) << 6) | (d[i++] & 0x3F));
    } else {
      final c2 = d[i++], c3 = d[i++];
      out.add(((c & 0x0F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F));
    }
  }
  return String.fromCharCodes(out);
}

/// Số ô (slot) của danh sách tham số trong descriptor và kiểu trả về ('V','I','J','F','D','L'...).
class Sig {
  final int argSlots;
  final String ret;
  final List<String> args; // mỗi phần tử là mã đầu: I J F D L [ ...
  Sig(this.argSlots, this.ret, this.args);
  static final Map<String, Sig> _cache = {};
  static Sig of(String desc) => _cache[desc] ??= _parse(desc);
  static Sig _parse(String d) {
    var i = 1, slots = 0;
    final args = <String>[];
    while (d[i] != ')') {
      final c = d[i];
      if (c == 'J' || c == 'D') {
        slots += 2;
        args.add(c);
        i++;
      } else if (c == 'L') {
        slots++;
        args.add('L');
        i = d.indexOf(';', i) + 1;
      } else if (c == '[') {
        slots++;
        args.add('[');
        while (d[i] == '[') { i++; }
        i = d[i] == 'L' ? d.indexOf(';', i) + 1 : i + 1;
      } else {
        slots++;
        args.add(c);
        i++;
      }
    }
    final r = d[i + 1];
    return Sig(slots, r, args);
  }
}
