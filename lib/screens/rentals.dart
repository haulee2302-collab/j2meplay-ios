import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'game.dart';

class RentalsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const RentalsScreen({super.key, required this.onLogout});
  @override
  State<RentalsScreen> createState() => _RentalsScreenState();
}

class _RentalsScreenState extends State<RentalsScreen> {
  List<Rental> rentals = [];
  bool loading = true;
  String? error;
  User? user = Api.instance.user;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final u = await Api.instance.me();
      final r = await Api.instance.rentals();
      if (!mounted) return;
      setState(() { user = u; rentals = r; loading = false; error = null; });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 401) { widget.onLogout(); return; }
      setState(() { loading = false; error = e.message; });
    }
  }

  String remaining(int endsAt) {
    if (endsAt <= 0) return '—';
    // endsAt có thể là mili giây hoặc giây; chuẩn hóa về mili giây.
    final ms = endsAt < 100000000000 ? endsAt * 1000 : endsAt;
    final left = DateTime.fromMillisecondsSinceEpoch(ms).difference(DateTime.now());
    if (left.isNegative) return 'Đã hết hạn';
    if (left.inDays >= 1) return 'Còn ${left.inDays} ngày ${left.inHours % 24} giờ';
    if (left.inHours >= 1) return 'Còn ${left.inHours} giờ ${left.inMinutes % 60} phút';
    return 'Còn ${left.inMinutes} phút';
  }

  Future<void> action(Rental r, String act, String title, String body) async {
    if (!await confirmDialog(context, title, body, danger: act == 'power-off')) return;
    try {
      await Api.instance.control(r.id, act);
      if (mounted) toast(context, 'Đã gửi lệnh');
      load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  void openMenu(Rental r) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Jp.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(title: Text(r.deviceName, style: TextStyle(fontWeight: FontWeight.w700, color: Jp.text)), subtitle: Text(r.productName ?? '')),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Jp.primary),
            title: Text('Khởi động lại máy', style: TextStyle(color: Jp.text)),
            onTap: () { Navigator.pop(c); action(r, 'restart', 'Khởi động lại?', '${r.deviceName} sẽ khởi động lại, game đang chạy sẽ mở lại từ đầu.'); },
          ),
          ListTile(
            leading: const Icon(Icons.power_settings_new, color: Jp.danger),
            title: const Text('Tắt máy', style: TextStyle(color: Jp.danger)),
            onTap: () { Navigator.pop(c); action(r, 'power-off', 'Tắt máy?', '${r.deviceName} sẽ tắt và game đang chạy bị đóng. Thời gian thuê vẫn tiếp tục.'); },
          ),
        ]),
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: EdgeInsets.zero, children: [
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
                Text('${rentals.length} phiên đang thuê', style: const TextStyle(color: Jp.highlight, fontSize: 13, fontWeight: FontWeight.w600)),
              ])),
              PrimaryButton('Thuê phiên mới', openRent, icon: Icons.add, container: Colors.white, content: Jp.primary, height: 40, fontSize: 12),
              const SizedBox(width: 8),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: SectionTitle('Phiên J2ME của bạn', count: rentals.length),
        ),
        if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Jp.primary)))
        else if (error != null) Padding(padding: const EdgeInsets.all(20), child: Text(error!, style: const TextStyle(color: Jp.danger)))
        else if (rentals.isEmpty) _empty()
        else Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rentals.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, mainAxisExtent: 215),
            itemBuilder: (c, i) => _card(rentals[i]),
          ),
        ),
        const SizedBox(height: 28),
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

  Widget _card(Rental r) {
    final active = r.status == 'active';
    final ratio = (r.screenWidth > 0 && r.screenHeight > 0) ? r.screenWidth / r.screenHeight : 3 / 4;
    return Container(
      decoration: cardDeco(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            color: Jp.gameBg,
            child: Stack(children: [
              Center(child: Icon(Icons.phone_android, size: 38, color: Jp.muted.withOpacity(0.6))),
              Positioned(top: 6, left: 6, child: StatusPill(active ? 'Đang chạy' : 'Đã dừng', active ? Jp.success : Jp.muted, white: true)),
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
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Jp.text)),
            const SizedBox(height: 2),
            Text(remaining(r.endsAt), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Jp.muted)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: PrimaryButton('Xem', () => Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(rental: r))), height: 30, fontSize: 12)),
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
