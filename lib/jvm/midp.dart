import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as im;

import 'gfx.dart';
import 'vm.dart';

class StreamIn {
  Uint8List b;
  int p = 0;
  bool live = false, closed = false;
  String? error;
  StreamIn(this.b);
  int get avail => b.length - p;
  void add(Uint8List d) {
    final rest = avail;
    final n = Uint8List(rest + d.length);
    n.setRange(0, rest, b, p);
    n.setRange(rest, n.length, d);
    b = n;
    p = 0;
  }
}

class StreamOut {
  final BytesBuilder b = BytesBuilder();
  void Function(List<int>)? sink; // luồng mạng: gửi ngay
  void put(List<int> d) {
    if (sink != null) {
      sink!(d);
    } else {
      b.add(d);
    }
  }
}

class _G {
  final Gfx g;
  JObject? font;
  _G(this.g);
}

class _F {
  final int face, style, size;
  _F(this.face, this.style, this.size);
}

class _Rs {
  int next = 1;
  final Map<int, Uint8List> recs = {};
}

class _RsEnum {
  final List<int> ids;
  int i = 0;
  _RsEnum(this.ids);
}

/// Lớp MIDP (javax.microedition.*) + java.io + java.util.Timer cho trình giả lập.
class Midp {
  final Vm vm;
  final int width, height;
  late Surface screen = Surface(width, height);
  final Map<String, String> attrs;
  GlyphSet? Function(int px, bool bold)? glyphProvider;

  JObject? midlet, canvas, display;
  bool repaintReq = true, dirty = false, destroyed = false;
  int keyStates = 0, keyLatch = 0;
  final Map<String, _Rs> rms = {};
  void Function()? onRmsChanged;
  void Function(String)? onPlatformRequest;
  void Function()? onExit;
  void Function()? onFrame;
  final List<JObject> serial = [];
  JObject? form; // Form/List/TextBox/Alert đang hiển thị
  void Function()? onScreen;
  Timer? _alertT;

  void setCurrent(JObject o) {
    if (o.cls.isSubOf(vm.loadClass('javax/microedition/lcdui/Canvas'))) {
      form = null;
      onScreen?.call();
      if (!identical(canvas, o)) {
        canvas = o;
        repaintReq = true;
        _held.clear();
        keyStates = 0;
        _call(o, 'showNotify()V');
      }
      repaintReq = true;
    } else {
      form = o;
      onScreen?.call();
      if (o.cls.name == 'javax/microedition/lcdui/Alert') {
        final to = (o.f['\$timeout'] ?? 2000) as int;
        _alertT?.cancel();
        if (to > 0) _alertT = Timer(Duration(milliseconds: to), () { if (identical(form, o)) dismissAlert(); });
      }
    }
  }

  void dismissAlert() {
    final o = form;
    if (o == null) return;
    final next = o.f['\$next'];
    form = null;
    onScreen?.call();
    if (next != null) setCurrent(next as JObject);
    repaintReq = true;
  }

  /// Người dùng bấm một lệnh (Command) trên màn hình Form/List/TextBox.
  void fireCommand(JObject cmd) {
    final o = form;
    if (o == null) return;
    final l = o.f['\$cl'];
    if (l != null) {
      _call(l as JObject, 'commandAction(Ljavax/microedition/lcdui/Command;Ljavax/microedition/lcdui/Displayable;)V', [cmd, o]);
    } else if (o.cls.name == 'javax/microedition/lcdui/Alert') {
      dismissAlert();
    }
  }

  void selectListItem(int idx) {
    final o = form;
    if (o == null) return;
    o.f['\$sel'] = idx;
    final c = vm.loadClass('javax/microedition/lcdui/List').statics['SELECT_COMMAND'];
    if (c != null && (o.f['\$ltype'] ?? 3) == 3) fireCommand(c as JObject);
  }

  Midp(this.vm, this.width, this.height, this.attrs);

  // ---------------- giao diện với phía Flutter ----------------
  JMethod? _m(JObject o, String key) => vm.findVirtual(o.cls, key);

  void _call(JObject? o, String key, [List<dynamic> args = const []]) {
    if (o == null) return;
    final m = _m(o, key);
    if (m == null) return;
    try {
      vm.callUi(m, [o, ...args]);
    } on JavaThrow catch (e) {
      vm.onLog?.call('Lỗi trong $key: ${vm.jtoString(e.obj)}');
    }
  }

  /// Vẽ lại màn hình nếu có yêu cầu (gọi theo nhịp fps).
  void tick() {
    if (destroyed) return;
    if (serial.isNotEmpty) {
      for (final r in List<JObject>.of(serial)) {
        serial.remove(r);
        final m = _m(r, 'run()V');
        if (m != null) vm.newThread(m, [r]);
      }
    }
    final c = canvas;
    if (c != null && repaintReq && !_isGame(c)) {
      repaintReq = false;
      _paintNow();
    } else if (c != null && _isGame(c) && repaintReq) {
      // GameCanvas thường tự flushGraphics; vẫn gọi paint() nếu game ghi đè.
      repaintReq = false;
      final m = _m(c, 'paint(Ljavax/microedition/lcdui/Graphics;)V');
      if (m != null && m.native == null) _paintNow();
    }
    if (dirty) {
      dirty = false;
      onFrame?.call();
    }
  }

  bool _isGame(JObject c) => c.cls.isSubOf(vm.loadClass('javax/microedition/lcdui/game/GameCanvas'));

  void _paintNow() {
    final c = canvas;
    if (c == null) return;
    final gx = Gfx(screen);
    final go = vm.box('javax/microedition/lcdui/Graphics', _G(gx));
    _call(c, 'paint(Ljavax/microedition/lcdui/Graphics;)V', [go]);
    dirty = true;
  }

  static int keyCodeOf(String k) {
    if (k.length == 1 && k.codeUnitAt(0) >= 48 && k.codeUnitAt(0) <= 57) return k.codeUnitAt(0);
    switch (k) {
      case 'STAR': return 42;
      case 'HASH': return 35;
      case 'UP': return -1;
      case 'DOWN': return -2;
      case 'LEFT': return -3;
      case 'RIGHT': return -4;
      case 'OK': return -5;
      case 'SOFT1': return -6;
      case 'SOFT2': return -7;
      case 'BACK':
      case 'BACKSPACE': return -8;
    }
    return 0;
  }

  static int gameAction(int code) {
    switch (code) {
      case -1: case 50: return 1;
      case -2: case 56: return 6;
      case -3: case 52: return 2;
      case -4: case 54: return 5;
      case -5: case 53: return 8;
      case 49: return 9;
      case 51: return 10;
      case 55: return 11;
      case 57: return 12;
    }
    return 0;
  }

  /// Phím từ bàn phím ảo: phase = down | up | press.
  void key(String name, String phase) {
    final code = keyCodeOf(name);
    if (code == 0) return;
    if (phase == 'press') {
      keyEvent(code, true);
      keyEvent(code, false);
    } else {
      keyEvent(code, phase == 'down');
    }
  }

  final Set<int> _held = {};

  void keyEvent(int code, bool down) {
    final c = canvas;
    if (c == null) return;
    final ga = gameAction(code);
    if (down) {
      final rep = _held.contains(code);
      _held.add(code);
      if (ga != 0) {
        keyStates |= 1 << ga;
        keyLatch |= 1 << ga;
      }
      _call(c, rep ? 'keyRepeated(I)V' : 'keyPressed(I)V', [code]);
    } else {
      _held.remove(code);
      if (ga != 0) keyStates &= ~(1 << ga);
      _call(c, 'keyReleased(I)V', [code]);
    }
    repaintReq = true;
  }

  /// Gõ ký tự (bàn phím iOS): gửi như phím số/ký tự Unicode.
  void typeChar(String ch) {
    if (ch.isEmpty) return;
    final code = ch.codeUnitAt(0);
    keyEvent(code, true);
    keyEvent(code, false);
  }

  void pointer(String phase, int x, int y) {
    final c = canvas;
    if (c == null) return;
    final k = phase == 'down' ? 'pointerPressed(II)V' : (phase == 'up' ? 'pointerReleased(II)V' : 'pointerDragged(II)V');
    _call(c, k, [x, y]);
    repaintReq = true;
  }

  void start(JObject m) {
    midlet = m;
    final sa = vm.findVirtual(m.cls, 'startApp()V');
    if (sa != null) vm.newThread(sa, [m]);
  }

  void destroy() {
    destroyed = true;
  }

  // ---------------- cài đặt lớp ----------------
  void install() {
    const obj = 'java/lang/Object';
    JObject s(String v) => vm.str(v);
    String ss(dynamic o) {
      if (o == null) throw vm.ex('java/lang/NullPointerException');
      return (o as JObject).native as String;
    }
    int i(List a, int k) => a[k] as int;

    // ----- ngoại lệ -----
    const exs = {
      'java/io/IOException': 'java/lang/Exception',
      'java/io/EOFException': 'java/io/IOException',
      'java/io/UnsupportedEncodingException': 'java/io/IOException',
      'java/io/InterruptedIOException': 'java/io/IOException',
      'javax/microedition/io/ConnectionNotFoundException': 'java/io/IOException',
      'javax/microedition/rms/RecordStoreException': 'java/lang/Exception',
      'javax/microedition/rms/RecordStoreNotFoundException': 'javax/microedition/rms/RecordStoreException',
      'javax/microedition/rms/RecordStoreFullException': 'javax/microedition/rms/RecordStoreException',
      'javax/microedition/rms/RecordStoreNotOpenException': 'javax/microedition/rms/RecordStoreException',
      'javax/microedition/rms/InvalidRecordIDException': 'javax/microedition/rms/RecordStoreException',
      'javax/microedition/midlet/MIDletStateChangeException': 'java/lang/Exception',
    };
    exs.forEach((k, v) {
      vm.defClass(k, v);
      vm.reg(k, '<init>', '()V', (v, t, a) => null);
      vm.reg(k, '<init>', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['message'] = a[1]; return null; });
    });

    // ----- java.io -----
    const IN = 'java/io/InputStream', OUT = 'java/io/OutputStream';
    vm.defClass(IN, obj);
    vm.defClass('java/io/ByteArrayInputStream', IN);
    vm.defClass('java/io/DataInputStream', IN);
    vm.defClass(OUT, obj);
    vm.defClass('java/io/ByteArrayOutputStream', OUT);
    vm.defClass('java/io/DataOutputStream', OUT);
    vm.defClass('java/io/DataInput', null, isInterface: true);
    vm.defClass('java/io/DataOutput', null, isInterface: true);

    StreamIn inn(dynamic o) {
      final n = (o as JObject).native;
      if (n is StreamIn) return n;
      throw vm.ex('java/io/IOException', 'Luồng không hợp lệ');
    }

    StreamOut outt(dynamic o) {
      final n = (o as JObject).native;
      if (n is StreamOut) return n;
      throw vm.ex('java/io/IOException', 'Luồng không hợp lệ');
    }

    Uint8List need(StreamIn x, int n) {
      if (x.p + n > x.b.length) throw vm.ex('java/io/EOFException');
      final r = Uint8List.sublistView(x.b, x.p, x.p + n);
      x.p += n;
      return r;
    }

    vm.reg(IN, '<init>', '()V', (v, t, a) => null);
    vm.reg('java/io/ByteArrayInputStream', '<init>', '([B)V', (v, t, a) {
      final d = (a[1] as JArray).data;
      (a[0] as JObject).native = StreamIn(Uint8List.fromList([for (final e in d) (e as int) & 255]));
      return null;
    });
    vm.reg('java/io/ByteArrayInputStream', '<init>', '([BII)V', (v, t, a) {
      final d = (a[1] as JArray).data;
      final o = i(a, 2), n = i(a, 3);
      (a[0] as JObject).native = StreamIn(Uint8List.fromList([for (var k = o; k < o + n; k++) (d[k] as int) & 255]));
      return null;
    });
    vm.reg('java/io/DataInputStream', '<init>', '(Ljava/io/InputStream;)V', (v, t, a) {
      (a[0] as JObject).native = inn(a[1]);
      return null;
    });
    dynamic rd(JThread t, StreamIn x, int Function() needFn, dynamic Function() f, {int slots = 1}) =>
        !x.live ? f() : vm.block(t, () => x.closed || x.avail >= needFn(), f, slots: slots);
    int u16(StreamIn x) => x.avail < 2 ? 2 : 2 + ((x.b[x.p] << 8) | x.b[x.p + 1]);
    int readInto(StreamIn x, JArray arr, int off, int len) {
      if (len == 0) return 0;
      if (x.p >= x.b.length) return -1;
      final n = len < x.b.length - x.p ? len : x.b.length - x.p;
      for (var k = 0; k < n; k++) {
        arr.data[off + k] = x.b[x.p + k].toSigned(8);
      }
      x.p += n;
      return n;
    }
    vm.reg(IN, 'read', '()I', (v, t, a) {
      final x = inn(a[0]);
      return rd(t, x, () => 1, () => x.p < x.b.length ? x.b[x.p++] : -1);
    });
    vm.reg(IN, 'read', '([B)I', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 1, () => readInto(x, a[1] as JArray, 0, (a[1] as JArray).length)); });
    vm.reg(IN, 'read', '([BII)I', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 1, () => readInto(x, a[1] as JArray, i(a, 2), i(a, 3))); });
    vm.reg(IN, 'available', '()I', (v, t, a) => inn(a[0]).avail);
    vm.reg(IN, 'skip', '(J)J', (v, t, a) {
      final x = inn(a[0]);
      final n = i(a, 1) < x.avail ? i(a, 1) : x.avail;
      x.p += n;
      return n;
    });
    vm.reg(IN, 'close', '()V', (v, t, a) {
      final x = (a[0] as JObject).native;
      if (x is StreamIn) x.closed = true;
      return null;
    });
    vm.reg(IN, 'mark', '(I)V', (v, t, a) => null);
    vm.reg(IN, 'reset', '()V', (v, t, a) { inn(a[0]).p = 0; return null; });
    vm.reg(IN, 'markSupported', '()Z', (v, t, a) => 0);
    vm.reg(IN, 'readByte', '()B', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 1, () => need(x, 1)[0].toSigned(8)); });
    vm.reg(IN, 'readUnsignedByte', '()I', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 1, () => need(x, 1)[0]); });
    vm.reg(IN, 'readBoolean', '()Z', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 1, () => need(x, 1)[0] != 0 ? 1 : 0); });
    vm.reg(IN, 'readShort', '()S', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 2, () => ByteData.sublistView(need(x, 2)).getInt16(0, Endian.big)); });
    vm.reg(IN, 'readUnsignedShort', '()I', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 2, () => ByteData.sublistView(need(x, 2)).getUint16(0, Endian.big)); });
    vm.reg(IN, 'readChar', '()C', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 2, () => ByteData.sublistView(need(x, 2)).getUint16(0, Endian.big)); });
    vm.reg(IN, 'readInt', '()I', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 4, () => ByteData.sublistView(need(x, 4)).getInt32(0, Endian.big)); });
    vm.reg(IN, 'readLong', '()J', (v, t, a) { final x = inn(a[0]); return rd(t, x, () => 8, () => ByteData.sublistView(need(x, 8)).getInt64(0, Endian.big), slots: 2); });
    vm.reg(IN, 'readUTF', '()Ljava/lang/String;', (v, t, a) {
      final x = inn(a[0]);
      return rd(t, x, () => u16(x), () {
        final n = ByteData.sublistView(need(x, 2)).getUint16(0, Endian.big);
        return s(utf8.decode(need(x, n), allowMalformed: true));
      });
    });
    void fully(StreamIn x, JArray arr, int off, int n) {
      final b = need(x, n);
      for (var k = 0; k < b.length; k++) {
        arr.data[off + k] = b[k].toSigned(8);
      }
    }
    vm.reg(IN, 'readFully', '([B)V', (v, t, a) {
      final x = inn(a[0]);
      final arr = a[1] as JArray;
      rd(t, x, () => arr.length, () { fully(x, arr, 0, arr.length); return null; }, slots: 0);
      return null;
    });
    vm.reg(IN, 'readFully', '([BII)V', (v, t, a) {
      final x = inn(a[0]);
      final arr = a[1] as JArray;
      rd(t, x, () => i(a, 3), () { fully(x, arr, i(a, 2), i(a, 3)); return null; }, slots: 0);
      return null;
    });

    vm.reg(OUT, '<init>', '()V', (v, t, a) => null);
    vm.reg('java/io/ByteArrayOutputStream', '<init>', '()V', (v, t, a) { (a[0] as JObject).native = StreamOut(); return null; });
    vm.reg('java/io/ByteArrayOutputStream', '<init>', '(I)V', (v, t, a) { (a[0] as JObject).native = StreamOut(); return null; });
    vm.reg('java/io/DataOutputStream', '<init>', '(Ljava/io/OutputStream;)V', (v, t, a) {
      (a[0] as JObject).native = outt(a[1]);
      return null;
    });
    vm.reg(OUT, 'write', '(I)V', (v, t, a) { outt(a[0]).put([i(a, 1) & 255]); return null; });
    vm.reg(OUT, 'write', '([B)V', (v, t, a) {
      outt(a[0]).put([for (final e in (a[1] as JArray).data) (e as int) & 255]);
      return null;
    });
    vm.reg(OUT, 'write', '([BII)V', (v, t, a) {
      final d = (a[1] as JArray).data;
      outt(a[0]).put([for (var k = i(a, 2); k < i(a, 2) + i(a, 3); k++) (d[k] as int) & 255]);
      return null;
    });
    vm.reg(OUT, 'flush', '()V', (v, t, a) => null);
    vm.reg(OUT, 'close', '()V', (v, t, a) => null);
    vm.reg(OUT, 'writeByte', '(I)V', (v, t, a) { outt(a[0]).put([i(a, 1) & 255]); return null; });
    vm.reg(OUT, 'writeBoolean', '(Z)V', (v, t, a) { outt(a[0]).put([i(a, 1) != 0 ? 1 : 0]); return null; });
    void wr(dynamic o, int n, void Function(ByteData) f) {
      final bd = ByteData(n);
      f(bd);
      outt(o).put(bd.buffer.asUint8List());
    }
    vm.reg(OUT, 'writeShort', '(I)V', (v, t, a) { wr(a[0], 2, (b) => b.setInt16(0, i(a, 1).toSigned(16), Endian.big)); return null; });
    vm.reg(OUT, 'writeChar', '(I)V', (v, t, a) { wr(a[0], 2, (b) => b.setUint16(0, i(a, 1) & 0xFFFF, Endian.big)); return null; });
    vm.reg(OUT, 'writeInt', '(I)V', (v, t, a) { wr(a[0], 4, (b) => b.setInt32(0, i(a, 1).toSigned(32), Endian.big)); return null; });
    vm.reg(OUT, 'writeLong', '(J)V', (v, t, a) { wr(a[0], 8, (b) => b.setInt64(0, i(a, 1), Endian.big)); return null; });
    vm.reg(OUT, 'writeUTF', '(Ljava/lang/String;)V', (v, t, a) {
      final b = utf8.encode(ss(a[1]));
      wr(a[0], 2, (d) => d.setUint16(0, b.length, Endian.big));
      outt(a[0]).put(b);
      return null;
    });
    vm.reg('java/io/ByteArrayOutputStream', 'toByteArray', '()[B', (v, t, a) =>
        JArray('[B', [for (final e in outt(a[0]).b.toBytes()) e.toSigned(8)]));
    vm.reg('java/io/ByteArrayOutputStream', 'size', '()I', (v, t, a) => outt(a[0]).b.length);
    vm.reg('java/io/ByteArrayOutputStream', 'reset', '()V', (v, t, a) { outt(a[0]).b.clear(); return null; });

    // ----- Class: tài nguyên, forName -----
    const C = 'java/lang/Class';
    vm.reg(C, 'getResourceAsStream', '(Ljava/lang/String;)Ljava/io/InputStream;', (v, t, a) {
      var n = ss(a[1]);
      if (n.startsWith('/')) n = n.substring(1);
      final d = v.jarResources[n];
      if (d == null) return null;
      final o = JObject(v.loadClass('java/io/ByteArrayInputStream'));
      o.native = StreamIn(d);
      return o;
    });
    vm.reg(C, 'forName', '(Ljava/lang/String;)Ljava/lang/Class;', (v, t, a) {
      final n = ss(a[0]).replaceAll('.', '/');
      try {
        return v.classObject(v.loadClass(n));
      } on JavaThrow {
        throw v.ex('java/lang/ClassNotFoundException', ss(a[0]));
      }
    }, isStatic: true);
    vm.reg(C, 'newInstance', '()Ljava/lang/Object;', (v, t, a) {
      final k = (a[0] as JObject).native as JClass;
      return v.newInstance(k.name);
    });

    // ----- Timer / TimerTask -----
    vm.defClass('java/util/TimerTask', obj, ifaces: ['java/lang/Runnable']);
    vm.defClass('java/util/Timer', obj);
    vm.reg('java/util/TimerTask', '<init>', '()V', (v, t, a) => null);
    vm.reg('java/util/TimerTask', 'run', '()V', (v, t, a) => null);
    vm.reg('java/util/TimerTask', 'cancel', '()Z', (v, t, a) {
      final n = (a[0] as JObject).native;
      if (n is VmTimer) n.cancelled = true;
      return 1;
    });
    vm.reg('java/util/Timer', '<init>', '()V', (v, t, a) { (a[0] as JObject).native = <VmTimer>[]; return null; });
    void sched(Vm v, dynamic timer, dynamic task, int delay, int period) {
      final l = (timer as JObject).native as List<VmTimer>;
      final e = VmTimer(task as JObject, v.clock.elapsedMilliseconds + delay, period);
      task.native = e;
      l.add(e);
      v.timers.add(e);
    }
    vm.reg('java/util/Timer', 'schedule', '(Ljava/util/TimerTask;J)V', (v, t, a) { sched(v, a[0], a[1], i(a, 2), 0); return null; });
    vm.reg('java/util/Timer', 'schedule', '(Ljava/util/TimerTask;JJ)V', (v, t, a) { sched(v, a[0], a[1], i(a, 2), i(a, 4)); return null; });
    vm.reg('java/util/Timer', 'scheduleAtFixedRate', '(Ljava/util/TimerTask;JJ)V', (v, t, a) { sched(v, a[0], a[1], i(a, 2), i(a, 4)); return null; });
    vm.reg('java/util/Timer', 'cancel', '()V', (v, t, a) {
      for (final e in (a[0] as JObject).native as List<VmTimer>) {
        e.cancelled = true;
      }
      return null;
    });

    // ----- MIDlet -----
    const ML = 'javax/microedition/midlet/MIDlet';
    vm.defClass(ML, obj);
    vm.reg(ML, '<init>', '()V', (v, t, a) => null);
    vm.reg(ML, 'notifyDestroyed', '()V', (v, t, a) { onExit?.call(); return null; });
    vm.reg(ML, 'notifyPaused', '()V', (v, t, a) => null);
    vm.reg(ML, 'resumeRequest', '()V', (v, t, a) => null);
    vm.reg(ML, 'getAppProperty', '(Ljava/lang/String;)Ljava/lang/String;', (v, t, a) {
      final r = attrs[ss(a[1])];
      return r == null ? null : s(r);
    });
    vm.reg(ML, 'platformRequest', '(Ljava/lang/String;)Z', (v, t, a) { onPlatformRequest?.call(ss(a[1])); return 0; });
    vm.reg(ML, 'checkPermission', '(Ljava/lang/String;)I', (v, t, a) => 1);

    // ----- lcdui cơ bản -----
    const D = 'javax/microedition/lcdui/Displayable';
    const CV = 'javax/microedition/lcdui/Canvas';
    const GC = 'javax/microedition/lcdui/game/GameCanvas';
    const DP = 'javax/microedition/lcdui/Display';
    const GR = 'javax/microedition/lcdui/Graphics';
    const IM = 'javax/microedition/lcdui/Image';
    const FT = 'javax/microedition/lcdui/Font';
    const CM = 'javax/microedition/lcdui/Command';
    vm.defClass('javax/microedition/lcdui/CommandListener', null, isInterface: true);
    vm.defClass(D, obj);
    vm.defClass(CV, D, statics: {
      'UP': 1, 'DOWN': 6, 'LEFT': 2, 'RIGHT': 5, 'FIRE': 8, 'GAME_A': 9, 'GAME_B': 10, 'GAME_C': 11, 'GAME_D': 12,
      'KEY_NUM0': 48, 'KEY_NUM1': 49, 'KEY_NUM2': 50, 'KEY_NUM3': 51, 'KEY_NUM4': 52, 'KEY_NUM5': 53,
      'KEY_NUM6': 54, 'KEY_NUM7': 55, 'KEY_NUM8': 56, 'KEY_NUM9': 57, 'KEY_STAR': 42, 'KEY_POUND': 35,
    });
    vm.defClass(GC, CV, statics: {
      'UP_PRESSED': 2, 'DOWN_PRESSED': 64, 'LEFT_PRESSED': 4, 'RIGHT_PRESSED': 32, 'FIRE_PRESSED': 256,
      'GAME_A_PRESSED': 512, 'GAME_B_PRESSED': 1024, 'GAME_C_PRESSED': 2048, 'GAME_D_PRESSED': 4096,
    });
    vm.defClass(DP, obj);
    vm.defClass(GR, obj, statics: {'HCENTER': 1, 'VCENTER': 2, 'LEFT': 4, 'RIGHT': 8, 'TOP': 16, 'BOTTOM': 32, 'BASELINE': 64, 'SOLID': 0, 'DOTTED': 1});
    vm.defClass(IM, obj);
    vm.defClass(FT, obj, statics: {
      'FACE_SYSTEM': 0, 'FACE_MONOSPACE': 32, 'FACE_PROPORTIONAL': 64,
      'STYLE_PLAIN': 0, 'STYLE_BOLD': 1, 'STYLE_ITALIC': 2, 'STYLE_UNDERLINED': 4,
      'SIZE_SMALL': 8, 'SIZE_MEDIUM': 0, 'SIZE_LARGE': 16,
    });
    vm.defClass(CM, obj, statics: {'SCREEN': 1, 'BACK': 2, 'CANCEL': 3, 'OK': 4, 'HELP': 5, 'STOP': 6, 'EXIT': 7, 'ITEM': 8});
    vm.defClass('javax/microedition/lcdui/Item', obj);
    vm.defClass('javax/microedition/lcdui/Screen', D);
    vm.defClass('javax/microedition/lcdui/Form', 'javax/microedition/lcdui/Screen');
    vm.defClass('javax/microedition/lcdui/List', 'javax/microedition/lcdui/Screen');
    vm.defClass('javax/microedition/lcdui/Alert', 'javax/microedition/lcdui/Screen');
    vm.defClass('javax/microedition/lcdui/TextBox', 'javax/microedition/lcdui/Screen');
    vm.defClass('javax/microedition/lcdui/AlertType', obj);

    // Displayable
    vm.reg(D, '<init>', '()V', (v, t, a) => null);
    vm.reg(D, 'getWidth', '()I', (v, t, a) => width);
    vm.reg(D, 'getHeight', '()I', (v, t, a) => height);
    vm.reg(D, 'isShown', '()Z', (v, t, a) => identical(canvas, a[0]) ? 1 : 0);
    vm.reg(D, 'setTitle', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['\$title'] = a[1]; onScreen?.call(); return null; });
    vm.reg(D, 'getTitle', '()Ljava/lang/String;', (v, t, a) => (a[0] as JObject).f['\$title']);
    vm.reg(D, 'setCommandListener', '(Ljavax/microedition/lcdui/CommandListener;)V', (v, t, a) { (a[0] as JObject).f['\$cl'] = a[1]; return null; });
    vm.reg(D, 'addCommand', '(Ljavax/microedition/lcdui/Command;)V', (v, t, a) {
      final l = ((a[0] as JObject).f['\$cmds'] ??= <JObject>[]) as List;
      if (!l.contains(a[1])) l.add(a[1]);
      return null;
    });
    vm.reg(D, 'removeCommand', '(Ljavax/microedition/lcdui/Command;)V', (v, t, a) {
      ((a[0] as JObject).f['\$cmds'] as List?)?.remove(a[1]);
      return null;
    });
    vm.reg(D, 'sizeChanged', '(II)V', (v, t, a) => null);

    // Canvas
    vm.reg(CV, '<init>', '()V', (v, t, a) => null);
    vm.reg(CV, 'repaint', '()V', (v, t, a) { repaintReq = true; return null; });
    vm.reg(CV, 'repaint', '(IIII)V', (v, t, a) { repaintReq = true; return null; });
    vm.reg(CV, 'serviceRepaints', '()V', (v, t, a) {
      if (identical(canvas, a[0])) {
        repaintReq = false;
        _paintNow();
      }
      return null;
    });
    for (final n in const ['showNotify', 'hideNotify']) {
      vm.reg(CV, n, '()V', (v, t, a) => null);
    }
    for (final n in const ['keyPressed', 'keyReleased', 'keyRepeated']) {
      vm.reg(CV, n, '(I)V', (v, t, a) => null);
    }
    for (final n in const ['pointerPressed', 'pointerReleased', 'pointerDragged']) {
      vm.reg(CV, n, '(II)V', (v, t, a) => null);
    }
    vm.reg(CV, 'setFullScreenMode', '(Z)V', (v, t, a) => null);
    vm.reg(CV, 'hasPointerEvents', '()Z', (v, t, a) => 1);
    vm.reg(CV, 'hasPointerMotionEvents', '()Z', (v, t, a) => 1);
    vm.reg(CV, 'hasRepeatEvents', '()Z', (v, t, a) => 1);
    vm.reg(CV, 'isDoubleBuffered', '()Z', (v, t, a) => 1);
    vm.reg(CV, 'getGameAction', '(I)I', (v, t, a) => gameAction(i(a, 1)));
    vm.reg(CV, 'getKeyCode', '(I)I', (v, t, a) {
      switch (i(a, 1)) {
        case 1: return -1;
        case 6: return -2;
        case 2: return -3;
        case 5: return -4;
        case 8: return -5;
        case 9: return 49;
        case 10: return 51;
        case 11: return 55;
        case 12: return 57;
      }
      return 0;
    });
    vm.reg(CV, 'getKeyName', '(I)Ljava/lang/String;', (v, t, a) => s('${i(a, 1)}'));

    // GameCanvas
    Surface gcBuf(dynamic o) {
      final ob = o as JObject;
      return (ob.native ??= Surface(width, height)) as Surface;
    }
    vm.reg(GC, '<init>', '(Z)V', (v, t, a) => null);
    vm.reg(GC, 'getGraphics', '()Ljavax/microedition/lcdui/Graphics;', (v, t, a) =>
        v.box(GR, _G(Gfx(gcBuf(a[0])))));
    void flush(dynamic o) {
      final b = gcBuf(o);
      screen.px.setAll(0, b.px);
      dirty = true;
    }
    vm.reg(GC, 'flushGraphics', '()V', (v, t, a) { flush(a[0]); return null; });
    vm.reg(GC, 'flushGraphics', '(IIII)V', (v, t, a) { flush(a[0]); return null; });
    vm.reg(GC, 'getKeyStates', '()I', (v, t, a) {
      final r = keyStates | keyLatch;
      keyLatch = 0;
      return r;
    });

    // Display
    vm.reg(DP, 'getDisplay', '(Ljavax/microedition/midlet/MIDlet;)Ljavax/microedition/lcdui/Display;', (v, t, a) =>
        display ??= JObject(v.loadClass(DP)), isStatic: true);
    void setCur(Vm v, dynamic d) {
      if (d != null) setCurrent(d as JObject);
    }
    vm.reg(DP, 'setCurrent', '(Ljavax/microedition/lcdui/Displayable;)V', (v, t, a) { setCur(v, a[1]); return null; });
    vm.reg(DP, 'setCurrent', '(Ljavax/microedition/lcdui/Alert;Ljavax/microedition/lcdui/Displayable;)V', (v, t, a) {
      (a[1] as JObject).f['\$next'] = a[2];
      setCur(v, a[1]);
      return null;
    });
    vm.reg(DP, 'getCurrent', '()Ljavax/microedition/lcdui/Displayable;', (v, t, a) => form ?? canvas);
    vm.reg(DP, 'getBestImageWidth', '(I)I', (v, t, a) => 32);
    vm.reg(DP, 'getBestImageHeight', '(I)I', (v, t, a) => 32);
    vm.reg(DP, 'getColor', '(I)I', (v, t, a) => i(a, 1) == 1 || i(a, 1) == 3 ? 0 : 0xFFFFFF);
    vm.reg(DP, 'setCurrentItem', '(Ljavax/microedition/lcdui/Item;)V', (v, t, a) => null);
    vm.reg(DP, 'callSerially', '(Ljava/lang/Runnable;)V', (v, t, a) { serial.add(a[1] as JObject); return null; });
    vm.reg(DP, 'isColor', '()Z', (v, t, a) => 1);
    vm.reg(DP, 'numColors', '()I', (v, t, a) => 16777216);
    vm.reg(DP, 'numAlphaLevels', '()I', (v, t, a) => 256);
    vm.reg(DP, 'vibrate', '(I)Z', (v, t, a) => 1);
    vm.reg(DP, 'flashBacklight', '(I)Z', (v, t, a) => 1);

    // Command
    vm.reg(CM, '<init>', '(Ljava/lang/String;II)V', (v, t, a) {
      final o = a[0] as JObject;
      o.f['\$l'] = a[1];
      o.f['\$t'] = a[2];
      o.f['\$p'] = a[3];
      return null;
    });
    vm.reg(CM, 'getLabel', '()Ljava/lang/String;', (v, t, a) => (a[0] as JObject).f['\$l']);
    vm.reg(CM, 'getCommandType', '()I', (v, t, a) => (a[0] as JObject).f['\$t']);
    vm.reg(CM, 'getPriority', '()I', (v, t, a) => (a[0] as JObject).f['\$p']);
    _installScreens();

    // ----- Font -----
    JObject mkFont(int face, int style, int size) => vm.box(FT, _F(face, style, size));
    _F fo(dynamic o) => (o as JObject).native as _F;
    GlyphSet gsOf(_F f) {
      final px = f.size == 8 ? 9 : (f.size == 16 ? 15 : 12);
      final g = glyphProvider?.call(px, (f.style & 1) != 0);
      return g ?? GlyphSet((px * 1.2).round(), px, const {});
    }
    vm.reg(FT, 'getFont', '(III)Ljavax/microedition/lcdui/Font;', (v, t, a) => mkFont(i(a, 0), i(a, 1), i(a, 2)), isStatic: true);
    vm.reg(FT, 'getDefaultFont', '()Ljavax/microedition/lcdui/Font;', (v, t, a) => mkFont(0, 0, 0), isStatic: true);
    vm.reg(FT, 'getHeight', '()I', (v, t, a) => gsOf(fo(a[0])).height);
    vm.reg(FT, 'getBaselinePosition', '()I', (v, t, a) => gsOf(fo(a[0])).ascent);
    vm.reg(FT, 'getStyle', '()I', (v, t, a) => fo(a[0]).style);
    vm.reg(FT, 'getSize', '()I', (v, t, a) => fo(a[0]).size);
    vm.reg(FT, 'getFace', '()I', (v, t, a) => fo(a[0]).face);
    vm.reg(FT, 'isBold', '()Z', (v, t, a) => (fo(a[0]).style & 1) != 0 ? 1 : 0);
    vm.reg(FT, 'isItalic', '()Z', (v, t, a) => (fo(a[0]).style & 2) != 0 ? 1 : 0);
    vm.reg(FT, 'isPlain', '()Z', (v, t, a) => fo(a[0]).style == 0 ? 1 : 0);
    int sw(_F f, String str) {
      final g = gsOf(f);
      var w = 0;
      for (final c in str.codeUnits) {
        w += g.adv(c);
      }
      return w;
    }
    vm.reg(FT, 'stringWidth', '(Ljava/lang/String;)I', (v, t, a) => sw(fo(a[0]), ss(a[1])));
    vm.reg(FT, 'charWidth', '(C)I', (v, t, a) => sw(fo(a[0]), String.fromCharCode(i(a, 1))));
    vm.reg(FT, 'substringWidth', '(Ljava/lang/String;II)I', (v, t, a) => sw(fo(a[0]), ss(a[1]).substring(i(a, 2), i(a, 2) + i(a, 3))));
    vm.reg(FT, 'charsWidth', '([CII)I', (v, t, a) {
      final d = (a[1] as JArray).data;
      return sw(fo(a[0]), String.fromCharCodes([for (var k = i(a, 2); k < i(a, 2) + i(a, 3); k++) d[k] as int]));
    });

    // ----- Image -----
    Surface sf(dynamic o) => (o as JObject).native as Surface;
    JObject mkImg(Surface x, {bool mutable = false}) {
      final o = vm.box(IM, x);
      o.f['\$m'] = mutable ? 1 : 0;
      return o;
    }
    Surface? decode(Uint8List b) {
      final d = im.decodeImage(b);
      if (d == null) return null;
      final out = Surface(d.width, d.height, fill: 0, hasAlpha: true);
      for (var y = 0; y < d.height; y++) {
        for (var x = 0; x < d.width; x++) {
          final p = d.getPixel(x, y);
          final r = (p.rNormalized * 255).round(), g = (p.gNormalized * 255).round(), bl = (p.bNormalized * 255).round();
          final al = d.hasAlpha ? (p.aNormalized * 255).round() : 255;
          out.px[y * d.width + x] = (al << 24) | (r << 16) | (g << 8) | bl;
        }
      }
      return out;
    }
    vm.reg(IM, 'createImage', '(II)Ljavax/microedition/lcdui/Image;', (v, t, a) => mkImg(Surface(i(a, 0), i(a, 1)), mutable: true), isStatic: true);
    vm.reg(IM, 'createImage', '(Ljava/lang/String;)Ljavax/microedition/lcdui/Image;', (v, t, a) {
      var n = ss(a[0]);
      if (n.startsWith('/')) n = n.substring(1);
      final d = v.jarResources[n];
      if (d == null) throw v.ex('java/io/IOException', n);
      final x = decode(d);
      if (x == null) throw v.ex('java/io/IOException', 'Ảnh không hợp lệ: $n');
      return mkImg(x);
    }, isStatic: true);
    vm.reg(IM, 'createImage', '([BII)Ljavax/microedition/lcdui/Image;', (v, t, a) {
      final d = (a[0] as JArray).data;
      final b = Uint8List.fromList([for (var k = i(a, 1); k < i(a, 1) + i(a, 2); k++) (d[k] as int) & 255]);
      final x = decode(b);
      if (x == null) throw v.ex('java/lang/IllegalArgumentException', 'Ảnh không hợp lệ');
      return mkImg(x);
    }, isStatic: true);
    vm.reg(IM, 'createImage', '(Ljavax/microedition/lcdui/Image;)Ljavax/microedition/lcdui/Image;', (v, t, a) => mkImg(sf(a[0]).copy()), isStatic: true);
    vm.reg(IM, 'createImage', '(Ljavax/microedition/lcdui/Image;IIIII)Ljavax/microedition/lcdui/Image;', (v, t, a) {
      final src = sf(a[0]);
      final x = i(a, 1), y = i(a, 2), w = i(a, 3), h = i(a, 4), tr = i(a, 5);
      final out = Surface(tr >= 4 ? h : w, tr >= 4 ? w : h, fill: 0, hasAlpha: true);
      Gfx(out).blit(src, x, y, w, h, tr, 0, 0);
      return mkImg(out);
    }, isStatic: true);
    vm.reg(IM, 'createRGBImage', '([IIIZ)Ljavax/microedition/lcdui/Image;', (v, t, a) {
      final d = (a[0] as JArray).data;
      final w = i(a, 1), h = i(a, 2);
      final al = i(a, 3) != 0;
      final out = Surface(w, h, fill: 0, hasAlpha: al);
      for (var k = 0; k < w * h && k < d.length; k++) {
        final c = (d[k] as int) & 0xFFFFFFFF;
        out.px[k] = al ? c : (0xFF000000 | c);
      }
      return mkImg(out);
    }, isStatic: true);
    vm.reg(IM, 'getWidth', '()I', (v, t, a) => sf(a[0]).w);
    vm.reg(IM, 'getHeight', '()I', (v, t, a) => sf(a[0]).h);
    vm.reg(IM, 'isMutable', '()Z', (v, t, a) => (a[0] as JObject).f['\$m'] ?? 0);
    vm.reg(IM, 'getGraphics', '()Ljavax/microedition/lcdui/Graphics;', (v, t, a) => v.box(GR, _G(Gfx(sf(a[0])))));
    vm.reg(IM, 'getRGB', '([IIIIIII)V', (v, t, a) {
      final arr = (a[1] as JArray).data;
      final src = sf(a[0]);
      final off = i(a, 2), scan = i(a, 3), x = i(a, 4), y = i(a, 5), w = i(a, 6), h = i(a, 7);
      for (var j = 0; j < h; j++) {
        for (var k = 0; k < w; k++) {
          arr[off + j * scan + k] = src.px[(y + j) * src.w + x + k].toSigned(32);
        }
      }
      return null;
    });

    // ----- Graphics -----
    _G gg(dynamic o) => (o as JObject).native as _G;
    vm.reg(GR, 'setColor', '(I)V', (v, t, a) { gg(a[0]).g.color = 0xFF000000 | (i(a, 1) & 0xFFFFFF); return null; });
    vm.reg(GR, 'setColor', '(III)V', (v, t, a) {
      gg(a[0]).g.color = 0xFF000000 | ((i(a, 1) & 255) << 16) | ((i(a, 2) & 255) << 8) | (i(a, 3) & 255);
      return null;
    });
    vm.reg(GR, 'setGrayScale', '(I)V', (v, t, a) { final x = i(a, 1) & 255; gg(a[0]).g.color = 0xFF000000 | (x << 16) | (x << 8) | x; return null; });
    vm.reg(GR, 'getColor', '()I', (v, t, a) => gg(a[0]).g.color & 0xFFFFFF);
    vm.reg(GR, 'getRedComponent', '()I', (v, t, a) => (gg(a[0]).g.color >> 16) & 255);
    vm.reg(GR, 'getGreenComponent', '()I', (v, t, a) => (gg(a[0]).g.color >> 8) & 255);
    vm.reg(GR, 'getBlueComponent', '()I', (v, t, a) => gg(a[0]).g.color & 255);
    vm.reg(GR, 'setStrokeStyle', '(I)V', (v, t, a) => null);
    vm.reg(GR, 'getStrokeStyle', '()I', (v, t, a) => 0);
    vm.reg(GR, 'setFont', '(Ljavax/microedition/lcdui/Font;)V', (v, t, a) { gg(a[0]).font = a[1] as JObject?; return null; });
    vm.reg(GR, 'getFont', '()Ljavax/microedition/lcdui/Font;', (v, t, a) => gg(a[0]).font ?? mkFont(0, 0, 0));
    vm.reg(GR, 'translate', '(II)V', (v, t, a) { final g = gg(a[0]).g; g.tx += i(a, 1); g.ty += i(a, 2); return null; });
    vm.reg(GR, 'getTranslateX', '()I', (v, t, a) => gg(a[0]).g.tx);
    vm.reg(GR, 'getTranslateY', '()I', (v, t, a) => gg(a[0]).g.ty);
    vm.reg(GR, 'setClip', '(IIII)V', (v, t, a) { gg(a[0]).g.setClip(i(a, 1), i(a, 2), i(a, 3), i(a, 4)); return null; });
    vm.reg(GR, 'clipRect', '(IIII)V', (v, t, a) { gg(a[0]).g.clipRect(i(a, 1), i(a, 2), i(a, 3), i(a, 4)); return null; });
    vm.reg(GR, 'getClipX', '()I', (v, t, a) { final g = gg(a[0]).g; return g.cx - g.tx; });
    vm.reg(GR, 'getClipY', '()I', (v, t, a) { final g = gg(a[0]).g; return g.cy - g.ty; });
    vm.reg(GR, 'getClipWidth', '()I', (v, t, a) => gg(a[0]).g.cw);
    vm.reg(GR, 'getClipHeight', '()I', (v, t, a) => gg(a[0]).g.ch);
    vm.reg(GR, 'drawLine', '(IIII)V', (v, t, a) { gg(a[0]).g.drawLine(i(a, 1), i(a, 2), i(a, 3), i(a, 4)); return null; });
    vm.reg(GR, 'fillRect', '(IIII)V', (v, t, a) { final g = gg(a[0]).g; g.fillRect(i(a, 1), i(a, 2), i(a, 3), i(a, 4)); return null; });
    vm.reg(GR, 'drawRect', '(IIII)V', (v, t, a) { final g = gg(a[0]).g; g.drawRect(i(a, 1), i(a, 2), i(a, 3), i(a, 4)); return null; });
    vm.reg(GR, 'fillRoundRect', '(IIIIII)V', (v, t, a) { final g = gg(a[0]).g; g.fillRoundRect(i(a, 1), i(a, 2), i(a, 3), i(a, 4), i(a, 5), i(a, 6)); return null; });
    vm.reg(GR, 'drawRoundRect', '(IIIIII)V', (v, t, a) { final g = gg(a[0]).g; g.drawRoundRect(i(a, 1), i(a, 2), i(a, 3), i(a, 4), i(a, 5), i(a, 6)); return null; });
    vm.reg(GR, 'fillArc', '(IIIIII)V', (v, t, a) { final g = gg(a[0]).g; g.fillArc(i(a, 1), i(a, 2), i(a, 3), i(a, 4), i(a, 5), i(a, 6)); return null; });
    vm.reg(GR, 'drawArc', '(IIIIII)V', (v, t, a) { final g = gg(a[0]).g; g.drawArc(i(a, 1), i(a, 2), i(a, 3), i(a, 4), i(a, 5), i(a, 6)); return null; });
    vm.reg(GR, 'fillTriangle', '(IIIIII)V', (v, t, a) {
      final g = gg(a[0]).g;
      g.fillTriangle(i(a, 1), i(a, 2), i(a, 3), i(a, 4), i(a, 5), i(a, 6));
      return null;
    });
    void text(_G g, String str, int x, int y, int anchor) {
      final gs = gsOf(g.font == null ? _F(0, 0, 0) : fo(g.font));
      g.g.drawText(gs, str, x, y, anchor);
    }
    vm.reg(GR, 'drawString', '(Ljava/lang/String;III)V', (v, t, a) { text(gg(a[0]), ss(a[1]), i(a, 2), i(a, 3), i(a, 4)); return null; });
    vm.reg(GR, 'drawSubstring', '(Ljava/lang/String;IIIII)V', (v, t, a) {
      text(gg(a[0]), ss(a[1]).substring(i(a, 2), i(a, 2) + i(a, 3)), i(a, 4), i(a, 5), i(a, 6));
      return null;
    });
    vm.reg(GR, 'drawChar', '(CIII)V', (v, t, a) { text(gg(a[0]), String.fromCharCode(i(a, 1)), i(a, 2), i(a, 3), i(a, 4)); return null; });
    vm.reg(GR, 'drawChars', '([CIIIII)V', (v, t, a) {
      final d = (a[1] as JArray).data;
      text(gg(a[0]), String.fromCharCodes([for (var k = i(a, 2); k < i(a, 2) + i(a, 3); k++) d[k] as int]), i(a, 4), i(a, 5), i(a, 6));
      return null;
    });
    vm.reg(GR, 'drawImage', '(Ljavax/microedition/lcdui/Image;III)Z', (v, t, a) {
      if (a[1] == null) throw v.ex('java/lang/NullPointerException');
      final src = sf(a[1]);
      final (ax, ay) = Gfx.anchorXY(i(a, 2), i(a, 3), src.w, src.h, i(a, 4));
      gg(a[0]).g.blit(src, 0, 0, src.w, src.h, 0, ax, ay);
      return 1;
    });
    vm.reg(GR, 'drawImage', '(Ljavax/microedition/lcdui/Image;III)V', (v, t, a) {
      if (a[1] == null) throw v.ex('java/lang/NullPointerException');
      final src = sf(a[1]);
      final (ax, ay) = Gfx.anchorXY(i(a, 2), i(a, 3), src.w, src.h, i(a, 4));
      gg(a[0]).g.blit(src, 0, 0, src.w, src.h, 0, ax, ay);
      return null;
    });
    vm.reg(GR, 'drawRegion', '(Ljavax/microedition/lcdui/Image;IIIIIIII)V', (v, t, a) {
      if (a[1] == null) throw v.ex('java/lang/NullPointerException');
      final src = sf(a[1]);
      final sx = i(a, 2), sy = i(a, 3), w = i(a, 4), h = i(a, 5), tr = i(a, 6);
      if (sx < 0 || sy < 0 || sx + w > src.w || sy + h > src.h) throw v.ex('java/lang/IllegalArgumentException', 'Vùng ảnh vượt giới hạn');
      final (ax, ay) = Gfx.anchorXY(i(a, 7), i(a, 8), tr >= 4 ? h : w, tr >= 4 ? w : h, i(a, 9));
      gg(a[0]).g.blit(src, sx, sy, w, h, tr, ax, ay);
      return null;
    });
    vm.reg(GR, 'drawRGB', '([IIIIIIIZ)V', (v, t, a) {
      final d = (a[1] as JArray).data;
      final off = i(a, 2), scan = i(a, 3), x = i(a, 4), y = i(a, 5), w = i(a, 6), h = i(a, 7), al = i(a, 8) != 0;
      final tmp = Surface(w, h, fill: 0, hasAlpha: true);
      for (var j = 0; j < h; j++) {
        for (var k = 0; k < w; k++) {
          final c = (d[off + j * scan + k] as int) & 0xFFFFFFFF;
          tmp.px[j * w + k] = al ? c : (0xFF000000 | c);
        }
      }
      gg(a[0]).g.blit(tmp, 0, 0, w, h, 0, x, y);
      return null;
    });
    vm.reg(GR, 'copyArea', '(IIIIIII)V', (v, t, a) => null);

    // ----- RMS -----
    const RS = 'javax/microedition/rms/RecordStore';
    const RE = 'javax/microedition/rms/RecordEnumeration';
    vm.defClass(RS, obj);
    vm.defClass(RE, obj);
    _Rs rs(dynamic o) {
      final n = (o as JObject).native;
      if (n is _Rs) return n;
      throw vm.ex('javax/microedition/rms/RecordStoreNotOpenException');
    }
    JArray bytesArr(Uint8List b) => JArray('[B', [for (final e in b) e.toSigned(8)]);
    Uint8List slice(JArray arr, int off, int len) => Uint8List.fromList([for (var k = off; k < off + len; k++) (arr.data[k] as int) & 255]);
    vm.reg(RS, 'openRecordStore', '(Ljava/lang/String;Z)Ljavax/microedition/rms/RecordStore;', (v, t, a) {
      final n = ss(a[0]);
      var r = rms[n];
      if (r == null) {
        if (i(a, 1) == 0) throw v.ex('javax/microedition/rms/RecordStoreNotFoundException', n);
        r = rms[n] = _Rs();
        onRmsChanged?.call();
      }
      final o = JObject(v.loadClass(RS));
      o.native = r;
      return o;
    }, isStatic: true);
    vm.reg(RS, 'deleteRecordStore', '(Ljava/lang/String;)V', (v, t, a) {
      if (rms.remove(ss(a[0])) == null) throw v.ex('javax/microedition/rms/RecordStoreNotFoundException', ss(a[0]));
      onRmsChanged?.call();
      return null;
    }, isStatic: true);
    vm.reg(RS, 'listRecordStores', '()[Ljava/lang/String;', (v, t, a) =>
        rms.isEmpty ? null : JArray('[Ljava/lang/String;', [for (final k in rms.keys) s(k)]), isStatic: true);
    vm.reg(RS, 'closeRecordStore', '()V', (v, t, a) => null);
    vm.reg(RS, 'getNumRecords', '()I', (v, t, a) => rs(a[0]).recs.length);
    vm.reg(RS, 'getNextRecordID', '()I', (v, t, a) => rs(a[0]).next);
    vm.reg(RS, 'getSize', '()I', (v, t, a) => rs(a[0]).recs.values.fold<int>(0, (p, e) => p + e.length));
    vm.reg(RS, 'getSizeAvailable', '()I', (v, t, a) => 16 * 1024 * 1024);
    vm.reg(RS, 'getName', '()Ljava/lang/String;', (v, t, a) => s('store'));
    vm.reg(RS, 'getVersion', '()I', (v, t, a) => 1);
    vm.reg(RS, 'getLastModified', '()J', (v, t, a) => DateTime.now().millisecondsSinceEpoch);
    vm.reg(RS, 'addRecord', '([BII)I', (v, t, a) {
      final r = rs(a[0]);
      final id = r.next++;
      r.recs[id] = a[1] == null ? Uint8List(0) : slice(a[1] as JArray, i(a, 2), i(a, 3));
      onRmsChanged?.call();
      return id;
    });
    vm.reg(RS, 'setRecord', '(I[BII)V', (v, t, a) {
      final r = rs(a[0]);
      if (!r.recs.containsKey(i(a, 1))) throw v.ex('javax/microedition/rms/InvalidRecordIDException');
      r.recs[i(a, 1)] = a[2] == null ? Uint8List(0) : slice(a[2] as JArray, i(a, 3), i(a, 4));
      onRmsChanged?.call();
      return null;
    });
    vm.reg(RS, 'getRecord', '(I)[B', (v, t, a) {
      final d = rs(a[0]).recs[i(a, 1)];
      if (d == null) throw v.ex('javax/microedition/rms/InvalidRecordIDException');
      return bytesArr(d);
    });
    vm.reg(RS, 'getRecord', '(I[BI)I', (v, t, a) {
      final d = rs(a[0]).recs[i(a, 1)];
      if (d == null) throw v.ex('javax/microedition/rms/InvalidRecordIDException');
      final arr = a[2] as JArray;
      for (var k = 0; k < d.length; k++) {
        arr.data[i(a, 3) + k] = d[k].toSigned(8);
      }
      return d.length;
    });
    vm.reg(RS, 'getRecordSize', '(I)I', (v, t, a) {
      final d = rs(a[0]).recs[i(a, 1)];
      if (d == null) throw v.ex('javax/microedition/rms/InvalidRecordIDException');
      return d.length;
    });
    vm.reg(RS, 'deleteRecord', '(I)V', (v, t, a) {
      if (rs(a[0]).recs.remove(i(a, 1)) == null) throw v.ex('javax/microedition/rms/InvalidRecordIDException');
      onRmsChanged?.call();
      return null;
    });
    vm.reg(RS, 'enumerateRecords', '(Ljavax/microedition/rms/RecordFilter;Ljavax/microedition/rms/RecordComparator;Z)Ljavax/microedition/rms/RecordEnumeration;', (v, t, a) {
      final ids = rs(a[0]).recs.keys.toList()..sort();
      final o = JObject(v.loadClass(RE));
      o.native = _RsEnum(ids);
      o.f['\$rs'] = a[0];
      return o;
    });
    vm.defClass('javax/microedition/rms/RecordFilter', null, isInterface: true);
    vm.defClass('javax/microedition/rms/RecordComparator', null, isInterface: true);
    _RsEnum en(dynamic o) => (o as JObject).native as _RsEnum;
    vm.reg(RE, 'numRecords', '()I', (v, t, a) => en(a[0]).ids.length);
    vm.reg(RE, 'hasNextElement', '()Z', (v, t, a) => en(a[0]).i < en(a[0]).ids.length ? 1 : 0);
    vm.reg(RE, 'hasPreviousElement', '()Z', (v, t, a) => en(a[0]).i > 0 ? 1 : 0);
    vm.reg(RE, 'nextRecordId', '()I', (v, t, a) => en(a[0]).ids[en(a[0]).i++]);
    vm.reg(RE, 'previousRecordId', '()I', (v, t, a) => en(a[0]).ids[--en(a[0]).i]);
    vm.reg(RE, 'nextRecord', '()[B', (v, t, a) {
      final e = en(a[0]);
      final id = e.ids[e.i++];
      return bytesArr(rs((a[0] as JObject).f['\$rs']).recs[id] ?? Uint8List(0));
    });
    vm.reg(RE, 'previousRecord', '()[B', (v, t, a) {
      final e = en(a[0]);
      final id = e.ids[--e.i];
      return bytesArr(rs((a[0] as JObject).f['\$rs']).recs[id] ?? Uint8List(0));
    });
    vm.reg(RE, 'reset', '()V', (v, t, a) { en(a[0]).i = 0; return null; });
    vm.reg(RE, 'rebuild', '()V', (v, t, a) => null);
    vm.reg(RE, 'destroy', '()V', (v, t, a) => null);

    // ----- Connector (mạng chưa hỗ trợ) -----
    vm.defClass('javax/microedition/io/Connector', obj, statics: {'READ': 1, 'WRITE': 2, 'READ_WRITE': 3});
    for (final d in const ['(Ljava/lang/String;)Ljavax/microedition/io/Connection;', '(Ljava/lang/String;I)Ljavax/microedition/io/Connection;', '(Ljava/lang/String;IZ)Ljavax/microedition/io/Connection;']) {
      vm.reg('javax/microedition/io/Connector', 'open', d, (v, t, a) {
        throw v.ex('javax/microedition/io/ConnectionNotFoundException', 'Mạng chưa được hỗ trợ: ${ss(a[0])}');
      }, isStatic: true);
    }
    vm.defClass('javax/microedition/io/Connection', null, isInterface: true);
  }

  void _installScreens() {
    const obj = 'java/lang/Object';
    const L = 'javax/microedition/lcdui/';
    JObject sv(String v) => vm.str(v);
    String ss(dynamic o) {
      if (o == null) throw vm.ex('java/lang/NullPointerException');
      return (o as JObject).native as String;
    }
    int i(List a, int k) => a[k] as int;
    String strOr(dynamic o) => o == null ? '' : (o as JObject).native as String;

    // Item
    vm.defClass('${L}Item', obj);
    vm.defClass('${L}StringItem', '${L}Item');
    vm.defClass('${L}TextField', '${L}Item', statics: {'ANY': 0, 'EMAILADDR': 1, 'NUMERIC': 2, 'PHONENUMBER': 3, 'URL': 4, 'DECIMAL': 5, 'PASSWORD': 0x10000, 'UNEDITABLE': 0x20000});
    vm.defClass('${L}ChoiceGroup', '${L}Item', statics: {'EXCLUSIVE': 1, 'MULTIPLE': 2, 'IMPLICIT': 3, 'POPUP': 4});
    vm.defClass('${L}Gauge', '${L}Item');
    vm.defClass('${L}ItemStateListener', null, isInterface: true);
    vm.reg('${L}Item', 'setLabel', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['\$label'] = a[1]; return null; });
    vm.reg('${L}Item', 'getLabel', '()Ljava/lang/String;', (v, t, a) => (a[0] as JObject).f['\$label']);
    vm.reg('${L}StringItem', '<init>', '(Ljava/lang/String;Ljava/lang/String;)V', (v, t, a) {
      final o = a[0] as JObject;
      o.f['\$label'] = a[1];
      o.f['\$text'] = a[2];
      return null;
    });
    vm.reg('${L}StringItem', 'setText', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['\$text'] = a[1]; onScreen?.call(); return null; });
    vm.reg('${L}StringItem', 'getText', '()Ljava/lang/String;', (v, t, a) => (a[0] as JObject).f['\$text']);
    const TF = '${L}TextField';
    vm.reg(TF, '<init>', '(Ljava/lang/String;Ljava/lang/String;II)V', (v, t, a) {
      final o = a[0] as JObject;
      o.f['\$label'] = a[1];
      o.f['\$text'] = a[2] ?? sv('');
      o.f['\$max'] = i(a, 3);
      o.f['\$cons'] = i(a, 4);
      return null;
    });
    vm.reg(TF, 'getString', '()Ljava/lang/String;', (v, t, a) => (a[0] as JObject).f['\$text']);
    vm.reg(TF, 'setString', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['\$text'] = a[1] ?? sv(''); onScreen?.call(); return null; });
    vm.reg(TF, 'size', '()I', (v, t, a) => strOr((a[0] as JObject).f['\$text']).length);
    vm.reg(TF, 'getMaxSize', '()I', (v, t, a) => (a[0] as JObject).f['\$max'] ?? 0);
    vm.reg(TF, 'setMaxSize', '(I)I', (v, t, a) { (a[0] as JObject).f['\$max'] = i(a, 1); return i(a, 1); });
    vm.reg(TF, 'setConstraints', '(I)V', (v, t, a) { (a[0] as JObject).f['\$cons'] = i(a, 1); return null; });
    vm.reg(TF, 'getConstraints', '()I', (v, t, a) => (a[0] as JObject).f['\$cons'] ?? 0);

    // Danh sách lựa chọn dùng chung cho ChoiceGroup và List
    List<JObject> els(dynamic o) => ((o as JObject).f['\$els'] ??= <JObject>[]) as List<JObject>;
    void choice(String cls) {
      vm.reg(cls, 'append', '(Ljava/lang/String;Ljavax/microedition/lcdui/Image;)I', (v, t, a) {
        els(a[0]).add(a[1] as JObject);
        onScreen?.call();
        return els(a[0]).length - 1;
      });
      vm.reg(cls, 'insert', '(ILjava/lang/String;Ljavax/microedition/lcdui/Image;)V', (v, t, a) { els(a[0]).insert(i(a, 1), a[2] as JObject); onScreen?.call(); return null; });
      vm.reg(cls, 'set', '(ILjava/lang/String;Ljavax/microedition/lcdui/Image;)V', (v, t, a) { els(a[0])[i(a, 1)] = a[2] as JObject; onScreen?.call(); return null; });
      vm.reg(cls, 'delete', '(I)V', (v, t, a) { els(a[0]).removeAt(i(a, 1)); onScreen?.call(); return null; });
      vm.reg(cls, 'deleteAll', '()V', (v, t, a) { els(a[0]).clear(); onScreen?.call(); return null; });
      vm.reg(cls, 'size', '()I', (v, t, a) => els(a[0]).length);
      vm.reg(cls, 'getString', '(I)Ljava/lang/String;', (v, t, a) => els(a[0])[i(a, 1)]);
      vm.reg(cls, 'getSelectedIndex', '()I', (v, t, a) => (a[0] as JObject).f['\$sel'] ?? (els(a[0]).isEmpty ? -1 : 0));
      vm.reg(cls, 'setSelectedIndex', '(IZ)V', (v, t, a) { (a[0] as JObject).f['\$sel'] = i(a, 1); onScreen?.call(); return null; });
      vm.reg(cls, 'isSelected', '(I)Z', (v, t, a) => ((a[0] as JObject).f['\$sel'] ?? 0) == i(a, 1) ? 1 : 0);
    }
    const CG = '${L}ChoiceGroup', LS = '${L}List';
    vm.reg(CG, '<init>', '(Ljava/lang/String;I)V', (v, t, a) { (a[0] as JObject).f['\$label'] = a[1]; (a[0] as JObject).f['\$ltype'] = i(a, 2); return null; });
    vm.reg(CG, '<init>', '(Ljava/lang/String;I[Ljava/lang/String;[Ljavax/microedition/lcdui/Image;)V', (v, t, a) {
      final o = a[0] as JObject;
      o.f['\$label'] = a[1];
      o.f['\$ltype'] = i(a, 2);
      if (a[3] != null) els(o).addAll([for (final e in (a[3] as JArray).data) e as JObject]);
      return null;
    });
    choice(CG);
    choice(LS);

    // Form
    const FM = '${L}Form';
    List<JObject> items(dynamic o) => ((o as JObject).f['\$items'] ??= <JObject>[]) as List<JObject>;
    vm.reg(FM, '<init>', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['\$title'] = a[1]; return null; });
    vm.reg(FM, '<init>', '(Ljava/lang/String;[Ljavax/microedition/lcdui/Item;)V', (v, t, a) {
      (a[0] as JObject).f['\$title'] = a[1];
      if (a[2] != null) items(a[0]).addAll([for (final e in (a[2] as JArray).data) e as JObject]);
      return null;
    });
    vm.reg(FM, 'append', '(Ljavax/microedition/lcdui/Item;)I', (v, t, a) { items(a[0]).add(a[1] as JObject); onScreen?.call(); return items(a[0]).length - 1; });
    vm.reg(FM, 'append', '(Ljava/lang/String;)I', (v, t, a) {
      final it = JObject(vm.loadClass('${L}StringItem'));
      it.f['\$text'] = a[1];
      items(a[0]).add(it);
      onScreen?.call();
      return items(a[0]).length - 1;
    });
    vm.reg(FM, 'append', '(Ljavax/microedition/lcdui/Image;)I', (v, t, a) => items(a[0]).length);
    vm.reg(FM, 'insert', '(ILjavax/microedition/lcdui/Item;)V', (v, t, a) { items(a[0]).insert(i(a, 1), a[2] as JObject); onScreen?.call(); return null; });
    vm.reg(FM, 'set', '(ILjavax/microedition/lcdui/Item;)V', (v, t, a) { items(a[0])[i(a, 1)] = a[2] as JObject; onScreen?.call(); return null; });
    vm.reg(FM, 'get', '(I)Ljavax/microedition/lcdui/Item;', (v, t, a) => items(a[0])[i(a, 1)]);
    vm.reg(FM, 'delete', '(I)V', (v, t, a) { items(a[0]).removeAt(i(a, 1)); onScreen?.call(); return null; });
    vm.reg(FM, 'deleteAll', '()V', (v, t, a) { items(a[0]).clear(); onScreen?.call(); return null; });
    vm.reg(FM, 'size', '()I', (v, t, a) => items(a[0]).length);
    vm.reg(FM, 'setItemStateListener', '(Ljavax/microedition/lcdui/ItemStateListener;)V', (v, t, a) => null);

    // List
    vm.reg(LS, '<init>', '(Ljava/lang/String;I)V', (v, t, a) { (a[0] as JObject).f['\$title'] = a[1]; (a[0] as JObject).f['\$ltype'] = i(a, 2); return null; });
    vm.reg(LS, '<init>', '(Ljava/lang/String;I[Ljava/lang/String;[Ljavax/microedition/lcdui/Image;)V', (v, t, a) {
      final o = a[0] as JObject;
      o.f['\$title'] = a[1];
      o.f['\$ltype'] = i(a, 2);
      if (a[3] != null) els(o).addAll([for (final e in (a[3] as JArray).data) e as JObject]);
      return null;
    });
    vm.reg(LS, 'setSelectCommand', '(Ljavax/microedition/lcdui/Command;)V', (v, t, a) => null);
    vm.defClass('${L}Choice', null, isInterface: true);
    vm.loadClass(LS).statics.addAll({'IMPLICIT': 3, 'EXCLUSIVE': 1, 'MULTIPLE': 2});

    // TextBox
    const TB = '${L}TextBox';
    vm.reg(TB, '<init>', '(Ljava/lang/String;Ljava/lang/String;II)V', (v, t, a) {
      final o = a[0] as JObject;
      o.f['\$title'] = a[1];
      o.f['\$text'] = a[2] ?? sv('');
      o.f['\$max'] = i(a, 3);
      o.f['\$cons'] = i(a, 4);
      return null;
    });
    vm.reg(TB, 'getString', '()Ljava/lang/String;', (v, t, a) => (a[0] as JObject).f['\$text']);
    vm.reg(TB, 'setString', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['\$text'] = a[1] ?? sv(''); onScreen?.call(); return null; });
    vm.reg(TB, 'size', '()I', (v, t, a) => strOr((a[0] as JObject).f['\$text']).length);
    vm.reg(TB, 'getMaxSize', '()I', (v, t, a) => (a[0] as JObject).f['\$max'] ?? 0);
    vm.reg(TB, 'setMaxSize', '(I)I', (v, t, a) { (a[0] as JObject).f['\$max'] = i(a, 1); return i(a, 1); });
    vm.reg(TB, 'setConstraints', '(I)V', (v, t, a) { (a[0] as JObject).f['\$cons'] = i(a, 1); return null; });
    vm.reg(TB, 'getConstraints', '()I', (v, t, a) => (a[0] as JObject).f['\$cons'] ?? 0);
    vm.reg(TB, 'insert', '(Ljava/lang/String;I)V', (v, t, a) {
      final o = a[0] as JObject;
      final cur = strOr(o.f['\$text']);
      final p = i(a, 2).clamp(0, cur.length);
      o.f['\$text'] = sv(cur.substring(0, p) + ss(a[1]) + cur.substring(p));
      return null;
    });
    vm.reg(TB, 'delete', '(II)V', (v, t, a) {
      final o = a[0] as JObject;
      final cur = strOr(o.f['\$text']);
      final p = i(a, 1).clamp(0, cur.length), e = (p + i(a, 2)).clamp(0, cur.length);
      o.f['\$text'] = sv(cur.substring(0, p) + cur.substring(e));
      return null;
    });

    // Alert
    const AL = '${L}Alert';
    vm.loadClass(AL).statics['FOREVER'] = -2;
    vm.reg(AL, '<init>', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['\$title'] = a[1]; return null; });
    vm.reg(AL, '<init>', '(Ljava/lang/String;Ljava/lang/String;Ljavax/microedition/lcdui/Image;Ljavax/microedition/lcdui/AlertType;)V', (v, t, a) {
      final o = a[0] as JObject;
      o.f['\$title'] = a[1];
      o.f['\$text'] = a[2];
      return null;
    });
    vm.reg(AL, 'setString', '(Ljava/lang/String;)V', (v, t, a) { (a[0] as JObject).f['\$text'] = a[1]; return null; });
    vm.reg(AL, 'getString', '()Ljava/lang/String;', (v, t, a) => (a[0] as JObject).f['\$text']);
    vm.reg(AL, 'setTimeout', '(I)V', (v, t, a) { (a[0] as JObject).f['\$timeout'] = i(a, 1); return null; });
    vm.reg(AL, 'getTimeout', '()I', (v, t, a) => (a[0] as JObject).f['\$timeout'] ?? 2000);
    vm.reg(AL, 'setType', '(Ljavax/microedition/lcdui/AlertType;)V', (v, t, a) => null);
    vm.reg(AL, 'setImage', '(Ljavax/microedition/lcdui/Image;)V', (v, t, a) => null);
    vm.reg('${L}AlertType', 'playSound', '(Ljavax/microedition/lcdui/Display;)Z', (v, t, a) => 1);
    vm.loadClass('${L}AlertType').statics.addAll({'INFO': null, 'WARNING': null, 'ERROR': null, 'ALARM': null, 'CONFIRMATION': null});

    // SELECT_COMMAND
    final sel = JObject(vm.loadClass('${L}Command'));
    sel.f['\$l'] = sv('Chọn');
    sel.f['\$t'] = 1;
    sel.f['\$p'] = 0;
    vm.loadClass(LS).statics['SELECT_COMMAND'] = sel;
  }

  /// Xuất/nhập RMS (JSON) để lưu bền.
  Map<String, dynamic> rmsExport() => {
        for (final e in rms.entries)
          e.key: {'next': e.value.next, 'recs': {for (final r in e.value.recs.entries) '${r.key}': base64Encode(r.value)}}
      };

  void rmsImport(Map<String, dynamic> j) {
    rms.clear();
    j.forEach((k, v) {
      final r = _Rs()..next = (v['next'] as num).toInt();
      (v['recs'] as Map).forEach((id, b) => r.recs[int.parse('$id')] = base64Decode('$b'));
      rms[k] = r;
    });
  }
}
