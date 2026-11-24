import 'package:flutter/material.dart';
import '../api.dart';
import 'auth_page.dart';
import 'workspaces_page.dart';
import 'home_tab.dart';
import 'ideas_tab.dart';
import 'tasks_tab.dart';
import 'leads_tab.dart';
import 'products_tab.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;
  static const _titles = ['Home', 'Ideas', 'Tasks', 'Leads', 'Products'];

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const HomeTab(),
      const IdeasTab(),
      const TasksTab(),
      const LeadsTab(),
      const ProductsTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_i]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final nav = Navigator.of(context);
              if (v == 'switch') {
                await Api.setTeam(null);
                nav.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const WorkspacesPage()), (_) => false);
              } else {
                await Api.signOut();
                nav.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text('${Api.user?['name'] ?? ''}')),
              const PopupMenuItem(value: 'switch', child: Text('Switch workspace')),
              const PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          )
        ],
      ),
      body: IndexedStack(index: _i, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.lightbulb_outline), label: 'Ideas'),
          NavigationDestination(icon: Icon(Icons.check_circle_outline), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Leads'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Products'),
        ],
      ),
    );
  }
}
