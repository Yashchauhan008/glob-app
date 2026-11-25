import 'package:flutter/material.dart';
import 'api.dart';
import 'chat_service.dart';
import 'notify.dart';
import 'push.dart';
import 'widget_sync.dart';
import 'package:home_widget/home_widget.dart';
import 'nav.dart';
import 'theme.dart';
import 'pages/auth_page.dart';
import 'pages/workspaces_page.dart';
import 'pages/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  await ThemeController.load();
  await Push.bootstrap();
  try {
    await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  } catch (_) {}
  try {
    await Notify.I.init();
  } catch (_) {}
  Api.onSignedOut = () {
    WidgetSync.clear();
    ChatService.I.disconnect();
    navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
  };
  runApp(const GlobApp());
  Notify.I.launchIntent();
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (_, mode, __) => MaterialApp(
        title: 'Glob',
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(false),
        darkTheme: buildTheme(true),
        themeMode: mode,
        themeAnimationDuration: const Duration(milliseconds: 350),
        themeAnimationCurve: Curves.easeInOut,
        home: home,
      ),
    );
  }
}
