import 'package:flutter/material.dart';
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

class _ProfileScreenState extends State<ProfileScreen> {
  User? user = Api.instance.user;

  @override
  void initState() {
    super.initState();
    Api.instance.me().then((u) { if (mounted) setState(() => user = u); }).catchError((_) {});
  }

  Future<void> logout() async {
    if (!await confirmDialog(context, 'Đăng xuất?', 'Bạn sẽ cần đăng nhập lại để dùng app.', ok: 'Đăng xuất', danger: true)) return;
    await Api.instance.logout();
    widget.onLogout();
  }

  Future<void> changePassword() async {
    final oldC = TextEditingController(), newC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Jp.surface,
        title: Text('Đổi mật khẩu', style: TextStyle(color: Jp.text, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: oldC, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại')),
          TextField(controller: newC, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu mới')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Hủy', style: TextStyle(color: Jp.muted))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Đổi', style: TextStyle(color: Jp.primary, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    final (code, json, _) = await _post('/api/site/change-password', {'currentPassword': oldC.text, 'newPassword': newC.text, 'passwordConfirmation': newC.text});
    if (!mounted) return;
    if (code >= 200 && code < 300) {
      toast(context, 'Đã đổi mật khẩu');
    } else {
      toast(context, '${json?['error'] ?? 'Đổi mật khẩu thất bại (mã $code)'}', error: true);
    }
  }

  Future<(int, Map<String, dynamic>?, dynamic)> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = await Api.instance.rawPost(path, body);
      return r;
    } catch (e) {
      return (0, <String, dynamic>{'error': '$e'}, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: EdgeInsets.zero, children: [
      HeroHeader(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.person, color: Colors.white, size: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user?.name.isNotEmpty == true ? user!.name : 'Tài khoản', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              Text(user?.email ?? '', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
            ])),
            const ThemeToggle(),
          ]),
          const SizedBox(height: 14),
          Text('Số dư', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          Text(money(user?.balance ?? 0), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 14),
      _row(Icons.dns_outlined, 'Phiên thuê của tôi', widget.onOpenRentals),
      _row(Icons.lock_outline, 'Đổi mật khẩu', changePassword),
      _row(Icons.logout, 'Đăng xuất', logout, danger: true),
      const SizedBox(height: 20),
      Center(child: Text('J2ME Play iOS · 1.0.1', style: TextStyle(fontSize: 12, color: Jp.muted))),
      const SizedBox(height: 28),
    ]);
  }

  Widget _row(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: cardDeco(),
        child: ListTile(
          leading: Icon(icon, color: danger ? Jp.danger : Jp.primary),
          title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? Jp.danger : Jp.text)),
          trailing: Icon(Icons.chevron_right, color: Jp.muted),
          onTap: onTap,
        ),
      );
}
