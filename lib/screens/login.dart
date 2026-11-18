import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool busy = false, hide = true;
  String? error;

  Future<void> submit() async {
    if (email.text.trim().isEmpty || pass.text.isEmpty) {
      setState(() => error = 'Nhập email và mật khẩu');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await Api.instance.login(email.text.trim(), pass.text);
      if (mounted) widget.onLoggedIn();
    } catch (e) {
      if (mounted) setState(() { busy = false; error = e.toString(); });
    }
  }

  InputDecoration deco(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Jp.muted),
        suffixIcon: suffix,
        filled: true,
        fillColor: Jp.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Jp.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Jp.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Jp.primary, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Jp.bgFaint,
      body: SingleChildScrollView(
        child: Column(children: [
          HeroHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.end, children: const [ThemeToggle()]),
              const SizedBox(height: 18),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.sports_esports, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 14),
              const Text('J2ME Play', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Thuê phiên J2ME, chơi game Java ngay trên điện thoại.', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
              const SizedBox(height: 14),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Đăng nhập', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Jp.text)),
              const SizedBox(height: 16),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, autocorrect: false, textInputAction: TextInputAction.next, decoration: deco('Email', Icons.mail_outline)),
              const SizedBox(height: 12),
              TextField(
                controller: pass,
                obscureText: hide,
                onSubmitted: (_) => submit(),
                decoration: deco('Mật khẩu', Icons.lock_outline, suffix: IconButton(icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20), onPressed: () => setState(() => hide = !hide))),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Jp.danger, fontSize: 13))),
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: PrimaryButton('Đăng nhập', submit, loading: busy)),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse('${Api.instance.base}/register'), mode: LaunchMode.externalApplication),
                  child: const Text('Chưa có tài khoản? Đăng ký trên website', style: TextStyle(color: Jp.primary, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
