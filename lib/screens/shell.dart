import 'package:flutter/material.dart';
import '../icons.dart';
import '../theme.dart';
import 'deposit.dart';
import 'emulator.dart';
import 'jars.dart';
import 'profile.dart';
import 'rentals.dart';

/// Khung chính: thanh menu dưới 5 mục (Phiên thuê, Kho JAR, Nạp tiền, Giả lập, Tài khoản) như bản Android.
class MainShell extends StatefulWidget {
  final VoidCallback onLogout;
  const MainShell({super.key, required this.onLogout});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0; // 0 Phiên thuê, 1 Kho JAR, 3 Giả lập, 2 Tài khoản
  int reload = 0;

  Future<void> _deposit() async {
    final paid = await showDeposit(context);
    if (paid && mounted) setState(() => reload++);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <int, Widget>{
      0: RentalsScreen(key: ValueKey('r$reload'), onLogout: widget.onLogout),
      1: const JarsScreen(),
      2: ProfileScreen(key: ValueKey('p$reload'), onLogout: widget.onLogout, onOpenRentals: () => setState(() => tab = 0)),
      3: EmulatorScreen(onOpenRentals: () => setState(() => tab = 0), onOpenJars: () => setState(() => tab = 1)),
    };
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(() => tab = 0); },
      child: Scaffold(
        backgroundColor: Jp.bgFaint,
        body: IndexedStack(index: tab, children: [pages[0]!, pages[1]!, pages[2]!, pages[3]!]),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(color: Jp.surface, border: Border(top: BorderSide(color: Jp.line))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Row(children: [
                _item('Phiên thuê', JpIcons.navRentals, 0),
                _item('Kho JAR', JpIcons.toolJar, 1),
                _depositItem(),
                _item('Giả lập', JpIcons.gamepad, 3),
                _item('Tài khoản', JpIcons.navUser, 2),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(String label, JpIconData icon, int i) {
    final on = tab == i;
    return Expanded(
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () => setState(() => tab = i),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          JpIcon(icon, size: 22, color: on ? Jp.primary : Jp.muted),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Jp.primary : Jp.muted)),
        ]),
      ),
    );
  }

  Widget _depositItem() {
    return Expanded(
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: _deposit,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 36, height: 36, decoration: const BoxDecoration(color: Jp.primary, shape: BoxShape.circle), child: const JpIcon(JpIcons.navDollar, color: Colors.white, size: 20)),
          const Text('Nạp tiền', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Jp.primary)),
        ]),
      ),
    );
  }
}
