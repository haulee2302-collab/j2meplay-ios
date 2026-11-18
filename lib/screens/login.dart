import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
const appVersion = '1.0.0';

/// Khung chung đăng nhập / đăng ký: phần tím gọn (logo) + thẻ trắng nổi lên.
class AuthScaffold extends StatelessWidget {
  final List<Widget> children;
  final Widget footer;
  const AuthScaffold({super.key, required this.children, required this.footer});
  @override
  Widget build(BuildContext context) {
    final host = Uri.parse(Api.instance.base).host.replaceFirst('www.', '');
    return Scaffold(
      backgroundColor: Jp.bgFaint,
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(children: [
          Container(
            width: double.infinity,
            height: 190 + MediaQuery.of(context).padding.top * 0,
            decoration: BoxDecoration(gradient: Jp.heroBrush),
            child: ClipRect(
              child: Stack(children: [
                Positioned(left: -60, top: -70, child: Container(width: 200, height: 200, decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), shape: BoxShape.circle))),
                Positioned.fill(child: SafeArea(
                  bottom: false,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    const SizedBox(height: 10),
                    Image.asset('assets/jp_logo.png', width: 140, fit: BoxFit.fitWidth),
                    const SizedBox(height: 2),
                    Text('Chơi game Java mọi lúc, mọi nơi', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
                  ]),
                )),
              ]),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -28),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: cardDeco(radius: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
          Transform.translate(offset: const Offset(0, -16), child: Column(children: [
            footer,
            Padding(padding: const EdgeInsets.only(top: 4, bottom: 16), child: Text('v$appVersion - $host', style: TextStyle(color: Jp.muted.withOpacity(0.8), fontSize: 12))),
          ])),
        ]),
      ),
    );
  }
}

/// Ô xác minh Turnstile: chỉ hiện khi máy chủ yêu cầu. Mở /app-turnstile.php; trang gọi JarplayApp.postMessage(token).
Future<void> showTurnstile(BuildContext context, void Function(String) onToken) async {
  String? err;
  var done = false, loaded = false;
  final ctrl = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white);
  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      ctrl.addJavaScriptChannel('JarplayApp', onMessageReceived: (m) {
        final v = m.message;
        if (v.startsWith('error:')) {
          set(() => err = v.substring(6));
        } else if (!done) {
          done = true;
          Navigator.pop(c);
          onToken(v);
        }
      });
      // Tương thích trang gọi JarplayApp.onToken(...) / onError(...) như bản Android.
      ctrl.setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        ctrl.runJavaScript('window.JarplayApp = {postMessage: window.JarplayApp.postMessage, onToken: function(t){JarplayApp.postMessage(t)}, onError: function(m){JarplayApp.postMessage("error:"+m)}};');
      }));
      if (!loaded) { loaded = true; ctrl.loadRequest(Uri.parse('${Api.instance.base}/app-turnstile.php')); }
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Xác minh bạn không phải robot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Jp.text)),
            Padding(padding: const EdgeInsets.only(top: 4, bottom: 10), child: Text('Cần thêm một bước vì có nhiều lần thử từ mạng này.', style: TextStyle(fontSize: 12, color: Jp.muted))),
            SizedBox(height: 90, child: WebViewWidget(controller: ctrl)),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: Jp.danger, fontSize: 13))),
            TextButton(onPressed: () => Navigator.pop(c), child: Text('Hủy', style: TextStyle(color: Jp.muted))),
          ]),
        ),
      );
    }),
  );
}

/// Đăng nhập Google: lấy Client ID web từ máy chủ → chọn tài khoản → gửi ID token.
Future<void> googleFlow(BuildContext context, {required void Function(String?) onError, required VoidCallback onDone, required void Function(bool) busy}) async {
  busy(true);
  onError(null);
  try {
    final webId = await Api.instance.googleClientId();
    if (webId.isEmpty) { onError('Đăng nhập Google chưa được bật trên hệ thống'); return; }
    if (_googleIosClientId.isEmpty) { onError('Bản iOS này chưa được cấu hình Google (thiếu iOS Client ID)'); return; }
    final gs = GoogleSignIn(clientId: _googleIosClientId, serverClientId: webId, scopes: const ['email', 'profile']);
    await gs.signOut();
    final acc = await gs.signIn();
    if (acc == null) return;
    final tok = (await acc.authentication).idToken;
    if (tok == null || tok.isEmpty) { onError('Không lấy được mã xác thực từ Google'); return; }
    Future<void> send(String cap) async {
      try {
        await Api.instance.loginGoogle(tok, cap);
        onDone();
      } on CaptchaRequired {
        if (context.mounted) await showTurnstile(context, (t) => send(t));
      } catch (e) {
        onError(e.toString());
      }
    }
    await send('');
  } catch (e) {
    onError(e.toString());
  } finally {
    busy(false);
  }
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(text: Api.instance.lastEmail);
  final pass = TextEditingController();
  bool busy = false, gbusy = false, needVerify = false;
  String? error, notice;

  Future<void> submit([String token = '']) async {
    if (email.text.trim().isEmpty || pass.text.isEmpty) {
      setState(() => error = 'Vui lòng nhập đầy đủ email và mật khẩu');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { busy = true; error = null; notice = null; });
    try {
      await Api.instance.login(email.text.trim(), pass.text, token);
      await Api.instance.saveEmail(email.text.trim());
      if (mounted) widget.onLoggedIn();
      return;
    } on CaptchaRequired {
      if (mounted) await showTurnstile(context, (t) => submit(t));
    } catch (e) {
      final m = e is ApiError ? e.message : e.toString();
      if (mounted) setState(() { error = m; needVerify = m.contains('xác minh') && m.contains('chưa'); });
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> resend() async {
    try {
      final m = await Api.instance.resendVerification(email.text.trim());
      setState(() { notice = m.isEmpty ? 'Đã gửi lại email xác minh. Hãy kiểm tra hộp thư.' : m; error = null; needVerify = false; });
    } catch (e) {
      setState(() => error = e is ApiError ? e.message : e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      footer: _Switch('Chưa có tài khoản?', 'Đăng ký ngay', () => Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(onLoggedIn: widget.onLoggedIn)))),
      children: [
        Text('Đăng nhập', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Jp.text)),
        Padding(padding: const EdgeInsets.only(top: 2, bottom: 16), child: Text('Dùng tài khoản J2ME Play của bạn', style: TextStyle(fontSize: 13, color: Jp.muted))),
        if (error != null) MessageBanner(error!),
        if (notice != null) MessageBanner(notice!, error: false),
        if (needVerify) TextButton(onPressed: resend, child: const Text('Gửi lại email xác minh', style: TextStyle(color: Jp.primary, fontWeight: FontWeight.w600))),
        JpField('Email', email, Icons.mail_outline, placeholder: 'ten@example.com', keyboard: TextInputType.emailAddress),
        const SizedBox(height: 12),
        JpField('Mật khẩu', pass, Icons.lock_outline, placeholder: 'Nhập mật khẩu', password: true, action: TextInputAction.done, onSubmit: submit),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: PrimaryButton('Đăng nhập', () => submit(), loading: busy, height: 50)),
        const OrDivider(),
        GoogleButton('Tiếp tục với Google', busy ? null : () => googleFlow(context, onError: (e) => setState(() => error = e), onDone: widget.onLoggedIn, busy: (b) => setState(() => gbusy = b)), loading: gbusy),
      ],
    );
  }
}

class _Switch extends StatelessWidget {
  final String prefix, action;
  final VoidCallback onTap;
  const _Switch(this.prefix, this.action, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$prefix ', style: TextStyle(color: Jp.muted, fontSize: 14)),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Text(action, style: const TextStyle(color: Jp.primary, fontSize: 14, fontWeight: FontWeight.w600))),
          ),
        ]),
      );
}

class RegisterScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const RegisterScreen({super.key, required this.onLoggedIn});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final email = TextEditingController(), pass = TextEditingController(), confirm = TextEditingController();
  bool accepted = false, busy = false, gbusy = false;
  String? error, sentTo, resendMsg;

  void back() => Navigator.of(context).popUntil((r) => r.isFirst);

  Future<void> submit([String token = '']) async {
    final e = email.text.trim();
    final err = e.isEmpty || !e.contains('@')
        ? 'Email không hợp lệ'
        : pass.text.length < 8
            ? 'Mật khẩu phải từ 8 ký tự'
            : pass.text != confirm.text
                ? 'Mật khẩu nhập lại chưa khớp'
                : !accepted
                    ? 'Bạn cần đồng ý với Điều khoản sử dụng và Chính sách bảo mật'
                    : null;
    setState(() => error = err);
    if (err != null) return;
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      await Api.instance.register(e, pass.text, confirm.text, token);
      await Api.instance.saveEmail(e);
      if (mounted) setState(() => sentTo = e);
    } on CaptchaRequired {
      if (mounted) await showTurnstile(context, (t) => submit(t));
    } catch (x) {
      if (mounted) setState(() => error = x is ApiError ? x.message : x.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  void open(String p) => launchUrl(Uri.parse('${Api.instance.base}/$p'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final to = sentTo;
    return AuthScaffold(
      footer: _Switch('Đã có tài khoản?', 'Đăng nhập', back),
      children: to != null
          ? [
              Center(child: Column(children: [
                Container(width: 60, height: 60, decoration: BoxDecoration(color: Jp.primarySoft, shape: BoxShape.circle), child: const Icon(Icons.mail_outline, color: Jp.primary, size: 30)),
                Padding(padding: const EdgeInsets.only(top: 14), child: Text('Kiểm tra email của bạn', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Jp.text))),
                Padding(padding: const EdgeInsets.only(top: 6, bottom: 16), child: Text('Đã gửi liên kết xác minh đến $to. Bấm vào liên kết trong thư rồi quay lại đăng nhập.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Jp.muted))),
                if (resendMsg != null) MessageBanner(resendMsg!, error: false),
                SizedBox(width: double.infinity, child: PrimaryButton('Đến trang đăng nhập', back, height: 48)),
                TextButton(
                  onPressed: () async {
                    try {
                      final m = await Api.instance.resendVerification(to);
                      setState(() => resendMsg = m.isEmpty ? 'Đã gửi lại email xác minh.' : m);
                    } catch (x) {
                      setState(() => resendMsg = x is ApiError ? x.message : x.toString());
                    }
                  },
                  child: const Text('Gửi lại email xác minh', style: TextStyle(color: Jp.primary)),
                ),
              ])),
            ]
          : [
              Text('Tạo tài khoản', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Jp.text)),
              Padding(padding: const EdgeInsets.only(top: 2, bottom: 14), child: Text('Miễn phí, chỉ cần email hoặc tài khoản Google', style: TextStyle(fontSize: 13, color: Jp.muted))),
              if (error != null) MessageBanner(error!),
              GoogleButton('Đăng ký với Google', busy ? null : () => googleFlow(context, onError: (e) => setState(() => error = e), onDone: () { back(); widget.onLoggedIn(); }, busy: (b) => setState(() => gbusy = b)), loading: gbusy),
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('Đăng ký bằng Google là bạn đồng ý với Điều khoản sử dụng và Chính sách bảo mật.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Jp.muted))),
              const OrDivider(),
              JpField('Email', email, Icons.mail_outline, placeholder: 'ten@example.com', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 10),
              JpField('Mật khẩu', pass, Icons.lock_outline, placeholder: 'Ít nhất 8 ký tự', password: true),
              const SizedBox(height: 10),
              JpField('Nhập lại mật khẩu', confirm, Icons.lock_outline, placeholder: 'Nhập lại mật khẩu', password: true, action: TextInputAction.done, onSubmit: submit),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 32, height: 32, child: Checkbox(value: accepted, activeColor: Jp.primary, side: BorderSide(color: Jp.lineStrong), onChanged: (v) => setState(() => accepted = v ?? false))),
                  const SizedBox(width: 4),
                  Expanded(child: Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(children: [
                    Text('Tôi đồng ý với ', style: TextStyle(fontSize: 13, color: Jp.muted)),
                    GestureDetector(onTap: () => open('terms'), child: const Text('Điều khoản sử dụng', style: TextStyle(fontSize: 13, color: Jp.primary, decoration: TextDecoration.underline))),
                    Text(' và ', style: TextStyle(fontSize: 13, color: Jp.muted)),
                    GestureDetector(onTap: () => open('privacy'), child: const Text('Chính sách bảo mật', style: TextStyle(fontSize: 13, color: Jp.primary, decoration: TextDecoration.underline))),
                  ]))),
                ]),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: PrimaryButton('Đăng ký', () => submit(), loading: busy, height: 50)),
            ],
    );
  }
}
