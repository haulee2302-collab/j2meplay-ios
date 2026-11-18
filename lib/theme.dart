import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chế độ sáng/tối (lưu khóa "dark"), cùng bảng màu với bản Android (JpColors).
class Jp {
  static final ValueNotifier<bool> darkNotifier = ValueNotifier(false);
  static bool get dark => darkNotifier.value;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    darkNotifier.value = p.getBool('dark') ?? false;
  }

  static Future<void> toggle() async {
    darkNotifier.value = !darkNotifier.value;
    final p = await SharedPreferences.getInstance();
    await p.setBool('dark', darkNotifier.value);
  }

  static const primary = Color(0xFF6943FF);
  static const primaryDark = Color(0xFF5634DD);
  static Color get primarySoft => dark ? const Color(0xFF2C2552) : const Color(0xFFEEE9FF);
  static Color get bgFaint => dark ? const Color(0xFF0F0F1A) : const Color(0xFFF6F6FA);
  static Color get surface => dark ? const Color(0xFF1B1B2B) : Colors.white;
  static Color get line => dark ? const Color(0xFF2E2C44) : const Color(0xFFE5DEF7);
  static Color get lineStrong => dark ? const Color(0xFF4A4275) : const Color(0xFFC9BBFF);
  static Color get text => dark ? const Color(0xFFECEAF6) : const Color(0xFF17172F);
  static Color get muted => dark ? const Color(0xFF9E99B3) : const Color(0xFF8F899F);
  static const danger = Color(0xFFDC2626);
  static Color get dangerBg => dark ? const Color(0xFF3A1A1F) : const Color(0xFFFFF1F2);
  static const success = Color(0xFF16805A);
  static const highlight = Color(0xFFDFFC9B);
  static const infoBlue = Color(0xFF1769D9);
  static Color get gameBg => dark ? const Color(0xFF17172F) : const Color(0xFFF6F6FA);

  static LinearGradient get heroBrush => dark
      ? const LinearGradient(colors: [Color(0xFF4A3A9E), Color(0xFF3A2A8C), Color(0xFF261A63)], begin: Alignment.topLeft, end: Alignment.bottomRight)
      : const LinearGradient(colors: [Color(0xFF8163FB), primary, Color(0xFF4A2BD0)], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static ThemeData themeData() => ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: dark ? Brightness.dark : Brightness.light, primary: primary, surface: surface),
        scaffoldBackgroundColor: bgFaint,
        canvasColor: surface,
        dividerColor: line,
        fontFamily: '.SF Pro Text',
      );
}

String money(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b đ';
}

String fmtSize(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(2)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

/// Khoảng trống phía trên cho tai thỏ/camera/thanh trạng thái (tối thiểu 28 để không sát mép).
double topInset(BuildContext c) {
  final t = MediaQuery.of(c).padding.top;
  return t < 28 ? 28 : t;
}
