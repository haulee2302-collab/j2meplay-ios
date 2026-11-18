import 'package:flutter/material.dart';

import '../api.dart';
import '../game/connection.dart';
import '../game/keypad.dart';
import '../game/midp.dart';
import '../theme.dart';
import '../widgets.dart';

/// Xem tất cả: mở mọi phiên đang chạy trong một trang. Một màn hình chính (to) + các màn hình nhỏ; chạm màn nhỏ để đưa lên chính.
/// Phím và chạm trên màn chính được gửi đồng thời tới tất cả các phiên (đồng bộ thao tác).
class SyncScreen extends StatefulWidget {
  final List<Rental> rentals;
  const SyncScreen({super.key, required this.rentals});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with WidgetsBindingObserver {
  late final List<GameConnection> conns;
  int main = 0;
  bool showPad = true;
  late final MultiKeyTarget all = MultiKeyTarget(() => conns);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    conns = [for (final r in widget.rentals) GameConnection(r.id)..addListener(_tick)];
    for (final c in conns) { c.start(); }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in conns) { c.removeListener(_tick); c.dispose(); }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    for (final c in conns) {
      if (s == AppLifecycleState.paused) c.pause();
      if (s == AppLifecycleState.resumed) c.resume();
    }
  }

  void _touch(String phase, Offset p, Size size) {
    final x = (p.dx / size.width).clamp(0.0, 1.0), y = (p.dy / size.height).clamp(0.0, 1.0);
    for (final c in conns) { c.touch(phase, x, y); }
  }

  Widget _frame(GameConnection c, Rental r, {required bool big}) {
    final w = c.frameW > 0 ? c.frameW : (r.screenWidth > 0 ? r.screenWidth : 320);
    final h = c.frameH > 0 ? c.frameH : (r.screenHeight > 0 ? r.screenHeight : 400);
    final live = c.firstFrame && !c.statusError;
    final rt = c.runtime;
    final native = big && runtimeNativeKind(rt) != null;
    return AspectRatio(
      aspectRatio: w / h,
      child: LayoutBuilder(builder: (ctx, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Container(
            decoration: BoxDecoration(color: Jp.surface, border: Border.all(color: big ? Jp.primary : Jp.lineStrong), borderRadius: BorderRadius.circular(7)),
            child: Stack(fit: StackFit.expand, children: [
              if (c.image != null)
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: big ? (e) => _touch('down', e.localPosition, size) : null,
                  onPointerMove: big ? (e) => _touch('move', e.localPosition, size) : null,
                  onPointerUp: big ? (e) => _touch('up', e.localPosition, size) : null,
                  onPointerCancel: big ? (e) => _touch('up', e.localPosition, size) : null,
                  child: RawImage(image: c.image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                ),
              if (c.image == null || !live)
                Center(child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (c.loading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Jp.primary)),
                    if (big || !c.loading) Text(c.statusText, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: big ? 13 : 10, color: c.statusError ? Jp.danger : Jp.infoBlue)),
                  ]),
                )),
              if (native && rt != null) Positioned.fill(child: MidpOverlay(runtime: rt, conn: c, onError: (m) => toast(context, m, error: true))),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = widget.rentals;
    final others = [for (var i = 0; i < rs.length; i++) if (i != main) i];
    return Scaffold(
      backgroundColor: Jp.bgFaint,
      body: Column(children: [
        Container(
          color: Jp.surface,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.arrow_back, color: Jp.text)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Xem tất cả (${rs.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Jp.text)),
                  Text(rs[main].deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Jp.muted)),
                ])),
                IconButton(onPressed: () => setState(() => showPad = !showPad), icon: Icon(Icons.gamepad_outlined, color: showPad ? Jp.primary : Jp.text)),
              ]),
            ),
          ),
        ),
        Divider(height: 1, color: Jp.line),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Center(child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.42), child: _frame(conns[main], rs[main], big: true))),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final i in others)
                  GestureDetector(
                    onTap: () => setState(() => main = i),
                    child: SizedBox(
                      width: (MediaQuery.of(context).size.width - 24 - 16) / 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        AbsorbPointer(child: _frame(conns[i], rs[i], big: false)),
                        const SizedBox(height: 2),
                        Text(rs[i].deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Jp.muted)),
                      ]),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
        if (showPad) Keypad(all),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ]),
    );
  }
}
