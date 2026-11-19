import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../emu/screens_ui.dart';
import '../emu/session.dart';
import '../game/connection.dart';
import '../game/keypad.dart';
import '../icons.dart';
import '../theme.dart';

Color get _pageBg => Jp.dark ? const Color(0xFF0F0F1A) : const Color(0xFFEEF3F8);
Color get _panelBg => Jp.dark ? const Color(0xFF1B1B2B) : const Color(0xFFF7FBFF);
Color get _navy => Jp.dark ? const Color(0xFFECEAF6) : const Color(0xFF14365D);
Color get _mutedC => Jp.dark ? const Color(0xFF9E99B3) : const Color(0xFF637D9C);
const _amber = Color(0xFFF59E0B);

/// "Xem tất cả" cho các giả lập J2ME chạy trên máy (giống SyncActivity của bản Android):
/// lưới màn hình nhỏ có chọn nhóm, màn hình chính nổi kèm thanh công cụ dọc, bàn phím chung, cài đặt.
class LocalSyncScreen extends StatefulWidget {
  final List<String> ids;
  const LocalSyncScreen({super.key, required this.ids});
  @override
  State<LocalSyncScreen> createState() => _LocalSyncScreenState();
}

class _LocalSyncScreenState extends State<LocalSyncScreen> {
  final Set<String> selected = {};
  String mainId = '', activeId = '';
  bool groupPad = false, selectedOnly = false, controlSmall = false, showInfo = false, sidebar = false, mainKeypad = false;
  int smallSize = 210;
  Offset floatDelta = Offset.zero;
  double _mcW = 0, _mcH = 0, _areaW = 0, _areaH = 0;
  SharedPreferences? _p;

  List<EmuSession> get sessions {
    final l = EmuRuntime.sessions.values.where((s) => widget.ids.contains(s.inst.id)).toList()..sort((a, b) => a.inst.createdAt.compareTo(b.inst.createdAt));
    return l;
  }

  String num(EmuSession s) => (sessions.indexOf(s) + 1).toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    EmuRuntime.changed.addListener(_tick);
    SharedPreferences.getInstance().then((p) {
      _p = p;
      if (mounted) setState(() { controlSmall = p.getBool('sync_control_small') ?? false; showInfo = p.getBool('sync_show_info') ?? false; smallSize = (p.getInt('sync_small_size') ?? 210).clamp(150, 500); });
    });
  }

  @override
  void dispose() {
    EmuRuntime.changed.removeListener(_tick);
    super.dispose();
  }

  void _tick() { if (mounted) setState(() {}); }

  void _save() {
    _p?.setBool('sync_control_small', controlSmall);
    _p?.setBool('sync_show_info', showInfo);
    _p?.setInt('sync_small_size', smallSize);
  }

  List<EmuSession> _targets(String? id) {
    final all = sessions;
    final list = all.where((s) => selected.contains(s.inst.id)).toList();
    final o = all.where((s) => s.inst.id == id).toList();
    if (o.isNotEmpty && !list.contains(o.first)) list.add(o.first);
    return list.isEmpty ? o : list;
  }

  late final MultiKeyTarget _mainTarget = MultiKeyTarget(() => _targets(mainId).map((s) => s.keys).toList());

  void _touch(EmuSession s, String phase, Offset p, Size size) {
    final id = s.inst.id;
    if (phase == 'down') {
      if (!selected.contains(id)) { selected..clear()..add(id); activeId = ''; }
      if (id != mainId && !controlSmall) { setState(() {}); return; }
      activeId = id;
      setState(() {});
    } else if (id != mainId && !controlSmall) {
      return;
    }
    for (final g in _targets(id)) {
      g.pointer(phase, (p.dx / size.width * g.inst.width).clamp(0, g.inst.width - 1).toInt(), (p.dy / size.height * g.inst.height).clamp(0, g.inst.height - 1).toInt());
    }
  }

  void _makeMain(EmuSession s) {
    setState(() {
      if (mainId == s.inst.id) { mainId = ''; mainKeypad = false; } else { mainId = s.inst.id; }
      floatDelta = Offset.zero;
    });
  }

  void _restart(EmuSession s) {
    final inst = s.inst;
    EmuRuntime.close(inst.id);
    EmuRuntime.open(inst).foreground = false;
    setState(() {});
  }

  void _dragMain(Offset d) {
    final mx = ((_areaW - _mcW) / 2).clamp(0.0, 4000.0), my = ((_areaH - _mcH) / 2).clamp(0.0, 4000.0);
    setState(() => floatDelta = Offset((floatDelta.dx + d.dx).clamp(-mx, mx), (floatDelta.dy + d.dy).clamp(-my, my)));
  }

  double m(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  Widget _screen(EmuSession s, {bool main = false}) {
    final inst = s.inst;
    return AspectRatio(
      aspectRatio: inst.width / inst.height,
      child: LayoutBuilder(builder: (ctx, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Jp.surface,
            child: AnimatedBuilder(
              animation: Listenable.merge([s, s.frame]),
              builder: (_, __) => Stack(fit: StackFit.expand, children: [
                if (s.frame.value != null)
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _touch(s, 'down', e.localPosition, size),
                    onPointerMove: (e) => _touch(s, 'move', e.localPosition, size),
                    onPointerUp: (e) => _touch(s, 'up', e.localPosition, size),
                    onPointerCancel: (e) => _touch(s, 'up', e.localPosition, size),
                    child: RawImage(image: s.frame.value, fit: BoxFit.fill, filterQuality: Jp.fq),
                  ),
                if (s.frame.value == null || s.error)
                  Container(
                    color: Jp.surface,
                    padding: const EdgeInsets.all(6),
                    alignment: Alignment.center,
                    child: Text(s.status, maxLines: 3, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: s.error ? Jp.danger : Jp.text)),
                  ),
                if (main && s.midp?.form != null) Positioned.fill(child: MidpScreenView(midp: s.midp!)),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _mini(JpIconData icon, double k, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          width: 18 * k, height: 18 * k,
          decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(5 * k)),
          child: Center(child: JpIcon(icon, size: 12 * k, color: Colors.white)),
        ),
      );

  Widget _small(EmuSession s, double width) {
    final id = s.inst.id;
    final sel = selected.contains(id);
    final k = m(width / 150, 0.6, 1.0);
    const shadow = Shadow(color: Color(0xCC000000), offset: Offset(0, 1.5), blurRadius: 4);
    return Container(
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Jp.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: id == activeId ? _amber : (sel ? Jp.primary : Jp.line), width: sel ? 2 : 1),
      ),
      child: Stack(children: [
        _screen(s),
        if (showInfo)
          Positioned(
            top: 4, left: 28, right: 28,
            child: IgnorePointer(child: Column(children: [
              Text(num(s), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, shadows: [shadow])),
              Text(s.inst.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, shadows: [shadow])),
            ])),
          ),
        Positioned(
          top: 3 * k, right: 3 * k,
          child: Column(children: [
            _mini(JpIcons.toolExpand, k, () => _makeMain(s)),
            SizedBox(height: 3 * k),
            _mini(JpIcons.toolReload, k, () => _restart(s)),
          ]),
        ),
      ]),
    );
  }

  Widget _mainCard(EmuSession s, double fullWidth, double maxH) {
    final ratio = s.inst.width / s.inst.height;
    final avail = maxH - 12 - (mainKeypad ? 150 : 0);
    final sw = (fullWidth - 50).clamp(60.0, (avail * ratio).clamp(60.0, 4000.0));
    final width = sw + 6 + 4 + 44;
    _mcW = width;
    _mcH = sw / ratio + 6 + (mainKeypad ? 150 : 0) + 8;
    _areaW = fullWidth + 10;
    _areaH = maxH + 12;
    Widget action(JpIconData icon, VoidCallback f) => InkWell(onTap: f, child: SizedBox(width: double.infinity, height: 36, child: Center(child: JpIcon(icon, size: 16, color: Jp.primary))));
    return SizedBox(
      width: width,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Jp.line)),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.all(3), child: _screen(s, main: true)),
              if (mainKeypad) ...[Divider(height: 1, color: Jp.line), Container(color: _panelBg, child: Keypad(_mainTarget))],
            ]),
          ),
        ),
        Container(
          width: 44,
          decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Jp.lineStrong)),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onPanUpdate: (d) => _dragMain(d.delta),
              child: Container(
                width: double.infinity,
                color: Jp.primary,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Text(num(s), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _makeMain(s),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xCCFFFFFF)), borderRadius: BorderRadius.circular(7)),
                      child: const Center(child: Text('✕', style: TextStyle(color: Colors.white, fontSize: 14))),
                    ),
                  ),
                ]),
              ),
            ),
            action(JpIcons.toolReload, () => _restart(s)),
            action(JpIcons.toolKeyboard, () => setState(() => mainKeypad = !mainKeypad)),
          ]),
        ),
      ]),
    );
  }

  Widget _switchRow(String title, bool v, ValueChanged<bool> f) => InkWell(
        onTap: () => f(!v),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 30, height: 18,
              padding: const EdgeInsets.all(2),
              alignment: v ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(color: v ? Jp.primary : const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(9)),
              child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            ),
          ]),
        ),
      );

  Widget _sideBtn(String text, VoidCallback f, {bool pressed = false}) => SizedBox(
        height: 30,
        child: OutlinedButton(
          onPressed: f,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            backgroundColor: pressed ? Jp.primarySoft : Jp.surface,
            foregroundColor: Jp.primary,
            side: BorderSide(color: pressed ? Jp.primary : Jp.lineStrong),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(text, maxLines: 1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _sidebar(List<EmuSession> all) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(16)),
            child: Material(
              color: Colors.transparent,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text('Cài đặt xem tất cả', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _navy))),
                    GestureDetector(onTap: () => setState(() => sidebar = false), child: Padding(padding: const EdgeInsets.all(6), child: Text('✕', style: TextStyle(fontSize: 14, color: _mutedC)))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text('Màn hình nhỏ', style: TextStyle(fontSize: 13, color: _navy))),
                    Text('$smallSize px', style: TextStyle(fontSize: 12, color: _mutedC)),
                  ]),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(trackHeight: 4, activeTrackColor: Jp.primary, inactiveTrackColor: Jp.line, thumbColor: Colors.white, overlayShape: SliderComponentShape.noOverlay, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 1)),
                    child: Slider(min: 150, max: 500, value: smallSize.toDouble(), onChanged: (v) { setState(() => smallSize = v.round()); _save(); }),
                  ),
                  _switchRow('Điều khiển màn nhỏ', controlSmall, (v) { setState(() => controlSmall = v); _save(); }),
                  const SizedBox(height: 8),
                  _switchRow('Hiển thị thông tin', showInfo, (v) { setState(() => showInfo = v); _save(); }),
                  const SizedBox(height: 8),
                  _switchRow('Làm mịn hình ảnh', Jp.smooth.value, (v) { Jp.setSmooth(v); setState(() {}); }),
                  const SizedBox(height: 10),
                  _sideBtn('Tải lại tất cả', () { for (final s in all) { _restart(s); } setState(() => sidebar = false); }),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _sideBtn('Chọn tất cả', () => setState(() { selected..clear()..addAll(all.map((e) => e.inst.id)); }))),
                    const SizedBox(width: 6),
                    Expanded(child: _sideBtn('Bỏ chọn', () => setState(() { selected.clear(); activeId = ''; }))),
                  ]),
                  const SizedBox(height: 10),
                  _sideBtn('Chỉ hiện đã chọn', () => setState(() => selectedOnly = !selectedOnly), pressed: selectedOnly),
                  const SizedBox(height: 10),
                  Text('THIẾT BỊ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _mutedC, letterSpacing: 0.6)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in all)
                      GestureDetector(
                        onTap: () => setState(() { final id = s.inst.id; if (!selected.remove(id)) selected.add(id); if (!selected.contains(id) && activeId == id) activeId = ''; }),
                        child: Container(
                          width: 38, height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected.contains(s.inst.id) ? Jp.primary : Jp.surface,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: s.inst.id == mainId ? _amber : (selected.contains(s.inst.id) ? Jp.primary : Jp.lineStrong), width: s.inst.id == mainId ? 2 : 1),
                          ),
                          child: Text(num(s), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected.contains(s.inst.id) ? Colors.white : _navy)),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, side: const BorderSide(color: Jp.danger), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Đóng xem tất cả', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Jp.danger)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final all = sessions;
    final screenW = MediaQuery.of(context).size.width;
    final smallW = (smallSize * 0.55).clamp(60.0, screenW - 10);
    final mainList = all.where((s) => s.inst.id == mainId).toList();
    return PopScope(
      canPop: !sidebar && mainList.isEmpty,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(() { if (sidebar) { sidebar = false; } else { mainId = ''; } }); },
      child: Scaffold(
        backgroundColor: _pageBg,
        body: Stack(children: [
          Column(children: [
            Container(
              color: _panelBg,
              padding: EdgeInsets.fromLTRB(2, (topInset(context) - 12).clamp(0.0, 200.0), 6, 0),
              constraints: BoxConstraints(minHeight: 50 + topInset(context) - 12),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: JpIcon(JpIcons.back, color: _navy)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Xem tất cả', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _navy)),
                  Text('${all.length} giả lập · đã chọn ${selected.length}', maxLines: 1, style: TextStyle(fontSize: 11, color: _mutedC)),
                ])),
                if (controlSmall) IconButton(onPressed: () => setState(() => groupPad = !groupPad), icon: JpIcon(JpIcons.toolKeyboard, color: groupPad ? Jp.primary : _navy)),
                IconButton(onPressed: () => setState(() => sidebar = true), icon: JpIcon(JpIcons.tune, color: _navy)),
              ]),
            ),
            const Divider(height: 1, color: Color(0xFFDBE7F3)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(5),
                child: SizedBox(width: double.infinity, child: Wrap(spacing: 4, runSpacing: 4, children: [
                  if (all.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('Chưa có giả lập nào đang chạy.', style: TextStyle(fontSize: 12, color: _mutedC))),
                  for (final s in all)
                    if (s.inst.id != mainId && (!selectedOnly || selected.contains(s.inst.id))) _small(s, smallW),
                ])),
              ),
            ),
            if (groupPad && mainList.isEmpty && controlSmall) ...[
              Divider(height: 1, color: Jp.line),
              Container(color: _panelBg, child: Keypad(_mainTarget)),
            ],
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ]),
          if (mainList.isNotEmpty)
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.center,
                  child: Transform.translate(offset: floatDelta, child: _mainCard(mainList.first, screenW - 10, MediaQuery.of(context).size.height - topInset(context) - 70 - MediaQuery.of(context).padding.bottom)),
                ),
              ),
            ),
          if (sidebar) ...[
            Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => sidebar = false), child: Container(color: const Color(0x33000000)))),
            _sidebar(all),
          ],
        ]),
      ),
    );
  }
}
