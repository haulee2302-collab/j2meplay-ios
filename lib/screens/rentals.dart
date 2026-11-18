import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'game.dart';
import 'rental_dialogs.dart';
import 'sync.dart';

class RentalsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const RentalsScreen({super.key, required this.onLogout});
  @override
  State<RentalsScreen> createState() => _RentalsScreenState();
}

class _RentalsScreenState extends State<RentalsScreen> {
  List<Rental> rentals = [];
  List<Product> products = [];
  final Map<String, Uint8List> shots = {};
  bool loading = true;
  String? error;
  String? busyId;
  User? user = Api.instance.user;
  Timer? _timer;
  int _shotRun = 0;

  @override
  void initState() {
    super.initState();
    load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    try {
      final u = await Api.instance.me();
      final r = await Api.instance.rentals();
      if (!mounted) return;
      setState(() { user = u; rentals = r; loading = false; error = null; });
      if (products.isEmpty) Api.instance.products().then((p) { if (mounted) setState(() => products = p); }).catchError((_) {});
      _loadShots();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 401) { widget.onLogout(); return; }
      if (!silent) setState(() { loading = false; error = e.message; });
    }
  }

  /// Ảnh màn hình thật của từng máy (tải lần lượt để không dồn yêu cầu).
  Future<void> _loadShots() async {
    final run = ++_shotRun;
    for (final r in List<Rental>.from(rentals)) {
      if (run != _shotRun || !mounted) return;
      if (!r.viewable || (r.status != 'active' && r.status != 'launch_error')) continue;
      final b = await Api.instance.screenShot(r.id);
      if (b != null && mounted && run == _shotRun) setState(() => shots[r.id] = Uint8List.fromList(b));
    }
  }

  String remaining(Rental r) {
    if (r.endsMs <= 0) return '—';
    final left = DateTime.fromMillisecondsSinceEpoch(r.endsMs).difference(DateTime.now());
    if (left.isNegative) return 'Đã hết hạn';
    if (left.inDays >= 1) return 'Còn ${left.inDays} ngày ${left.inHours % 24} giờ';
    if (left.inHours >= 1) return 'Còn ${left.inHours} giờ ${left.inMinutes % 60} phút';
    return 'Còn ${left.inMinutes} phút';
  }

  Future<void> powerOn(Rental r) async {
    setState(() => busyId = r.id);
    try {
      await Api.instance.control(r.id, 'power-on');
      if (mounted) toast(context, 'Đang bật ${r.deviceName}…');
      load(silent: true);
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => busyId = null);
  }

  Future<void> dialog(String kind, Rental r) async {
    final msg = await showRentalAction(context, kind, r);
    if (msg != null && mounted) {
      toast(context, msg);
      load(silent: true);
    }
  }

  Future<void> extend(Rental r) async {
    final msg = await showExtend(context, r, products);
    if (msg != null && mounted) {
      toast(context, msg);
      load(silent: true);
    }
  }

  Future<void> toggleAutoRenew(Rental r) async {
    final (c, j, _) = await Api.instance.rawPost('/api/site/rentals/${Uri.encodeComponent(r.id)}/auto-renew', {'enabled': !r.autoRenew});
    if (!mounted) return;
    if (c >= 200 && c < 300) {
      final m = '${j?['message'] ?? ''}';
      toast(context, m.isEmpty ? (r.autoRenew ? 'Đã tắt gia hạn tự động.' : 'Đã bật gia hạn tự động.') : m);
      load(silent: true);
    } else {
      toast(context, '${j?['error'] ?? 'Thao tác thất bại (mã $c)'}', error: true);
    }
  }

  void openMenu(Rental r) {
    final off = r.poweredOff;
    final canPlay = r.viewable && r.status != 'provisioning' && r.status != 'powering_off';
    Widget item(IconData icon, String text, VoidCallback f, {bool enabled = true, bool danger = false}) => ListTile(
          dense: true,
          enabled: enabled,
          leading: Icon(icon, size: 20, color: !enabled ? Jp.lineStrong : (danger ? Jp.danger : Jp.primary)),
          title: Text(text, style: TextStyle(fontSize: 14, color: !enabled ? Jp.muted : (danger ? Jp.danger : Jp.text))),
          onTap: () { Navigator.pop(context); f(); },
        );
    showModalBottomSheet(
      context: context,
      backgroundColor: Jp.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            ListTile(title: Text(r.deviceName, style: TextStyle(fontWeight: FontWeight.w700, color: Jp.text)), subtitle: Text(r.productName ?? '')),
            if (off)
              item(Icons.power_settings_new, 'Bật J2ME', () => powerOn(r))
            else ...[
              item(Icons.restart_alt, 'Khởi động lại', () => dialog('restart', r), enabled: canPlay),
              item(Icons.aspect_ratio, 'Đổi kích thước', () => dialog('screen-size', r), enabled: canPlay),
              item(Icons.public, 'Proxy', () => dialog('proxy', r), enabled: canPlay),
            ],
            item(Icons.schedule, 'Gia hạn', () => extend(r)),
            item(r.autoRenew ? Icons.toggle_on : Icons.toggle_off, r.autoRenew ? 'Tắt gia hạn tự động' : 'Bật gia hạn tự động', () => toggleAutoRenew(r)),
            item(Icons.edit_outlined, 'Đổi tên máy', () => dialog('name', r)),
            if (!off) item(Icons.power_settings_new, 'Tắt J2ME', () => dialog('power-off', r), danger: true),
            const SizedBox(height: 6),
          ]),
        ),
      ),
    );
  }

  void openRent() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Jp.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => const RentSheet(),
    );
    if (ok == true) load();
  }

  void openGame(Rental r) => Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(rental: r)));

  @override
  Widget build(BuildContext context) {
    final viewable = rentals.where((r) => r.viewable).toList();
    final cardW = (MediaQuery.of(context).size.width - 34) / 2;
    final extent = cardW * 3 / 4 + 92;
    return RefreshIndicator(
      onRefresh: load,
      child: Stack(children: [
        ListView(padding: EdgeInsets.zero, children: [
          HeroHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.person, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Xin chào', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                  Text(user?.name.isNotEmpty == true ? user!.name : (user?.email ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                ])),
                const ThemeToggle(),
              ]),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Số dư', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                  Text(money(user?.balance ?? 0), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                  Text('${rentals.where((r) => !r.expired).length} phiên đang thuê', style: const TextStyle(color: Jp.highlight, fontSize: 13, fontWeight: FontWeight.w600)),
                ])),
                PrimaryButton('Thuê phiên mới', openRent, icon: Icons.add, container: Colors.white, content: Jp.primary, height: 40, fontSize: 12),
                const SizedBox(width: 8),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Row(children: [
              Expanded(child: SectionTitle('Phiên J2ME của bạn', count: rentals.length)),
              IconButton(
                onPressed: () => load(),
                icon: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Jp.primary)) : const Icon(Icons.refresh, color: Jp.primary),
              ),
            ]),
          ),
          if (rentals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryButton('Xem tất cả (${viewable.length})', viewable.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyncScreen(rentals: viewable))),
                    icon: Icons.sync, height: 34, fontSize: 12),
              ),
            ),
          if (loading && rentals.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Jp.primary)))
          else if (error != null) Padding(padding: const EdgeInsets.all(20), child: Text(error!, style: const TextStyle(color: Jp.danger)))
          else if (rentals.isEmpty) _empty()
          else Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rentals.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, mainAxisExtent: extent),
              itemBuilder: (c, i) => _card(rentals[i]),
            ),
          ),
          const SizedBox(height: 80),
        ]),
        if (viewable.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 18,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: PrimaryButton('Xem tất cả (${viewable.length})', () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyncScreen(rentals: viewable))), icon: Icons.sync, height: 44, fontSize: 13),
            ),
          ),
      ]),
    );
  }

  Widget _empty() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        decoration: cardDeco(radius: 12),
        child: Column(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.sports_esports, color: Jp.primary)),
          const SizedBox(height: 10),
          Text('Chưa có máy J2ME nào', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Jp.text)),
          const SizedBox(height: 4),
          Text('Thuê một phiên để bắt đầu chơi game Java ngay trên điện thoại.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Jp.muted)),
          const SizedBox(height: 14),
          PrimaryButton('Thuê phiên mới', openRent, icon: Icons.add, height: 38, fontSize: 13),
        ]),
      );

  (String, Color) _state(Rental r) {
    if (r.expired) return ('Hết hạn', Jp.danger);
    switch (r.status) {
      case 'active': return ('Đang chạy', Jp.success);
      case 'powered_off': return ('Đã tắt', Jp.muted);
      case 'provisioning': return ('Đang tạo', Jp.infoBlue);
      case 'powering_on': return ('Đang bật', Jp.infoBlue);
      case 'powering_off': return ('Đang tắt', Jp.infoBlue);
      case 'restarting': return ('Khởi động lại', Jp.infoBlue);
      default: return ('Đã dừng', Jp.muted);
    }
  }

  Widget _card(Rental r) {
    final (label, color) = _state(r);
    final shot = shots[r.id];
    final off = r.poweredOff;
    return Container(
      decoration: cardDeco(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            color: Jp.gameBg,
            child: Stack(fit: StackFit.expand, children: [
              if (shot != null) Image.memory(shot, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.none)
              else Center(child: Icon(Icons.phone_android, size: 38, color: Jp.muted.withOpacity(0.6))),
              Positioned(top: 6, left: 6, child: StatusPill(label, color, white: true)),
              if (r.screenWidth > 0)
                Positioned(
                  bottom: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(5)),
                    child: Text('${r.screenWidth}×${r.screenHeight}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Jp.text)),
            const SizedBox(height: 2),
            Text(remaining(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Jp.muted)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: off
                    ? PrimaryButton('Bật', busyId == r.id ? null : () => powerOn(r), loading: busyId == r.id, height: 30, fontSize: 12)
                    : PrimaryButton('Xem', r.viewable ? () => openGame(r) : null, height: 30, fontSize: 12),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 30, height: 30,
                child: OutlinedButton(
                  onPressed: () => openMenu(r),
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, side: BorderSide(color: Jp.lineStrong), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Icon(Icons.more_vert, size: 16, color: Jp.primary),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class RentSheet extends StatefulWidget {
  const RentSheet({super.key});
  @override
  State<RentSheet> createState() => _RentSheetState();
}

class _RentSheetState extends State<RentSheet> {
  List<Product> products = [];
  Product? picked;
  int qty = 1;
  Map<String, dynamic>? preview;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    Api.instance.products().then((p) {
      if (!mounted) return;
      setState(() { products = p; if (p.isNotEmpty) picked = p.first; });
      refresh();
    }).catchError((e) { if (mounted) setState(() => error = e.toString()); });
  }

  Future<void> refresh() async {
    if (picked == null) return;
    try {
      final p = await Api.instance.previewRental(picked!.id, qty);
      if (mounted) setState(() { preview = p; error = null; });
    } on ApiError catch (e) {
      if (mounted) setState(() { preview = null; error = e.message; });
    }
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await Api.instance.createRental(picked!.id, qty);
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) setState(() { busy = false; error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = ((preview?['amount'] ?? 0) as num).toInt();
    final enough = preview?['enoughBalance'] != false;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Thuê phiên mới', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Jp.text)),
          const SizedBox(height: 2),
          Text('Chọn gói và số chu kỳ.', style: TextStyle(fontSize: 13, color: Jp.muted)),
          const SizedBox(height: 12),
          if (products.isEmpty && error == null) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Jp.primary))),
          for (final p in products)
            GestureDetector(
              onTap: () { setState(() => picked = p); refresh(); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: picked?.id == p.id ? Jp.primarySoft : Jp.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: picked?.id == p.id ? Jp.primary : Jp.line, width: picked?.id == p.id ? 1.5 : 1),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: TextStyle(fontWeight: FontWeight.w700, color: Jp.text)),
                    Text('${p.durationDays} ngày / chu kỳ', style: TextStyle(fontSize: 12, color: Jp.muted)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(p.price), style: const TextStyle(fontWeight: FontWeight.w800, color: Jp.primary)),
                    if (p.originalPrice > p.price) Text(money(p.originalPrice), style: TextStyle(fontSize: 11, color: Jp.muted, decoration: TextDecoration.lineThrough)),
                  ]),
                ]),
              ),
            ),
          Row(children: [
            Expanded(child: Text('Số chu kỳ', style: TextStyle(color: Jp.muted, fontSize: 14))),
            IconButton(onPressed: qty > 1 ? () { setState(() => qty--); refresh(); } : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$qty', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.text)),
            IconButton(onPressed: qty < 12 ? () { setState(() => qty++); refresh(); } : null, icon: const Icon(Icons.add_circle_outline)),
          ]),
          Row(children: [
            Expanded(child: Text('Thành tiền', style: TextStyle(color: Jp.muted, fontSize: 14))),
            Text(money(amount), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Jp.text)),
          ]),
          if (!enough) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Số dư không đủ. Hãy nạp thêm tiền.', style: TextStyle(color: Jp.danger, fontSize: 13))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: const TextStyle(color: Jp.danger, fontSize: 13))),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: PrimaryButton('Thuê ngay', picked != null && enough ? submit : null, loading: busy)),
        ]),
      ),
    );
  }
}
