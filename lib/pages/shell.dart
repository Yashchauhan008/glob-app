import 'package:flutter/material.dart';
import '../api.dart';
import '../call.dart';
import '../theme.dart';
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

  List<_Dest> get _all => [
        _Dest('Home', Icons.home_outlined, () => HomeTab(onGo: (i) => setState(() => _i = i))),
        _Dest('Ideas', Icons.lightbulb_outline, () => const IdeasTab()),
        _Dest('Tasks', Icons.check_circle_outline, () => const TasksTab()),
        _Dest('Leads', Icons.people_outline, () => const LeadsTab()),
        _Dest('Products', Icons.inventory_2_outlined, () => const ProductsTab()),
        _Dest('Calendar', Icons.event_outlined, () => const CalendarTab()),
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

  Future<void> _menu(String v) async {
    final nav = Navigator.of(context);
    await call.leave();
    if (v == 'switch') {
      await Api.setTeam(null);
      nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WorkspacesPage()), (_) => false);
    } else {
      await Api.signOut();
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
    }
  }

  Widget _header() {
    final name = '${Api.user?['name'] ?? ''}';
    final initial = name.isEmpty ? 'G' : name.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        PopupMenuButton<String>(
          onSelected: _menu,
          offset: const Offset(0, 52),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'switch', child: Text('Switch workspace')),
            PopupMenuItem(value: 'out', child: Text('Sign out')),
          ],
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(color: C.ink, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(initial,
                style: const TextStyle(color: C.yellow, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hey,', style: TextStyle(color: C.muted, fontSize: 13)),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ]),
        ),
        if (call.connected)
          GestureDetector(
            onTap: () => setState(() => _i = 8),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(20)),
              child: const Row(children: [
                Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 12),
                SizedBox(width: 6),
                Text('Live', style: TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
          ),
        GestureDetector(
          onTap: () => _scaffold.currentState?.openDrawer(),
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.apps_rounded),
          ),
        ),
      ]),
    );
  }

  Widget _navItem(IconData icon, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: selected ? C.yellow : Colors.transparent, shape: BoxShape.circle),
          child: Icon(icon, color: selected ? C.ink : Colors.white70),
        ),
      );

  Widget _nav(List<_Dest> all) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: C.ink,
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var k = 0; k < 4; k++) _navItem(all[k].icon, _i == k, () => setState(() => _i = k)),
          _navItem(Icons.menu_rounded, _i >= 4, () => _scaffold.currentState?.openDrawer()),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final d = all[_i];
    return Scaffold(
      key: _scaffold,
      drawer: Drawer(
        child: SafeArea(
          child: ListTileTheme(
            data: const ListTileThemeData(
                tileColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20)))),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              const Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 16),
                  child: Text('Glob', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
              for (var k = 0; k < all.length; k++)
                ListTile(
                  leading: Icon(all[k].icon),
                  title: Text(all[k].title),
                  selected: k == _i,
                  selectedTileColor: C.yellow,
                  selectedColor: C.ink,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _i = k);
                  },
                ),
            ]),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          Column(children: [
            _header(),
            if (_i != 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(d.title,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
              ),
            Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 92), child: d.build())),
          ]),
          Positioned(left: 24, right: 24, bottom: 14, child: _nav(all)),
        ]),
      ),
    );
  }
}
