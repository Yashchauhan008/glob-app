import 'package:flutter/material.dart';
import '../api.dart';
import '../call.dart';
import '../chat_service.dart';
import '../notify.dart';
import '../push.dart';
import '../theme.dart';
import 'auth_page.dart';
import 'workspaces_page.dart';
import 'common.dart';
import 'home_tab.dart';
import 'ideas_tab.dart';
import 'tasks_tab.dart';
import 'leads_tab.dart';
import 'products_tab.dart';
import 'calendar_tab.dart';
import 'map_tab.dart';
import 'qa_tab.dart';
import 'call_tab.dart';
import 'chat_tab.dart';
import 'conversation_page.dart';
import 'notifications_page.dart';

class Shell extends StatefulWidget {
  /// Where to go on start-up, when the app was opened from a notification in another workspace.
  final Map<String, String>? intent;
  const Shell({super.key, this.intent});
  @override
  State<Shell> createState() => _ShellState();
}

class _Dest {
  final String title;
  final IconData icon;
  final Widget Function() build;
  const _Dest(this.title, this.icon, this.build);
}

const _kQa = 7;
const _kCall = 8;
const _kChat = 9;

class _ShellState extends State<Shell> {
  int _i = 0;
  final _scaffold = GlobalKey<ScaffoldState>();
  final call = CallService.I;
  final chat = ChatService.I;

  List<_Dest> get _all => [
        _Dest('Overview', Icons.home_outlined, () => HomeTab(onGo: (i) => setState(() => _i = i))),
        _Dest('Ideas', Icons.lightbulb_outline, () => const IdeasTab()),
        _Dest('Tasks', Icons.check_circle_outline, () => const TasksTab()),
        _Dest('Leads', Icons.people_outline, () => const LeadsTab()),
        _Dest('Products', Icons.inventory_2_outlined, () => const ProductsTab()),
        _Dest('Calendar', Icons.event_outlined, () => const CalendarTab()),
        _Dest('Map', Icons.map_outlined, () => const MapTab()),
        _Dest('Q&A', Icons.help_outline, () => const QaTab()),
        _Dest('Call', Icons.headset_mic_outlined, () => const CallTab()),
        _Dest('Message', Icons.chat_bubble_outline, () => const ChatTab()),
      ];

  @override
  void initState() {
    super.initState();
    call.addListener(_r);
    chat.addListener(_r);
    NavIntent.notifier.addListener(_onIntent);
    chat.start();
    Notify.I.init().then((_) => Notify.I.requestPermission());
    Push.register();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = widget.intent ?? NavIntent.pending;
      if (pending != null) {
        NavIntent.pending = null;
        _handleIntent(pending);
      }
    });
  }

  @override
  void dispose() {
    call.removeListener(_r);
    chat.removeListener(_r);
    NavIntent.notifier.removeListener(_onIntent);
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  void _onIntent() {
    final i = NavIntent.pending;
    if (i == null || !mounted) return;
    NavIntent.pending = null;
    _handleIntent(i);
  }

  Future<void> _handleIntent(Map<String, String> i) async {
    final team = i['team_id'] ?? '';
    final nav = Navigator.of(context);
    if (team.isNotEmpty && team != Api.teamId) {
      // the notification belongs to another workspace: switch to it, then open it
      await call.leave();
      chat.disconnect();
      await Api.setTeam(team);
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => Shell(intent: i)), (_) => false);
      return;
    }
    switch (i['type']) {
      case 'dm':
        final id = i['from_id'] ?? '';
        if (chat.inbox == null) await chat.loadInbox();
        final peer = chat.personById(id);
        if (!mounted) return;
        setState(() => _i = _kChat);
        if (peer != null) nav.push(MaterialPageRoute(builder: (_) => ConversationPage(peer: peer)));
        break;
      case 'chat':
        setState(() => _i = _kChat);
        nav.push(MaterialPageRoute(builder: (_) => const ConversationPage()));
        break;
      case 'answer':
        setState(() => _i = _kQa);
        break;
    }
  }

  Future<void> _menu(String v) async {
    final nav = Navigator.of(context);
    await call.leave();
    if (v == 'switch') {
      chat.disconnect();
      await Api.setTeam(null);
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WorkspacesPage()), (_) => false);
    } else {
      await Push.unregister();
      chat.disconnect();
      await Api.signOut();
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
    }
  }

  Widget _badged(Widget child, int count) => Stack(clipBehavior: Clip.none, children: [
        child,
        Positioned(right: -3, top: -3, child: CountBadge(count)),
      ]);

  Widget _header() {
    final name = '${Api.user?['name'] ?? ''}';
    final me = Api.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: [
        PopupMenuButton<String>(
          onSelected: _menu,
          offset: const Offset(0, 56),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'switch', child: Text('Switch workspace')),
            PopupMenuItem(value: 'out', child: Text('Sign out')),
          ],
          child: Avatar(id: '${me?['id'] ?? ''}', name: name, url: me?['avatar_url'] as String?, size: 48),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Hello, ', style: TextStyle(color: context.muted)),
                TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16)),
        ),
        if (call.connected)
          GestureDetector(
            onTap: () => setState(() => _i = _kCall),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(20)),
              child: const Row(children: [
                Icon(Icons.graphic_eq, size: 16, color: C.dark),
                SizedBox(width: 6),
                Text('In call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.dark)),
              ]),
            ),
          ),
        const ThemeToggle(),
        const SizedBox(width: 8),
        _badged(
          RoundBtn(Icons.notifications_none_rounded, onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
            chat.loadNotifUnread();
          }),
          chat.notifUnread,
        ),
        const SizedBox(width: 8),
        // the chat button sits where the menu button used to be
        _badged(RoundBtn(Icons.chat_bubble_outline_rounded, onTap: () => setState(() => _i = _kChat)), chat.unread),
      ]),
    );
  }

  Widget _navItem(IconData icon, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: selected ? context.ink : Colors.transparent, shape: BoxShape.circle),
          child: AnimatedScale(
            scale: selected ? 1.08 : 1,
            duration: const Duration(milliseconds: 250),
            child: Icon(icon, color: selected ? context.bg : context.muted),
          ),
        ),
      );

  Widget _nav(List<_Dest> all) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 22, offset: Offset(0, 8))],
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(22)))),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  child: Row(children: [
                    Image.asset('assets/logo.png', width: 40, height: 40),
                    const SizedBox(width: 10),
                    const Text('Glob', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  ])),
              for (var k = 0; k < all.length; k++)
                ListTile(
                  leading: Icon(all[k].icon),
                  title: Text(all[k].title),
                  selected: k == _i,
                  selectedTileColor: C.blue,
                  selectedColor: C.dark,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: c)),
                  child: Text(d.title,
                      key: ValueKey(d.title),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 92),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                          position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
                          child: child)),
                  child: KeyedSubtree(key: ValueKey(_i), child: d.build()),
                ),
              ),
            ),
          ]),
          Positioned(left: 24, right: 24, bottom: 14, child: _nav(all)),
        ]),
      ),
    );
  }
}
