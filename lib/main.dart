import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'emu/keepalive.dart';
import 'screens/login.dart';
import 'screens/shell.dart';
import 'screens/floating.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.instance.load();
  await Jp.load();
  KeepAlive.init();
  runApp(const J2mePlayApp());
}

class J2mePlayApp extends StatefulWidget {
  const J2mePlayApp({super.key});
  @override
  State<J2mePlayApp> createState() => _J2mePlayAppState();
}

class _J2mePlayAppState extends State<J2mePlayApp> {
  bool loggedIn = Api.instance.loggedIn;

  void _set(bool v) => setState(() => loggedIn = v);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Jp.darkNotifier,
      builder: (context, dark, _) => MaterialApp(
        title: 'J2ME Play',
        debugShowCheckedModeBanner: false,
        theme: Jp.themeData(),
        navigatorKey: navKey,
        builder: (context, child) => FloatingHost(child: child ?? const SizedBox()),
        home: loggedIn ? MainShell(onLogout: () => _set(false)) : LoginScreen(onLoggedIn: () => _set(true)),
      ),
    );
  }
}
