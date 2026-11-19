import 'dart:convert';

import 'package:crypto/crypto.dart' as cr;
import 'dart:math' as math;

import 'collections.dart';
import 'vm.dart';

/// Bổ sung thư viện Java mà các game hay gọi (mã hoá chuỗi, Date/Calendar, số học...).
void installExtra(Vm vm) {
  installCollections(vm);
  vm.props.addAll({
    'microedition.platform': 'Nokia6300/5.0',
    'microedition.encoding': 'ISO-8859-1',
    'microedition.configuration': 'CLDC-1.1',
    'microedition.profiles': 'MIDP-2.0',
    'microedition.locale': 'en-US',
    'microedition.hostname': 'localhost',
    'microedition.commports': '',
    'microedition.media.version': '1.0',
    'microedition.m3g.version': '1.1',
    'file.separator': '/',
    'path.separator': ':',
    'line.separator': '\n',
    'user.dir': '/',
    'java.version': '1.3',
    'os.name': 'J2ME',
    'file.encoding': 'ISO-8859-1',
  });
  const obj = 'java/lang/Object';
  // ---- javax.microedition.media (không phát tiếng, chỉ để game không lỗi) ----
  const MP = 'javax/microedition/media/';
  vm.defClass('${MP}MediaException', 'java/lang/Exception');
  for (final n in ['Control', 'PlayerListener', 'Player']) {
    vm.defClass('$MP$n', null, isInterface: true);
  }
  vm.defClass('${MP}control/VolumeControl', null, isInterface: true);
  vm.defClass('${MP}\$Player', obj, ifaces: ['${MP}Player', '${MP}Control']);
  vm.defClass('${MP}Manager', obj);
  JObject player() => JObject(vm.loadClass('${MP}\$Player'))..native = <String, int>{'state': 100, 'loop': 1};
  vm.reg('${MP}Manager', 'createPlayer', '(Ljava/io/InputStream;Ljava/lang/String;)Ljavax/microedition/media/Player;', (v, t, a) => player(), isStatic: true);
  vm.reg('${MP}Manager', 'createPlayer', '(Ljava/lang/String;)Ljavax/microedition/media/Player;', (v, t, a) => player(), isStatic: true);
  vm.reg('${MP}Manager', 'playTone', '(III)V', (v, t, a) => null, isStatic: true);
  vm.reg('${MP}Manager', 'getSupportedContentTypes', '(Ljava/lang/String;)[Ljava/lang/String;', (v, t, a) => v.newArray('[Ljava/lang/String;', 0), isStatic: true);
  for (final m in ['start', 'stop', 'close', 'realize', 'prefetch', 'deallocate']) {
    vm.reg('${MP}\$Player', m, '()V', (v, t, a) => null);
  }
  vm.reg('${MP}\$Player', 'setLoopCount', '(I)V', (v, t, a) => null);
  vm.reg('${MP}\$Player', 'getState', '()I', (v, t, a) => 100);
  vm.reg('${MP}\$Player', 'addPlayerListener', '(Ljavax/microedition/media/PlayerListener;)V', (v, t, a) => null);
  vm.reg('${MP}\$Player', 'removePlayerListener', '(Ljavax/microedition/media/PlayerListener;)V', (v, t, a) => null);
  vm.reg('${MP}\$Player', 'getControl', '(Ljava/lang/String;)Ljavax/microedition/media/Control;', (v, t, a) => null);
  vm.reg('${MP}\$Player', 'setLevel', '(I)I', (v, t, a) => a[1]);
  vm.reg('${MP}\$Player', 'getLevel', '()I', (v, t, a) => 50);
  vm.reg('${MP}\$Player', 'setMute', '(Z)V', (v, t, a) => null);

  // ---- java.net.URL (chỉ khai báo) ----
  vm.defClass('java/net/MalformedURLException', 'java/io/IOException');
  vm.defClass('java/net/URL', obj);
  vm.reg('java/net/URL', '<init>', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).native = (a[1] as JObject).native; return null; });
  vm.reg('java/net/URL', 'toString', '()Ljava/lang/String;', (v, t, a) => vm.str((a[0] as JObject).native as String));
  vm.reg('java/net/URL', 'openStream', '()Ljava/io/InputStream;', (v, t, a) => throw v.ex('java/io/IOException', 'URL.openStream chưa hỗ trợ'));

  // ---- java.security.MessageDigest ----
  vm.defClass('java/security/NoSuchAlgorithmException', 'java/lang/Exception');
  vm.defClass('java/security/MessageDigest', obj);
  const MD = 'java/security/MessageDigest';
  vm.reg(MD, 'getInstance', '(Ljava/lang/String;)Ljava/security/MessageDigest;', (v, t, a) {
    final n = ((a[0] as JObject).native as String).toUpperCase().replaceAll('-', '');
    if (n != 'MD5' && n != 'SHA1' && n != 'SHA256') throw v.ex('java/security/NoSuchAlgorithmException', n);
    return JObject(v.loadClass(MD))..native = [n, <int>[]];
  }, isStatic: true);
  List md(dynamic o) => (o as JObject).native as List;
  vm.reg(MD, 'update', '([B)V', (v, t, a) { (md(a[0])[1] as List<int>).addAll([for (final b in (a[1] as JArray).data) (b as int) & 255]); return null; });
  vm.reg(MD, 'update', '([BII)V', (v, t, a) {
    final d = a[1] as JArray;
    (md(a[0])[1] as List<int>).addAll([for (var k = a[2] as int; k < (a[2] as int) + (a[3] as int); k++) (d.data[k] as int) & 255]);
    return null;
  });
  vm.reg(MD, 'reset', '()V', (v, t, a) { (md(a[0])[1] as List<int>).clear(); return null; });
  JArray finish(Vm v, dynamic o) {
    final m = md(o);
    final data = m[1] as List<int>;
    final d = m[0] == 'MD5' ? cr.md5.convert(data) : (m[0] == 'SHA1' ? cr.sha1.convert(data) : cr.sha256.convert(data));
    data.clear();
    return JArray('[B', [for (final b in d.bytes) b.toSigned(8)]);
  }
  vm.reg(MD, 'digest', '()[B', (v, t, a) => finish(v, a[0]));
  vm.reg(MD, 'digest', '([B)[B', (v, t, a) {
    (md(a[0])[1] as List<int>).addAll([for (final b in (a[1] as JArray).data) (b as int) & 255]);
    return finish(v, a[0]);
  });
  int i(List a, int k) => a[k] as int;
  JObject s(String v) => vm.str(v);
  String ss(dynamic o) {
    if (o == null) throw vm.ex('java/lang/NullPointerException');
    return (o as JObject).native as String;
  }

  vm.reg('java/lang/String', 'isEmpty', '()Z', (v, t, a) => ss(a[0]).isEmpty ? 1 : 0);
  vm.reg('java/lang/String', 'matches', '(Ljava/lang/String;)Z', (v, t, a) {
    final m = RegExp('^(?:${ss(a[1])})\$').firstMatch(ss(a[0]));
    return m != null ? 1 : 0;
  });

  List<int> bytesOf(JArray a, [int off = 0, int? len]) {
    final n = len ?? a.length - off;
    return [for (var k = off; k < off + n; k++) (a.data[k] as int) & 255];
  }

  String decode(List<int> b, String enc) {
    final e = enc.toUpperCase().replaceAll('_', '-');
    if (e == 'ISO-8859-1' || e == 'ISO8859-1' || e == 'LATIN1' || e == 'US-ASCII' || e == 'ASCII') return String.fromCharCodes(b);
    return utf8.decode(b, allowMalformed: true);
  }

  List<int> encode(String str, String enc) {
    final e = enc.toUpperCase().replaceAll('_', '-');
    if (e == 'ISO-8859-1' || e == 'ISO8859-1' || e == 'LATIN1' || e == 'US-ASCII' || e == 'ASCII') {
      return [for (final c in str.codeUnits) c > 255 ? 63 : c];
    }
    return utf8.encode(str);
  }

  JArray barr(List<int> b) => JArray('[B', [for (final e in b) e.toSigned(8)]);

  // ---------- String ----------
  const S = 'java/lang/String';
  vm.reg(S, '<init>', '([BLjava/lang/String;)V', (v, t, a) {
    (a[0] as JObject).native = decode(bytesOf(a[1] as JArray), ss(a[2]));
    return null;
  });
  vm.reg(S, '<init>', '([BIILjava/lang/String;)V', (v, t, a) {
    (a[0] as JObject).native = decode(bytesOf(a[1] as JArray, i(a, 2), i(a, 3)), ss(a[4]));
    return null;
  });
  vm.reg(S, 'getBytes', '(Ljava/lang/String;)[B', (v, t, a) => barr(encode(ss(a[0]), ss(a[1]))));
  vm.reg(S, 'split', '(Ljava/lang/String;)[Ljava/lang/String;', (v, t, a) {
    final p = ss(a[1]);
    final parts = ss(a[0]).split(RegExp(p));
    while (parts.length > 1 && parts.last.isEmpty) {
      parts.removeLast();
    }
    return JArray('[Ljava/lang/String;', [for (final x in parts) s(x)]);
  });
  vm.reg(S, 'replaceAll', '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;', (v, t, a) =>
      s(ss(a[0]).replaceAll(RegExp(ss(a[1])), ss(a[2]))));
  vm.reg(S, 'contains', '(Ljava/lang/CharSequence;)Z', (v, t, a) => ss(a[0]).contains(v.jtoString(a[1])) ? 1 : 0);
  vm.reg(S, 'replace', '(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;', (v, t, a) =>
      s(ss(a[0]).replaceAll(v.jtoString(a[1]), v.jtoString(a[2]))));
  vm.reg(S, 'copyValueOf', '([C)Ljava/lang/String;', (v, t, a) => s(String.fromCharCodes((a[0] as JArray).data.cast<int>())), isStatic: true);
  vm.reg(S, 'format', '(Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/String;', (v, t, a) {
    final args = (a[1] as JArray).data;
    var k = 0;
    final out = ss(a[0]).replaceAllMapped(RegExp(r'%(\d*)([sdxXc%])'), (m) {
      if (m.group(2) == '%') return '%';
      final x = k < args.length ? args[k++] : null;
      final str = x is JObject ? (x.native is num ? '${x.native}' : v.jtoString(x)) : '$x';
      final w = int.tryParse(m.group(1) ?? '') ?? 0;
      return str.padLeft(w);
    });
    return s(out);
  }, isStatic: true);

  // ---------- số ----------
  vm.reg('java/lang/Double', 'isNaN', '(D)Z', (v, t, a) => (a[0] as double).isNaN ? 1 : 0, isStatic: true);
  vm.reg('java/lang/Double', 'isInfinite', '(D)Z', (v, t, a) => (a[0] as double).isInfinite ? 1 : 0, isStatic: true);
  vm.reg('java/lang/Float', 'isNaN', '(F)Z', (v, t, a) => (a[0] as double).isNaN ? 1 : 0, isStatic: true);
  vm.reg('java/lang/Float', 'isInfinite', '(F)Z', (v, t, a) => (a[0] as double).isInfinite ? 1 : 0, isStatic: true);
  vm.reg('java/lang/Integer', 'toString', '(II)Ljava/lang/String;', (v, t, a) => s(i(a, 0).toRadixString(i(a, 1))), isStatic: true);
  vm.reg('java/lang/Integer', 'parseInt', '(Ljava/lang/String;I)I', (v, t, a) {
    final r = int.tryParse(ss(a[0]), radix: i(a, 1));
    if (r == null || r.abs() > 0x7fffffff + 1) throw v.ex('java/lang/NumberFormatException', ss(a[0]));
    return r.toSigned(32);
  }, isStatic: true);
  vm.reg('java/lang/Long', 'toString', '(JI)Ljava/lang/String;', (v, t, a) => s(i(a, 0).toRadixString(i(a, 2))), isStatic: true);
  vm.reg('java/lang/Short', 'parseShort', '(Ljava/lang/String;)S', (v, t, a) {
    final r = int.tryParse(ss(a[0]));
    if (r == null || r < -32768 || r > 32767) throw v.ex('java/lang/NumberFormatException', ss(a[0]));
    return r;
  }, isStatic: true);
  vm.reg('java/lang/Byte', 'parseByte', '(Ljava/lang/String;)B', (v, t, a) {
    final r = int.tryParse(ss(a[0]));
    if (r == null || r < -128 || r > 127) throw v.ex('java/lang/NumberFormatException', ss(a[0]));
    return r;
  }, isStatic: true);
  vm.reg('java/lang/Short', 'shortValue', '()S', (v, t, a) => ((a[0] as JObject).native as int).toSigned(16));
  vm.reg('java/lang/Byte', 'byteValue', '()B', (v, t, a) => ((a[0] as JObject).native as int).toSigned(8));
  for (final c in const ['java/lang/Integer', 'java/lang/Short', 'java/lang/Byte', 'java/lang/Long']) {
    vm.reg(c, 'shortValue', '()S', (v, t, a) => ((a[0] as JObject).native as int).toSigned(16));
    vm.reg(c, 'byteValue', '()B', (v, t, a) => ((a[0] as JObject).native as int).toSigned(8));
  }
  vm.reg('java/lang/Long', 'toHexString', '(J)Ljava/lang/String;', (v, t, a) => s(i(a, 0).toUnsigned(64).toRadixString(16)), isStatic: true);
  vm.reg('java/lang/Integer', 'toBinaryString', '(I)Ljava/lang/String;', (v, t, a) => s((i(a, 0) & 0xFFFFFFFF).toRadixString(2)), isStatic: true);
  vm.reg('java/lang/Math', 'random', '()D', (v, t, a) => math.Random().nextDouble(), isStatic: true);
  vm.reg('java/lang/System', 'nanoTime', '()J', (v, t, a) => v.clock.elapsedMicroseconds * 1000, isStatic: true);
  vm.reg('java/lang/System', 'getenv', '(Ljava/lang/String;)Ljava/lang/String;', (v, t, a) => null, isStatic: true);
  vm.reg('java/lang/System', 'setOut', '(Ljava/io/PrintStream;)V', (v, t, a) => null, isStatic: true);
  vm.reg('java/lang/System', 'setErr', '(Ljava/io/PrintStream;)V', (v, t, a) => null, isStatic: true);
  vm.reg('java/io/PrintStream', '<init>', '(Ljava/io/OutputStream;)V', (v, t, a) => null);
  vm.reg('java/lang/Thread', 'isInterrupted', '()Z', (v, t, a) => 0);
  vm.reg('java/lang/Thread', 'getName', '()Ljava/lang/String;', (v, t, a) => s('Thread-0'));
  vm.reg('java/lang/Thread', 'setName', '(Ljava/lang/String;)V', (v, t, a) => null);
  vm.reg('java/lang/Thread', 'activeCount', '()I', (v, t, a) => v.threads.length, isStatic: true);
  vm.reg('java/lang/Class', 'isInstance', '(Ljava/lang/Object;)Z', (v, t, a) {
    final k = (a[0] as JObject).native as JClass;
    final o = a[1];
    return o is JObject && o.cls.isSubOf(k) ? 1 : 0;
  });
  vm.reg('java/lang/Class', 'getSimpleName', '()Ljava/lang/String;', (v, t, a) {
    final n = ((a[0] as JObject).native as JClass).name;
    return s(n.substring(n.lastIndexOf('/') + 1));
  });
  vm.reg('java/util/Hashtable', 'contains', '(Ljava/lang/Object;)Z', (v, t, a) {
    final m = (a[0] as JObject).native as Map;
    return m.values.any((e) => v.jequals(e, a[1])) ? 1 : 0;
  });

  // ---------- Date / Calendar / TimeZone ----------
  const D = 'java/util/Date', CA = 'java/util/Calendar', TZ = 'java/util/TimeZone';
  vm.defClass(D, obj);
  vm.defClass(TZ, obj);
  vm.defClass(CA, obj, statics: {
    'YEAR': 1, 'MONTH': 2, 'WEEK_OF_YEAR': 3, 'DATE': 5, 'DAY_OF_MONTH': 5, 'DAY_OF_YEAR': 6, 'DAY_OF_WEEK': 7,
    'AM_PM': 9, 'HOUR': 10, 'HOUR_OF_DAY': 11, 'MINUTE': 12, 'SECOND': 13, 'MILLISECOND': 14,
    'JANUARY': 0, 'SUNDAY': 1, 'MONDAY': 2, 'AM': 0, 'PM': 1,
  });
  vm.reg(D, '<init>', '()V', (v, t, a) { (a[0] as JObject).native = DateTime.now().millisecondsSinceEpoch; return null; });
  vm.reg(D, '<init>', '(J)V', (v, t, a) { (a[0] as JObject).native = i(a, 1); return null; });
  vm.reg(D, 'getTime', '()J', (v, t, a) => (a[0] as JObject).native);
  vm.reg(D, 'setTime', '(J)V', (v, t, a) { (a[0] as JObject).native = i(a, 1); return null; });
  vm.reg(D, 'toString', '()Ljava/lang/String;', (v, t, a) =>
      s(DateTime.fromMillisecondsSinceEpoch((a[0] as JObject).native as int).toString()));
  vm.reg(TZ, 'getDefault', '()Ljava/util/TimeZone;', (v, t, a) => JObject(v.loadClass(TZ)), isStatic: true);
  vm.reg(TZ, 'getTimeZone', '(Ljava/lang/String;)Ljava/util/TimeZone;', (v, t, a) => JObject(v.loadClass(TZ)), isStatic: true);
  vm.reg(TZ, 'getRawOffset', '()I', (v, t, a) => DateTime.now().timeZoneOffset.inMilliseconds);
  vm.reg(TZ, 'getID', '()Ljava/lang/String;', (v, t, a) => s('GMT'));
  vm.reg(CA, 'getInstance', '()Ljava/util/Calendar;', (v, t, a) {
    final o = JObject(v.loadClass(CA));
    o.native = DateTime.now().millisecondsSinceEpoch;
    return o;
  }, isStatic: true);
  vm.reg(CA, 'getInstance', '(Ljava/util/TimeZone;)Ljava/util/Calendar;', (v, t, a) {
    final o = JObject(v.loadClass(CA));
    o.native = DateTime.now().millisecondsSinceEpoch;
    return o;
  }, isStatic: true);
  DateTime dt(dynamic o) => DateTime.fromMillisecondsSinceEpoch((o as JObject).native as int);
  vm.reg(CA, 'setTime', '(Ljava/util/Date;)V', (v, t, a) { (a[0] as JObject).native = (a[1] as JObject).native; return null; });
  vm.reg(CA, 'getTime', '()Ljava/util/Date;', (v, t, a) {
    final o = JObject(v.loadClass(D));
    o.native = (a[0] as JObject).native;
    return o;
  });
  vm.reg(CA, 'setTimeInMillis', '(J)V', (v, t, a) { (a[0] as JObject).native = i(a, 1); return null; });
  vm.reg(CA, 'getTimeInMillis', '()J', (v, t, a) => (a[0] as JObject).native);
  vm.reg(CA, 'get', '(I)I', (v, t, a) {
    final d = dt(a[0]);
    switch (i(a, 1)) {
      case 1: return d.year;
      case 2: return d.month - 1;
      case 5: return d.day;
      case 6: return d.difference(DateTime(d.year, 1, 1)).inDays + 1;
      case 7: return d.weekday % 7 + 1;
      case 9: return d.hour >= 12 ? 1 : 0;
      case 10: return d.hour % 12;
      case 11: return d.hour;
      case 12: return d.minute;
      case 13: return d.second;
      case 14: return d.millisecond;
    }
    return 0;
  });
}
