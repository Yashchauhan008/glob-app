import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'common.dart';

class HomeTab extends StatefulWidget {
  final void Function(int) onGo;
  const HomeTab({super.key, required this.onGo});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<dynamic> _f = Api.get('/dashboard');

  Widget _stat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _action(String label, IconData icon, bool dark, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: dark ? C.ink : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: dark ? null : Border.all(color: C.ink, width: 1.2),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: dark ? C.yellow : C.ink, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: dark ? Colors.white : C.ink, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _tile(String label, String value, {bool dark = false}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: dark ? C.ink : C.yellowSoft, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : C.ink)),
          const Spacer(),
          Align(
              alignment: Alignment.bottomRight,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : C.ink))),
        ]),
      );

  Widget _row(IconData icon, String title, String trailing) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(color: C.yellow, shape: BoxShape.circle),
              child: Icon(icon, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis)),
          Text(trailing, style: const TextStyle(color: C.muted, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              GCard(
                child: IntrinsicHeight(
                  child: Row(children: [
                    _stat('Ideas', '${t['ideas'] ?? 0}'),
                    const VerticalDivider(width: 24),
                    _stat('Open questions', '${t['open_questions'] ?? 0}'),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                _action('Add task', Icons.add_task, true, () => widget.onGo(2)),
                const SizedBox(width: 12),
                _action('New idea', Icons.lightbulb_outline, false, () => widget.onGo(1)),
              ]),
              SectionTitle('Due & follow-ups', action: 'See all', onAction: () => widget.onGo(2)),
              Panel(
                child: Column(children: [
                  if (due.isEmpty && fu.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('All clear. Nothing due.',
                            style: TextStyle(fontWeight: FontWeight.w600))),
                  for (final x in due)
                    _row(Icons.check_rounded, '${x['title']}', shortDate(x['due_date'])),
                  for (final f in fu)
                    _row(Icons.phone_callback_outlined, 'Follow up: ${f['name']}',
                        shortDate(f['next_follow_up_at'])),
                ]),
              ),
              const SectionTitle('Team stats'),
              Panel(
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.5,
                  children: [
                    _tile('Ideas', '${t['ideas'] ?? 0}'),
                    _tile('Tasks done', '${t['todos_done'] ?? 0}/${t['todos_total'] ?? 0}', dark: true),
                    _tile('Open questions', '${t['open_questions'] ?? 0}'),
                    _tile('Avg feasibility', '${t['feasibility'] ?? '–'}'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
