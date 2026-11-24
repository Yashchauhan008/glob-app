import 'package:flutter/material.dart';
import '../api.dart';
import '../call.dart';
import 'auth_page.dart';
import 'workspaces_page.dart';
import 'home_tab.dart';
import 'ideas_tab.dart';
import 'tasks_tab.dart';
import 'leads_tab.dart';
import 'products_tab.dart';
import 'calendar_tab.dart';
import 'map_tab.dart';
import 'qa_tab.dart';
import 'call_tab.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _Dest {
  final String title;
  final IconData icon;
  final Widget Function() build;
  const _Dest(this.title, this.icon, this.build);
}

class _ShellState extends State<Shell> {
  int _i = 0;
  final _scaffold = GlobalKey<ScaffoldState>();
  final call = CallService.I;

  static final List<_Dest> _all = [
    _Dest('Home', Icons.dashboard_outlined, () => const HomeTab()),
    _Dest('Ideas', Icons.lightbulb_outline, () => const IdeasTab()),
    _Dest('Tasks', Icons.check_circle_outline, () => const TasksTab()),
    _Dest('Leads', Icons.people_outline, () => const LeadsTab()),
    _Dest('Products', Icons.inventory_2_outlined, () => const ProductsTab()),
    _Dest('Calendar', Icons.event, () => const CalendarTab()),
    _Dest('Map', Icons.map_outlined, () => const MapTab()),
    _Dest('Q&A', Icons.help_outline, () => const QaTab()),
    _Dest('Call', Icons.headset_mic_outlined, () => const CallTab()),
  ];

  @override
  void initState() {
    super.initState();
    call.addListener(_r);
  }

  @override
  void dispose() {
    call.removeListener(_r);
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final d = _all[_i];
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Text(d.title),
        actions: [
          if (call.connected)
            IconButton(
                tooltip: 'In call',
                icon: const Icon(Icons.headset_mic, color: Colors.green),
                onPressed: () => setState(() => _i = 8)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final nav = Navigator.of(context);
              await call.leave();
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
      drawer: Drawer(
        child: SafeArea(
          child: ListView(children: [
            const ListTile(title: Text('Glob', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            for (var k = 0; k < _all.length; k++)
              ListTile(
                leading: Icon(_all[k].icon),
                title: Text(_all[k].title),
                selected: k == _i,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _i = k);
                },
              ),
          ]),
        ),
      ),
      body: d.build(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i < 4 ? _i : 4,
        onDestinationSelected: (i) {
          if (i == 4) {
            _scaffold.currentState?.openDrawer();
          } else {
            setState(() => _i = i);
          }
        },
        destinations: [
          for (var k = 0; k < 4; k++)
            NavigationDestination(icon: Icon(_all[k].icon), label: _all[k].title),
          const NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    );
  }
}
