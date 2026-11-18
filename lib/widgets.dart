import 'package:flutter/material.dart';
import 'theme.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool loading;
  final IconData? icon;
  final double height;
  final double fontSize;
  final Color? container;
  final Color? content;
  const PrimaryButton(this.text, this.onTap, {super.key, this.loading = false, this.icon, this.height = 46, this.fontSize = 15, this.container, this.content});

  @override
  Widget build(BuildContext context) {
    final fg = content ?? Colors.white;
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: container ?? Jp.primary,
          foregroundColor: fg,
          disabledBackgroundColor: (container ?? Jp.primary).withOpacity(0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: loading
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
                Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
              ]),
      ),
    );
  }
}

class OutlineButton2 extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final Color? color;
  const OutlineButton2(this.text, this.onTap, {super.key, this.icon, this.height = 38, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Jp.primary;
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: color ?? Jp.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 5)],
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final bool small;
  final bool white;
  const StatusPill(this.text, this.color, {super.key, this.small = true, this.white = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(color: white ? Colors.white : color.withOpacity(0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: small ? 5 : 7, height: small ? 5 : 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: small ? 4 : 6),
        Text(text, style: TextStyle(color: color, fontSize: small ? 10 : 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Đầu trang nền tím chuyển màu, bo góc dưới (giống HeroHeader của bản Android).
class HeroHeader extends StatelessWidget {
  final Widget child;
  const HeroHeader({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: Jp.heroBrush, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28))),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: Stack(children: [
          Positioned(top: -50, right: -70, child: Container(width: 200, height: 200, decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), shape: BoxShape.circle))),
          SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 12, 20), child: child)),
        ]),
      ),
    );
  }
}

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: Jp.toggle,
      icon: Icon(Jp.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: Colors.white),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final int? count;
  const SectionTitle(this.text, {super.key, this.count});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Jp.text)),
      if (count != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(99)),
          child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Jp.primary)),
        ),
      ],
    ]);
  }
}

BoxDecoration cardDeco({double radius = 10}) => BoxDecoration(
      color: Jp.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Jp.line),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 3, offset: const Offset(0, 1))],
    );

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? Jp.danger : const Color(0xFF14365D),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
}

Future<bool> confirmDialog(BuildContext context, String title, String body, {String ok = 'Đồng ý', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Jp.surface,
      title: Text(title, style: TextStyle(color: Jp.text, fontWeight: FontWeight.w700, fontSize: 18)),
      content: Text(body, style: TextStyle(color: Jp.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Hủy', style: TextStyle(color: Jp.muted))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok, style: TextStyle(color: danger ? Jp.danger : Jp.primary, fontWeight: FontWeight.w600))),
      ],
    ),
  );
  return r == true;
}
