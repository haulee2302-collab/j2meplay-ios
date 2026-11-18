import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../theme.dart';
import 'rentals.dart';
import 'jars.dart';
import 'profile.dart';

/// Khung chính: thanh menu dưới 4 mục (Phiên thuê, Kho JAR, Nạp tiền, Tài khoản) như bản Android.
/// Mục "Giả lập" (chạy JAR trên máy) không có trên iOS vì iOS không cho chạy máy ảo Java.
class MainShell extends StatefulWidget {
  final VoidCallback onLogout;
  const MainShell({super.key, required this.onLogout});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      RentalsScreen(onLogout: widget.onLogout),
      const JarsScreen(),
      ProfileScreen(onLogout: widget.onLogout, onOpenRentals: () => setState(() => tab = 0)),
    ];
    final index = tab == 3 ? 2 : tab; // tab 3 = Tài khoản, ánh xạ về trang 2
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(() => tab = 0); },
      child: Scaffold(
        backgroundColor: Jp.bgFaint,
        body: IndexedStack(index: index, children: pages),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(color: Jp.surface, border: Border(top: BorderSide(color: Jp.line))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Row(children: [
                _item('Phiên thuê', Icons.dns_outlined, 0),
                _item('Kho JAR', Icons.folder_zip_outlined, 1),
                _deposit(),
                _item('Tài khoản', Icons.person_outline, 3),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(String label, IconData icon, int i) {
    final on = tab == i;
    return Expanded(
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () => setState(() => tab = i),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: on ? Jp.primary : Jp.muted),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Jp.primary : Jp.muted)),
        ]),
      ),
    );
  }

  Widget _deposit() {
    return Expanded(
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        // Nạp tiền qua chuyển khoản ngân hàng trên website (trang nạp của tài khoản đang đăng nhập).
        onTap: () => launchUrl(Uri.parse('${Api.instance.base}/deposit'), mode: LaunchMode.externalApplication),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 36, height: 36, decoration: const BoxDecoration(color: Jp.primary, shape: BoxShape.circle), child: const Icon(Icons.attach_money, color: Colors.white, size: 20)),
          const Text('Nạp tiền', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Jp.primary)),
        ]),
      ),
    );
  }
}
