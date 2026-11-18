import 'package:flutter/material.dart';

import '../game/keypad.dart';
import '../icons.dart';
import '../screens/floating.dart';
import '../screens/game.dart';
import '../theme.dart';
import '../widgets.dart';
import 'kbd.dart';
import 'session.dart';
import 'store.dart';

/// Màn chơi giả lập local: header (thoát · tên game · trạng thái), màn hình game, thanh chức năng và bàn phím ảo.
class LocalGameScreen extends StatefulWidget {
  final LocalInstance inst;
  final VoidCallback? onConfig;
  const LocalGameScreen({super.key, required this.inst, this.onConfig});
  @override
  State<LocalGameScreen> createState() => _LocalGameScreenState();
}

class _LocalGameScreenState extends State<LocalGameScreen> {
  late final EmuSession s;
  bool showPad = true, menu = false;
  final GlobalKey<HiddenKeyboardState> _kb = GlobalKey();

  void _config() {
    final f = widget.onConfig;
    if (f != null) {
      f();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mở Cấu hình từ trang Giả lập')));
    }
  }

  Color get _bg => Jp.dark ? const Color(0xFF0F0F1A) : const Color(0xFFEEF3F8);
  Color get _panel => Jp.dark ? const Color(0xFF1B1B2B) : const Color(0xFFF7FBFF);
  Color get _line => Jp.dark ? const Color(0xFF2E2C44) : const Color(0xFFE4ECF6);
  Color get _title => Jp.dark ? const Color(0xFFECEAF6) : const Color(0xFF14365D);
  Color get _sub => Jp.dark ? const Color(0xFF9E99B3) : const Color(0xFF637D9C);

  @override
  void initState() {
    super.initState();
    s = EmuRuntime.open(widget.inst);
    s.addListener(_t);
    s.frame.addListener(_t);
    SharedPrefsLite.load().then((v) { if (mounted) setState(() => showPad = v); });
  }

  void _t() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    s.removeListener(_t);
    s.frame.removeListener(_t);
    s.saveShot();
    s.foreground = false; // chạy ẩn khi thoát màn hình
    EmuRuntime.changed.value++;
    super.dispose();
  }

  Widget _toolItem(String text, JpIconData icon, VoidCallback f, {bool danger = false}) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () { setState(() => menu = false); f(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(children: [
            JpIcon(icon, size: 18, color: danger ? Jp.danger : Jp.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: danger ? Jp.danger : Jp.text))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final inst = widget.inst;
    final dot = s.error ? Jp.danger : (s.ready ? Jp.success : const Color(0xFFF59E0B));
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        Container(
          color: _panel,
          padding: EdgeInsets.fromLTRB(2, topInset(context) - 10 < 0 ? 0 : topInset(context) - 10, 14, 6),
          constraints: BoxConstraints(minHeight: 58 + topInset(context) - 10),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: JpIcon(JpIcons.back, color: _title)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inst.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _title)),
              Row(children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Flexible(child: Text(s.error ? 'Lỗi' : (s.ready ? 'Đang chạy' : 'Đang khởi động'), maxLines: 1, style: TextStyle(fontSize: 11, color: _sub))),
              ]),
            ])),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Bàn phím iOS',
              onPressed: () => _kb.currentState?.toggle(),
              icon: JpIcon(JpIcons.toolKeyboard, size: 20, color: _title),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Cửa sổ nổi',
              onPressed: () { LocalFloats.open(inst); Navigator.pop(context); },
              icon: JpIcon(JpIcons.toolExpand, size: 20, color: _title),
            ),
          ]),
        ),
        Divider(height: 1, color: _line),
        Expanded(
          child: Container(
            color: _bg,
            padding: const EdgeInsets.all(10),
            child: Stack(children: [
              Positioned.fill(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: inst.width / inst.height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        color: Jp.surface,
                        child: LayoutBuilder(builder: (ctx, box) {
                          void touch(String ph, Offset p) => s.pointer(ph, (p.dx / box.maxWidth * inst.width).clamp(0, inst.width - 1).toInt(), (p.dy / box.maxHeight * inst.height).clamp(0, inst.height - 1).toInt());
                          return Stack(fit: StackFit.expand, children: [
                            if (s.frame.value != null)
                              Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (e) => touch('down', e.localPosition),
                                onPointerMove: (e) => touch('move', e.localPosition),
                                onPointerUp: (e) => touch('up', e.localPosition),
                                onPointerCancel: (e) => touch('up', e.localPosition),
                                child: RawImage(image: s.frame.value, fit: BoxFit.fill, filterQuality: Jp.fq),
                              ),
                            if (s.frame.value == null || s.error)
                              Container(
                                color: Jp.surface,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(20),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  if (!s.error) ...[const LoadingBoxes(), const SizedBox(height: 18)],
                                  Text(s.status, textAlign: TextAlign.center, style: TextStyle(color: s.error ? Jp.danger : const Color(0xFF1769D9), fontSize: 13, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                          ]);
                        }),
                      ),
                    ),
                  ),
                ),
              ),
              if (menu) ...[
                Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => menu = false))),
                Positioned(
                  right: 2, bottom: 2, width: 220,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Jp.line), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))]),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _toolItem('Khởi động lại', JpIcons.restart2, () { EmuRuntime.close(inst.id); Navigator.pop(context); }),
                      _toolItem('Cấu hình', JpIcons.tune, () { Navigator.pop(context); _config(); }),
                      _toolItem('Tắt giả lập', JpIcons.power, () { EmuRuntime.close(inst.id); Navigator.pop(context); }, danger: true),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ),
        Container(
          color: _panel,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(child: SizedBox(height: 30, child: ElevatedButton(
              onPressed: _config,
              style: ElevatedButton.styleFrom(elevation: 0, backgroundColor: Jp.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Cấu hình', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ))),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 30, child: OutlinedButton(
              onPressed: () { setState(() => showPad = !showPad); SharedPrefsLite.save(showPad); },
              style: OutlinedButton.styleFrom(backgroundColor: showPad ? Jp.primarySoft : Jp.surface, foregroundColor: Jp.primary, side: BorderSide(color: showPad ? Jp.lineStrong : Jp.line), padding: const EdgeInsets.symmetric(horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Bàn phím', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ))),
            const SizedBox(width: 8),
            SizedBox(width: 36, height: 30, child: OutlinedButton(
              onPressed: () => setState(() => menu = !menu),
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, side: BorderSide(color: Jp.lineStrong), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const JpIcon(JpIcons.tune, size: 16, color: Jp.primary),
            )),
          ]),
        ),
        if (showPad) ...[
          Divider(height: 1, color: _line),
          Container(color: _panel, child: Keypad(s.keys)),
        ],
        HiddenKeyboard(key: _kb, onChar: s.typeChar, onKey: (k) => s.keys.key(k, 'press')),
        Container(color: _panel, height: MediaQuery.of(context).padding.bottom),
      ]),
    );
  }
}
