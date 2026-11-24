import 'package:flutter/material.dart';
import 'api.dart';
import 'pages/auth_page.dart';
import 'pages/workspaces_page.dart';
import 'pages/shell.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  Api.onSignedOut = () {
    navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
  };
  runApp(const GlobApp());
}

class GlobApp extends StatelessWidget {
  const GlobApp({super.key});

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (Api.token == null) {
      home = const AuthPage();
    } else if (Api.teamId == null) {
      home = const WorkspacesPage();
    } else {
      home = const Shell();
    }
    return MaterialApp(
      title: 'Glob',
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F46E5),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F46E5),
        brightness: Brightness.dark,
      ),
      home: home,
    );
  }
}
