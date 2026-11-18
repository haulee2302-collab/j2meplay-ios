import 'package:flutter/material.dart';
import '../icons.dart';

import '../theme.dart';
import '../widgets.dart';

/// Tab "Giả lập": bố cục giống Android (header, nút Kho JAR / Tạo giả lập, danh sách). iOS không cho chạy máy ảo Java
/// trong ứng dụng nên danh sách luôn trống và có thẻ giải thích, chuyển sang Phiên thuê / Kho JAR.
class EmulatorScreen extends StatelessWidget {
  final VoidCallback onOpenRentals, onOpenJars;
  const EmulatorScreen({super.key, required this.onOpenRentals, required this.onOpenJars});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: EdgeInsets.zero, children: [
      HeroHeader(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const JpIcon(JpIcons.gamepad, size: 22, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Chạy trên máy', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
              const Text('Giả lập J2ME', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ])),
            const ThemeToggle(),
          ]),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Giả lập', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                const Text('0', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                const Text('0 đang chạy', style: TextStyle(color: Jp.highlight, fontSize: 13, fontWeight: FontWeight.w600)),
              ])),
              OutlineButton2('Kho JAR', onOpenJars, icon: JpIcons.toolJar, height: 44, color: Colors.white),
              const SizedBox(width: 8),
              PrimaryButton('Tạo giả lập', () => toast(context, 'iPhone chưa chạy được giả lập trên máy. Hãy dùng Phiên thuê.', error: true), icon: JpIcons.add, container: Colors.white, content: Jp.primary, height: 44, fontSize: 14),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Row(children: [
          Text('Giả lập trên máy của bạn', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Jp.text)),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(99)), child: const Text('0', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Jp.primaryDark))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(children: [
          Expanded(child: OutlineButton2('Xem đã chọn (0)', null, height: 36)),
          const SizedBox(width: 10),
          Expanded(child: PrimaryButton('Xem tất cả (0)', null, icon: JpIcons.toolExpand, height: 36, fontSize: 13)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Container(
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
      ),
    ]);
  }
}
