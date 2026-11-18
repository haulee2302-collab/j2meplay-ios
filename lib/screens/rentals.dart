import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../icons.dart';
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
  final ScrollController _scroll = ScrollController();
  bool headerGone = false;

  String get _name => (user?.name.isNotEmpty == true ? user!.name : (user?.email ?? 'Bạn'));
  String get _initial => _name.trim().isEmpty ? '?' : _name.trim().characters.first.toUpperCase();

  @override
  void initState() {
    super.initState();
    load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => load(silent: true));
    _scroll.addListener(() {
      final g = _scroll.offset > 300;
      if (g != headerGone) setState(() => headerGone = g);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
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

  Future<void> openMenu(Rental r, BuildContext btn) async {
    final off = r.poweredOff;
    final canPlay = r.viewable && r.status != 'provisioning' && r.status != 'powering_off';
    final box = btn.findRenderObject() as RenderBox;
    final overlay = Overlay.of(btn).context.findRenderObject() as RenderBox;
    final tl = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = overlay.size;
    const menuW = 190.0;
    final menuH = (off ? 4 : 7) * 42.0 + 16;
    var left = tl.dx + box.size.width + 12 - menuW;
    left = left.clamp(6.0, size.width - menuW - 6);
    final below = tl.dy + box.size.height + 6;
    final bottomPad = MediaQuery.of(context).padding.bottom + 66;
    final top = below + menuH > size.height - bottomPad ? (tl.dy - 6 - menuH).clamp(6.0, size.height) : below;
    final position = RelativeRect.fromLTRB(left, top, size.width - left - menuW, 0);
    PopupMenuItem<String> item(String v, JpIconData icon, String text, {bool enabled = true, bool danger = false}) => PopupMenuItem<String>(
          value: v,
          enabled: enabled,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            JpIcon(icon, size: 18, color: !enabled ? Jp.lineStrong : (danger ? Jp.danger : Jp.primary)),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: !enabled ? Jp.muted : (danger ? Jp.danger : Jp.text)))),
          ]),
        );
    final v = await showMenu<String>(
      context: context,
      position: position,
      color: Jp.surface,
      elevation: 10,
      constraints: const BoxConstraints(minWidth: menuW, maxWidth: menuW + 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Jp.line)),
      items: [
        if (off)
          item('power-on', JpIcons.power, 'Bật J2ME')
        else ...[
          item('restart', JpIcons.restart2, 'Khởi động lại', enabled: canPlay),
          item('screen-size', JpIcons.screen, 'Đổi kích thước', enabled: canPlay),
          item('proxy', JpIcons.globe, 'Proxy', enabled: canPlay),
        ],
        item('extend', JpIcons.clock, 'Gia hạn'),
        item('auto-renew', r.autoRenew ? JpIcons.toggleOn : JpIcons.toggleOff, r.autoRenew ? 'Tắt gia hạn tự động' : 'Bật gia hạn tự động'),
        item('name', JpIcons.edit, 'Đổi tên máy'),
        if (!off) item('power-off', JpIcons.power, 'Tắt J2ME', danger: true),
      ],
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'power-on': powerOn(r); break;
      case 'extend': extend(r); break;
      case 'auto-renew': toggleAutoRenew(r); break;
      default: dialog(v, r);
    }
  }

  void openRent() async {
    final ok = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Jp.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => const RentSheet(),
    );
    if (ok != null && mounted) { toast(context, ok); load(silent: true); }
  }

  void openGame(Rental r) => Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(rental: r)));

  @override
  Widget build(BuildContext context) {
    final viewable = rentals.where((r) => r.viewable).toList();
    final cardW = (MediaQuery.of(context).size.width - 34) / 2;
    final extent = cardW * 3 / 4 + 98;
    return RefreshIndicator(
      onRefresh: load,
      child: Stack(children: [
        ListView(controller: _scroll, padding: EdgeInsets.zero, children: [
          HeroHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: Text(_initial, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Xin chào', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                  Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                ])),
                const ThemeToggle(),
              ]),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      JpIcon(JpIcons.wallet, size: 16, color: Colors.white.withOpacity(0.8)),
                      const SizedBox(width: 6),
                      Text('Số dư', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                    ]),
                    Text(money(user?.balance ?? 0), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                    Text('${rentals.where((r) => !r.expired).length} phiên đang thuê', style: const TextStyle(color: Jp.highlight, fontSize: 13, fontWeight: FontWeight.w600)),
                  ])),
                  PrimaryButton('Thuê phiên', openRent, icon: JpIcons.add, container: Colors.white, content: Jp.primary, height: 44, fontSize: 14),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Text('Phiên J2ME của bạn', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Jp.text)),
              if (rentals.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(99)), child: Text('${rentals.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Jp.primaryDark))),
              ],
              const Spacer(),
              IconButton(
                onPressed: () => load(),
                icon: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Jp.primary)) : const JpIcon(JpIcons.refresh, color: Jp.primary),
              ),
            ]),
          ),
          if (rentals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryButton('Xem tất cả (${viewable.length})', viewable.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyncScreen(rentals: viewable))),
                    icon: JpIcons.syncIcon, height: 30, fontSize: 12),
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
        if (viewable.isNotEmpty && headerGone)
          Positioned(
            right: 16,
            bottom: 18,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: PrimaryButton('Xem tất cả (${viewable.length})', () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyncScreen(rentals: viewable))), icon: JpIcons.syncIcon, height: 44, fontSize: 13),
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
          Container(width: 48, height: 48, decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(12)), child: const JpIcon(JpIcons.gamepad, color: Jp.primary)),
          const SizedBox(height: 10),
          Text('Chưa có máy J2ME nào', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Jp.text)),
          const SizedBox(height: 4),
          Text('Thuê một phiên để bắt đầu chơi game Java ngay trên điện thoại.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Jp.muted)),
          const SizedBox(height: 14),
          PrimaryButton('Thuê phiên mới', openRent, icon: JpIcons.add, height: 38, fontSize: 13),
        ]),
      );

  (String, Color) _state(Rental r) {
    if (r.expired || r.status == 'expired') return ('Hết hạn', Jp.muted);
    if (r.status == 'powered_off') return ('Đã tắt', Jp.muted);
    if (r.status == 'powering_off') return ('Đang tắt...', Jp.muted);
    if (r.status == 'powering_on') return ('Đang bật...', Jp.infoBlue);
    if (r.status == 'restarting') return ('Đang khởi động...', Jp.infoBlue);
    if (r.status == 'provisioning') return ('Đang khởi tạo...', Jp.infoBlue);
    if (r.connectionStatus == 'disconnected') return ('Mất kết nối', Jp.danger);
    if (r.status == 'launch_error') return ('Lỗi khởi chạy', Jp.danger);
    if (r.status == 'active') return ('Sẵn sàng', Jp.success);
    return (r.status, Jp.muted);
  }

  Widget _card(Rental r) {
    final (label, color) = _state(r);
    final shot = shots[r.id];
    final off = r.poweredOff;
    final expired = r.expired;
    final canPlay = !expired && !off && r.status != 'provisioning' && r.status != 'powering_off';
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
              else Center(child: Opacity(opacity: off || expired ? 0.35 : 0.85, child: FractionallySizedBox(widthFactor: 0.7, child: Image.asset('assets/jp_logo.png', fit: BoxFit.fitWidth)))),
              if (off || expired) Container(color: Colors.black.withOpacity(0.35)),
              Positioned(top: 6, left: 6, child: StatusPill(label, color, white: true)),
              if (busyId == r.id) const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.deviceName.isEmpty ? 'Máy J2ME' : r.deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Jp.text)),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Row(children: [
                JpIcon(JpIcons.clock, size: 12, color: expired ? Jp.danger : Jp.muted),
                const SizedBox(width: 4),
                Expanded(child: Text(remaining(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: expired ? Jp.danger : Jp.muted))),
              ]),
            ),
            if (!expired)
              Row(children: [
                Expanded(
                  child: off
                      ? PrimaryButton('Bật máy', busyId == r.id ? null : () => powerOn(r), loading: busyId == r.id, height: 30, fontSize: 12)
                      : PrimaryButton('Màn hình', canPlay ? () => openGame(r) : null, height: 30, fontSize: 12),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 30, height: 30,
                  child: Builder(builder: (bc) => OutlinedButton(
                    onPressed: busyId == r.id ? null : () => openMenu(r, bc),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, side: BorderSide(color: Jp.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: const JpIcon(JpIcons.more, size: 18, color: Jp.primary),
                  )),
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
  int cycles = 1, devices = 1;
  Map<String, dynamic>? preview;
  bool calculating = false, busy = false;
  String? error;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    Api.instance.products().then((p) {
      if (!mounted) return;
      setState(() { products = p; if (p.isNotEmpty) picked = p.first; });
      refresh();
    }).catchError((e) { if (mounted) setState(() => error = e.toString()); });
  }

  /// Đổi lựa chọn: giữ bảng giá cũ (không nháy), chờ 250ms rồi hỏi giá mới.
  Future<void> refresh() async {
    final p = picked;
    if (p == null) return;
    final run = ++_run;
    setState(() => calculating = true);
    await Future.delayed(const Duration(milliseconds: 250));
    if (run != _run || !mounted) return;
    try {
      final r = await Api.instance.previewBulk(p.id, cycles, devices);
      if (mounted && run == _run) setState(() { preview = r; error = null; calculating = false; });
    } on ApiError catch (e) {
      if (mounted && run == _run) setState(() { error = e.message; calculating = false; });
    }
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      final n = await Api.instance.createBulk(picked!.id, cycles, devices);
      if (mounted) Navigator.pop(context, 'Đã thuê $n phiên mới. Máy đang được khởi tạo…');
    } on ApiError catch (e) {
      if (mounted) setState(() { busy = false; error = e.message; });
    }
  }

  String _unit(int d) => d == 1 ? 'ngày' : d == 7 ? 'tuần' : d == 30 ? 'tháng' : '$d ngày';
  int _n(dynamic v) => v is num ? v.toInt() : 0;

  Widget _stepper(String label, String hint, int value, int min, int max, void Function(int) f) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Jp.text)),
            Text(hint, style: TextStyle(fontSize: 12, color: Jp.muted)),
          ])),
          Container(
            height: 34,
            decoration: BoxDecoration(border: Border.all(color: Jp.line), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              InkWell(onTap: value > min ? () { f(value - 1); refresh(); } : null, child: SizedBox(width: 34, height: 34, child: Center(child: JpIcon(JpIcons.remove, size: 18, color: value > min ? Jp.primary : Jp.lineStrong)))),
              ConstrainedBox(constraints: const BoxConstraints(minWidth: 36), child: Text('$value', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.text))),
              InkWell(onTap: value < max ? () { f(value + 1); refresh(); } : null, child: SizedBox(width: 34, height: 34, child: Center(child: JpIcon(JpIcons.add, size: 18, color: value < max ? Jp.primary : Jp.lineStrong)))),
            ]),
          ),
        ]),
      );

  Widget _row(String l, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(l, style: TextStyle(color: Jp.muted, fontSize: 14))), Text(v, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w600))]),
      );

  @override
  Widget build(BuildContext context) {
    final pv = preview;
    final dur = picked?.durationDays ?? 1;
    final base = _n(pv?['baseAmount']), amount = _n(pv?['amount']);
    final enoughBal = pv?['enoughBalance'] != false, enoughCap = pv?['enoughCapacity'] != false;
    final msg = error ?? (pv == null ? null : !enoughBal ? 'Số dư không đủ để thuê.' : !enoughCap ? 'Máy chủ hiện không đủ chỗ cho số máy đã chọn.' : null);
    final can = !calculating && error == null && pv != null && enoughBal && enoughCap;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Thuê phiên mới', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Jp.text)),
          Padding(padding: const EdgeInsets.only(top: 2, bottom: 14), child: Text('Chọn gói, số chu kỳ và số máy.', style: TextStyle(fontSize: 13, color: Jp.muted))),
          if (products.isEmpty && error == null) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Jp.primary))),
          for (final p in products)
            GestureDetector(
              onTap: () { setState(() => picked = p); refresh(); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: picked?.id == p.id ? Jp.primarySoft : Jp.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: picked?.id == p.id ? Jp.primary : Jp.line, width: picked?.id == p.id ? 1.5 : 1),
                ),
                child: Row(children: [
                  JpIcon(picked?.id == p.id ? JpIcons.radioOn : JpIcons.radioOff, size: 20, color: picked?.id == p.id ? Jp.primary : Jp.muted),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Jp.text)),
                    Text('${p.durationDays} ngày / chu kỳ', style: TextStyle(fontSize: 12, color: Jp.muted)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(p.price), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.primary)),
                    if (p.originalPrice > p.price) Text(money(p.originalPrice), style: TextStyle(fontSize: 12, color: Jp.muted, decoration: TextDecoration.lineThrough)),
                  ]),
                ]),
              ),
            ),
          _stepper('Số chu kỳ', '$cycles ${_unit(dur)} = ${cycles * dur} ngày', cycles, 1, 3650 ~/ (dur < 1 ? 1 : dur), (v) => setState(() => cycles = v)),
          _stepper('Số máy', 'Mỗi máy là một phiên riêng', devices, 1, 50, (v) => setState(() => devices = v)),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Jp.bgFaint, borderRadius: BorderRadius.circular(10)),
            child: Opacity(
              opacity: calculating && pv != null ? 0.55 : 1,
              child: Column(children: [
                _row('Tạm tính', pv == null ? '—' : money(base), Jp.text),
                _row('Ưu đãi', pv == null ? '—' : (base > amount ? '-${money(base - amount)}' : '0 đ'), Jp.success),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Jp.line)),
                Row(children: [
                  Expanded(child: Text('Thành tiền', style: TextStyle(color: Jp.muted, fontSize: 14))),
                  if (calculating) const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Jp.primary))),
                  Text(pv == null ? '—' : money(amount), style: TextStyle(color: Jp.text, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                _row('Số dư sau khi thuê', pv == null ? '—' : money(_n(pv['balanceAfter'])), !enoughBal ? Jp.danger : Jp.muted),
              ]),
            ),
          ),
          ConstrainedBox(constraints: const BoxConstraints(minHeight: 22), child: Padding(padding: const EdgeInsets.only(top: 6), child: msg == null ? null : Text(msg, style: const TextStyle(color: Jp.danger, fontSize: 13, fontWeight: FontWeight.w500)))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: PrimaryButton(devices > 1 ? 'Xác nhận thuê $devices máy' : 'Xác nhận thuê', can ? submit : null, loading: busy, height: 50)),
        ]),
      ),
    );
  }
}
