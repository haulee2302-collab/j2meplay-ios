import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onOpenRentals;
  const ProfileScreen({super.key, required this.onLogout, required this.onOpenRentals});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

String _date(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms < 100000000000 ? ms * 1000 : ms);
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)}/${d.year}';
}

String _dateTime(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms < 100000000000 ? ms * 1000 : ms);
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.hour)}:${t(d.minute)} ${t(d.day)}/${t(d.month)}/${d.year}';
}

int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

String _txLabel(String type) {
  switch (type) {
    case 'deposit': return 'Nạp tiền';
    case 'rental': case 'purchase': case 'order': return 'Thuê phiên';
    case 'extension': case 'renewal': return 'Gia hạn';
    case 'refund': return 'Hoàn tiền';
    case 'admin_adjustment': return 'Điều chỉnh số dư';
    default: return type.isEmpty ? 'Giao dịch' : type;
  }
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? me;
  int active = -1;
  List<Map<String, dynamic>> txs = [];
  String? page; // info | security | tx | contact
  Map<String, dynamic>? contact;
  bool contactFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (c, j, _) = await Api.instance.rawGet('/api/site/me');
    if (c == 401) { widget.onLogout(); return; }
    if (mounted) setState(() => me = (j?['user'] as Map?)?.cast<String, dynamic>());
    try {
      final r = await Api.instance.rentals();
      if (mounted) setState(() => active = r.where((e) => !e.expired).length);
    } catch (_) {}
    final (tc, tj, _) = await Api.instance.rawGet('/api/site/transactions');
    if (tc >= 200 && tc < 300 && mounted) {
      final a = (tj?['transactions'] as List?) ?? [];
      setState(() => txs = [for (final e in a.take(30)) if (e is Map) e.cast<String, dynamic>()]);
    }
  }

  Future<void> _loadContact() async {
    final (c, j, _) = await Api.instance.rawGet('/api/site/contact');
    if (!mounted) return;
    if (c >= 200 && c < 300) {
      setState(() => contact = (j?['contact'] as Map?)?.cast<String, dynamic>() ?? {});
    } else {
      setState(() => contactFailed = true);
    }
  }

  Future<void> _logout() async {
    if (!await confirmDialog(context, 'Đăng xuất?', 'Bạn sẽ cần đăng nhập lại để dùng ứng dụng.', ok: 'Đăng xuất', danger: true)) return;
    await Api.instance.logout();
    widget.onLogout();
  }

  Future<void> _changePassword() async {
    final cur = TextEditingController(), next = TextEditingController(), again = TextEditingController();
    String? err;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setS) => AlertDialog(
        backgroundColor: Jp.surface,
        title: Text('Đổi mật khẩu', style: TextStyle(color: Jp.text, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mật khẩu mới từ 8 ký tự. Các thiết bị khác sẽ bị đăng xuất.', style: TextStyle(color: Jp.muted, fontSize: 13)),
          TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại')),
          TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu mới')),
          TextField(controller: again, obscureText: true, decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới')),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Jp.danger, fontSize: 12))),
        ]),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(d), child: Text('Hủy', style: TextStyle(color: Jp.muted))),
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    if (next.text.length < 8) { setS(() => err = 'Mật khẩu mới phải từ 8 ký tự'); return; }
                    if (next.text != again.text) { setS(() => err = 'Mật khẩu nhập lại chưa khớp'); return; }
                    setS(() { saving = true; err = null; });
                    final (c, j, _) = await Api.instance.rawPost('/api/site/change-password', {'currentPassword': cur.text, 'newPassword': next.text, 'passwordConfirmation': again.text});
                    if (c >= 200 && c < 300) {
                      if (d.mounted) Navigator.pop(d);
                      if (mounted) toast(context, '${j?['message'] ?? 'Mật khẩu đã được cập nhật.'}');
                    } else {
                      setS(() { saving = false; err = '${j?['error'] ?? j?['message'] ?? 'Không đổi được mật khẩu (mã $c)'}'; });
                    }
                  },
            child: Text(saving ? 'Đang lưu…' : 'Lưu', style: const TextStyle(color: Jp.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      )),
    );
  }

  void _open(String uri) {
    launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
  }

  Widget _head(String eyebrow, String title, String desc) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eyebrow, style: const TextStyle(color: Jp.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Jp.text)),
              const SizedBox(height: 2),
              Text(desc, style: TextStyle(fontSize: 12, color: Jp.muted)),
            ]),
          ),
        ),
      );

  Widget _section(String title, String sub, List<Widget> children) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(14),
        decoration: cardDeco(radius: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.text)),
          Text(sub, style: TextStyle(fontSize: 12, color: Jp.muted)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  Widget _info(String l, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(l, style: TextStyle(fontSize: 13, color: Jp.muted))),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? Jp.text))),
        ]),
      );

  Widget _menuItem(String key, IconData icon, String label) {
    final danger = key == 'logout';
    return GestureDetector(
      onTap: () {
        if (danger) { _logout(); return; }
        setState(() => page = key);
        if (key == 'contact' && contact == null) _loadContact();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: danger ? const Color(0xFFFECACA) : Jp.line)),
        child: Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: danger ? Jp.dangerBg : Jp.primarySoft, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 17, color: danger ? Jp.danger : Jp.primary)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: danger ? Jp.danger : Jp.text))),
          if (!danger) Text('›', style: TextStyle(fontSize: 20, color: Jp.muted)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = me;
    final name = ('${u?['name'] ?? ''}').isEmpty ? '—' : '${u?['name']}';
    final email = '${u?['email'] ?? ''}';
    final role = u == null ? '—' : (u['role'] == 'admin' ? 'Quản trị viên' : 'Thành viên');
    final verified = u?['emailVerified'] == true;
    final created = _n(u?['createdAt']);
    final st = '${u?['status'] ?? ''}';
    final statusLabel = u == null ? '—' : (st == 'active' ? 'Đang hoạt động' : ['locked', 'banned', 'disabled'].contains(st) ? 'Bị khóa' : st);
    final balance = _n(u?['balance'] ?? Api.instance.user?.balance);

    final titles = {'info': 'Thông tin tài khoản', 'security': 'Bảo mật & truy cập', 'tx': 'Lịch sử giao dịch', 'contact': 'Liên hệ'};
    final children = <Widget>[
      if (page == 'contact')
        _head('HỖ TRỢ', 'Liên hệ', 'Liên hệ J2ME Play để được hỗ trợ tài khoản, nạp tiền, phiên giả lập JAR và dịch vụ J2ME cloud.')
      else
        _head('TRANG CÁ NHÂN', titles[page] ?? 'Tài khoản', 'Tất cả thông tin và quyền kiểm soát tài khoản của bạn.'),
      if (page != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: InkWell(
            onTap: () => setState(() => page = null),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.arrow_back, size: 18, color: Jp.primary),
                const SizedBox(width: 4),
                const Text('Tài khoản', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Jp.primary)),
              ]),
            ),
          ),
        ),
      if (page == null) ...[
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Jp.primary, Color(0xFF8B5CF6)]), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Row(children: [
              Container(width: 44, height: 44, alignment: Alignment.center, decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle), child: Text(name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
              ])),
              const Text('✦ Thành viên', style: TextStyle(color: Jp.highlight, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _stat('Số dư khả dụng', money(balance), 18)),
              Expanded(child: _stat('Phiên đang thuê', active < 0 ? '—' : '$active', 18)),
              Expanded(child: _stat('Đồng hành từ', _date(created), 14)),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            _menuItem('info', Icons.person_outline, 'Thông tin tài khoản'),
            const SizedBox(height: 8),
            _menuItem('security', Icons.lock_outline, 'Bảo mật & truy cập'),
            const SizedBox(height: 8),
            _menuItem('tx', Icons.account_balance_wallet_outlined, 'Lịch sử giao dịch'),
            const SizedBox(height: 8),
            _menuItem('contact', Icons.support_agent, 'Liên hệ hỗ trợ'),
            const SizedBox(height: 8),
            _menuItem('logout', Icons.logout, 'Đăng xuất'),
          ]),
        ),
      ],
      if (page == 'info')
        _section('Thông tin cá nhân', 'Một vài thông tin về bạn trên J2ME Play', [
          _info('Tên', name),
          _info('Vai trò', role),
          _info('Xác minh email', u == null ? '—' : (verified ? 'Đã xác minh' : 'Chưa xác minh'), color: verified ? Jp.success : Jp.danger),
          _info('Ngày tạo tài khoản', _date(created)),
          _info('Trạng thái tài khoản', statusLabel),
        ]),
      if (page == 'security')
        _section('Bảo mật & truy cập', 'Mọi thứ quan trọng đều được kiểm soát', [
          _info('Địa chỉ email', email.isEmpty ? '—' : email),
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mật khẩu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Jp.text)),
              Text('Dùng mật khẩu hiện tại để đặt mật khẩu mới', style: TextStyle(fontSize: 11, color: Jp.muted)),
            ])),
            OutlineButton2('Đổi mật khẩu', _changePassword, height: 32),
          ])),
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Phiên thuê', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Jp.text)),
              Text('Quản lý các máy J2ME đang hoạt động', style: TextStyle(fontSize: 11, color: Jp.muted)),
            ])),
            OutlineButton2('Quản lý ›', widget.onOpenRentals, height: 32),
          ])),
        ]),
      if (page == 'tx')
        _section('Lịch sử giao dịch', '30 giao dịch gần nhất của ví', [
          if (txs.isEmpty) Text('Chưa có giao dịch.', style: TextStyle(fontSize: 13, color: Jp.muted)),
          for (var i = 0; i < txs.length; i++) ...[
            if (i > 0) Divider(height: 1, color: Jp.line),
            _txRow(txs[i]),
          ],
        ]),
      if (page == 'contact') ..._contactRows(),
    ];
    return ListView(padding: const EdgeInsets.only(bottom: 20), children: children);
  }

  Widget _stat(String l, String v, double size) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11)),
        Text(v, style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w900)),
      ]);

  Widget _txRow(Map<String, dynamic> t) {
    final amt = _n(t['amount']);
    final note = '${t['note'] ?? ''}'.isEmpty ? _txLabel('${t['type'] ?? ''}') : '${t['note']}';
    final order = '${t['orderId'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Jp.text)),
          Text(_dateTime(_n(t['createdAt'])) + (order.isEmpty ? '' : ' · $order'), style: TextStyle(fontSize: 11, color: Jp.muted)),
        ])),
        const SizedBox(width: 8),
        Text('${amt > 0 ? '+' : ''}${money(amt)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: amt >= 0 ? Jp.success : Jp.danger)),
      ]),
    );
  }

  List<Widget> _contactRows() {
    if (contactFailed) {
      return [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Không tải được thông tin liên hệ.', style: TextStyle(fontSize: 13, color: Jp.muted))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Align(alignment: Alignment.centerLeft, child: OutlineButton2('Mở trang liên hệ trên web', () => _open('${Api.instance.base}/contact')))),
      ];
    }
    final c = contact;
    if (c == null) return [const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: Jp.primary)))];
    String s(String k) => '${c[k] ?? ''}'.trim();
    final zaloPhone = s('zalo_phone');
    final zaloUrl = s('zalo_url').isNotEmpty ? s('zalo_url') : (zaloPhone.isNotEmpty ? 'https://zalo.me/${zaloPhone.replaceAll(RegExp(r'\D'), '')}' : '');
    final hotline = s('hotline');
    final rows = <(String, String, IconData, String, Color?)>[
      (s('facebook_label').isEmpty ? 'Facebook J2ME Play' : s('facebook_label'), 'Nhắn tin fanpage', Icons.facebook, s('facebook_url'), const Color(0xFF1877F2)),
      (s('zalo_label').isEmpty ? 'Zalo hỗ trợ' : s('zalo_label'), zaloPhone.isEmpty ? 'Chat Zalo với hỗ trợ viên' : zaloPhone, Icons.chat_bubble, zaloUrl, const Color(0xFF0068FF)),
      ('Nhóm Zalo cộng đồng', 'Tham gia box Zalo J2ME Play', Icons.groups, s('box_zalo_url'), const Color(0xFF0068FF)),
      ('Hotline', hotline.isEmpty ? 'Chưa cập nhật' : hotline, Icons.phone, hotline.isEmpty ? '' : 'tel:${hotline.replaceAll(RegExp(r'[^0-9+]'), '')}', null),
      ('Trang chủ', Api.instance.base.replaceFirst(RegExp(r'^https?://'), ''), Icons.home_outlined, Api.instance.base, null),
    ];
    return [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: r.$4.isEmpty ? null : () => _open(r.$4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Jp.line)),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: r.$5 ?? Jp.primarySoft, borderRadius: BorderRadius.circular(10)), child: Icon(r.$3, size: 22, color: r.$5 != null ? Colors.white : Jp.primary)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Jp.text)),
                  Text(r.$4.isEmpty && r.$2.isEmpty ? 'Chưa cập nhật' : r.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Jp.muted)),
                ])),
                if (r.$4.isNotEmpty) Text('›', style: TextStyle(fontSize: 20, color: Jp.muted)),
              ]),
            ),
          ),
        ),
    ];
  }
}
