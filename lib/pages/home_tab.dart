import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<dynamic> _f = Api.get('/dashboard');

  Widget _tile(String v, String label) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final first = '${Api.user?['name'] ?? ''}'.split(' ').first;
    return FutureBuilder<dynamic>(
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
                onPressed: () => setState(() => _f = Api.get('/dashboard')),
                child: const Text('Retry'))
          ]));
        }
        final d = (s.data is Map ? s.data as Map : {});
        final t = (d['team'] is Map ? d['team'] as Map : {});
        final due = (d['todos_due'] is List ? d['todos_due'] as List : []);
        final fu = (d['follow_ups'] is List ? d['follow_ups'] as List : []);
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _f = Api.get('/dashboard'));
            await _f;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('Hi $first 👋', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.8,
                children: [
                  _tile('${t['ideas'] ?? 0}', 'Ideas'),
                  _tile('${t['open_questions'] ?? 0}', 'Open questions'),
                  _tile('${t['feasibility'] ?? '–'}', 'Avg feasibility /5'),
                  _tile('${t['todos_done'] ?? 0}/${t['todos_total'] ?? 0}', 'Tasks done'),
                ],
              ),
              const SizedBox(height: 16),
              Text('Due & follow-ups', style: Theme.of(context).textTheme.titleMedium),
              if (due.isEmpty && fu.isEmpty) const ListTile(title: Text('All clear.')),
              for (final x in due)
                ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text('${x['title']}'),
                    trailing: Text(shortDate(x['due_date']))),
              for (final f in fu)
                ListTile(
                    dense: true,
                    leading: const Icon(Icons.phone_callback_outlined),
                    title: Text('Follow up: ${f['name']}'),
                    trailing: Text(shortDate(f['next_follow_up_at']))),
            ],
          ),
        );
      },
    );
  }
}
