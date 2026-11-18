import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../icons.dart';

import '../api.dart';
import '../game/connection.dart';
import '../game/keypad.dart';
import '../game/midp.dart';
import '../theme.dart';
import '../widgets.dart';
import 'game.dart';
import 'rental_dialogs.dart';

Color get _pageBg => Jp.dark ? const Color(0xFF0F0F1A) : const Color(0xFFEEF3F8);
Color get _panelBg => Jp.dark ? const Color(0xFF1B1B2B) : const Color(0xFFF7FBFF);
Color get _navy => Jp.dark ? const Color(0xFFECEAF6) : const Color(0xFF14365D);
Color get _mutedC => Jp.dark ? const Color(0xFF9E99B3) : const Color(0xFF637D9C);
const _amber = Color(0xFFF59E0B);

class _Tile {
  final Rental rental;
  final int index;
  final GameConnection conn;
  _Tile(this.rental, this.index, this.conn);
  String get id => rental.id;
  String get number => (index + 1).toString().padLeft(2, '0');
  String get name => rental.deviceName.isEmpty ? 'Máy J2ME ${index + 1}' : rental.deviceName;
  int get w => conn.frameW > 0 ? conn.frameW : (rental.screenWidth > 0 ? rental.screenWidth : 240);
  int get h => conn.frameH > 0 ? conn.frameH : (rental.screenHeight > 0 ? rental.screenHeight : 320);
}

/// Xem tất cả (bản của SyncActivity bên Android): lưới màn hình nhỏ có chọn nhóm, màn hình chính nổi kèm thanh công cụ dọc,
/// cài đặt (cỡ màn nhỏ, điều khiển màn nhỏ, hiển thị thông tin, chọn thiết bị theo số...).
class SyncScreen extends StatefulWidget {
  final List<Rental> rentals;
  const SyncScreen({super.key, required this.rentals});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with WidgetsBindingObserver {
  late final List<_Tile> tiles;
  final Set<String> selected = {};
  String mainId = '', activeId = '';
  bool selectedOnly = false, controlSmall = false, showInfo = false, sidebar = false, mainKeypad = false;
  int smallSize = 210;
  Offset floatDelta = Offset.zero;
  SharedPreferences? _p;
  String? toastMsg;
  Timer? _toastT;
  List<Product> products = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tiles = [for (var i = 0; i < widget.rentals.length; i++) _Tile(widget.rentals[i], i, GameConnection(widget.rentals[i].id)..addListener(_tick))];
    for (final t in tiles) { t.conn.start(); }
    SharedPreferences.getInstance().then((p) {
      _p = p;
      if (mounted) setState(() { controlSmall = p.getBool('sync_control_small') ?? false; showInfo = p.getBool('sync_show_info') ?? false; smallSize = (p.getInt('sync_small_size') ?? 210).clamp(150, 500); });
    });
  }

  void _save() {
    _p?.setBool('sync_control_small', controlSmall);
    _p?.setBool('sync_show_info', showInfo);
    _p?.setInt('sync_small_size', smallSize);
  }

  void _tick() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toastT?.cancel();
    for (final t in tiles) { t.conn.removeListener(_tick); t.conn.dispose(); }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    for (final t in tiles) {
      if (s == AppLifecycleState.paused) t.conn.pause();
      if (s == AppLifecycleState.resumed) t.conn.resume();
    }
  }

  void _toast(String m) {
    _toastT?.cancel();
    setState(() => toastMsg = m);
    _toastT = Timer(const Duration(seconds: 3), () { if (mounted) setState(() => toastMsg = null); });
  }

  /// Nhóm nhận thao tác: các ô đã chọn (luôn kèm ô phát sinh).
  List<_Tile> _targets(String? id) {
    final sel = tiles.where((t) => selected.contains(t.id)).toList();
    final origin = tiles.where((t) => t.id == id).toList();
    final list = [...sel];
    if (origin.isNotEmpty && !list.contains(origin.first)) list.add(origin.first);
    return list.isEmpty ? origin : list;
  }

  late final MultiKeyTarget _mainTarget = MultiKeyTarget(() => _targets(mainId).map((t) => t.conn).toList());

  void _touch(_Tile t, String phase, Offset p, Size size) {
    final x = (p.dx / size.width).clamp(0.0, 1.0), y = (p.dy / size.height).clamp(0.0, 1.0);
    if (phase == 'down') {
      if (!selected.contains(t.id)) { selected..clear()..add(t.id); activeId = ''; }
      if (t.id != mainId && !controlSmall) { setState(() {}); return; }
      activeId = t.id;
      setState(() {});
    } else if (t.id != mainId && !controlSmall) {
      return;
    }
    for (final g in _targets(t.id)) { g.conn.touch(phase, x, y); }
  }

  void _makeMain(_Tile t) {
    setState(() {
      if (mainId == t.id) { mainId = ''; mainKeypad = false; } else { mainId = t.id; }
      floatDelta = Offset.zero;
    });
  }

  void _reload(_Tile t) { t.conn.reload(); }

  Future<void> _dialog(String kind, _Tile t) async {
    final r = Rental(t.id, t.name, 'active', 0, null, null, null, t.w, t.h);
    final msg = await showRentalAction(context, kind, r);
    if (msg == null || !mounted) return;
    _toast(msg);
    if (kind == 'restart') t.conn.reload();
  }

  void _openJar(_Tile t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Jp.surface,
      builder: (_) => JarSheet(conn: t.conn, onSelected: () { Navigator.pop(context); t.conn.reload(); }),
    );
  }

  // ---------- màn hình một ô ----------
  Widget _screen(_Tile t, {bool main = false}) {
    final c = t.conn;
    final live = c.firstFrame && !c.statusError;
    final rt = c.runtime;
    final native = runtimeNativeKind(rt) != null;
    return AspectRatio(
      aspectRatio: t.w / (t.h < 1 ? 1 : t.h),
      child: LayoutBuilder(builder: (ctx, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Container(
            color: Jp.surface,
            child: Stack(fit: StackFit.expand, children: [
              if (c.image != null)
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _touch(t, 'down', e.localPosition, size),
                  onPointerMove: (e) => _touch(t, 'move', e.localPosition, size),
                  onPointerUp: (e) => _touch(t, 'up', e.localPosition, size),
                  onPointerCancel: (e) => _touch(t, 'up', e.localPosition, size),
                  child: RawImage(image: c.image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                ),
              if (main && native && rt != null && !c.jarBlocked) Positioned.fill(child: MidpOverlay(runtime: rt, conn: c, onError: (m) => _toast(m)))
              else if (!live || native || c.noGame || c.jarBlocked)
                Container(
                  color: Jp.surface,
                  padding: const EdgeInsets.all(6),
                  alignment: Alignment.center,
                  child: c.jarBlocked
                      ? Text('JAR ghép đã bị chặn', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Jp.danger))
                      : native
                          ? Text('Game đang mở form\nPhóng to để điền', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Jp.text))
                          : c.noGame
                              ? Text('Chưa chạy game', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Jp.text))
                              : !c.statusError
                                  ? Transform.scale(scale: (m(size.shortestSide / 110, 0.35, 1.0)), child: const LoadingBoxes())
                                  : Text(c.statusText.isEmpty ? 'Lỗi kết nối' : c.statusText, maxLines: 3, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Jp.danger)),
                ),
            ]),
          ),
        );
      }),
    );
  }

  double m(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  Widget _mini(JpIconData icon, double k, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          width: 18 * k, height: 18 * k,
          decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(5 * k)),
          child: Center(child: JpIcon(icon, size: 12 * k, color: Colors.white)),
        ),
      );

  Widget _small(_Tile t, double width) {
    final sel = selected.contains(t.id);
    final active = t.id == activeId;
    final k = m(width / 150, 0.6, 1.0);
    const shadow = Shadow(color: Color(0xCC000000), offset: Offset(0, 1.5), blurRadius: 4);
    return Container(
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Jp.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? _amber : (sel ? Jp.primary : Jp.line), width: sel ? 2 : 1),
      ),
      child: Stack(children: [
        _screen(t),
        if (showInfo)
          Positioned(
            top: 4, left: 28, right: 28,
            child: IgnorePointer(child: Column(children: [
              Text(t.number, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, shadows: [shadow])),
              Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, shadows: [shadow])),
            ])),
          ),
        Positioned(
          top: 3 * k, right: 3 * k,
          child: Column(children: [
            _mini(JpIcons.toolExpand, k, () => _makeMain(t)),
            SizedBox(height: 3 * k),
            _mini(JpIcons.toolReload, k, () => _reload(t)),
          ]),
        ),
      ]),
    );
  }

  Widget _mainCard(_Tile t, double width) {
    const rl = BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10));
    const rr = BorderRadius.only(topRight: Radius.circular(10), bottomRight: Radius.circular(10));
    Widget action(String k, JpIconData icon) => InkWell(
          onTap: () {
            switch (k) {
              case 'reload': _reload(t); break;
              case 'restart': _dialog('restart', t); break;
              case 'jar': _openJar(t); break;
              case 'proxy': _dialog('proxy', t); break;
              case 'keyboard': setState(() => mainKeypad = !mainKeypad); break;
            }
          },
          child: SizedBox(width: double.infinity, height: 36, child: Center(child: JpIcon(icon, size: 16, color: Jp.primary))),
        );
    return SizedBox(
      width: width,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: Jp.surface, borderRadius: rl, border: Border.all(color: Jp.line)),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsets.all(3), child: _screen(t, main: true)),
                if (mainKeypad) ...[Divider(height: 1, color: Jp.line), Container(color: _panelBg, child: Keypad(_mainTarget))],
              ]),
            ),
          ),
          Container(
            width: 44,
            decoration: BoxDecoration(color: Jp.surface, borderRadius: rr, border: Border.all(color: Jp.lineStrong)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              GestureDetector(
                onPanUpdate: (d) => setState(() => floatDelta += d.delta),
                child: Container(
                  width: double.infinity,
                  color: Jp.primary,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    Text(t.number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _makeMain(t),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xCCFFFFFF)), borderRadius: BorderRadius.circular(7)),
                        child: const Center(child: Text('✕', style: TextStyle(color: Colors.white, fontSize: 14))),
                      ),
                    ),
                  ]),
                ),
              ),
              action('reload', JpIcons.toolReload),
              action('restart', JpIcons.restart2),
              action('jar', JpIcons.toolJar),
              action('proxy', JpIcons.toolGlobe),
              action('keyboard', JpIcons.toolKeyboard),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---------- thanh bên (cài đặt) ----------
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

  Widget _sidebar() => Center(
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
                  const SizedBox(height: 10),
                  _sideBtn('Tải lại', () { for (final t in tiles) { t.conn.reload(); } setState(() => sidebar = false); }),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _sideBtn('Chọn tất cả', () => setState(() { selected..clear()..addAll(tiles.map((e) => e.id)); }))),
                    const SizedBox(width: 6),
                    Expanded(child: _sideBtn('Bỏ chọn', () => setState(() { selected.clear(); activeId = ''; }))),
                  ]),
                  const SizedBox(height: 10),
                  _sideBtn('Chỉ hiện đã chọn', () => setState(() => selectedOnly = !selectedOnly), pressed: selectedOnly),
                  const SizedBox(height: 10),
                  Text('THIẾT BỊ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _mutedC, letterSpacing: 0.6)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in tiles)
                      GestureDetector(
                        onTap: () => setState(() { if (!selected.remove(t.id)) selected.add(t.id); if (!selected.contains(t.id) && activeId == t.id) activeId = ''; }),
                        child: Container(
                          width: 38, height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected.contains(t.id) ? Jp.primary : Jp.surface,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: t.id == mainId ? _amber : (selected.contains(t.id) ? Jp.primary : Jp.lineStrong), width: t.id == mainId ? 2 : 1),
                          ),
                          child: Text(t.number, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected.contains(t.id) ? Colors.white : _navy)),
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
    final screenW = MediaQuery.of(context).size.width;
    final smallW = (smallSize * 0.55).clamp(60.0, screenW - 10);
    final mainTile = tiles.where((t) => t.id == mainId);
    return PopScope(
      canPop: !sidebar && mainId.isEmpty,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(() { if (sidebar) { sidebar = false; } else { mainId = ''; } }); },
      child: Scaffold(
        backgroundColor: _pageBg,
        body: Stack(children: [
          Column(children: [
            Container(
              color: _panelBg,
              padding: EdgeInsets.fromLTRB(2, topInset(context) - 12 < 0 ? 0 : topInset(context) - 12, 6, 0),
              constraints: BoxConstraints(minHeight: 50 + topInset(context) - 12),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: JpIcon(JpIcons.back, color: _navy)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Xem tất cả', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _navy)),
                  Text('${tiles.length} thiết bị · đã chọn ${selected.length}', maxLines: 1, style: TextStyle(fontSize: 11, color: _mutedC)),
                ])),
                IconButton(onPressed: () => setState(() => sidebar = !sidebar), icon: JpIcon(JpIcons.tune, color: _navy)),
              ]),
            ),
            const Divider(height: 1, color: Color(0xFFDBE7F3)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(5),
                child: Wrap(spacing: 4, runSpacing: 4, children: [
                  if (tiles.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('Chưa có phiên J2ME đang hoạt động để xem.', style: TextStyle(fontSize: 12, color: _mutedC))),
                  for (final t in tiles)
                    if (t.id != mainId && (!selectedOnly || selected.contains(t.id))) _small(t, smallW),
                ]),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ]),
          if (mainTile.isNotEmpty)
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.center,
                  child: Transform.translate(offset: floatDelta, child: _mainCard(mainTile.first, screenW - 10)),
                ),
              ),
            ),
          if (sidebar) ...[
            Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => sidebar = false), child: Container(color: const Color(0x33000000)))),
            _sidebar(),
          ],
          if (toastMsg != null)
            Positioned(
              top: topInset(context) + 50, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(10)),
                child: Text(toastMsg!, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
        ]),
      ),
    );
  }
}
