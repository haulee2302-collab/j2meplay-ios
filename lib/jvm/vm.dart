import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'classfile.dart';

typedef NativeFn = dynamic Function(Vm vm, JThread t, List<dynamic> a);

/// Ngoại lệ Java đang được ném (đối tượng Throwable).
class VmTimer {
  final JObject task;
  int due;
  final int period;
  bool cancelled = false;
  VmTimer(this.task, this.due, this.period);
}

class JavaThrow implements Exception {
  final JObject obj;
  JavaThrow(this.obj);
}

class JClass {
  final String name;
  JClass? sup;
  List<JClass> ifaces = [];
  ClassFile? cf;
  bool isInterface = false;
  final Map<String, JMethod> methods = {};
  final Map<String, dynamic> statics = {};
  final Map<int, JMethod> mcache = {};
  final Map<int, JClass> ccache = {};
  final Map<int, List<dynamic>> fcache = {}; // idx -> [name, ownerClass?]
  final Map<String, JMethod?> vcache = {};
  List<MapEntry<String, dynamic>>? _defaults;
  int initState = 0;
  JObject? classObj;
  JClass(this.name);

  bool isSubOf(JClass o) {
    if (identical(this, o)) return true;
    if (sup != null && sup!.isSubOf(o)) return true;
    for (final i in ifaces) {
      if (i.isSubOf(o)) return true;
    }
    return false;
  }

  List<MapEntry<String, dynamic>> get defaults {
    final d = _defaults;
    if (d != null) return d;
    final l = <MapEntry<String, dynamic>>[];
    if (sup != null) l.addAll(sup!.defaults);
    final c = cf;
    if (c != null) {
      for (final f in c.fields) {
        if (!f.isStatic) l.add(MapEntry('${f.name}:${f.desc}', defaultFor(f.desc)));
      }
    }
    return _defaults = l;
  }
}

dynamic defaultFor(String desc) {
  switch (desc[0]) {
    case 'I': case 'S': case 'B': case 'C': case 'Z': case 'J':
      return 0;
    case 'F': case 'D':
      return 0.0;
    default:
      return null;
  }
}

class JMethod {
  final JClass cls;
  final String name, desc;
  final MethodInfo? info;
  final NativeFn? native;
  final Sig sig;
  JMethod(this.cls, this.name, this.desc, this.info, this.native) : sig = Sig.of(desc);
  bool get isStatic => info != null ? info!.isStatic : staticNative;
  bool staticNative = false;
  bool get isAbstract => info != null && info!.isAbstract;
}

class JObject {
  final JClass cls;
  final Map<String, dynamic> f = {};
  dynamic native;
  JThread? lockOwner;
  int lockCount = 0;
  final List<JThread> waiters = [];
  int? _hash;
  JObject(this.cls) {
    for (final e in cls.defaults) {
      f[e.key] = e.value;
    }
  }
  int get hash => _hash ??= (math.Random(identityHashCode(this)).nextInt(0x7FFFFFFF));
}

class JArray {
  final String type; // ví dụ "[I", "[Ljava/lang/String;"
  final List<dynamic> data;
  JArray(this.type, this.data);
  int get length => data.length;
}

class Frame {
  final JMethod m;
  final List<dynamic> locals;
  final List<dynamic> stack;
  final Uint8List code;
  int sp = 0, pc = 0;
  JObject? lock;
  Frame(this.m, this.locals, this.stack, this.code);
}

class JThread {
  final int id;
  final List<Frame> frames = [];
  JObject? obj;
  bool done = false, daemon = false, yieldReq = false, notified = false;
  bool Function()? blocker;
  void Function()? onWake;
  dynamic retVal;
  JObject? uncaught;
  int priority = 5;
  JThread(this.id);
}

final Float32List _f32buf = Float32List(1);
double f32(double d) {
  _f32buf[0] = d;
  return _f32buf[0];
}

int _d2i(double d) {
  if (d.isNaN) return 0;
  if (d >= 2147483647.0) return 2147483647;
  if (d <= -2147483648.0) return -2147483648;
  return d.truncate();
}

int _d2l(double d) {
  if (d.isNaN) return 0;
  if (d >= 9.223372036854775807e18) return 9223372036854775807;
  if (d <= -9.223372036854775808e18) return -9223372036854775808;
  return d.truncate();
}

class Vm {
  final Map<String, Uint8List> jarClasses = {};
  final Map<String, Uint8List> jarResources = {};
  final Map<String, JClass> classes = {};
  final Map<String, _NativeDef> _defs = {};
  final Map<String, JObject> _interned = {};
  final List<JThread> threads = [];
  int _nextTid = 1;
  final Stopwatch clock = Stopwatch()..start();
  void Function(String)? onLog;
  bool stopped = false;
  JThread? mainThread;
  final Map<String, dynamic> props = {};

  Vm();

  // ---------------- đăng ký lớp/phương thức gốc ----------------
  void defClass(String name, String? sup, {List<String> ifaces = const [], bool isInterface = false, Map<String, dynamic>? statics}) {
    _defs[name] = _NativeDef(name, sup, ifaces, isInterface, statics ?? {});
  }

  void reg(String cls, String name, String desc, NativeFn fn, {bool isStatic = false}) {
    final d = _defs[cls] ?? (throw StateError('Chưa khai báo lớp $cls'));
    d.methods['$name$desc'] = _NM(name, desc, fn, isStatic);
  }

  // ---------------- nạp lớp ----------------
  JClass loadClass(String name) {
    final c = classes[name];
    if (c != null) return c;
    if (name.startsWith('[')) return loadClass('java/lang/Object');
    final def = _defs[name];
    if (def != null) {
      final k = JClass(name);
      classes[name] = k;
      k.isInterface = def.isInterface;
      if (def.sup != null) k.sup = loadClass(def.sup!);
      k.ifaces = [for (final i in def.ifaces) loadClass(i)];
      k.statics.addAll(def.statics);
      for (final e in def.methods.entries) {
        final nm = e.value;
        final m = JMethod(k, nm.name, nm.desc, null, nm.fn)..staticNative = nm.isStatic;
        k.methods[e.key] = m;
      }
      k.initState = 2;
      return k;
    }
    final bytes = jarClasses[name];
    if (bytes == null) throw ex('java/lang/NoClassDefFoundError', name);
    final cf = ClassFile(bytes);
    final k = JClass(name)..cf = cf;
    classes[name] = k;
    k.isInterface = (cf.access & 0x200) != 0;
    if (cf.superName != null) k.sup = loadClass(cf.superName!);
    k.ifaces = [for (final i in cf.interfaces) loadClass(i)];
    for (final mi in cf.methods) {
      NativeFn? nf;
      if (mi.isNative) {
        nf = _defs[name]?.methods['${mi.name}${mi.desc}']?.fn;
      }
      k.methods['${mi.name}${mi.desc}'] = JMethod(k, mi.name, mi.desc, mi, nf);
    }
    for (final fi in cf.fields) {
      if (fi.isStatic) {
        var v = fi.constValue;
        if (v is String && v.startsWith('S:')) {
          v = str(v.substring(2));
        }
        k.statics['${fi.name}:${fi.desc}'] = v ?? defaultFor(fi.desc);
      }
    }
    return k;
  }

  JMethod? findMethod(JClass c, String key) {
    for (JClass? k = c; k != null; k = k.sup) {
      final m = k.methods[key];
      if (m != null) return m;
    }
    for (JClass? k = c; k != null; k = k.sup) {
      for (final i in k.ifaces) {
        final m = findMethod(i, key);
        if (m != null) return m;
      }
    }
    return null;
  }

  JMethod? findVirtual(JClass c, String key) => _virtualLookup(c, key);

  JMethod? _virtualLookup(JClass c, String key) {
    if (c.vcache.containsKey(key)) return c.vcache[key];
    JMethod? r;
    for (JClass? k = c; k != null && r == null; k = k.sup) {
      final m = k.methods[key];
      if (m != null && !m.isAbstract) r = m;
    }
    if (r == null) {
      for (JClass? k = c; k != null && r == null; k = k.sup) {
        for (final i in k.ifaces) {
          final m = findMethod(i, key);
          if (m != null && !m.isAbstract) { r = m; break; }
        }
      }
    }
    return c.vcache[key] = r;
  }

  // ---------------- tiện ích đối tượng ----------------
  JObject str(String s) {
    final o = JObject(loadClass('java/lang/String'));
    o.native = s;
    return o;
  }

  JObject intern(String s) => _interned[s] ??= str(s);

  String? jstr(dynamic o) => o == null ? null : (o as JObject).native as String;

  JObject box(String cls, dynamic v) {
    final o = JObject(loadClass(cls));
    o.native = v;
    return o;
  }

  JThread? _cur;
  JavaThrow ex(String cls, [String? msg]) {
    if (msg == null && cls == 'java/lang/NullPointerException' && _cur != null) msg = _trace(_cur!);
    final o = JObject(loadClass(cls));
    if (msg != null) o.f['message'] = str(msg);
    return JavaThrow(o);
  }

  JArray newArray(String type, int n) {
    if (n < 0) throw ex('java/lang/NegativeArraySizeException', '$n');
    final d = type == '[F' || type == '[D' ? 0.0 : (type.length == 2 && type != '[L' ? 0 : null);
    return JArray(type, List<dynamic>.filled(n, d, growable: false));
  }

  JObject classObject(JClass c) {
    final o = c.classObj;
    if (o != null) return o;
    final co = JObject(loadClass('java/lang/Class'));
    co.native = c;
    return c.classObj = co;
  }

  bool instanceOf(dynamic o, String cname) {
    if (o == null) return false;
    if (o is JArray) {
      if (cname == 'java/lang/Object' || cname == 'java/lang/Cloneable' || cname == o.type) return true;
      if (!cname.startsWith('[')) return false;
      // mảng tham chiếu: [Lx; hoặc [[...] tương thích khi cả hai đều là mảng đối tượng
      final refA = o.type.startsWith('[L') || o.type.startsWith('[[');
      final refB = cname.startsWith('[L') || cname.startsWith('[[');
      return refA && refB;
    }
    if (cname.startsWith('[')) return false;
    final obj = o as JObject;
    return obj.cls.isSubOf(loadClass(cname));
  }

  bool jequals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a is JObject && a.native is String && b is JObject && b.native is String) return a.native == b.native;
    if (a is JObject && b is JObject && a.cls.name == b.cls.name && a.native != null && (a.native is num || a.native is bool)) {
      return a.native == b.native;
    }
    if (a is JObject) {
      final m = _virtualLookup(a.cls, 'equals(Ljava/lang/Object;)Z');
      if (m != null && m.native == null) {
        return callSync(m, [a, b]) == 1;
      }
    }
    return false;
  }

  int jhash(dynamic a) {
    if (a == null) return 0;
    if (a is JArray) return identityHashCode(a);
    final o = a as JObject;
    final n = o.native;
    if (n is String) {
      var h = 0;
      for (final c in n.codeUnits) {
        h = (31 * h + c).toSigned(32);
      }
      return h;
    }
    if (n is int) return n.toSigned(32);
    final m = _virtualLookup(o.cls, 'hashCode()I');
    if (m != null && m.native == null) return callSync(m, [o]) as int;
    return o.hash;
  }

  /// toString() của đối tượng Java bất kỳ (gọi cả phương thức viết bằng bytecode).
  String jtoString(dynamic o) {
    if (o == null) return 'null';
    if (o is JArray) return '${o.type}@${identityHashCode(o).toRadixString(16)}';
    final obj = o as JObject;
    final n = obj.native;
    if (n is String) return n;
    final m = _virtualLookup(obj.cls, 'toString()Ljava/lang/String;');
    if (m != null) {
      final r = m.native != null ? m.native!(this, currentThread ?? mainThread!, [obj]) : callSync(m, [obj]);
      return (r as JObject).native as String;
    }
    return '${obj.cls.name}@${obj.hash.toRadixString(16)}';
  }

  JMethod? _lastNat;

  String _trace(JThread t) {
    final b = StringBuffer();
    var n = 0;
    for (var k = t.frames.length - 1; k >= 0 && n < 6; k--, n++) {
      final f = t.frames[k];
      b.write('${f.m.cls.name}.${f.m.name}${f.m.desc}@${f.pc} ');
    }
    return b.toString();
  }
  JThread? currentThread;

  // ---------------- gọi đồng bộ (cho native gọi lại Java) ----------------
  dynamic callSync(JMethod m, List<dynamic> args) {
    final t = currentThread ?? mainThread!;
    if (m.native != null) return m.native!(this, t, args);
    final base = t.frames.length;
    _pushFrame(t, m, args);
    _exec(t, base, 1 << 40, true);
    final u = t.uncaught;
    if (u != null) {
      t.uncaught = null;
      throw JavaThrow(u);
    }
    return t.retVal;
  }

  dynamic callVirtual(dynamic recv, String name, String desc, List<dynamic> args) {
    final o = recv as JObject;
    final m = _virtualLookup(o.cls, '$name$desc');
    if (m == null) throw ex('java/lang/NoSuchMethodError', '$name$desc');
    return callSync(m, [o, ...args]);
  }

  void _pushFrame(JThread t, JMethod m, List<dynamic> args) {
    final info = m.info!;
    final code = info.code ?? (throw ex('java/lang/AbstractMethodError', '${m.cls.name}.${m.name}'));
    final loc = List<dynamic>.filled(info.maxLocals < args.length ? args.length : info.maxLocals, null);
    for (var i = 0; i < args.length; i++) {
      loc[i] = args[i];
    }
    t.frames.add(Frame(m, loc, List<dynamic>.filled(info.maxStack + 2, null), code));
  }

  // ---------------- luồng ----------------
  JThread newThread(JMethod m, List<dynamic> args, {JObject? obj}) {
    final t = JThread(_nextTid++)..obj = obj;
    _pushFrame(t, m, args);
    threads.add(t);
    return t;
  }

  /// Khởi động tiến trình điều phối: chia lát thời gian cho các luồng Java.
  Future<void> runScheduler() async {
    while (!stopped) {
      final sw = Stopwatch()..start();
      var ran = false;
      for (final t in List<JThread>.of(threads)) {
        if (stopped) break;
        if (t.done) continue;
        final b = t.blocker;
        if (b != null) {
          if (!b()) continue;
          t.blocker = null;
          final w = t.onWake;
          t.onWake = null;
          w?.call();
        }
        currentThread = t;
        ran = true;
        try {
          _exec(t, 0, 30000, false);
        } catch (e) {
          onLog?.call('Lỗi VM: $e');
          t.done = true;
        }
        if (t.frames.isEmpty) t.done = true;
        if (t.uncaught != null) {
          final u = t.uncaught!;
          onLog?.call('Ngoại lệ chưa bắt: ${u.cls.name}: ${jstr(u.f['message']) ?? ''}');
          t.done = true;
        }
      }
      threads.removeWhere((t) => t.done);
      _tickTimers();
      await Future.delayed(Duration(milliseconds: ran && sw.elapsedMilliseconds < 12 ? 1 : 8));
    }
  }

  final JThread uiThread = JThread(0);

  /// Hẹn giờ java.util.Timer: [due] theo đồng hồ VM; period > 0 = lặp.
  final List<VmTimer> timers = [];

  void _tickTimers() {
    if (timers.isEmpty) return;
    final now = clock.elapsedMilliseconds;
    for (final e in List<VmTimer>.of(timers)) {
      if (e.cancelled) {
        timers.remove(e);
        continue;
      }
      if (e.due <= now) {
        final m = findVirtual(e.task.cls, 'run()V');
        if (m != null) newThread(m, [e.task], obj: null);
        if (e.period > 0) {
          e.due += e.period;
        } else {
          timers.remove(e);
        }
      }
    }
  }

  /// Gọi phương thức Java từ giao diện (luồng riêng, không chặn).
  dynamic callUi(JMethod m, List<dynamic> args) {
    final prev = currentThread;
    currentThread = uiThread;
    try {
      return callSync(m, args);
    } finally {
      currentThread = prev;
    }
  }

  /// Khởi tạo lớp (chạy <clinit>) từ phía máy chủ.
  void ensureInit(JClass c) {
    if (c.initState != 0) return;
    c.initState = 1;
    if (c.sup != null) ensureInit(c.sup!);
    final m = c.methods['<clinit>()V'];
    if (m != null && m.info != null && m.info!.code != null) callSync(m, const []);
    c.initState = 2;
  }

  JObject newInstance(String cls, [String ctorDesc = '()V', List<dynamic> args = const []]) {
    final c = loadClass(cls);
    ensureInit(c);
    final o = JObject(c);
    final m = findMethod(c, '<init>$ctorDesc');
    if (m != null) callSync(m, [o, ...args]);
    return o;
  }

  /// Ném ngoại lệ vào luồng đang chờ (sau khi native chặn xong và thất bại).
  void throwInto(JThread t, JObject e) {
    if (t.frames.isEmpty) return;
    final f = t.frames.last;
    if (f.pc > 0) f.pc -= 1;
    _throw(t, e, 0);
  }

  /// Chặn luồng [t] đến khi [ready]; khi xong gọi [result] để thay giá trị trả về (đã đặt chỗ trên stack).
  /// [slots] = 2 cho long/double, 0 cho void.
  dynamic block(JThread t, bool Function() ready, dynamic Function() result, {int slots = 1, dynamic placeholder = 0}) {
    if (ready()) return result();
    t.blocker = ready;
    t.yieldReq = true;
    t.onWake = () {
      try {
        final r = result();
        if (slots > 0 && t.frames.isNotEmpty) {
          final f = t.frames.last;
          f.stack[f.sp - slots] = r;
        }
      } on JavaThrow catch (e) {
        throwInto(t, e.obj);
      }
    };
    return placeholder;
  }

  void stop() => stopped = true;

  // ---------------- khởi tạo lớp ----------------
  bool _initClass(JThread t, JClass c) {
    if (c.initState != 0) return false;
    c.initState = 1;
    var pushed = false;
    final m = c.methods['<clinit>()V'];
    if (m != null && m.info != null && m.info!.code != null) {
      _pushFrame(t, m, const []);
      pushed = true;
    }
    if (c.sup != null && _initClass(t, c.sup!)) pushed = true;
    if (!pushed) c.initState = 2;
    return pushed;
  }

  // ---------------- giải quyết tham chiếu ----------------
  JClass _cls(JClass cur, int idx) => cur.ccache[idx] ??= loadClass(cur.cf!.className(idx));

  JMethod _resolveMethod(JClass cur, int idx) {
    final c = cur.mcache[idx];
    if (c != null) return c;
    final cf = cur.cf!;
    final ref = cf.cp[idx] as CpRef;
    final nt = cf.cp[ref.b] as CpRef;
    final name = cf.utf(nt.a), desc = cf.utf(nt.b);
    final owner = loadClass(cf.className(ref.a));
    final m = findMethod(owner, '$name$desc') ?? (name == 'clone' ? findMethod(loadClass('java/lang/Object'), '$name$desc') : null);
    if (m == null) {
      // Giao diện của thư viện native (Enumeration, CommandListener...): tạo phương thức trừu tượng, gọi ảo sẽ tìm bản cài đặt trong lớp game.
      if (owner.isInterface && owner.cf == null) return cur.mcache[idx] = JMethod(owner, name, desc, null, null);
      throw ex('java/lang/NoSuchMethodError', '${owner.name}.$name$desc');
    }
    return cur.mcache[idx] = m;
  }

  List<dynamic> _resolveField(JClass cur, int idx, bool isStatic) {
    final c = cur.fcache[idx];
    if (c != null) return c;
    final cf = cur.cf!;
    final ref = cf.cp[idx] as CpRef;
    final nt = cf.cp[ref.b] as CpRef;
    final name = cf.utf(nt.a);
    final desc = cf.utf(nt.b);
    final key = '$name:$desc';
    JClass? owner;
    String k = name;
    if (isStatic) {
      owner = _staticOwner(loadClass(cf.className(ref.a)), name, key);
      if (owner == null) throw ex('java/lang/NoSuchFieldError', name);
      k = owner.cf != null ? key : name;
    } else {
      for (JClass? c = loadClass(cf.className(ref.a)); c != null; c = c.sup) {
        if (c.cf != null && c.cf!.fields.any((x) => !x.isStatic && x.name == name && x.desc == desc)) {
          k = key;
          break;
        }
      }
    }
    return cur.fcache[idx] = [k, owner];
  }

  JClass? _staticOwner(JClass c, String name, String key) {
    if (c.statics.containsKey(c.cf != null ? key : name)) return c;
    for (final i in c.ifaces) {
      final r = _staticOwner(i, name, key);
      if (r != null) return r;
    }
    return c.sup == null ? null : _staticOwner(c.sup!, name, key);
  }

  // ---------------- ném / bắt ngoại lệ ----------------
  void _throw(JThread t, JObject exo, int base) {
    while (t.frames.length > base) {
      final f = t.frames.last;
      for (final h in f.m.info!.handlers) {
        if (f.pc >= h.start && f.pc < h.end) {
          if (h.type == null || exo.cls.isSubOf(loadClass(h.type!))) {
            f.sp = 0;
            f.stack[0] = exo;
            f.sp = 1;
            f.pc = h.handler;
            return;
          }
        }
      }
      _release(f);
      t.frames.removeLast();
    }
    t.uncaught = exo;
  }

  void _release(Frame f) {
    final l = f.lock;
    if (l != null) {
      l.lockCount--;
      if (l.lockCount <= 0) {
        l.lockOwner = null;
        l.lockCount = 0;
      }
      f.lock = null;
    }
  }

  // ---------------- vòng lặp thông dịch ----------------
  void _exec(JThread t, int base, int budget, bool nested) {
    _cur = t;
    var count = 0;
    outer:
    while (t.frames.length > base) {
      final f = t.frames.last;
      final code = f.code;
      final st = f.stack;
      final loc = f.locals;
      var sp = f.sp;
      var pc = f.pc;
      var opPc = pc;
      try {
        while (true) {
          if (!nested && ++count > budget) {
            f.sp = sp;
            f.pc = pc;
            return;
          }
          opPc = pc;
          final op = code[pc++];
          switch (op) {
            case 0:
              break;
            case 1:
              st[sp++] = null;
              break;
            case 2: case 3: case 4: case 5: case 6: case 7: case 8:
              st[sp++] = op - 3;
              break;
            case 9: case 10:
              st[sp++] = op - 9;
              st[sp++] = null;
              break;
            case 11: case 12: case 13:
              st[sp++] = (op - 11).toDouble();
              break;
            case 14: case 15:
              st[sp++] = (op - 14).toDouble();
              st[sp++] = null;
              break;
            case 16:
              st[sp++] = code[pc++].toSigned(8);
              break;
            case 17:
              st[sp++] = ((code[pc] << 8) | code[pc + 1]).toSigned(16);
              pc += 2;
              break;
            case 18: case 19: {
              final idx = op == 18 ? code[pc++] : ((code[pc++] << 8) | code[pc++]);
              final v = f.m.cls.cf!.cp[idx];
              if (v is CpRef) {
                if (v.tag == 8) {
                  st[sp++] = intern(f.m.cls.cf!.utf(v.a));
                } else {
                  st[sp++] = classObject(_cls(f.m.cls, idx));
                }
              } else {
                st[sp++] = v is double ? f32(v) : v;
              }
              break;
            }
            case 20: {
              final idx = (code[pc++] << 8) | code[pc++];
              st[sp++] = f.m.cls.cf!.cp[idx];
              st[sp++] = null;
              break;
            }
            case 21: case 23: case 25:
              st[sp++] = loc[code[pc++]];
              break;
            case 22: case 24: {
              st[sp++] = loc[code[pc++]];
              st[sp++] = null;
              break;
            }
            case 26: case 27: case 28: case 29:
              st[sp++] = loc[op - 26];
              break;
            case 30: case 31: case 32: case 33:
              st[sp++] = loc[op - 30];
              st[sp++] = null;
              break;
            case 34: case 35: case 36: case 37:
              st[sp++] = loc[op - 34];
              break;
            case 38: case 39: case 40: case 41:
              st[sp++] = loc[op - 38];
              st[sp++] = null;
              break;
            case 42: case 43: case 44: case 45:
              st[sp++] = loc[op - 42];
              break;
            case 46: case 48: case 50: case 51: case 52: case 53: {
              final i = st[--sp] as int;
              final a = st[--sp];
              if (a == null) throw ex('java/lang/NullPointerException');
              final d = (a as JArray).data;
              if (i < 0 || i >= d.length) throw ex('java/lang/ArrayIndexOutOfBoundsException', '$i');
              st[sp++] = d[i];
              break;
            }
            case 47: case 49: {
              final i = st[--sp] as int;
              final a = st[--sp];
              if (a == null) throw ex('java/lang/NullPointerException');
              final d = (a as JArray).data;
              if (i < 0 || i >= d.length) throw ex('java/lang/ArrayIndexOutOfBoundsException', '$i');
              st[sp++] = d[i];
              st[sp++] = null;
              break;
            }
            case 54: case 56: case 58:
              loc[code[pc++]] = st[--sp];
              break;
            case 55: case 57: {
              sp--;
              loc[code[pc++]] = st[--sp];
              break;
            }
            case 59: case 60: case 61: case 62:
              loc[op - 59] = st[--sp];
              break;
            case 63: case 64: case 65: case 66:
              sp--;
              loc[op - 63] = st[--sp];
              break;
            case 67: case 68: case 69: case 70:
              loc[op - 67] = st[--sp];
              break;
            case 71: case 72: case 73: case 74:
              sp--;
              loc[op - 71] = st[--sp];
              break;
            case 75: case 76: case 77: case 78:
              loc[op - 75] = st[--sp];
              break;
            case 79: case 81: case 83: case 84: case 85: case 86: {
              final v = st[--sp];
              final i = st[--sp] as int;
              final a = st[--sp];
              if (a == null) throw ex('java/lang/NullPointerException');
              final d = (a as JArray).data;
              if (i < 0 || i >= d.length) throw ex('java/lang/ArrayIndexOutOfBoundsException', '$i');
              if (op == 84) {
                d[i] = (v as int).toSigned(8);
              } else if (op == 85) {
                d[i] = (v as int) & 0xFFFF;
              } else if (op == 86) {
                d[i] = (v as int).toSigned(16);
              } else {
                d[i] = v;
              }
              break;
            }
            case 80: case 82: {
              sp--;
              final v = st[--sp];
              final i = st[--sp] as int;
              final a = st[--sp];
              if (a == null) throw ex('java/lang/NullPointerException');
              final d = (a as JArray).data;
              if (i < 0 || i >= d.length) throw ex('java/lang/ArrayIndexOutOfBoundsException', '$i');
              d[i] = v;
              break;
            }
            case 87:
              sp--;
              break;
            case 88:
              sp -= 2;
              break;
            case 89:
              st[sp] = st[sp - 1];
              sp++;
              break;
            case 90: {
              final a = st[sp - 1], b = st[sp - 2];
              st[sp - 2] = a;
              st[sp - 1] = b;
              st[sp++] = a;
              break;
            }
            case 91: {
              final a = st[sp - 1], b = st[sp - 2], c = st[sp - 3];
              st[sp - 3] = a;
              st[sp - 2] = c;
              st[sp - 1] = b;
              st[sp++] = a;
              break;
            }
            case 92:
              st[sp] = st[sp - 2];
              st[sp + 1] = st[sp - 1];
              sp += 2;
              break;
            case 93: {
              final a = st[sp - 1], b = st[sp - 2], c = st[sp - 3];
              st[sp - 3] = b;
              st[sp - 2] = a;
              st[sp - 1] = c;
              st[sp] = b;
              st[sp + 1] = a;
              sp += 2;
              break;
            }
            case 94: {
              final a = st[sp - 1], b = st[sp - 2], c = st[sp - 3], d = st[sp - 4];
              st[sp - 4] = b;
              st[sp - 3] = a;
              st[sp - 2] = d;
              st[sp - 1] = c;
              st[sp] = b;
              st[sp + 1] = a;
              sp += 2;
              break;
            }
            case 95: {
              final a = st[sp - 1];
              st[sp - 1] = st[sp - 2];
              st[sp - 2] = a;
              break;
            }
            // ---- số học int ----
            case 96: { final b = st[--sp] as int; st[sp - 1] = ((st[sp - 1] as int) + b).toSigned(32); break; }
            case 100: { final b = st[--sp] as int; st[sp - 1] = ((st[sp - 1] as int) - b).toSigned(32); break; }
            case 104: { final b = st[--sp] as int; st[sp - 1] = ((st[sp - 1] as int) * b).toSigned(32); break; }
            case 108: {
              final b = st[--sp] as int;
              if (b == 0) throw ex('java/lang/ArithmeticException', '/ by zero');
              st[sp - 1] = ((st[sp - 1] as int) ~/ b).toSigned(32);
              break;
            }
            case 112: {
              final b = st[--sp] as int;
              if (b == 0) throw ex('java/lang/ArithmeticException', '/ by zero');
              st[sp - 1] = (st[sp - 1] as int).remainder(b);
              break;
            }
            case 116: st[sp - 1] = (-(st[sp - 1] as int)).toSigned(32); break;
            case 120: { final b = st[--sp] as int; st[sp - 1] = ((st[sp - 1] as int) << (b & 31)).toSigned(32); break; }
            case 122: { final b = st[--sp] as int; st[sp - 1] = (st[sp - 1] as int) >> (b & 31); break; }
            case 124: { final b = st[--sp] as int; st[sp - 1] = (((st[sp - 1] as int) & 0xFFFFFFFF) >> (b & 31)).toSigned(32); break; }
            case 126: { final b = st[--sp] as int; st[sp - 1] = (st[sp - 1] as int) & b; break; }
            case 128: { final b = st[--sp] as int; st[sp - 1] = (st[sp - 1] as int) | b; break; }
            case 130: { final b = st[--sp] as int; st[sp - 1] = (st[sp - 1] as int) ^ b; break; }
            // ---- long ----
            case 97: { sp -= 2; final b = st[sp] as int; st[sp - 2] = (st[sp - 2] as int) + b; break; }
            case 101: { sp -= 2; final b = st[sp] as int; st[sp - 2] = (st[sp - 2] as int) - b; break; }
            case 105: { sp -= 2; final b = st[sp] as int; st[sp - 2] = (st[sp - 2] as int) * b; break; }
            case 109: {
              sp -= 2;
              final b = st[sp] as int;
              if (b == 0) throw ex('java/lang/ArithmeticException', '/ by zero');
              st[sp - 2] = (st[sp - 2] as int) ~/ b;
              break;
            }
            case 113: {
              sp -= 2;
              final b = st[sp] as int;
              if (b == 0) throw ex('java/lang/ArithmeticException', '/ by zero');
              st[sp - 2] = (st[sp - 2] as int).remainder(b);
              break;
            }
            case 117: st[sp - 2] = -(st[sp - 2] as int); break;
            case 121: { final b = st[--sp] as int; st[sp - 2] = (st[sp - 2] as int) << (b & 63); break; }
            case 123: { final b = st[--sp] as int; st[sp - 2] = (st[sp - 2] as int) >> (b & 63); break; }
            case 125: { final b = st[--sp] as int; st[sp - 2] = (st[sp - 2] as int) >>> (b & 63); break; }
            case 127: { sp -= 2; final b = st[sp] as int; st[sp - 2] = (st[sp - 2] as int) & b; break; }
            case 129: { sp -= 2; final b = st[sp] as int; st[sp - 2] = (st[sp - 2] as int) | b; break; }
            case 131: { sp -= 2; final b = st[sp] as int; st[sp - 2] = (st[sp - 2] as int) ^ b; break; }
            // ---- float / double ----
            case 98: { final b = st[--sp] as double; st[sp - 1] = f32((st[sp - 1] as double) + b); break; }
            case 102: { final b = st[--sp] as double; st[sp - 1] = f32((st[sp - 1] as double) - b); break; }
            case 106: { final b = st[--sp] as double; st[sp - 1] = f32((st[sp - 1] as double) * b); break; }
            case 110: { final b = st[--sp] as double; st[sp - 1] = f32((st[sp - 1] as double) / b); break; }
            case 114: { final b = st[--sp] as double; st[sp - 1] = f32((st[sp - 1] as double).remainder(b)); break; }
            case 118: st[sp - 1] = -(st[sp - 1] as double); break;
            case 99: { sp -= 2; final b = st[sp] as double; st[sp - 2] = (st[sp - 2] as double) + b; break; }
            case 103: { sp -= 2; final b = st[sp] as double; st[sp - 2] = (st[sp - 2] as double) - b; break; }
            case 107: { sp -= 2; final b = st[sp] as double; st[sp - 2] = (st[sp - 2] as double) * b; break; }
            case 111: { sp -= 2; final b = st[sp] as double; st[sp - 2] = (st[sp - 2] as double) / b; break; }
            case 115: { sp -= 2; final b = st[sp] as double; st[sp - 2] = (st[sp - 2] as double).remainder(b); break; }
            case 119: st[sp - 2] = -(st[sp - 2] as double); break;
            case 132: {
              final i = code[pc++];
              loc[i] = ((loc[i] as int) + code[pc++].toSigned(8)).toSigned(32);
              break;
            }
            // ---- chuyển kiểu ----
            case 133: st[sp] = null; sp++; break; // i2l: giữ nguyên giá trị, thêm pad
            case 134: st[sp - 1] = f32((st[sp - 1] as int).toDouble()); break;
            case 135: st[sp - 1] = (st[sp - 1] as int).toDouble(); st[sp++] = null; break;
            case 136: sp--; st[sp - 1] = (st[sp - 1] as int).toSigned(32); break;
            case 137: sp--; st[sp - 1] = f32((st[sp - 1] as int).toDouble()); break;
            case 138: st[sp - 2] = (st[sp - 2] as int).toDouble(); break;
            case 139: st[sp - 1] = _d2i(st[sp - 1] as double); break;
            case 140: st[sp - 1] = _d2l(st[sp - 1] as double); st[sp++] = null; break;
            case 141: st[sp++] = null; break; // f2d
            case 142: sp--; st[sp - 1] = _d2i(st[sp - 1] as double); break;
            case 143: st[sp - 2] = _d2l(st[sp - 2] as double); break;
            case 144: sp--; st[sp - 1] = f32(st[sp - 1] as double); break;
            case 145: st[sp - 1] = (st[sp - 1] as int).toSigned(8); break;
            case 146: st[sp - 1] = (st[sp - 1] as int) & 0xFFFF; break;
            case 147: st[sp - 1] = (st[sp - 1] as int).toSigned(16); break;
            case 148: {
              sp -= 4;
              final a = st[sp] as int, b = st[sp + 2] as int;
              st[sp++] = a < b ? -1 : (a > b ? 1 : 0);
              break;
            }
            case 149: case 150: {
              final b = st[--sp] as double, a = st[--sp] as double;
              st[sp++] = (a.isNaN || b.isNaN) ? (op == 149 ? -1 : 1) : (a < b ? -1 : (a > b ? 1 : 0));
              break;
            }
            case 151: case 152: {
              sp -= 4;
              final a = st[sp] as double, b = st[sp + 2] as double;
              st[sp++] = (a.isNaN || b.isNaN) ? (op == 151 ? -1 : 1) : (a < b ? -1 : (a > b ? 1 : 0));
              break;
            }
            // ---- nhảy ----
            case 153: case 154: case 155: case 156: case 157: case 158: {
              final v = st[--sp] as int;
              final jump = switch (op) { 153 => v == 0, 154 => v != 0, 155 => v < 0, 156 => v >= 0, 157 => v > 0, _ => v <= 0 };
              if (jump) { pc = opPc + ((code[pc] << 8) | code[pc + 1]).toSigned(16); } else { pc += 2; }
              break;
            }
            case 159: case 160: case 161: case 162: case 163: case 164: {
              final b = st[--sp] as int, a = st[--sp] as int;
              final jump = switch (op) { 159 => a == b, 160 => a != b, 161 => a < b, 162 => a >= b, 163 => a > b, _ => a <= b };
              if (jump) { pc = opPc + ((code[pc] << 8) | code[pc + 1]).toSigned(16); } else { pc += 2; }
              break;
            }
            case 165: case 166: {
              final b = st[--sp], a = st[--sp];
              final eq = identical(a, b);
              if (eq == (op == 165)) { pc = opPc + ((code[pc] << 8) | code[pc + 1]).toSigned(16); } else { pc += 2; }
              break;
            }
            case 198: case 199: {
              final a = st[--sp];
              if ((a == null) == (op == 198)) { pc = opPc + ((code[pc] << 8) | code[pc + 1]).toSigned(16); } else { pc += 2; }
              break;
            }
            case 167:
              pc = opPc + ((code[pc] << 8) | code[pc + 1]).toSigned(16);
              break;
            case 200:
              pc = opPc + ((code[pc] << 24) | (code[pc + 1] << 16) | (code[pc + 2] << 8) | code[pc + 3]).toSigned(32);
              break;
            case 168:
              st[sp++] = pc + 2;
              pc = opPc + ((code[pc] << 8) | code[pc + 1]).toSigned(16);
              break;
            case 169:
              pc = loc[code[pc]] as int;
              break;
            case 170: {
              pc = (pc + 3) & ~3;
              int rd() { final v = ((code[pc] << 24) | (code[pc + 1] << 16) | (code[pc + 2] << 8) | code[pc + 3]).toSigned(32); pc += 4; return v; }
              final def = rd(), lo = rd(), hi = rd();
              final v = st[--sp] as int;
              if (v < lo || v > hi) {
                pc = opPc + def;
              } else {
                pc += (v - lo) * 4;
                pc = opPc + rd();
              }
              break;
            }
            case 171: {
              pc = (pc + 3) & ~3;
              int rd() { final v = ((code[pc] << 24) | (code[pc + 1] << 16) | (code[pc + 2] << 8) | code[pc + 3]).toSigned(32); pc += 4; return v; }
              final def = rd(), n = rd();
              final v = st[--sp] as int;
              var target = def;
              for (var i = 0; i < n; i++) {
                final k = rd(), o = rd();
                if (k == v) { target = o; break; }
              }
              pc = opPc + target;
              break;
            }
            // ---- trả về ----
            case 172: case 174: case 176: case 173: case 175: case 177: {
              dynamic rv;
              final two = op == 173 || op == 175;
              if (op != 177) {
                if (two) sp--;
                rv = st[--sp];
              }
              _release(f);
              t.frames.removeLast();
              if (t.frames.length > base) {
                final c = t.frames.last;
                if (op != 177) {
                  c.stack[c.sp++] = rv;
                  if (two) c.stack[c.sp++] = null;
                }
              } else {
                t.retVal = rv;
              }
              continue outer;
            }
            // ---- trường ----
            case 178: case 179: {
              final idx = (code[pc] << 8) | code[pc + 1];
              final r = _resolveField(f.m.cls, idx, true);
              final owner = r[1] as JClass;
              if (owner.initState == 0) {
                f.sp = sp; f.pc = opPc;
                if (_initClass(t, owner)) continue outer;
              }
              pc += 2;
              final name = r[0] as String;
              final nt = f.m.cls.cf!.cp[(f.m.cls.cf!.cp[idx] as CpRef).b] as CpRef;
              final big = f.m.cls.cf!.utf(nt.b);
              final two = big == 'J' || big == 'D';
              if (op == 178) {
                st[sp++] = owner.statics[name];
                if (two) st[sp++] = null;
              } else {
                if (two) sp--;
                owner.statics[name] = st[--sp];
              }
              break;
            }
            case 180: {
              final idx = (code[pc] << 8) | code[pc + 1];
              pc += 2;
              final r = _resolveField(f.m.cls, idx, false);
              final o = st[--sp];
              if (o == null) throw ex('java/lang/NullPointerException');
              st[sp++] = (o as JObject).f[r[0] as String];
              final cf = f.m.cls.cf!;
              final d = cf.utf((cf.cp[(cf.cp[idx] as CpRef).b] as CpRef).b);
              if (d == 'J' || d == 'D') st[sp++] = null;
              break;
            }
            case 181: {
              final idx = (code[pc] << 8) | code[pc + 1];
              pc += 2;
              final r = _resolveField(f.m.cls, idx, false);
              final cf = f.m.cls.cf!;
              final d = cf.utf((cf.cp[(cf.cp[idx] as CpRef).b] as CpRef).b);
              if (d == 'J' || d == 'D') sp--;
              final v = st[--sp];
              final o = st[--sp];
              if (o == null) throw ex('java/lang/NullPointerException');
              (o as JObject).f[r[0] as String] = v;
              break;
            }
            // ---- gọi phương thức ----
            case 182: case 183: case 184: case 185: {
              final idx = (code[pc] << 8) | code[pc + 1];
              final m = _resolveMethod(f.m.cls, idx);
              if (op == 184 && m.cls.initState == 0) {
                f.sp = sp; f.pc = opPc;
                if (_initClass(t, m.cls)) continue outer;
              }
              final isStatic = op == 184;
              final n = m.sig.argSlots + (isStatic ? 0 : 1);
              var target = m;
              if (!isStatic) {
                final recv = st[sp - n];
                if (recv == null) throw ex('java/lang/NullPointerException');
                if (op == 182 || op == 185) {
                  final rc = recv is JArray ? loadClass('java/lang/Object') : (recv as JObject).cls;
                  target = _virtualLookup(rc, '${m.name}${m.desc}') ?? m;
                }
              }
              pc += op == 185 ? 4 : 2;
              if (target.native != null) {
                final args = st.sublist(sp - n, sp);
                f.sp = sp - n;
                f.pc = pc;
                currentThread = t;
                _lastNat = target;
                final r = target.native!(this, t, args);
                sp -= n;
                final rt = target.sig.ret;
                if (rt != 'V') {
                  st[sp++] = r;
                  if (rt == 'J' || rt == 'D') st[sp++] = null;
                }
                if (t.yieldReq) {
                  t.yieldReq = false;
                  if (!nested) {
                    f.sp = sp;
                    f.pc = pc;
                    return;
                  }
                }
              } else {
                if (target.isAbstract || target.info == null || target.info!.code == null) {
                  throw ex('java/lang/AbstractMethodError', '${target.cls.name}.${target.name}');
                }
                final args = st.sublist(sp - n, sp);
                sp -= n;
                f.sp = sp;
                f.pc = pc;
                if (target.info!.isSynchronized) {
                  final lo = isStatic ? classObject(target.cls) : args[0] as JObject;
                  if (!nested && lo.lockOwner != null && !identical(lo.lockOwner, t)) {
                    // chờ khoá: chạy lại lệnh gọi sau
                    sp += n;
                    f.sp = sp;
                    f.pc = opPc;
                    t.blocker = () => lo.lockOwner == null;
                    return;
                  }
                  lo.lockOwner = t;
                  lo.lockCount++;
                  _pushFrame(t, target, args);
                  t.frames.last.lock = lo;
                } else {
                  _pushFrame(t, target, args);
                }
                continue outer;
              }
              break;
            }
            // ---- đối tượng / mảng ----
            case 187: {
              final idx = (code[pc] << 8) | code[pc + 1];
              final c = _cls(f.m.cls, idx);
              if (c.initState == 0) {
                f.sp = sp; f.pc = opPc;
                if (_initClass(t, c)) continue outer;
              }
              pc += 2;
              st[sp++] = JObject(c);
              break;
            }
            case 188: {
              final n = st[sp - 1] as int;
              const types = {4: '[Z', 5: '[C', 6: '[F', 7: '[D', 8: '[B', 9: '[S', 10: '[I', 11: '[J'};
              st[sp - 1] = newArray(types[code[pc++]]!, n);
              break;
            }
            case 189: {
              final idx = (code[pc] << 8) | code[pc + 1];
              pc += 2;
              final n = st[sp - 1] as int;
              final cn = f.m.cls.cf!.className(idx);
              st[sp - 1] = newArray(cn.startsWith('[') ? '[$cn' : '[L$cn;', n);
              break;
            }
            case 190: {
              final a = st[sp - 1];
              if (a == null) throw ex('java/lang/NullPointerException');
              st[sp - 1] = (a as JArray).data.length;
              break;
            }
            case 191: {
              final e = st[--sp];
              if (e == null) throw ex('java/lang/NullPointerException');
              throw JavaThrow(e as JObject);
            }
            case 192: {
              final idx = (code[pc] << 8) | code[pc + 1];
              pc += 2;
              final o = st[sp - 1];
              if (o != null && !instanceOf(o, f.m.cls.cf!.className(idx))) {
                throw ex('java/lang/ClassCastException', f.m.cls.cf!.className(idx));
              }
              break;
            }
            case 193: {
              final idx = (code[pc] << 8) | code[pc + 1];
              pc += 2;
              st[sp - 1] = instanceOf(st[sp - 1], f.m.cls.cf!.className(idx)) ? 1 : 0;
              break;
            }
            case 194: {
              final o = st[sp - 1];
              if (o == null) throw ex('java/lang/NullPointerException');
              final ob = o as JObject;
              if (!nested && ob.lockOwner != null && !identical(ob.lockOwner, t)) {
                f.sp = sp;
                f.pc = opPc;
                t.blocker = () => ob.lockOwner == null;
                return;
              }
              sp--;
              ob.lockOwner = t;
              ob.lockCount++;
              break;
            }
            case 195: {
              final ob = st[--sp] as JObject?;
              if (ob != null && ob.lockCount > 0) {
                ob.lockCount--;
                if (ob.lockCount == 0) ob.lockOwner = null;
              }
              break;
            }
            case 196: {
              final op2 = code[pc++];
              final i = (code[pc] << 8) | code[pc + 1];
              pc += 2;
              if (op2 == 132) {
                loc[i] = ((loc[i] as int) + ((code[pc] << 8) | code[pc + 1]).toSigned(16)).toSigned(32);
                pc += 2;
              } else if (op2 >= 21 && op2 <= 25) {
                st[sp++] = loc[i];
                if (op2 == 22 || op2 == 24) st[sp++] = null;
              } else if (op2 >= 54 && op2 <= 58) {
                if (op2 == 55 || op2 == 57) sp--;
                loc[i] = st[--sp];
              } else if (op2 == 169) {
                pc = loc[i] as int;
              }
              break;
            }
            case 197: {
              final idx = (code[pc] << 8) | code[pc + 1];
              final dims = code[pc + 2];
              pc += 3;
              final sizes = <int>[for (var i = 0; i < dims; i++) st[sp - dims + i] as int];
              sp -= dims;
              final tn = f.m.cls.cf!.className(idx);
              JArray mk(String type, int d) {
                final n = sizes[d];
                if (d == dims - 1) return newArray(type, n);
                final a = newArray(type, n);
                final sub = type.substring(1);
                for (var i = 0; i < n; i++) {
                  a.data[i] = mk(sub, d + 1);
                }
                return a;
              }
              st[sp++] = mk(tn, 0);
              break;
            }
            default:
              throw ex('java/lang/Error', 'Opcode chưa hỗ trợ: $op');
          }
        }
      } on JavaThrow catch (e) {
        f.pc = opPc;
        _throw(t, e.obj, base);
        continue outer;
      } on RangeError catch (e) {
        f.pc = opPc;
        _throw(t, ex('java/lang/ArrayIndexOutOfBoundsException', '$e').obj, base);
        continue outer;
      } on TypeError catch (e) {
        f.pc = opPc;
        if (e.toString().contains("'Null'") || e.toString().contains('null')) {
          _throw(t, ex('java/lang/NullPointerException', '${_lastNat?.cls.name}.${_lastNat?.name}').obj, base);
          continue outer;
        }
        _throw(t, ex('java/lang/Error', 'Lỗi kiểu trong VM: $e (native ${_lastNat?.cls.name}.${_lastNat?.name}${_lastNat?.desc}; tại ${_trace(t)})').obj, base);
        continue outer;
      }
    }
  }
}

class _NM {
  final String name, desc;
  final NativeFn fn;
  final bool isStatic;
  _NM(this.name, this.desc, this.fn, this.isStatic);
}

class _NativeDef {
  final String name;
  final String? sup;
  final List<String> ifaces;
  final bool isInterface;
  final Map<String, dynamic> statics;
  final Map<String, _NM> methods = {};
  _NativeDef(this.name, this.sup, this.ifaces, this.isInterface, this.statics);
}
