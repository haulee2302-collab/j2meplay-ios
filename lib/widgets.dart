import 'package:flutter/material.dart';
import 'icons.dart';
import 'theme.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool loading;
  final JpIconData? icon;
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
                if (icon != null) ...[JpIcon(icon, size: 16), const SizedBox(width: 6)],
                Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
              ]),
      ),
    );
  }
}

class OutlineButton2 extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final JpIconData? icon;
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
          if (icon != null) ...[JpIcon(icon, size: 15), const SizedBox(width: 5)],
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
          Padding(padding: EdgeInsets.fromLTRB(20, topInset(context) + 8, 12, 20), child: child),
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
      icon: JpIcon(Jp.dark ? JpIcons.sun : JpIcons.moon, color: Colors.white),
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

/// Ô nhập có nhãn trên, icon trái, nút hiện/ẩn mật khẩu (giống JpField của Android).
class JpField extends StatefulWidget {
  final String label, placeholder;
  final TextEditingController controller;
  final JpIconData icon;
  final bool password;
  final TextInputType keyboard;
  final TextInputAction action;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;
  final int? maxLen;
  const JpField(this.label, this.controller, this.icon,
      {super.key, this.placeholder = '', this.password = false, this.keyboard = TextInputType.text, this.action = TextInputAction.next, this.onSubmit, this.onChanged, this.maxLen});
  @override
  State<JpField> createState() => _JpFieldState();
}

class _JpFieldState extends State<JpField> {
  bool visible = false;
  @override
  Widget build(BuildContext context) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Jp.primaryDark))),
      TextField(
        controller: widget.controller,
        obscureText: widget.password && !visible,
        keyboardType: widget.keyboard,
        textInputAction: widget.action,
        autocorrect: false,
        enableSuggestions: !widget.password,
        onSubmitted: (_) => widget.onSubmit?.call(),
        onChanged: widget.onChanged,
        maxLength: widget.maxLen,
        buildCounter: (c, {required currentLength, required isFocused, maxLength}) => null,
        style: TextStyle(fontSize: 15, color: Jp.text),
        decoration: InputDecoration(
          hintText: widget.placeholder,
          hintStyle: TextStyle(color: Jp.muted, fontSize: 15),
          prefixIcon: JpIcon(widget.icon, size: 20, color: Jp.muted),
          suffixIcon: widget.password
              ? IconButton(icon: JpIcon(visible ? JpIcons.eye : JpIcons.eye, size: 20, color: visible ? Jp.primary : Jp.muted), onPressed: () => setState(() => visible = !visible))
              : null,
          filled: true,
          fillColor: Jp.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: b(Jp.line),
          enabledBorder: b(Jp.line),
          focusedBorder: b(Jp.primary, 1.5),
        ),
      ),
    ]);
  }
}

class MessageBanner extends StatelessWidget {
  final String text;
  final bool error;
  const MessageBanner(this.text, {super.key, this.error = true});
  @override
  Widget build(BuildContext context) {
    final c = error ? Jp.danger : Jp.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.3))),
      child: Text(text, style: TextStyle(color: c, fontSize: 13)),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Expanded(child: Divider(color: Jp.line)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('hoặc', style: TextStyle(color: Jp.muted, fontSize: 12))),
          Expanded(child: Divider(color: Jp.line)),
        ]),
      );
}

class _GLogo extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 24;
    c.scale(k);
    void p(int col, String d) => c.drawPath(_parse(d), Paint()..color = Color(col));
    p(0xFF4285F4, 'M20.5 12.2c0-.7-.1-1.4-.2-2H12v3.7h4.8a4.1 4.1 0 0 1-1.8 2.7v2.3h3c1.8-1.6 2.5-4 2.5-6.7Z');
    p(0xFF34A853, 'M12 21c2.4 0 4.5-.8 6-2.1l-3-2.3c-.8.6-1.9.9-3 .9-2.3 0-4.3-1.6-5-3.7H4v2.4A9 9 0 0 0 12 21Z');
    p(0xFFFBBC05, 'M7 13.8a5.4 5.4 0 0 1 0-3.6V7.8H4a9 9 0 0 0 0 8.4l3-2.4Z');
    p(0xFFEA4335, 'M12 6.5c1.3 0 2.5.5 3.5 1.4L18.1 5A8.7 8.7 0 0 0 4 7.8l3 2.4c.7-2.1 2.7-3.7 5-3.7Z');
  }

  // Bộ phân tích path tối giản cho M/m c/C h/H v/V a/A l/L z (A xấp xỉ bằng đường thẳng).
  Path _parse(String d) {
    final path = Path();
    final t = RegExp(r'[a-zA-Z]|-?\d*\.?\d+').allMatches(d).map((m) => m.group(0)!).toList();
    var i = 0, x = 0.0, y = 0.0;
    String cmd = 'M';
    double n() => double.parse(t[i++]);
    while (i < t.length) {
      if (RegExp(r'[a-zA-Z]').hasMatch(t[i])) cmd = t[i++];
      final rel = cmd == cmd.toLowerCase();
      switch (cmd.toLowerCase()) {
        case 'm': { final a = n(), b = n(); x = rel ? x + a : a; y = rel ? y + b : b; path.moveTo(x, y); cmd = rel ? 'l' : 'L'; break; }
        case 'l': { final a = n(), b = n(); x = rel ? x + a : a; y = rel ? y + b : b; path.lineTo(x, y); break; }
        case 'h': { final a = n(); x = rel ? x + a : a; path.lineTo(x, y); break; }
        case 'v': { final a = n(); y = rel ? y + a : a; path.lineTo(x, y); break; }
        case 'c': {
          final v = List.generate(6, (_) => n());
          final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
          path.cubicTo(ox + v[0], oy + v[1], ox + v[2], oy + v[3], ox + v[4], oy + v[5]);
          x = ox + v[4]; y = oy + v[5];
          break;
        }
        case 'a': {
          final v = List.generate(7, (_) => n());
          final nx = rel ? x + v[5] : v[5], ny = rel ? y + v[6] : v[6];
          path.arcToPoint(Offset(nx, ny), radius: Radius.circular(v[0]), largeArc: v[3] == 1, clockwise: v[4] == 1);
          x = nx; y = ny;
          break;
        }
        case 'z': path.close(); break;
        default: i++;
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_) => false;
}

class GoogleButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool loading;
  const GoogleButton(this.text, this.onTap, {super.key, this.loading = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: loading ? null : onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: Jp.surface,
            foregroundColor: Jp.text,
            side: BorderSide(color: Jp.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Jp.primary))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CustomPaint(size: const Size(20, 20), painter: _GLogo()),
                  const SizedBox(width: 10),
                  Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ]),
        ),
      );
}

/// Đầu trang nền tím: nhãn nhỏ + tiêu đề lớn + mô tả + nút sáng/tối (giống PageHead của Android).
class PageHead extends StatelessWidget {
  final String eyebrow, title, desc;
  final Widget? action;
  const PageHead(this.eyebrow, this.title, this.desc, {super.key, this.action});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(gradient: Jp.heroBrush, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28))),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: Stack(children: [
          Positioned(top: -50, right: -70, child: Container(width: 200, height: 200, decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), shape: BoxShape.circle))),
          Padding(
              padding: EdgeInsets.fromLTRB(20, topInset(context) + 8, 20, 18),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(right: 40), child: Text(eyebrow, style: const TextStyle(color: Jp.highlight, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1))),
                  Padding(padding: const EdgeInsets.only(top: 2, right: 40), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(desc, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12, height: 1.4))),
                ])),
                if (action != null) action!,
              ]),
          ),
          Positioned(top: topInset(context) - 4, right: 4, child: const ThemeToggle()),
        ]),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final String? sub;
  final List<Widget> children;
  const SectionCard(this.title, {super.key, this.sub, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: cardDeco(radius: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.text)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 1), child: Text(sub!, style: TextStyle(fontSize: 12, color: Jp.muted))),
          const SizedBox(height: 10),
          ...children,
        ]),
      );
}
