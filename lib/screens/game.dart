import 'dart:async';
import 'dart:convert';
import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../icons.dart';

import '../api.dart';
import '../game/connection.dart';
import '../game/keypad.dart';
import '../game/midp.dart';
import '../theme.dart';
import '../widgets.dart';
import 'rental_dialogs.dart';

Color get _pageBg => Jp.dark ? const Color(0xFF0F0F1A) : const Color(0xFFEEF6FF);
Color get _bodyBg => Jp.dark ? const Color(0xFF0F0F1A) : const Color(0xFFEEF3F8);
Color get _panelBg => Jp.dark ? const Color(0xFF1B1B2B) : const Color(0xFFF7FBFF);
Color get _panelLine => Jp.dark ? const Color(0xFF2E2C44) : const Color(0xFFE4ECF6);
Color get _headTitle => Jp.dark ? const Color(0xFFECEAF6) : const Color(0xFF14365D);
Color get _headSub => Jp.dark ? const Color(0xFF9E99B3) : const Color(0xFF637D9C);
Color get _headTimer => Jp.dark ? const Color(0xFF7FB2FF) : const Color(0xFF0F4FA9);
const _loadingBlue = Color(0xFF1769D9);

/// Hai ô vuông viền xanh xoay ngược chiều (4,5 s và 3,5 s) — như .rental-loading-box trên web / LoadingBoxes bên Android.
class LoadingBoxes extends StatefulWidget {
  const LoadingBoxes({super.key});
  @override
  State<LoadingBoxes> createState() => _LoadingBoxesState();
}

class _LoadingBoxesState extends State<LoadingBoxes> with TickerProviderStateMixin {
  late final AnimationController a = AnimationController(vsync: this, duration: const Duration(milliseconds: 4500))..repeat();
  late final AnimationController b = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500))..repeat();
  @override
  void dispose() { a.dispose(); b.dispose(); super.dispose(); }
  Widget box(AnimationController c, double dir) => AnimatedBuilder(
        animation: c,
        builder: (_, __) => Transform.rotate(
          angle: dir * 2 * m.pi * c.value,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Color.lerp(const Color(0x291769D9), const Color(0x0F7552FF), c.value),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _loadingBlue),
            ),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => SizedBox(width: 40, height: 40, child: Stack(children: [box(a, -1), box(b, 1)]));
}

/// Màn hình xem/chơi một phiên thuê (bố cục như GameActivity + GameViewerLayout bên Android).
class GameScreen extends StatefulWidget {
  final Rental rental;
  const GameScreen({super.key, required this.rental});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final GameConnection conn;
  bool showPad = true, tools = false;
  late Rental rental = widget.rental;
  List<Product> products = [];
  Timer? _tick;
  String? toastMsg;
  Timer? _toastT;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    conn = GameConnection(widget.rental.id)..addListener(_onConn);
    conn.start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    SharedPrefsLite.load().then((v) { if (mounted) setState(() => showPad = v); });
    _refreshRental();
    Api.instance.products().then((p) { if (mounted) setState(() => products = p); }).catchError((_) {});
  }

  Future<void> _refreshRental() async {
    try {
      final l = await Api.instance.rentals();
      final r = l.where((e) => e.id == widget.rental.id);
      if (r.isNotEmpty && mounted) setState(() => rental = r.first);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _toastT?.cancel();
    conn.removeListener(_onConn);
    conn.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) conn.pause();
    if (s == AppLifecycleState.resumed) conn.resume();
  }

  void _onConn() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    _toastT?.cancel();
    setState(() => toastMsg = msg);
    _toastT = Timer(const Duration(milliseconds: 2600), () { if (mounted) setState(() => toastMsg = null); });
  }

  void _touch(String phase, Offset p, Size size) {
    final x = (p.dx / size.width).clamp(0.0, 1.0), y = (p.dy / size.height).clamp(0.0, 1.0);
    conn.touch(phase, x, y);
  }

  String _countdown(int ms) {
    if (ms <= 0) return '--:--:--';
    final s = ms ~/ 1000, d = s ~/ 86400, h = (s % 86400) ~/ 3600, mi = (s % 3600) ~/ 60, sec = s % 60;
    String t(int n) => n.toString().padLeft(2, '0');
    final hms = '${t(h)}:${t(mi)}:${t(sec)}';
    return d > 0 ? '$d ngày $hms' : hms;
  }

  Future<void> _action(String kind) async {
    final r = Rental(rental.id, rental.deviceName, 'active', rental.endsAt, null, null, null, conn.frameW, conn.frameH);
    final msg = await showRentalAction(context, kind, r);
    if (msg == null || !mounted) return;
    _toast(msg);
    if (kind != 'proxy' && kind != 'name') conn.reload();
  }

  Future<void> _extend() async {
    final msg = await showExtend(context, rental, products);
    if (msg != null && mounted) { _toast(msg); _refreshRental(); }
  }

  Future<void> _autoRenew() async {
    final (c, j, _) = await Api.instance.rawPost('/api/site/rentals/${Uri.encodeComponent(rental.id)}/auto-renew', {'enabled': !rental.autoRenew});
    if (!mounted) return;
    if (c >= 200 && c < 300) {
      final msg = '${j?['message'] ?? ''}';
      _toast(msg.isEmpty ? (rental.autoRenew ? 'Đã tắt gia hạn tự động.' : 'Đã bật gia hạn tự động.') : msg);
      _refreshRental();
    } else {
      _toast('${j?['error'] ?? 'Không đổi được gia hạn tự động'}');
    }
  }

  void _openJars() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Jp.surface,
      builder: (_) => JarSheet(conn: conn, onSelected: () { Navigator.pop(context); conn.reload(); }),
    );
  }

  Widget _toolItem(String text, JpIconData icon, VoidCallback f, {bool danger = false}) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () { setState(() => tools = false); f(); },
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
    final r = rental;
    final w = conn.frameW > 0 ? conn.frameW : (r.screenWidth > 0 ? r.screenWidth : 320);
    final h = conn.frameH > 0 ? conn.frameH : (r.screenHeight > 0 ? r.screenHeight : 400);
    final rt = conn.runtime;
    final native = runtimeNativeKind(rt) != null;
    final live = conn.ready && conn.firstFrame && !conn.statusError;
    final (dot, label) = conn.statusError
        ? (Jp.danger, conn.statusText.isEmpty ? 'Lỗi kết nối' : conn.statusText)
        : live
            ? (Jp.success, 'Đang chạy')
            : (const Color(0xFFE0A100), conn.statusText.isEmpty ? 'Đang kết nối…' : conn.statusText);
    final left = r.endsMs - DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      backgroundColor: _pageBg,
      body: Column(children: [
        Container(
          color: _panelBg,
          padding: EdgeInsets.fromLTRB(2, topInset(context) - 10 < 0 ? 0 : topInset(context) - 10, 14, 6),
          constraints: BoxConstraints(minHeight: 58 + topInset(context) - 10),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: JpIcon(JpIcons.back, color: _headTitle)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _headTitle)),
              Row(children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: _headSub))),
              ]),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              if (r.deviceCode.isNotEmpty) Text(r.deviceCode, maxLines: 1, style: TextStyle(fontSize: 11, color: _headSub, fontFamily: 'Menlo', fontFamilyFallback: const ['monospace'])),
              Text(_countdown(left), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _headTimer, fontFamily: 'Menlo', fontFamilyFallback: const ['monospace'])),
            ]),
          ]),
        ),
        Divider(height: 1, color: _panelLine),
        Expanded(
          child: Container(
            color: _bodyBg,
            padding: const EdgeInsets.all(10),
            child: Stack(children: [
              Positioned.fill(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: w / h,
                    child: LayoutBuilder(builder: (ctx, box) {
                      final size = Size(box.maxWidth, box.maxHeight);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        clipBehavior: Clip.antiAlias,
                        child: Container(
                          color: Jp.surface,
                          child: Stack(fit: StackFit.expand, children: [
                            if (conn.image != null)
                              Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (e) => _touch('down', e.localPosition, size),
                                onPointerMove: (e) => _touch('move', e.localPosition, size),
                                onPointerUp: (e) => _touch('up', e.localPosition, size),
                                onPointerCancel: (e) => _touch('up', e.localPosition, size),
                                child: RawImage(image: conn.image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                              ),
                            if (!conn.firstFrame && rt == null)
                              Container(
                                color: Jp.surface,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(24),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  if (!conn.noGame && !conn.statusError) ...[const LoadingBoxes(), const SizedBox(height: 18)],
                                  Text(conn.statusText.isEmpty ? 'Xin chờ' : conn.statusText, textAlign: TextAlign.center, style: TextStyle(color: conn.statusError ? Jp.danger : _loadingBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                                  if (conn.noGame) ...[
                                    const SizedBox(height: 14),
                                    PrimaryButton('Chọn JAR', _openJars, height: 36, fontSize: 14),
                                  ],
                                ]),
                              ),
                            if (native && rt != null && !conn.jarBlocked) Positioned.fill(child: MidpOverlay(runtime: rt, conn: conn, onError: (m) => _toast(m))),
                            if (conn.jarBlocked)
                              Container(
                                color: Jp.surface,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(24),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 56, height: 56, decoration: BoxDecoration(color: Jp.dangerBg, borderRadius: BorderRadius.circular(14)), child: const Center(child: JpIcon(JpIcons.toolJar, color: Jp.danger, size: 28))),
                                  Padding(padding: const EdgeInsets.only(top: 14), child: Text('JAR ghép đã bị chặn', style: TextStyle(color: Jp.text, fontSize: 16, fontWeight: FontWeight.w700))),
                                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('JAR này gộp nhiều ứng dụng nên không được chạy. Hãy chọn một tệp JAR chỉ chứa một ứng dụng.', textAlign: TextAlign.center, style: TextStyle(color: Jp.muted, fontSize: 13, height: 1.4))),
                                  const SizedBox(height: 16),
                                  PrimaryButton('Chọn JAR khác', _openJars, height: 36, fontSize: 13),
                                ]),
                              ),
                          ]),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              if (tools) ...[
                Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => tools = false))),
                Positioned(
                  right: 2, bottom: 2, width: 220,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Jp.line), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))]),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _toolItem('Tải lại màn hình', JpIcons.refresh, () => conn.reload()),
                      _toolItem('Khởi động lại', JpIcons.restart2, () => _action('restart')),
                      _toolItem('Proxy', JpIcons.globe, () => _action('proxy')),
                      _toolItem('Đổi kích thước', JpIcons.screen, () => _action('screen-size')),
                      _toolItem('Gia hạn', JpIcons.clock, _extend),
                      _toolItem(rental.autoRenew ? 'Tắt gia hạn tự động' : 'Bật gia hạn tự động', rental.autoRenew ? JpIcons.toggleOn : JpIcons.toggleOff, _autoRenew),
                      _toolItem('Tắt J2ME', JpIcons.power, () => _action('power-off'), danger: true),
                    ]),
                  ),
                ),
              ],
              if (toastMsg != null)
                Positioned(
                  left: 12, right: 12, bottom: 12,
                  child: Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xEE17172F), borderRadius: BorderRadius.circular(8)),
                    child: Text(toastMsg!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  )),
                ),
            ]),
          ),
        ),
        // Thanh chức năng: Đổi JAR · Bàn phím · ⋮
        Container(
          color: _panelBg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(child: SizedBox(height: 30, child: ElevatedButton(
              onPressed: _openJars,
              style: ElevatedButton.styleFrom(backgroundColor: Jp.primary, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Đổi JAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ))),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 30, child: OutlinedButton(
              onPressed: () { setState(() => showPad = !showPad); SharedPrefsLite.save(showPad); },
              style: OutlinedButton.styleFrom(backgroundColor: showPad ? Jp.primarySoft : Jp.surface, foregroundColor: Jp.primary, side: BorderSide(color: showPad ? Jp.lineStrong : Jp.line), padding: const EdgeInsets.symmetric(horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Bàn phím', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ))),
            const SizedBox(width: 8),
            SizedBox(width: 36, height: 30, child: OutlinedButton(
              onPressed: () => setState(() => tools = !tools),
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, side: BorderSide(color: Jp.lineStrong), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const JpIcon(JpIcons.tune, size: 16, color: Jp.primary),
            )),
          ]),
        ),
        // Bàn phím ảo; ẩn khi game đang mở form
        if (showPad && rt == null) ...[
          Divider(height: 1, color: _panelLine),
          Container(color: _panelBg, child: Keypad(conn)),
        ],
        Container(color: _panelBg, height: MediaQuery.of(context).padding.bottom),
      ]),
    );
  }
}

/// Ghi nhớ bật/tắt bàn phím ảo (khoá "keypad", như prefs game_ui bên Android).
class SharedPrefsLite {
  static Future<bool> load() async => (await SharedPreferences.getInstance()).getBool('keypad') ?? true;
  static Future<void> save(bool v) async => (await SharedPreferences.getInstance()).setBool('keypad', v);
}

// ---------------- Chọn JAR ----------------
class _JarItem {
  final String source, id, name;
  final int size;
  _JarItem(this.source, this.id, this.name, this.size);
}

List<_JarItem> _items(dynamic arr, String? source) {
  if (arr is! List) return [];
  return [
    for (final o in arr)
      if (o is Map)
        _JarItem(source ?? '${o['source'] ?? 'server'}', o['id'] == null ? '' : '${o['id']}', '${o['name'] ?? ''}', ((o['size'] ?? 0) as num).toInt())
  ];
}

class JarSheet extends StatefulWidget {
  final GameConnection conn;
  final VoidCallback onSelected;
  const JarSheet({required this.conn, required this.onSelected});
  @override
  State<JarSheet> createState() => _JarSheetState();
}

class _JarSheetState extends State<JarSheet> {
  int tab = 0;
  List<_JarItem> system = [], mine = [];
  bool loading = true;
  String? busy, error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = Api.instance;
    final a = widget.conn.access;
    final (_, sys, _) = await api.rawGet('/api/site/system-jars');
    final (_, mj, _) = await api.rawGet('/api/site/jars');
    Map<String, dynamic>? lib;
    if (a != null) {
      lib = (await widget.conn.sessionRequest(a, 'GET', '/api/public-session/library?id=${Uri.encodeQueryComponent(a.sessionId)}')).$2;
    }
    final direct = _items(sys?['jars'], 'system');
    final seen = direct.map((e) => 'system:${e.id.isEmpty ? e.name : e.id}').toSet();
    final extra = _items(lib?['server'], null).where((e) => seen.add('${e.source}:${e.id.isEmpty ? e.name : e.id}'));
    if (!mounted) return;
    setState(() {
      system = [...direct, ...extra];
      mine = _items(mj?['jars'], 'mine');
      loading = false;
    });
  }

  Future<void> _select(_JarItem it) async {
    final a = widget.conn.access;
    if (a == null) {
      setState(() => error = 'Phiên J2ME chưa sẵn sàng. Thử lại sau giây lát.');
      return;
    }
    setState(() { busy = 'Đang mở ${it.name}…'; error = null; });
    var ok = false;
    var last = '';
    for (var i = 0; i < 6; i++) {
      final body = <String, dynamic>{'id': a.sessionId, 'source': it.source, 'name': it.name};
      if ((it.source == 'mine' || it.source == 'system') && it.id.isNotEmpty) body['jarId'] = int.tryParse(it.id) ?? it.id;
      final (c, j) = await widget.conn.sessionRequest(a, 'POST', '/api/public-session/select', body: utf8.encode(jsonEncode(body)), timeoutMs: 60000);
      if (c >= 200 && c < 300) { ok = true; break; }
      last = '${j?['error'] ?? ''}'.isEmpty ? 'Không chạy được JAR (mã $c)' : '${j!['error']}';
      if (!RegExp('runner.*sẵn sàng|chưa sẵn sàng|đang được khôi phục', caseSensitive: false).hasMatch(last)) break;
      await Future.delayed(const Duration(milliseconds: 700));
    }
    if (!mounted) return;
    setState(() => busy = null);
    if (ok) {
      widget.onSelected();
    } else {
      setState(() => error = last);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = tab == 0 ? system : mine;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          const SizedBox(height: 10),
          Row(children: [
            const SizedBox(width: 12),
            for (final (i, t) in ['Hệ thống', 'Kho của tôi'].indexed)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(t), selected: tab == i, onSelected: (_) => setState(() => tab = i)),
              ),
          ]),
          if (error != null) Padding(padding: const EdgeInsets.all(10), child: Text(error!, style: const TextStyle(color: Jp.danger))),
          if (busy != null) Padding(padding: const EdgeInsets.all(10), child: Text(busy!, style: TextStyle(color: Jp.muted))),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: Jp.primary))
                : list.isEmpty
                    ? Center(child: Text('Chưa có JAR nào', style: TextStyle(color: Jp.muted)))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => ListTile(
                          enabled: busy == null,
                          title: Text(list[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Jp.text)),
                          subtitle: list[i].size > 0 ? Text('${(list[i].size / 1024).round()} KB', style: TextStyle(color: Jp.muted)) : null,
                          onTap: () => _select(list[i]),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}
