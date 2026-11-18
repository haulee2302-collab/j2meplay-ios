import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'vm.dart';

class _SB {
  StringBuffer buf = StringBuffer();
  String get text => buf.toString();
  void set(String s) => buf = StringBuffer(s);
}

class _Enum {
  final List<dynamic> items;
  int i = 0;
  _Enum(this.items);
}

class _Rnd {
  int seed;
  static const mask = (1 << 48) - 1;
  _Rnd(int s) : seed = (s ^ 0x5DEECE66D) & mask;
  int next(int bits) {
    seed = (seed * 0x5DEECE66D + 0xB) & mask;
    return (seed >>> (48 - bits)).toSigned(32);
  }
}

String _numStr(double d) {
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  var s = d.toString();
  if (s.contains('e')) {
    s = s.replaceFirst('e+', 'E').replaceFirst('e', 'E');
    if (!s.split('E')[0].contains('.')) s = s.replaceFirst('E', '.0E');
  }
  return s;
}

/// Cài đặt các lớp thư viện Java cơ bản (java.lang, java.util) viết bằng Dart.
void installCore(Vm vm) {
  const obj = 'java/lang/Object';
  vm.defClass(obj, null);
  vm.defClass('java/lang/Class', obj);
  vm.defClass('java/lang/String', obj);
  vm.defClass('java/lang/StringBuffer', obj);
  vm.defClass('java/lang/StringBuilder', obj);
  vm.defClass('java/lang/Runnable', null, isInterface: true);
  vm.defClass('java/lang/Comparable', null, isInterface: true);
  vm.defClass('java/lang/Math', obj);
  vm.defClass('java/lang/System', obj);
  vm.defClass('java/lang/Runtime', obj);
  vm.defClass('java/lang/Thread', obj, ifaces: ['java/lang/Runnable']);
  vm.defClass('java/io/PrintStream', obj);
  vm.defClass('java/lang/Number', obj);
  vm.defClass('java/lang/Integer', 'java/lang/Number', statics: {'MAX_VALUE': 2147483647, 'MIN_VALUE': -2147483648});
  vm.defClass('java/lang/Long', 'java/lang/Number', statics: {'MAX_VALUE': 9223372036854775807, 'MIN_VALUE': -9223372036854775808});
  vm.defClass('java/lang/Short', 'java/lang/Number', statics: {'MAX_VALUE': 32767, 'MIN_VALUE': -32768});
  vm.defClass('java/lang/Byte', 'java/lang/Number', statics: {'MAX_VALUE': 127, 'MIN_VALUE': -128});
  vm.defClass('java/lang/Float', 'java/lang/Number');
  vm.defClass('java/lang/Double', 'java/lang/Number');
  vm.defClass('java/lang/Character', obj, statics: {'MAX_VALUE': 65535, 'MIN_VALUE': 0});
  vm.defClass('java/lang/Boolean', obj);
  vm.defClass('java/util/Enumeration', null, isInterface: true);
  vm.defClass('java/util/Vector', obj);
  vm.defClass('java/util/Stack', 'java/util/Vector');
  vm.defClass('java/util/Hashtable', obj);
  vm.defClass('java/util/Random', obj);
  vm.defClass('java/util/\$Enum', obj, ifaces: ['java/util/Enumeration']);

  const exs = {
    'java/lang/Throwable': obj,
    'java/lang/Exception': 'java/lang/Throwable',
    'java/lang/Error': 'java/lang/Throwable',
    'java/lang/RuntimeException': 'java/lang/Exception',
    'java/lang/NullPointerException': 'java/lang/RuntimeException',
    'java/lang/ArithmeticException': 'java/lang/RuntimeException',
    'java/lang/ClassCastException': 'java/lang/RuntimeException',
    'java/lang/IllegalArgumentException': 'java/lang/RuntimeException',
    'java/lang/NumberFormatException': 'java/lang/IllegalArgumentException',
    'java/lang/IllegalStateException': 'java/lang/RuntimeException',
    'java/lang/IllegalMonitorStateException': 'java/lang/RuntimeException',
    'java/lang/IndexOutOfBoundsException': 'java/lang/RuntimeException',
    'java/lang/ArrayIndexOutOfBoundsException': 'java/lang/IndexOutOfBoundsException',
    'java/lang/StringIndexOutOfBoundsException': 'java/lang/IndexOutOfBoundsException',
    'java/lang/NegativeArraySizeException': 'java/lang/RuntimeException',
    'java/lang/ArrayStoreException': 'java/lang/RuntimeException',
    'java/lang/SecurityException': 'java/lang/RuntimeException',
    'java/lang/UnsupportedOperationException': 'java/lang/RuntimeException',
    'java/lang/InterruptedException': 'java/lang/Exception',
    'java/lang/ClassNotFoundException': 'java/lang/Exception',
    'java/lang/InstantiationException': 'java/lang/Exception',
    'java/lang/IllegalAccessException': 'java/lang/Exception',
    'java/io/IOException': 'java/lang/Exception',
    'java/io/EOFException': 'java/io/IOException',
    'java/io/UnsupportedEncodingException': 'java/io/IOException',
    'java/util/NoSuchElementException': 'java/lang/RuntimeException',
    'java/util/EmptyStackException': 'java/lang/RuntimeException',
    'java/lang/VirtualMachineError': 'java/lang/Error',
    'java/lang/OutOfMemoryError': 'java/lang/VirtualMachineError',
    'java/lang/StackOverflowError': 'java/lang/VirtualMachineError',
    'java/lang/LinkageError': 'java/lang/Error',
    'java/lang/NoClassDefFoundError': 'java/lang/LinkageError',
    'java/lang/IncompatibleClassChangeError': 'java/lang/LinkageError',
    'java/lang/NoSuchMethodError': 'java/lang/IncompatibleClassChangeError',
    'java/lang/NoSuchFieldError': 'java/lang/IncompatibleClassChangeError',
    'java/lang/AbstractMethodError': 'java/lang/IncompatibleClassChangeError',
  };
  exs.forEach((k, v) => vm.defClass(k, v));

  int i(List a, int k) => a[k] as int;
  JObject s(String v) => vm.str(v);
  String ss(dynamic o) {
    if (o == null) throw vm.ex('java/lang/NullPointerException');
    return (o as JObject).native as String;
  }

  // ---------- Object / Class ----------
  vm.reg(obj, '<init>', '()V', (v, t, a) => null);
  vm.reg(obj, 'hashCode', '()I', (v, t, a) => a[0] is JArray ? identityHashCode(a[0]) : (a[0] as JObject).hash);
  vm.reg(obj, 'equals', '(Ljava/lang/Object;)Z', (v, t, a) => v.jequals(a[0], a[1]) ? 1 : 0);
  vm.reg(obj, 'toString', '()Ljava/lang/String;', (v, t, a) {
    final o = a[0];
    if (o is JArray) return s('${o.type}@${identityHashCode(o).toRadixString(16)}');
    final ob = o as JObject;
    return s('${ob.cls.name.replaceAll('/', '.')}@${ob.hash.toRadixString(16)}');
  });
  vm.reg(obj, 'getClass', '()Ljava/lang/Class;', (v, t, a) => v.classObject(a[0] is JArray ? v.loadClass(obj) : (a[0] as JObject).cls));
  vm.reg(obj, 'clone', '()Ljava/lang/Object;', (v, t, a) {
    final o = a[0];
    if (o is JArray) return JArray(o.type, List<dynamic>.of(o.data));
    return o;
  });
  vm.reg(obj, 'notify', '()V', (v, t, a) {
    final o = a[0] as JObject;
    if (o.waiters.isNotEmpty) o.waiters.removeAt(0).notified = true;
    return null;
  });
  vm.reg(obj, 'notifyAll', '()V', (v, t, a) {
    final o = a[0] as JObject;
    for (final w in o.waiters) {
      w.notified = true;
    }
    o.waiters.clear();
    return null;
  });
  void doWait(Vm v, JThread t, JObject o, int timeout) {
    final saved = o.lockCount;
    o.lockOwner = null;
    o.lockCount = 0;
    t.notified = false;
    o.waiters.add(t);
    final until = timeout > 0 ? v.clock.elapsedMilliseconds + timeout : -1;
    t.blocker = () => (t.notified || (until >= 0 && v.clock.elapsedMilliseconds >= until)) && o.lockOwner == null;
    t.onWake = () {
      o.waiters.remove(t);
      if (saved > 0) {
        o.lockOwner = t;
        o.lockCount = saved;
      }
    };
    t.yieldReq = true;
  }
  vm.reg(obj, 'wait', '()V', (v, t, a) { doWait(v, t, a[0] as JObject, 0); return null; });
  vm.reg(obj, 'wait', '(J)V', (v, t, a) { doWait(v, t, a[0] as JObject, i(a, 1)); return null; });
  vm.reg('java/lang/Class', 'getName', '()Ljava/lang/String;', (v, t, a) => s(((a[0] as JObject).native as JClass).name.replaceAll('/', '.')));

  // ---------- String ----------
  const S = 'java/lang/String';
  void setStr(dynamic o, String v) => (o as JObject).native = v;
  vm.reg(S, '<init>', '()V', (v, t, a) { setStr(a[0], ''); return null; });
  vm.reg(S, '<init>', '(Ljava/lang/String;)V', (v, t, a) { setStr(a[0], ss(a[1])); return null; });
  vm.reg(S, '<init>', '([C)V', (v, t, a) { setStr(a[0], String.fromCharCodes(((a[1] as JArray).data).cast<int>())); return null; });
  vm.reg(S, '<init>', '([CII)V', (v, t, a) { setStr(a[0], String.fromCharCodes((a[1] as JArray).data.cast<int>().sublist(i(a, 2), i(a, 2) + i(a, 3)))); return null; });
  vm.reg(S, '<init>', '([B)V', (v, t, a) { setStr(a[0], utf8.decode(((a[1] as JArray).data).map((e) => (e as int) & 255).toList(), allowMalformed: true)); return null; });
  vm.reg(S, '<init>', '([BII)V', (v, t, a) { setStr(a[0], utf8.decode((a[1] as JArray).data.sublist(i(a, 2), i(a, 2) + i(a, 3)).map((e) => (e as int) & 255).toList(), allowMalformed: true)); return null; });
  vm.reg(S, 'length', '()I', (v, t, a) => ss(a[0]).length);
  vm.reg(S, 'charAt', '(I)C', (v, t, a) {
    final x = ss(a[0]);
    final k = i(a, 1);
    if (k < 0 || k >= x.length) throw v.ex('java/lang/StringIndexOutOfBoundsException', '$k');
    return x.codeUnitAt(k);
  });
  vm.reg(S, 'substring', '(I)Ljava/lang/String;', (v, t, a) {
    final x = ss(a[0]);
    final b = i(a, 1);
    if (b < 0 || b > x.length) throw v.ex('java/lang/StringIndexOutOfBoundsException', '$b');
    return s(x.substring(b));
  });
  vm.reg(S, 'substring', '(II)Ljava/lang/String;', (v, t, a) {
    final x = ss(a[0]);
    final b = i(a, 1), e = i(a, 2);
    if (b < 0 || e > x.length || b > e) throw v.ex('java/lang/StringIndexOutOfBoundsException', '$b,$e');
    return s(x.substring(b, e));
  });
  vm.reg(S, 'indexOf', '(I)I', (v, t, a) => ss(a[0]).indexOf(String.fromCharCode(i(a, 1))));
  vm.reg(S, 'indexOf', '(II)I', (v, t, a) => ss(a[0]).indexOf(String.fromCharCode(i(a, 1)), i(a, 2) < 0 ? 0 : i(a, 2)));
  vm.reg(S, 'indexOf', '(Ljava/lang/String;)I', (v, t, a) => ss(a[0]).indexOf(ss(a[1])));
  vm.reg(S, 'indexOf', '(Ljava/lang/String;I)I', (v, t, a) => ss(a[0]).indexOf(ss(a[1]), i(a, 2) < 0 ? 0 : i(a, 2)));
  vm.reg(S, 'lastIndexOf', '(I)I', (v, t, a) => ss(a[0]).lastIndexOf(String.fromCharCode(i(a, 1))));
  vm.reg(S, 'equals', '(Ljava/lang/Object;)Z', (v, t, a) => (a[1] is JObject && (a[1] as JObject).native is String && (a[1] as JObject).native == ss(a[0])) ? 1 : 0);
  vm.reg(S, 'equalsIgnoreCase', '(Ljava/lang/String;)Z', (v, t, a) => a[1] != null && ss(a[0]).toLowerCase() == ss(a[1]).toLowerCase() ? 1 : 0);
  vm.reg(S, 'hashCode', '()I', (v, t, a) => v.jhash(a[0]));
  vm.reg(S, 'compareTo', '(Ljava/lang/String;)I', (v, t, a) {
    final x = ss(a[0]), y = ss(a[1]);
    final n = math.min(x.length, y.length);
    for (var k = 0; k < n; k++) {
      final d = x.codeUnitAt(k) - y.codeUnitAt(k);
      if (d != 0) return d;
    }
    return x.length - y.length;
  });
  vm.reg(S, 'concat', '(Ljava/lang/String;)Ljava/lang/String;', (v, t, a) => s(ss(a[0]) + ss(a[1])));
  vm.reg(S, 'toCharArray', '()[C', (v, t, a) => JArray('[C', ss(a[0]).codeUnits.toList()));
  vm.reg(S, 'getBytes', '()[B', (v, t, a) => JArray('[B', utf8.encode(ss(a[0])).map((e) => e.toSigned(8)).toList()));
  vm.reg(S, 'trim', '()Ljava/lang/String;', (v, t, a) => s(ss(a[0]).trim()));
  vm.reg(S, 'toUpperCase', '()Ljava/lang/String;', (v, t, a) => s(ss(a[0]).toUpperCase()));
  vm.reg(S, 'toLowerCase', '()Ljava/lang/String;', (v, t, a) => s(ss(a[0]).toLowerCase()));
  vm.reg(S, 'startsWith', '(Ljava/lang/String;)Z', (v, t, a) => ss(a[0]).startsWith(ss(a[1])) ? 1 : 0);
  vm.reg(S, 'startsWith', '(Ljava/lang/String;I)Z', (v, t, a) => ss(a[0]).startsWith(ss(a[1]), i(a, 2)) ? 1 : 0);
  vm.reg(S, 'endsWith', '(Ljava/lang/String;)Z', (v, t, a) => ss(a[0]).endsWith(ss(a[1])) ? 1 : 0);
  vm.reg(S, 'replace', '(CC)Ljava/lang/String;', (v, t, a) => s(ss(a[0]).replaceAll(String.fromCharCode(i(a, 1)), String.fromCharCode(i(a, 2)))));
  vm.reg(S, 'toString', '()Ljava/lang/String;', (v, t, a) => a[0]);
  vm.reg(S, 'intern', '()Ljava/lang/String;', (v, t, a) => v.intern(ss(a[0])));
  vm.reg(S, 'valueOf', '(I)Ljava/lang/String;', (v, t, a) => s('${i(a, 0)}'), isStatic: true);
  vm.reg(S, 'valueOf', '(J)Ljava/lang/String;', (v, t, a) => s('${i(a, 0)}'), isStatic: true);
  vm.reg(S, 'valueOf', '(C)Ljava/lang/String;', (v, t, a) => s(String.fromCharCode(i(a, 0))), isStatic: true);
  vm.reg(S, 'valueOf', '(Z)Ljava/lang/String;', (v, t, a) => s(i(a, 0) != 0 ? 'true' : 'false'), isStatic: true);
  vm.reg(S, 'valueOf', '(F)Ljava/lang/String;', (v, t, a) => s(_numStr(a[0] as double)), isStatic: true);
  vm.reg(S, 'valueOf', '(D)Ljava/lang/String;', (v, t, a) => s(_numStr(a[0] as double)), isStatic: true);
  vm.reg(S, 'valueOf', '(Ljava/lang/Object;)Ljava/lang/String;', (v, t, a) => s(v.jtoString(a[0])), isStatic: true);
  vm.reg(S, 'valueOf', '([C)Ljava/lang/String;', (v, t, a) => s(String.fromCharCodes((a[0] as JArray).data.cast<int>())), isStatic: true);

  // ---------- StringBuffer / StringBuilder ----------
  for (final B in ['java/lang/StringBuffer', 'java/lang/StringBuilder']) {
    _SB sb(dynamic o) => ((o as JObject).native ??= _SB()) as _SB;
    final self = 'L$B;';
    vm.reg(B, '<init>', '()V', (v, t, a) { sb(a[0]); return null; });
    vm.reg(B, '<init>', '(I)V', (v, t, a) { sb(a[0]); return null; });
    vm.reg(B, '<init>', '(Ljava/lang/String;)V', (v, t, a) { sb(a[0]).buf.write(ss(a[1])); return null; });
    vm.reg(B, 'append', '(Ljava/lang/String;)$self', (v, t, a) { sb(a[0]).buf.write(a[1] == null ? 'null' : ss(a[1])); return a[0]; });
    vm.reg(B, 'append', '(Ljava/lang/Object;)$self', (v, t, a) { sb(a[0]).buf.write(v.jtoString(a[1])); return a[0]; });
    vm.reg(B, 'append', '(I)$self', (v, t, a) { sb(a[0]).buf.write(i(a, 1)); return a[0]; });
    vm.reg(B, 'append', '(J)$self', (v, t, a) { sb(a[0]).buf.write(i(a, 1)); return a[0]; });
    vm.reg(B, 'append', '(C)$self', (v, t, a) { sb(a[0]).buf.writeCharCode(i(a, 1)); return a[0]; });
    vm.reg(B, 'append', '(Z)$self', (v, t, a) { sb(a[0]).buf.write(i(a, 1) != 0 ? 'true' : 'false'); return a[0]; });
    vm.reg(B, 'append', '(F)$self', (v, t, a) { sb(a[0]).buf.write(_numStr(a[1] as double)); return a[0]; });
    vm.reg(B, 'append', '(D)$self', (v, t, a) { sb(a[0]).buf.write(_numStr(a[1] as double)); return a[0]; });
    vm.reg(B, 'append', '([C)$self', (v, t, a) { sb(a[0]).buf.write(String.fromCharCodes((a[1] as JArray).data.cast<int>())); return a[0]; });
    vm.reg(B, 'toString', '()Ljava/lang/String;', (v, t, a) => s(sb(a[0]).text));
    vm.reg(B, 'length', '()I', (v, t, a) => sb(a[0]).text.length);
    vm.reg(B, 'charAt', '(I)C', (v, t, a) {
      final x = sb(a[0]).text;
      if (i(a, 1) < 0 || i(a, 1) >= x.length) throw v.ex('java/lang/StringIndexOutOfBoundsException', '${i(a, 1)}');
      return x.codeUnitAt(i(a, 1));
    });
    vm.reg(B, 'setLength', '(I)V', (v, t, a) {
      final x = sb(a[0]);
      final n = i(a, 1);
      final cur = x.text;
      x.set(n <= cur.length ? cur.substring(0, n) : cur + String.fromCharCodes(List.filled(n - cur.length, 0)));
      return null;
    });
    vm.reg(B, 'reverse', '()$self', (v, t, a) { final x = sb(a[0]); x.set(x.text.split('').reversed.join()); return a[0]; });
    vm.reg(B, 'deleteCharAt', '(I)$self', (v, t, a) { final x = sb(a[0]); final c = x.text; x.set(c.substring(0, i(a, 1)) + c.substring(i(a, 1) + 1)); return a[0]; });
    vm.reg(B, 'delete', '(II)$self', (v, t, a) { final x = sb(a[0]); final c = x.text; final e = math.min(i(a, 2), c.length); x.set(c.substring(0, i(a, 1)) + c.substring(e)); return a[0]; });
    vm.reg(B, 'insert', '(ILjava/lang/String;)$self', (v, t, a) { final x = sb(a[0]); final c = x.text; x.set(c.substring(0, i(a, 1)) + ss(a[2]) + c.substring(i(a, 1))); return a[0]; });
    vm.reg(B, 'insert', '(IC)$self', (v, t, a) { final x = sb(a[0]); final c = x.text; x.set(c.substring(0, i(a, 1)) + String.fromCharCode(i(a, 2)) + c.substring(i(a, 1))); return a[0]; });
    vm.reg(B, 'setCharAt', '(IC)V', (v, t, a) { final x = sb(a[0]); final c = x.text; x.set(c.substring(0, i(a, 1)) + String.fromCharCode(i(a, 2)) + c.substring(i(a, 1) + 1)); return null; });
  }

  // ---------- Math ----------
  const M = 'java/lang/Math';
  double d(List a, [int k = 0]) => a[k] as double;
  vm.reg(M, 'sqrt', '(D)D', (v, t, a) => math.sqrt(d(a)), isStatic: true);
  vm.reg(M, 'sin', '(D)D', (v, t, a) => math.sin(d(a)), isStatic: true);
  vm.reg(M, 'cos', '(D)D', (v, t, a) => math.cos(d(a)), isStatic: true);
  vm.reg(M, 'tan', '(D)D', (v, t, a) => math.tan(d(a)), isStatic: true);
  vm.reg(M, 'atan', '(D)D', (v, t, a) => math.atan(d(a)), isStatic: true);
  vm.reg(M, 'atan2', '(DD)D', (v, t, a) => math.atan2(d(a), d(a, 2)), isStatic: true);
  vm.reg(M, 'pow', '(DD)D', (v, t, a) => math.pow(d(a), d(a, 2)).toDouble(), isStatic: true);
  vm.reg(M, 'exp', '(D)D', (v, t, a) => math.exp(d(a)), isStatic: true);
  vm.reg(M, 'log', '(D)D', (v, t, a) => math.log(d(a)), isStatic: true);
  vm.reg(M, 'floor', '(D)D', (v, t, a) => d(a).floorToDouble(), isStatic: true);
  vm.reg(M, 'ceil', '(D)D', (v, t, a) => d(a).ceilToDouble(), isStatic: true);
  vm.reg(M, 'abs', '(I)I', (v, t, a) => i(a, 0).abs().toSigned(32), isStatic: true);
  vm.reg(M, 'abs', '(J)J', (v, t, a) => i(a, 0).abs(), isStatic: true);
  vm.reg(M, 'abs', '(F)F', (v, t, a) => d(a).abs(), isStatic: true);
  vm.reg(M, 'abs', '(D)D', (v, t, a) => d(a).abs(), isStatic: true);
  vm.reg(M, 'min', '(II)I', (v, t, a) => math.min(i(a, 0), i(a, 1)), isStatic: true);
  vm.reg(M, 'max', '(II)I', (v, t, a) => math.max(i(a, 0), i(a, 1)), isStatic: true);
  vm.reg(M, 'min', '(JJ)J', (v, t, a) => math.min(i(a, 0), i(a, 2)), isStatic: true);
  vm.reg(M, 'max', '(JJ)J', (v, t, a) => math.max(i(a, 0), i(a, 2)), isStatic: true);
  vm.reg(M, 'min', '(FF)F', (v, t, a) => math.min(d(a), d(a, 1)), isStatic: true);
  vm.reg(M, 'max', '(FF)F', (v, t, a) => math.max(d(a), d(a, 1)), isStatic: true);
  vm.reg(M, 'min', '(DD)D', (v, t, a) => math.min(d(a), d(a, 2)), isStatic: true);
  vm.reg(M, 'max', '(DD)D', (v, t, a) => math.max(d(a), d(a, 2)), isStatic: true);
  vm.reg(M, 'round', '(F)I', (v, t, a) => d(a).isNaN ? 0 : (d(a) + 0.5).floor().clamp(-2147483648, 2147483647), isStatic: true);
  vm.reg(M, 'round', '(D)J', (v, t, a) => d(a).isNaN ? 0 : (d(a) + 0.5).floor(), isStatic: true);
  vm.reg(M, 'toRadians', '(D)D', (v, t, a) => d(a) / 180.0 * math.pi, isStatic: true);
  vm.reg(M, 'toDegrees', '(D)D', (v, t, a) => d(a) * 180.0 / math.pi, isStatic: true);

  // ---------- System / Runtime / PrintStream ----------
  const Y = 'java/lang/System';
  vm.reg(Y, 'currentTimeMillis', '()J', (v, t, a) => DateTime.now().millisecondsSinceEpoch, isStatic: true);
  vm.reg(Y, 'identityHashCode', '(Ljava/lang/Object;)I', (v, t, a) => a[0] == null ? 0 : (a[0] is JArray ? identityHashCode(a[0]) : (a[0] as JObject).hash), isStatic: true);
  vm.reg(Y, 'gc', '()V', (v, t, a) => null, isStatic: true);
  vm.reg(Y, 'exit', '(I)V', (v, t, a) { v.stop(); return null; }, isStatic: true);
  vm.reg(Y, 'getProperty', '(Ljava/lang/String;)Ljava/lang/String;', (v, t, a) {
    final k = ss(a[0]);
    final r = v.props[k];
    return r == null ? null : s('$r');
  }, isStatic: true);
  vm.reg(Y, 'arraycopy', '(Ljava/lang/Object;ILjava/lang/Object;II)V', (v, t, a) {
    if (a[0] == null || a[2] == null) throw v.ex('java/lang/NullPointerException');
    final src = a[0] as JArray, dst = a[2] as JArray;
    final sp = i(a, 1), dp = i(a, 3), n = i(a, 4);
    if (sp < 0 || dp < 0 || n < 0 || sp + n > src.length || dp + n > dst.length) throw v.ex('java/lang/ArrayIndexOutOfBoundsException', 'arraycopy');
    dst.data.setRange(dp, dp + n, List<dynamic>.of(src.data.sublist(sp, sp + n)));
    return null;
  }, isStatic: true);
  const R = 'java/lang/Runtime';
  vm.reg(R, 'getRuntime', '()Ljava/lang/Runtime;', (v, t, a) => JObject(v.loadClass(R)), isStatic: true);
  vm.reg(R, 'freeMemory', '()J', (v, t, a) => 32 * 1024 * 1024);
  vm.reg(R, 'totalMemory', '()J', (v, t, a) => 64 * 1024 * 1024);
  vm.reg(R, 'gc', '()V', (v, t, a) => null);
  const P = 'java/io/PrintStream';
  void out(Vm v, String x) => v.onLog?.call(x);
  vm.reg(P, 'println', '()V', (v, t, a) { out(v, ''); return null; });
  vm.reg(P, 'println', '(Ljava/lang/String;)V', (v, t, a) { out(v, a[1] == null ? 'null' : ss(a[1])); return null; });
  vm.reg(P, 'println', '(Ljava/lang/Object;)V', (v, t, a) { out(v, v.jtoString(a[1])); return null; });
  vm.reg(P, 'println', '(I)V', (v, t, a) { out(v, '${i(a, 1)}'); return null; });
  vm.reg(P, 'println', '(C)V', (v, t, a) { out(v, String.fromCharCode(i(a, 1))); return null; });
  vm.reg(P, 'println', '(Z)V', (v, t, a) { out(v, i(a, 1) != 0 ? 'true' : 'false'); return null; });
  vm.reg(P, 'println', '(J)V', (v, t, a) { out(v, '${i(a, 1)}'); return null; });
  vm.reg(P, 'print', '(Ljava/lang/String;)V', (v, t, a) { out(v, a[1] == null ? 'null' : ss(a[1])); return null; });
  vm.reg(P, 'print', '(I)V', (v, t, a) { out(v, '${i(a, 1)}'); return null; });
  vm.reg(P, 'print', '(C)V', (v, t, a) { out(v, String.fromCharCode(i(a, 1))); return null; });

  // ---------- Thread ----------
  const T = 'java/lang/Thread';
  vm.reg(T, '<init>', '()V', (v, t, a) => null);
  vm.reg(T, '<init>', '(Ljava/lang/Runnable;)V', (v, t, a) { (a[0] as JObject).f['target'] = a[1]; return null; });
  vm.reg(T, '<init>', '(Ljava/lang/Runnable;Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['target'] = a[1]; return null; });
  vm.reg(T, '<init>', '(Ljava/lang/String;)V', (v, t, a) => null);
  vm.reg(T, 'run', '()V', (v, t, a) => null);
  vm.reg(T, 'start', '()V', (v, t, a) {
    final o = a[0] as JObject;
    if (o.native != null) throw v.ex('java/lang/IllegalStateException');
    final run = v.findVirtual(o.cls, 'run()V');
    final target = o.f['target'];
    JMethod? m;
    List<dynamic> args = [o];
    if (run != null && run.native == null) {
      m = run;
    } else if (target != null) {
      m = v.findVirtual((target as JObject).cls, 'run()V');
      args = [target];
    }
    if (m == null) return null;
    o.native = v.newThread(m, args, obj: o);
    return null;
  });
  vm.reg(T, 'sleep', '(J)V', (v, t, a) {
    final until = v.clock.elapsedMilliseconds + i(a, 0);
    t.blocker = () => v.clock.elapsedMilliseconds >= until;
    t.yieldReq = true;
    return null;
  }, isStatic: true);
  vm.reg(T, 'yield', '()V', (v, t, a) { t.yieldReq = true; return null; }, isStatic: true);
  vm.reg(T, 'currentThread', '()Ljava/lang/Thread;', (v, t, a) {
    if (t.obj == null) {
      final o = JObject(v.loadClass(T));
      o.native = t;
      t.obj = o;
    }
    return t.obj;
  }, isStatic: true);
  vm.reg(T, 'join', '()V', (v, t, a) {
    final jt = (a[0] as JObject).native;
    if (jt is JThread && !jt.done) {
      t.blocker = () => jt.done;
      t.yieldReq = true;
    }
    return null;
  });
  vm.reg(T, 'isAlive', '()Z', (v, t, a) {
    final jt = (a[0] as JObject).native;
    return jt is JThread && !jt.done ? 1 : 0;
  });
  vm.reg(T, 'setPriority', '(I)V', (v, t, a) => null);
  vm.reg(T, 'setDaemon', '(Z)V', (v, t, a) => null);
  vm.reg(T, 'interrupt', '()V', (v, t, a) => null);

  // ---------- Throwable ----------
  const TH = 'java/lang/Throwable';
  vm.reg(TH, '<init>', '()V', (v, t, a) => null);
  vm.reg(TH, '<init>', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['message'] = a[1]; return null; });
  vm.reg(TH, 'getMessage', '()Ljava/lang/String;', (v, t, a) => (a[0] as JObject).f['message']);
  vm.reg(TH, 'toString', '()Ljava/lang/String;', (v, t, a) {
    final o = a[0] as JObject;
    final m = v.jstr(o.f['message']);
    final n = o.cls.name.replaceAll('/', '.');
    return s(m == null ? n : '$n: $m');
  });
  vm.reg(TH, 'printStackTrace', '()V', (v, t, a) {
    final o = a[0] as JObject;
    v.onLog?.call('${v.jtoString(o)}');
    return null;
  });

  // ---------- Boxed ----------
  void boxed(String c, String prim, {String? valueOfDesc}) {
    vm.reg(c, '<init>', '($prim)V', (v, t, a) { (a[0] as JObject).native = a[1]; return null; });
    vm.reg(c, 'valueOf', '($prim)L$c;', (v, t, a) => v.box(c, a[0]), isStatic: true);
    vm.reg(c, 'toString', '()Ljava/lang/String;', (v, t, a) {
      final n = (a[0] as JObject).native;
      if (c == 'java/lang/Boolean') return s(n == 1 || n == true ? 'true' : 'false');
      if (c == 'java/lang/Character') return s(String.fromCharCode(n as int));
      return s(n is double ? _numStr(n) : '$n');
    });
    vm.reg(c, 'hashCode', '()I', (v, t, a) => v.jhash(a[0]));
    vm.reg(c, 'equals', '(Ljava/lang/Object;)Z', (v, t, a) => v.jequals(a[0], a[1]) ? 1 : 0);
  }
  boxed('java/lang/Integer', 'I');
  boxed('java/lang/Long', 'J');
  boxed('java/lang/Short', 'S');
  boxed('java/lang/Byte', 'B');
  boxed('java/lang/Character', 'C');
  boxed('java/lang/Boolean', 'Z');
  boxed('java/lang/Float', 'F');
  boxed('java/lang/Double', 'D');
  dynamic nat(dynamic o) => (o as JObject).native;
  for (final c in ['java/lang/Integer', 'java/lang/Long', 'java/lang/Short', 'java/lang/Byte', 'java/lang/Float', 'java/lang/Double']) {
    vm.reg(c, 'intValue', '()I', (v, t, a) => nat(a[0]) is double ? (nat(a[0]) as double).truncate() : (nat(a[0]) as int).toSigned(32));
    vm.reg(c, 'longValue', '()J', (v, t, a) => nat(a[0]) is double ? (nat(a[0]) as double).truncate() : nat(a[0]));
    vm.reg(c, 'doubleValue', '()D', (v, t, a) => (nat(a[0]) as num).toDouble());
    vm.reg(c, 'floatValue', '()F', (v, t, a) => (nat(a[0]) as num).toDouble());
  }
  vm.reg('java/lang/Character', 'charValue', '()C', (v, t, a) => nat(a[0]));
  vm.reg('java/lang/Boolean', 'booleanValue', '()Z', (v, t, a) => nat(a[0]));
  int parse(Vm v, dynamic str, int radix) {
    final x = ss(str);
    final r = int.tryParse(x.startsWith('+') ? x.substring(1) : x, radix: radix);
    if (r == null) throw v.ex('java/lang/NumberFormatException', x);
    return r;
  }
  vm.reg('java/lang/Integer', 'parseInt', '(Ljava/lang/String;)I', (v, t, a) {
    final r = parse(v, a[0], 10);
    if (r > 2147483647 || r < -2147483648) throw v.ex('java/lang/NumberFormatException', ss(a[0]));
    return r;
  }, isStatic: true);
  vm.reg('java/lang/Integer', 'parseInt', '(Ljava/lang/String;I)I', (v, t, a) => parse(v, a[0], i(a, 1)), isStatic: true);
  vm.reg('java/lang/Integer', 'valueOf', '(Ljava/lang/String;)Ljava/lang/Integer;', (v, t, a) => v.box('java/lang/Integer', parse(v, a[0], 10)), isStatic: true);
  vm.reg('java/lang/Integer', 'toString', '(I)Ljava/lang/String;', (v, t, a) => s('${i(a, 0)}'), isStatic: true);
  vm.reg('java/lang/Integer', 'toHexString', '(I)Ljava/lang/String;', (v, t, a) => s((i(a, 0) & 0xFFFFFFFF).toRadixString(16)), isStatic: true);
  vm.reg('java/lang/Long', 'parseLong', '(Ljava/lang/String;)J', (v, t, a) => parse(v, a[0], 10), isStatic: true);
  vm.reg('java/lang/Long', 'toString', '(J)Ljava/lang/String;', (v, t, a) => s('${i(a, 0)}'), isStatic: true);
  vm.reg('java/lang/Double', 'parseDouble', '(Ljava/lang/String;)D', (v, t, a) {
    final r = double.tryParse(ss(a[0]).trim());
    if (r == null) throw v.ex('java/lang/NumberFormatException', ss(a[0]));
    return r;
  }, isStatic: true);
  vm.reg('java/lang/Float', 'parseFloat', '(Ljava/lang/String;)F', (v, t, a) {
    final r = double.tryParse(ss(a[0]).trim());
    if (r == null) throw v.ex('java/lang/NumberFormatException', ss(a[0]));
    return f32(r);
  }, isStatic: true);
  const C = 'java/lang/Character';
  bool isDig(int c) => c >= 48 && c <= 57;
  bool isUp(int c) => c >= 65 && c <= 90;
  bool isLow(int c) => c >= 97 && c <= 122;
  vm.reg(C, 'isDigit', '(C)Z', (v, t, a) => isDig(i(a, 0)) ? 1 : 0, isStatic: true);
  vm.reg(C, 'isLetter', '(C)Z', (v, t, a) => (isUp(i(a, 0)) || isLow(i(a, 0)) || i(a, 0) > 127) ? 1 : 0, isStatic: true);
  vm.reg(C, 'isUpperCase', '(C)Z', (v, t, a) => isUp(i(a, 0)) ? 1 : 0, isStatic: true);
  vm.reg(C, 'isLowerCase', '(C)Z', (v, t, a) => isLow(i(a, 0)) ? 1 : 0, isStatic: true);
  vm.reg(C, 'toUpperCase', '(C)C', (v, t, a) => isLow(i(a, 0)) ? i(a, 0) - 32 : i(a, 0), isStatic: true);
  vm.reg(C, 'toLowerCase', '(C)C', (v, t, a) => isUp(i(a, 0)) ? i(a, 0) + 32 : i(a, 0), isStatic: true);
  vm.reg(C, 'digit', '(CI)I', (v, t, a) {
    final c = i(a, 0);
    final r = isDig(c) ? c - 48 : (isLow(c) ? c - 87 : (isUp(c) ? c - 55 : -1));
    return r >= 0 && r < i(a, 1) ? r : -1;
  }, isStatic: true);

  // ---------- java.util ----------
  List<dynamic> vec(dynamic o) => ((o as JObject).native ??= <dynamic>[]) as List<dynamic>;
  const V = 'java/util/Vector';
  vm.reg(V, '<init>', '()V', (v, t, a) { vec(a[0]); return null; });
  vm.reg(V, '<init>', '(I)V', (v, t, a) { vec(a[0]); return null; });
  vm.reg(V, '<init>', '(II)V', (v, t, a) { vec(a[0]); return null; });
  vm.reg(V, 'addElement', '(Ljava/lang/Object;)V', (v, t, a) { vec(a[0]).add(a[1]); return null; });
  vm.reg(V, 'size', '()I', (v, t, a) => vec(a[0]).length);
  vm.reg(V, 'isEmpty', '()Z', (v, t, a) => vec(a[0]).isEmpty ? 1 : 0);
  vm.reg(V, 'elementAt', '(I)Ljava/lang/Object;', (v, t, a) {
    final l = vec(a[0]);
    if (i(a, 1) < 0 || i(a, 1) >= l.length) throw v.ex('java/lang/ArrayIndexOutOfBoundsException', '${i(a, 1)}');
    return l[i(a, 1)];
  });
  vm.reg(V, 'firstElement', '()Ljava/lang/Object;', (v, t, a) {
    final l = vec(a[0]);
    if (l.isEmpty) throw v.ex('java/util/NoSuchElementException');
    return l.first;
  });
  vm.reg(V, 'lastElement', '()Ljava/lang/Object;', (v, t, a) {
    final l = vec(a[0]);
    if (l.isEmpty) throw v.ex('java/util/NoSuchElementException');
    return l.last;
  });
  vm.reg(V, 'removeElementAt', '(I)V', (v, t, a) {
    final l = vec(a[0]);
    if (i(a, 1) < 0 || i(a, 1) >= l.length) throw v.ex('java/lang/ArrayIndexOutOfBoundsException', '${i(a, 1)}');
    l.removeAt(i(a, 1));
    return null;
  });
  vm.reg(V, 'insertElementAt', '(Ljava/lang/Object;I)V', (v, t, a) { vec(a[0]).insert(i(a, 2), a[1]); return null; });
  vm.reg(V, 'setElementAt', '(Ljava/lang/Object;I)V', (v, t, a) { vec(a[0])[i(a, 2)] = a[1]; return null; });
  vm.reg(V, 'removeAllElements', '()V', (v, t, a) { vec(a[0]).clear(); return null; });
  int indexOf(Vm v, List<dynamic> l, dynamic x) {
    for (var k = 0; k < l.length; k++) {
      if (v.jequals(l[k], x)) return k;
    }
    return -1;
  }
  vm.reg(V, 'indexOf', '(Ljava/lang/Object;)I', (v, t, a) => indexOf(v, vec(a[0]), a[1]));
  vm.reg(V, 'contains', '(Ljava/lang/Object;)Z', (v, t, a) => indexOf(v, vec(a[0]), a[1]) >= 0 ? 1 : 0);
  vm.reg(V, 'removeElement', '(Ljava/lang/Object;)Z', (v, t, a) {
    final l = vec(a[0]);
    final k = indexOf(v, l, a[1]);
    if (k < 0) return 0;
    l.removeAt(k);
    return 1;
  });
  vm.reg(V, 'copyInto', '([Ljava/lang/Object;)V', (v, t, a) {
    final l = vec(a[0]);
    final d = (a[1] as JArray).data;
    for (var k = 0; k < l.length; k++) {
      d[k] = l[k];
    }
    return null;
  });
  vm.reg(V, 'elements', '()Ljava/util/Enumeration;', (v, t, a) => v.box('java/util/\$Enum', _Enum(List<dynamic>.of(vec(a[0])))));
  vm.reg('java/util/\$Enum', 'hasMoreElements', '()Z', (v, t, a) { final e = nat(a[0]) as _Enum; return e.i < e.items.length ? 1 : 0; });
  vm.reg('java/util/\$Enum', 'nextElement', '()Ljava/lang/Object;', (v, t, a) {
    final e = nat(a[0]) as _Enum;
    if (e.i >= e.items.length) throw v.ex('java/util/NoSuchElementException');
    return e.items[e.i++];
  });
  vm.reg('java/util/Stack', '<init>', '()V', (v, t, a) { vec(a[0]); return null; });
  vm.reg('java/util/Stack', 'push', '(Ljava/lang/Object;)Ljava/lang/Object;', (v, t, a) { vec(a[0]).add(a[1]); return a[1]; });
  vm.reg('java/util/Stack', 'pop', '()Ljava/lang/Object;', (v, t, a) {
    final l = vec(a[0]);
    if (l.isEmpty) throw v.ex('java/util/EmptyStackException');
    return l.removeLast();
  });
  vm.reg('java/util/Stack', 'peek', '()Ljava/lang/Object;', (v, t, a) {
    final l = vec(a[0]);
    if (l.isEmpty) throw v.ex('java/util/EmptyStackException');
    return l.last;
  });
  vm.reg('java/util/Stack', 'empty', '()Z', (v, t, a) => vec(a[0]).isEmpty ? 1 : 0);

  const H = 'java/util/Hashtable';
  Map<dynamic, dynamic> ht(Vm v, dynamic o) => ((o as JObject).native ??= LinkedHashMap<dynamic, dynamic>(equals: v.jequals, hashCode: v.jhash)) as Map<dynamic, dynamic>;
  vm.reg(H, '<init>', '()V', (v, t, a) { ht(v, a[0]); return null; });
  vm.reg(H, '<init>', '(I)V', (v, t, a) { ht(v, a[0]); return null; });
  vm.reg(H, 'put', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', (v, t, a) {
    if (a[1] == null || a[2] == null) throw v.ex('java/lang/NullPointerException');
    final m = ht(v, a[0]);
    final old = m[a[1]];
    m[a[1]] = a[2];
    return old;
  });
  vm.reg(H, 'get', '(Ljava/lang/Object;)Ljava/lang/Object;', (v, t, a) => ht(v, a[0])[a[1]]);
  vm.reg(H, 'remove', '(Ljava/lang/Object;)Ljava/lang/Object;', (v, t, a) => ht(v, a[0]).remove(a[1]));
  vm.reg(H, 'containsKey', '(Ljava/lang/Object;)Z', (v, t, a) => ht(v, a[0]).containsKey(a[1]) ? 1 : 0);
  vm.reg(H, 'size', '()I', (v, t, a) => ht(v, a[0]).length);
  vm.reg(H, 'isEmpty', '()Z', (v, t, a) => ht(v, a[0]).isEmpty ? 1 : 0);
  vm.reg(H, 'clear', '()V', (v, t, a) { ht(v, a[0]).clear(); return null; });
  vm.reg(H, 'keys', '()Ljava/util/Enumeration;', (v, t, a) => v.box('java/util/\$Enum', _Enum(ht(v, a[0]).keys.toList())));
  vm.reg(H, 'elements', '()Ljava/util/Enumeration;', (v, t, a) => v.box('java/util/\$Enum', _Enum(ht(v, a[0]).values.toList())));

  const RN = 'java/util/Random';
  _Rnd rnd(dynamic o) => ((o as JObject).native ??= _Rnd(DateTime.now().microsecondsSinceEpoch)) as _Rnd;
  vm.reg(RN, '<init>', '()V', (v, t, a) { rnd(a[0]); return null; });
  vm.reg(RN, '<init>', '(J)V', (v, t, a) { (a[0] as JObject).native = _Rnd(i(a, 1)); return null; });
  vm.reg(RN, 'setSeed', '(J)V', (v, t, a) { (a[0] as JObject).native = _Rnd(i(a, 1)); return null; });
  vm.reg(RN, 'nextInt', '()I', (v, t, a) => rnd(a[0]).next(32));
  vm.reg(RN, 'nextInt', '(I)I', (v, t, a) {
    final n = i(a, 1);
    if (n <= 0) throw v.ex('java/lang/IllegalArgumentException', 'n must be positive');
    final r = rnd(a[0]);
    if ((n & -n) == n) return ((n * r.next(31)) >> 31).toSigned(32);
    int bits, val;
    do {
      bits = r.next(31);
      val = bits % n;
    } while (bits - val + (n - 1) > 2147483647);
    return val;
  });
  vm.reg(RN, 'nextLong', '()J', (v, t, a) { final r = rnd(a[0]); return ((r.next(32) << 32) + r.next(32)); });

  // System.out / err
  final ps = JObject(vm.loadClass(P));
  final sys = vm.loadClass(Y);
  sys.statics['out'] = ps;
  sys.statics['err'] = ps;
}
