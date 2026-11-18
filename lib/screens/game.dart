import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../game/connection.dart';
import '../game/keypad.dart';
import '../game/midp.dart';
import '../theme.dart';
import '../widgets.dart';

/// Màn hình xem/chơi một phiên thuê (bố cục như GameViewerLayout bên Android): đầu trang, khung game đúng tỉ lệ
/// (hình vẽ từ luồng JPC1, chạm → toạ độ chuẩn hoá), thanh công cụ, bàn phím ảo; form/danh sách MIDP hiện bằng giao diện Native.
class GameScreen extends StatefulWidget {
  final Rental rental;
  const GameScreen({super.key, required this.rental});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final GameConnection conn;
  bool showPad = true;
  String? lastKind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    conn = GameConnection(widget.rental.id)..addListener(_onConn);
    conn.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  void _touch(String phase, Offset p, Size size) {
    final x = (p.dx / size.width).clamp(0.0, 1.0), y = (p.dy / size.height).clamp(0.0, 1.0);
    conn.touch(phase, x, y);
  }

  Future<void> _typeText() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Jp.surface,
        title: Text('Nhập chữ vào game', style: TextStyle(color: Jp.text, fontSize: 16)),
        content: TextField(controller: c, autofocus: true, style: TextStyle(color: Jp.text)),
        actions: [
          TextButton(onPressed: () { conn.key('BACKSPACE', 'tap'); }, child: const Text('Xóa lùi')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Đóng', style: TextStyle(color: Jp.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Gửi')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      final ok = await conn.text(v);
      if (!ok && mounted) toast(context, 'Không gửi được chữ tới máy J2ME', error: true);
    }
  }

  Future<void> _control(String action, String confirm) async {
    if (!await confirmDialog(context, confirm, 'Thực hiện thao tác này trên máy J2ME?')) return;
    try {
      await Api.instance.control(widget.rental.id, action);
      if (!mounted) return;
      toast(context, 'Đã gửi lệnh');
      conn.reload();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  void _openJars() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Jp.surface,
      builder: (_) => _JarSheet(conn: conn, onSelected: () { Navigator.pop(context); conn.reload(); }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rental;
    final w = conn.frameW > 0 ? conn.frameW : (r.screenWidth > 0 ? r.screenWidth : 320);
    final h = conn.frameH > 0 ? conn.frameH : (r.screenHeight > 0 ? r.screenHeight : 400);
    final rt = conn.runtime;
    final native = runtimeNativeKind(rt) != null;
    final live = conn.firstFrame && !conn.statusError;
    return Scaffold(
      backgroundColor: Jp.bgFaint,
      body: Column(children: [
        Container(
          color: Jp.surface,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: JpIcon(JpIcons.back, color: Jp.text)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Jp.text)),
                  Row(children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: conn.statusError ? Jp.danger : (live ? Jp.success : Jp.muted), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Flexible(child: Text(live ? 'Đang chạy' : conn.statusText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Jp.muted))),
                  ]),
                ])),
                IconButton(onPressed: _typeText, icon: JpIcon(JpIcons.toolKeyboard, color: Jp.text)),
                IconButton(onPressed: () => setState(() => showPad = !showPad), icon: JpIcon(JpIcons.gamepad, color: showPad ? Jp.primary : Jp.text)),
              ]),
            ),
          ),
        ),
        Divider(height: 1, color: Jp.line),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AspectRatio(
                aspectRatio: w / h,
                child: LayoutBuilder(builder: (ctx, box) {
                  final size = Size(box.maxWidth, box.maxHeight);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      decoration: BoxDecoration(color: Jp.surface, border: Border.all(color: Jp.lineStrong), borderRadius: BorderRadius.circular(7)),
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
                        if (conn.image == null || !live)
                          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            if (conn.loading) const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Jp.primary)),
                            if (conn.loading) const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(conn.statusText, textAlign: TextAlign.center, style: TextStyle(color: conn.statusError ? Jp.danger : Jp.infoBlue, fontWeight: FontWeight.w600)),
                            ),
                            if (conn.noGame) ...[
                              const SizedBox(height: 10),
                              PrimaryButton('Chọn JAR', _openJars, height: 38, fontSize: 13),
                            ],
                          ])),
                        if (native && rt != null) Positioned.fill(child: MidpOverlay(runtime: rt, conn: conn, onError: (m) => toast(context, m, error: true))),
                      ]),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(flex: 2, child: PrimaryButton('Chọn JAR', _openJars, height: 40, fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: OutlineButton2('Bàn phím', () => setState(() => showPad = !showPad), height: 40)),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 40,
              child: PopupMenuButton<String>(
                color: Jp.surface,
                onSelected: (v) {
                  if (v == 'reload') conn.reload();
                  if (v == 'restart') _control('restart', 'Khởi động lại máy?');
                  if (v == 'stop') _control('power-off', 'Tắt máy?');
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reload', child: Text('Kết nối lại màn hình')),
                  PopupMenuItem(value: 'restart', child: Text('Khởi động lại máy')),
                  PopupMenuItem(value: 'stop', child: Text('Tắt máy')),
                ],
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: Jp.lineStrong), borderRadius: BorderRadius.circular(9)),
                  child: const JpIcon(JpIcons.tune, color: Jp.primary, size: 18),
                ),
              ),
            ),
          ]),
        ),
        if (showPad) Keypad(conn),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ]),
    );
  }
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

class _JarSheet extends StatefulWidget {
  final GameConnection conn;
  final VoidCallback onSelected;
  const _JarSheet({required this.conn, required this.onSelected});
  @override
  State<_JarSheet> createState() => _JarSheetState();
}

class _JarSheetState extends State<_JarSheet> {
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
