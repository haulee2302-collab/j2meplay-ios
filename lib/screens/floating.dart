import 'package:flutter/material.dart';

import '../api.dart';
import '../game/connection.dart';
import '../game/keypad.dart';
import '../game/midp.dart';
import '../icons.dart';
import '../theme.dart';
import 'game.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

class _FloatWin {
  final Rental rental;
  final GameConnection conn;
  Offset pos;
  bool collapsed = false, keypad = false;
  int sizeStep = 1; // 0 nhỏ · 1 vừa · 2 lớn
  _FloatWin(this.rental, this.conn, this.pos);
  String get name => rental.deviceName.isEmpty ? 'Máy J2ME' : rental.deviceName;
}

/// Cửa sổ nổi (trong ứng dụng): màn hình game nổi trên mọi trang, kéo thả được, có bàn phím ảo.
/// iOS không cho vẽ đè lên ứng dụng khác, nên cửa sổ chỉ nổi bên trong J2ME Play.
class Floating {
  static final ValueNotifier<List<_FloatWin>> windows = ValueNotifier([]);

  static void open(Rental r) {
    if (windows.value.any((w) => w.rental.id == r.id)) return;
    final n = windows.value.length;
    final c = GameConnection(r.id);
    final w = _FloatWin(r, c, Offset(16.0 + n * 24, 120.0 + n * 24));
    c.start();
    windows.value = [...windows.value, w];
  }

  static void _close(_FloatWin w) {
    w.conn.dispose();
    windows.value = windows.value.where((e) => e != w).toList();
  }

  static void closeById(String id) {
    for (final w in windows.value.where((e) => e.rental.id == id).toList()) { _close(w); }
  }
}

class FloatingHost extends StatefulWidget {
  final Widget child;
  const FloatingHost({super.key, required this.child});
  @override
  State<FloatingHost> createState() => _FloatingHostState();
}

class _FloatingHostState extends State<FloatingHost> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    for (final w in Floating.windows.value) {
      if (s == AppLifecycleState.paused) w.conn.pause();
      if (s == AppLifecycleState.resumed) w.conn.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: widget.child),
      ValueListenableBuilder<List<_FloatWin>>(
        valueListenable: Floating.windows,
        builder: (_, list, __) => Stack(children: [for (final w in list) _FloatView(key: ValueKey(w.rental.id), win: w)]),
      ),
    ]);
  }
}

class _FloatView extends StatefulWidget {
  final _FloatWin win;
  const _FloatView({super.key, required this.win});
  @override
  State<_FloatView> createState() => _FloatViewState();
}

class _FloatViewState extends State<_FloatView> {
  _FloatWin get w => widget.win;

  @override
  void initState() {
    super.initState();
    w.conn.addListener(_t);
  }

  @override
  void dispose() {
    w.conn.removeListener(_t);
    super.dispose();
  }

  void _t() { if (mounted) setState(() {}); }

  void _move(Offset d) {
    final s = MediaQuery.of(context).size;
    setState(() => w.pos = Offset((w.pos.dx + d.dx).clamp(-60.0, s.width - 60), (w.pos.dy + d.dy).clamp(MediaQuery.of(context).padding.top, s.height - 60)));
  }

  void _openInApp() {
    final r = w.rental;
    Floating._close(w);
    navKey.currentState?.push(MaterialPageRoute(builder: (_) => GameScreen(rental: r)));
  }

  Widget _hb(JpIconData icon, VoidCallback f, {bool on = false}) => GestureDetector(
        onTap: f,
        child: Container(
          width: 26, height: 26,
          decoration: BoxDecoration(color: on ? const Color(0x33FFFFFF) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
          child: Center(child: JpIcon(icon, size: 15, color: Colors.white)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = w.conn;
    final s = MediaQuery.of(context).size;
    if (w.collapsed) {
      return Positioned(
        left: w.pos.dx, top: w.pos.dy,
        child: GestureDetector(
          onPanUpdate: (d) => _move(d.delta),
          onTap: () => setState(() => w.collapsed = false),
          child: Container(
            width: 58, height: 58,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 8)]),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/jp_logo.png', fit: BoxFit.cover),
          ),
        ),
      );
    }
    final fw = c.frameW > 0 ? c.frameW : (w.rental.screenWidth > 0 ? w.rental.screenWidth : 240);
    final fh = c.frameH > 0 ? c.frameH : (w.rental.screenHeight > 0 ? w.rental.screenHeight : 320);
    final desired = [170.0, 230.0, 300.0][w.sizeStep];
    final width = desired.clamp(120.0, s.width - 12);
    final native = runtimeNativeKind(c.runtime) != null;
    return Positioned(
      left: w.pos.dx, top: w.pos.dy,
      width: width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Jp.lineStrong), boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 12, offset: Offset(0, 4))]),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onPanUpdate: (d) => _move(d.delta),
              child: Container(
                height: 30,
                color: Jp.primary,
                padding: const EdgeInsets.only(left: 8, right: 2),
                child: Row(children: [
                  Expanded(child: Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                  _hb(JpIcons.toolKeyboard, () => setState(() => w.keypad = !w.keypad), on: w.keypad),
                  _hb(JpIcons.toolExpand, () => setState(() => w.sizeStep = w.sizeStep == 2 ? 0 : w.sizeStep + 1)),
                  _hb(JpIcons.screen, _openInApp),
                  _hb(JpIcons.chevronDown, () => setState(() => w.collapsed = true)),
                  GestureDetector(onTap: () => Floating._close(w), child: const SizedBox(width: 26, height: 26, child: Center(child: Text('✕', style: TextStyle(color: Colors.white, fontSize: 13))))),
                ]),
              ),
            ),
            AspectRatio(
              aspectRatio: fw / (fh < 1 ? 1 : fh),
              child: LayoutBuilder(builder: (ctx, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                void touch(String ph, Offset p) => c.touch(ph, (p.dx / size.width).clamp(0.0, 1.0), (p.dy / size.height).clamp(0.0, 1.0));
                return Stack(fit: StackFit.expand, children: [
                  Container(color: Jp.bgFaint),
                  if (c.image != null)
                    Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) => touch('down', e.localPosition),
                      onPointerMove: (e) => touch('move', e.localPosition),
                      onPointerUp: (e) => touch('up', e.localPosition),
                      onPointerCancel: (e) => touch('up', e.localPosition),
                      child: RawImage(image: c.image, fit: BoxFit.fill, filterQuality: Jp.fq),
                    ),
                  if (!c.firstFrame || native)
                    GestureDetector(
                      onTap: native ? _openInApp : null,
                      child: Container(
                        color: Jp.surface,
                        padding: const EdgeInsets.all(10),
                        alignment: Alignment.center,
                        child: native
                            ? Text('Game đang mở form\nChạm để mở trong app', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Jp.text))
                            : Column(mainAxisSize: MainAxisSize.min, children: [
                                if (!c.statusError && !c.noGame) ...[const LoadingBoxes(), const SizedBox(height: 10)],
                                Text(c.noGame ? 'Chưa chạy game' : (c.statusText.isEmpty ? 'Xin chờ' : c.statusText), maxLines: 2, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.statusError ? Jp.danger : const Color(0xFF1769D9))),
                              ]),
                      ),
                    ),
                ]);
              }),
            ),
            if (w.keypad) FittedBox(fit: BoxFit.fitWidth, child: SizedBox(width: 360, child: Container(color: Jp.surface, child: Keypad(c)))),
          ]),
        ),
      ),
    );
  }
}
