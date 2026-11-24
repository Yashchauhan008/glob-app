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

  // index in Shell: 1 ideas, 2 tasks, 3 leads, 4 products, 5 calendar, 6 map, 7 q&a, 8 call
  static const _jump = <List<Object>>[
    [1, Icons.lightbulb_outline, 'Ideas'],
    [2, Icons.check_circle_outline, 'Tasks'],
    [3, Icons.people_outline, 'Leads'],
    [5, Icons.event_outlined, 'Calendar'],
    [6, Icons.map_outlined, 'Map'],
    [7, Icons.help_outline, 'Q&A'],
    [8, Icons.headset_mic_outlined, 'Call'],
    [4, Icons.inventory_2_outlined, 'Products'],
  ];

  Widget _hero(String first) => Pastel(
        color: C.blue,
        radius: 32,
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 128,
          child: Stack(children: [
            Positioned(
                right: -6,
                bottom: -14,
                child: Icon(Icons.bolt_rounded, size: 120, color: Colors.white.withAlpha(150))),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Tag('Your workspace', icon: Icons.groups_2_outlined),
              const SizedBox(height: 14),
              Text('Hi $first,\nplan with your team',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
              const Spacer(),
              GestureDetector(
                onTap: () => widget.onGo(2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Add a task', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(color: C.dark, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18)),
                ]),
              ),
            ]),
          ]),
        ),
      );

  Widget _jumpRow() => SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _jump.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (c, i) {
            final j = _jump[i];
            return FadeIn(
              index: i,
              child: GestureDetector(
                onTap: () => widget.onGo(j[0] as int),
                child: Column(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: i == 0 ? C.coral : c.cardBg, shape: BoxShape.circle),
                    child: Icon(j[1] as IconData, size: 24, color: i == 0 ? C.dark : c.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(j[2] as String, style: TextStyle(fontSize: 11, color: c.muted)),
                ]),
              ),
            );
          },
        ),
      );

  Widget _gaugeRow(String title, String sub, String big, double v, Color color) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
            Text(sub, style: TextStyle(color: context.muted, fontSize: 11)),
            const SizedBox(height: 10),
            Text(big, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          ]),
        ),
        Gauge(value: v, color: color),
      ]);

  Widget _tile(IconData icon, String label, String value, Color? color) {
    final inner = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: color == null ? context.bg : Colors.white, shape: BoxShape.circle),
          child: Icon(icon, size: 20)),
      const SizedBox(height: 18),
      Text(label, style: TextStyle(fontSize: 11, color: color == null ? context.muted : const Color(0xFF55555C))),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
    ]);
    return Expanded(
      child: color == null
          ? GCard(padding: const EdgeInsets.all(16), child: inner)
          : Pastel(color: color, padding: const EdgeInsets.all(16), child: inner),
    );
  }

  Widget _dueRow(IconData icon, String title, String when) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Pastel(
          color: C.yellow,
          radius: 30,
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(icon, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(when, style: const TextStyle(fontSize: 12, color: Color(0xFF55555C))),
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
        final done = int.tryParse('${t['todos_done'] ?? 0}') ?? 0;
        final total = int.tryParse('${t['todos_total'] ?? 0}') ?? 0;
        final pct = total == 0 ? 0.0 : done / total;
        final feas = double.tryParse('${t['feasibility']}');
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _f = Api.get('/dashboard'));
            await _f;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              FadeIn(child: _hero(first)),
              const SectionTitle('Jump to'),
              _jumpRow(),
              const SectionTitle('Team progress'),
              FadeIn(
                index: 2,
                child: GCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    _gaugeRow('Tasks done', '$done of $total finished', '${(pct * 100).round()}%', pct,
                        const Color(0xFF4A9BB5)),
                    const Divider(height: 28),
                    _gaugeRow('Feasibility', 'Average idea score',
                        feas == null ? '–' : '${feas.toStringAsFixed(1)}/5', (feas ?? 0) / 5, C.coral),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FadeIn(
                index: 3,
                child: Row(children: [
                  _tile(Icons.lightbulb_outline, 'Ideas', '${t['ideas'] ?? 0}', C.green),
                  const SizedBox(width: 12),
                  _tile(Icons.help_outline, 'Open questions', '${t['open_questions'] ?? 0}', null),
                ]),
              ),
              SectionTitle('Due & follow-ups', action: 'See all', onAction: () => widget.onGo(2)),
              if (due.isEmpty && fu.isEmpty) const GCard(child: Text('All clear. Nothing due.')),
              for (var k = 0; k < due.length; k++)
                FadeIn(
                    index: k,
                    child: _dueRow(Icons.check_rounded, '${due[k]['title']}', shortDate(due[k]['due_date']))),
              for (var k = 0; k < fu.length; k++)
                FadeIn(
                    index: k,
                    child: _dueRow(Icons.phone_callback_outlined, 'Follow up: ${fu[k]['name']}',
                        shortDate(fu[k]['next_follow_up_at']))),
            ],
          ),
        );
      },
    );
  }
}
