import 'dart:async';

import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import 'connection.dart';

/// Bàn phím ảo (bố cục như Keypad trong GameActivity.kt của Android).
/// Trái: bảng phím [Trái OK Phải / * 0 #] ↔ [1–9 kiểu T9] (nút đổi ở góc). Phải: cần gạt 8 hướng ↔ bàn phím 4 hướng.
class Keypad extends StatefulWidget {
  final KeyTarget target;
  const Keypad(this.target, {super.key});
  @override
  State<Keypad> createState() => _KeypadState();
}

const _letters = {'1': '.,?!', '2': 'abc', '3': 'def', '4': 'ghi', '5': 'jkl', '6': 'mno', '7': 'pqrs', '8': 'tuv', '9': 'wxyz', '0': ' '};
const _subs = {'1': '.,?', '2': 'ABC', '3': 'DEF', '4': 'GHI', '5': 'JKL', '6': 'MNO', '7': 'PQRS', '8': 'TUV', '9': 'WXYZ'};

/// T9: chờ 0,5 giây sau lần bấm cuối rồi gửi MỘT ký tự (1 lần = số, 2 lần = chữ đầu...).
class _MultiTap {
  String key = '';
  int count = 0;
  KeyTarget? target;
  Timer? timer;

  void tap(KeyTarget t, String k) {
    if (k != key || target != t) flush();
    target = t;
    if (k == key) {
      count++;
    } else {
      key = k;
      count = 0;
    }
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 500), flush);
  }

  void flush() {
    timer?.cancel();
    final t = target, k = key;
    if (t != null && k.isNotEmpty) {
      final cycle = _letters[k] ?? '';
      final n = cycle.isEmpty ? 0 : count % (cycle.length + 1);
      if (n == 0) {
        t.key(k, 'down');
        t.key(k, 'up');
      } else {
        t.sendInputNow({'type': 'text', 'text': cycle[n - 1]});
      }
    }
    key = '';
    count = 0;
    target = null;
  }
}

class _KeypadState extends State<Keypad> {
  bool numMode = false, dpad = false;
  final _mt = _MultiTap();
  SharedPreferences? _p;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _p = p;
      if (mounted) setState(() { numMode = p.getString('keys') == 'num'; dpad = p.getString('pad') == 'dpad'; });
    });
  }

  @override
  void dispose() {
    _mt.flush();
    super.dispose();
  }

  Widget _swap(VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox(width: 24, height: 24, child: Center(child: JpIcon(JpIcons.swap, size: 14, color: Jp.primary))),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    Widget key(String k, String label, {String sub = '', bool primary = false, JpIconData? icon, bool multi = false}) => Expanded(
          child: _Hold(
            onDown: () { if (multi) { _mt.tap(t, k); } else { _mt.flush(); t.key(k, 'down'); } },
            onUp: () { if (!multi) t.key(k, 'up'); },
            builder: (pressed) => Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primary ? (pressed ? Jp.primaryDark : Jp.primary) : (pressed ? Jp.primarySoft : _numBg),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primary ? Jp.primary : _numLine),
              ),
              child: icon != null
                  ? JpIcon(icon, size: 18, color: primary ? Colors.white : Jp.primary)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: primary ? 11 : 12, height: 1.1, color: primary ? Colors.white : Jp.primary)),
                      if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 7, height: 1.1, fontWeight: FontWeight.w600, color: _numSub)),
                    ]),
            ),
          ),
        );

    Widget row(List<Widget> k) => SizedBox(height: 30, child: Row(children: [
          for (var i = 0; i < k.length; i++) ...[if (i > 0) const SizedBox(width: 5), k[i]],
        ]));

    Widget dkey(String k, {JpIconData? icon, String label = ''}) {
      final ok = k == 'OK';
      return _Hold(
        onDown: () { _mt.flush(); t.key(k, 'down'); },
        onUp: () => t.key(k, 'up'),
        builder: (pressed) => Container(
          width: 34, height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ok ? (pressed ? Jp.primaryDark : Jp.primary) : (pressed ? Jp.primarySoft : Jp.surface),
            borderRadius: BorderRadius.circular(10),
            border: ok ? null : Border.all(color: Jp.lineStrong),
          ),
          child: icon != null
              ? JpIcon(icon, size: icon == JpIcons.softKey ? 18 : 17, color: Jp.primary)
              : Text(label, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      );
    }

    final left = numMode
        ? [
            row([for (final d in ['1', '2', '3']) key(d, d, sub: _subs[d]!, multi: true)]),
            row([for (final d in ['4', '5', '6']) key(d, d, sub: _subs[d]!, multi: true)]),
            row([for (final d in ['7', '8', '9']) key(d, d, sub: _subs[d]!, multi: true)]),
          ]
        : [
            row([key('SOFT1', '', icon: JpIcons.softKey), key('OK', 'OK', primary: true), key('SOFT2', '', icon: JpIcons.softKey)]),
            row([key('STAR', '*'), key('0', '0', sub: '␣', multi: true), key('HASH', '#')]),
          ];

    final dp = Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [dkey('SOFT1', icon: JpIcons.softKey), const SizedBox(width: 3), dkey('UP', icon: JpIcons.chevronUp), const SizedBox(width: 3), dkey('SOFT2', icon: JpIcons.softKey)]),
      const SizedBox(height: 3),
      Row(mainAxisSize: MainAxisSize.min, children: [dkey('LEFT', icon: JpIcons.chevronLeft), const SizedBox(width: 3), dkey('OK', label: 'OK'), const SizedBox(width: 3), dkey('RIGHT', icon: JpIcons.chevronRight)]),
      const SizedBox(height: 3),
      Row(mainAxisSize: MainAxisSize.min, children: [dkey('BACK', icon: JpIcons.undo), const SizedBox(width: 3), dkey('DOWN', icon: JpIcons.chevronDown), const SizedBox(width: 3), dkey('BACKSPACE', icon: JpIcons.erase)]),
    ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _swap(() { setState(() => numMode = !numMode); _p?.setString('keys', numMode ? 'num' : 'soft'); }),
          const Spacer(),
          _swap(() { setState(() => dpad = !dpad); _p?.setString('pad', dpad ? 'dpad' : 'stick'); }),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 108,
          child: Row(children: [
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < left.length; i++) ...[if (i > 0) const SizedBox(height: 5), left[i]],
            ])),
            const SizedBox(width: 14),
            SizedBox(width: 112, height: 108, child: Center(child: dpad ? dp : _Joystick(t))),
          ]),
        ),
      ]),
    );
  }
}

Color get _numBg => Jp.dark ? const Color(0xFF262238) : const Color(0xFFF3F0FB);
Color get _numLine => Jp.dark ? const Color(0xFF3A3458) : const Color(0xFFE2DCF4);
Color get _numSub => Jp.dark ? const Color(0xFFA99BEA) : const Color(0xFF8F7FD6);

class _Hold extends StatefulWidget {
  final VoidCallback onDown, onUp;
  final Widget Function(bool pressed) builder;
  const _Hold({required this.onDown, required this.onUp, required this.builder});
  @override
  State<_Hold> createState() => _HoldState();
}

class _HoldState extends State<_Hold> {
  bool down = false;
  void _d() { if (!down) { down = true; widget.onDown(); if (mounted) setState(() {}); } }
  void _u() { if (down) { down = false; widget.onUp(); if (mounted) setState(() {}); } }
  @override
  void dispose() { if (down) { down = false; widget.onUp(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _d(),
        onPointerUp: (_) => _u(),
        onPointerCancel: (_) => _u(),
        child: widget.builder(down),
      );
}

/// Cần gạt 8 hướng: kéo núm, gửi phím hướng tương ứng (giữ khi còn kéo).
class _Joystick extends StatefulWidget {
  final KeyTarget target;
  const _Joystick(this.target);
  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  Offset knob = Offset.zero;
  Set<String> held = {};
  static const sectors = [
    ['RIGHT'], ['RIGHT', 'DOWN'], ['DOWN'], ['DOWN', 'LEFT'], ['LEFT'], ['LEFT', 'UP'], ['UP'], ['UP', 'RIGHT'],
  ];

  void _update(Offset local, double r) {
    var d = local - Offset(r, r);
    final dist = d.distance;
    final max = r * 0.62;
    if (dist > max) d = d * (max / dist);
    Set<String> next = {};
    if (dist > r * 0.22) {
      var a = d.direction; // 0 = phải, +π/2 = xuống (hệ toạ độ màn hình)
      if (a < 0) a += 6.283185307179586;
      final idx = ((a / (6.283185307179586 / 8)) + 0.5).floor() % 8;
      next = sectors[idx].toSet();
    }
    for (final k in held.difference(next)) { widget.target.key(k, 'up'); }
    for (final k in next.difference(held)) { widget.target.key(k, 'down'); }
    held = next;
    setState(() => knob = d);
  }

  void _release() {
    for (final k in held) { widget.target.key(k, 'up'); }
    held = {};
    setState(() => knob = Offset.zero);
  }

  @override
  void dispose() {
    for (final k in held) { widget.target.key(k, 'up'); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, box) {
        final size = math(104, math(box.maxWidth, box.maxHeight));
        final r = size / 2;
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _update(e.localPosition, r),
              onPointerMove: (e) => _update(e.localPosition, r),
              onPointerUp: (_) => _release(),
              onPointerCancel: (_) => _release(),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Jp.surface, Jp.surface, Jp.primarySoft]),
                  border: Border.all(color: held.isNotEmpty ? Jp.primary : Jp.lineStrong, width: 2),
                ),
                child: Stack(alignment: Alignment.center, children: [
                Container(width: 82, height: 82, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Jp.primary.withOpacity(0.25)))),
                Transform.translate(offset: knob, child: Container(width: 42, height: 42, decoration: const BoxDecoration(color: Jp.primary, shape: BoxShape.circle))),
              ])),
            ),
          ),
        );
      });

  double math(double a, double b) => a < b ? a : b;
}
