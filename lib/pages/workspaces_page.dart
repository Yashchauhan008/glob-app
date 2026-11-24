import 'package:flutter/material.dart';
import '../api.dart';
import 'auth_page.dart';
import 'shell.dart';

class WorkspacesPage extends StatefulWidget {
  const WorkspacesPage({super.key});
  @override
  State<WorkspacesPage> createState() => _WorkspacesPageState();
}

class _WorkspacesPageState extends State<WorkspacesPage> {
  late Future<dynamic> _f;

  @override
  void initState() {
    super.initState();
    _f = Api.get('/teams');
  }

  Future<void> _open(Map<String, dynamic> t) async {
    await Api.setTeam('${t['id']}');
    try {
      await Api.put('/teams/${t['id']}/last', {});
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Shell()), (_) => false);
  }

  Future<void> _logout() async {
    await Api.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your workspaces'), actions: [
        IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Sign out')
      ]),
      body: FutureBuilder<dynamic>(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${s.error}'),
              TextButton(
                  onPressed: () => setState(() => _f = Api.get('/teams')),
                  child: const Text('Retry'))
            ]));
          }
          final teams = items(s.data);
          if (teams.isEmpty) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'You are not in any workspace yet. Ask your team owner to invite you, then reopen the app.',
                        textAlign: TextAlign.center)));
          }
          return ListView(
            children: [
              for (final t in teams)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.groups)),
                  title: Text('${t['name']}'),
                  subtitle: Text('${t['members'] ?? ''} members · ${t['role'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(t),
                )
            ],
          );
        },
      ),
    );
  }
}
