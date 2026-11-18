import 'package:flutter/material.dart';
import '../icons.dart';

import '../theme.dart';
import '../widgets.dart';

/// Tab "Giả lập": trên Android đây là nơi chạy JAR ngay trên máy. iOS không cho chạy máy ảo Java trong ứng dụng,
/// nên trang này chỉ giải thích và chuyển người dùng sang Phiên thuê / Kho JAR (chạy trên máy chủ, xem qua mạng).
class EmulatorScreen extends StatelessWidget {
  final VoidCallback onOpenRentals, onOpenJars;
  const EmulatorScreen({super.key, required this.onOpenRentals, required this.onOpenJars});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GIẢ LẬP', style: TextStyle(color: Jp.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            Text('Giả lập trên máy của bạn', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Jp.text)),
          ]),
        ),
      ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(radius: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(10)), child: const JpIcon(JpIcons.gamepad, color: Jp.primary)),
            const SizedBox(width: 12),
            Expanded(child: Text('Chạy JAR trực tiếp chưa hỗ trợ trên iPhone', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.text))),
          ]),
          const SizedBox(height: 10),
          Text('iOS không cho ứng dụng chạy máy ảo Java nên không thể giả lập JAR ngay trên điện thoại như bản Android. '
              'Bạn vẫn chơi được đầy đủ bằng cách thuê máy J2ME: game chạy trên máy chủ, iPhone chỉ hiển thị hình và gửi phím / cảm ứng.',
              style: TextStyle(fontSize: 13, color: Jp.muted, height: 1.4)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: PrimaryButton('Phiên thuê', onOpenRentals, height: 40, fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: OutlineButton2('Kho JAR', onOpenJars, height: 40)),
          ]),
        ]),
      ),
    ]);
  }
}
