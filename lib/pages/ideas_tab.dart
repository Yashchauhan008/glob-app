import 'package:flutter/material.dart';
import '../api.dart';
import '../widget_sync.dart';
import '../theme.dart';
import 'common.dart';

const _statuses = ['idea', 'planning', 'building', 'paused', 'dropped', 'shipped'];

Color statusColor(String s) {
  switch (s) {
    case 'planning':
      return C.blue;
    case 'building':
      return C.lilac;
    case 'paused':
      return C.grey;
    case 'dropped':
      return C.coral;
    case 'shipped':
      return C.green;
    default:
      return C.yellow;
  }
}

IconData statusIcon(String s) {
  switch (s) {
    case 'planning':
      return Icons.edit_note_rounded;
    case 'building':
      return Icons.construction_rounded;
    case 'paused':
      return Icons.pause_circle_outline;
    case 'dropped':
      return Icons.close_rounded;
    case 'shipped':
      return Icons.rocket_launch_outlined;
    default:
      return Icons.lightbulb_outline;
  }
}

Color tagColor(dynamic t) {
  switch ('$t') {
    case 'problem':
      return C.coral;
    case 'solution':
      return C.green;
    case 'conclusion':
      return C.blue;
    default:
      return C.grey;
  }
}

class IdeasTab extends StatefulWidget {
  const IdeasTab({super.key});
  @override
  State<IdeasTab> createState() => _IdeasTabState();
}

class _IdeasTabState extends State<IdeasTab> {
  final _key = GlobalKey<AsyncListState>();
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (WidgetActions.take('new_idea') && mounted) _add();
    });
  }

  Future<void> _add() async {
    final r = await askFields(context, 'New idea', ['Title', 'Description']);
    if (r == null || r['Title']!.isEmpty) return;
    try {
      await Api.post('/ideas', {'title': r['Title'], 'description': r['Description'] ?? ''});
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Widget _chip(String label, Color color) {
    final sel = _status == label;
    return GestureDetector(
      onTap: () {
        setState(() => _status = label);
        WidgetsBinding.instance.addPostFrameCallback((_) => _key.currentState?.reload());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? color : color.withAlpha(context.isDark ? 70 : 110),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: sel ? context.ink : Colors.transparent, width: 1.5),
        ),
        child: Text(label[0].toUpperCase() + label.substring(1),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: context.isDark && !sel ? context.ink : C.dark)),
      ),
    );
  }

  Widget _card(BuildContext c, Map<String, dynamic> i, VoidCallback reload) {
    final st = '${i['status'] ?? 'idea'}';
    final desc = '${i['description'] ?? ''}'.trim();
    final feas = i['feasibility'];
    return GestureDetector(
      onTap: () async {
        await Navigator.of(c).push(MaterialPageRoute(builder: (_) => IdeaPage(idea: i)));
        reload();
      },
      child: Pastel(
        color: statusColor(st),
        radius: 30,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Tag(st, icon: statusIcon(st)),
            const Spacer(),
            if (feas != null) Tag('$feas/5', icon: Icons.star_rounded),
          ]),
          const SizedBox(height: 14),
          Text('${i['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Avatar(id: '${i['owner_id']}', name: '${i['owner_name'] ?? '?'}', url: i['owner_avatar'] as String?, size: 26),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${i['owner_name'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
            const Icon(Icons.chat_bubble_outline, size: 15),
            const SizedBox(width: 4),
            Text('${i['messages'] ?? 0}', style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 12),
            const Icon(Icons.thumb_up_alt_outlined, size: 15),
            const SizedBox(width: 4),
            Text('${i['votes'] ?? 0}', style: const TextStyle(fontSize: 12)),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _chip('all', C.blue),
              for (final s in _statuses) _chip(s, statusColor(s)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: AsyncList(
            key: _key,
            load: () async {
              final all = items(await Api.get('/ideas'));
              return _status == 'all' ? all : all.where((e) => '${e['status']}' == _status).toList();
            },
            empty: 'No ideas here yet. Add one!',
            row: _card,
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}

class IdeaPage extends StatefulWidget {
  final Map<String, dynamic> idea;
  const IdeaPage({super.key, required this.idea});
  @override
  State<IdeaPage> createState() => _IdeaPageState();
}

class _IdeaPageState extends State<IdeaPage> {
  final _key = GlobalKey<AsyncListState>();
  final _msg = TextEditingController();
  String? _tag; // null = plain note

  Future<void> _send() async {
    final t = _msg.text.trim();
    if (t.isEmpty) return;
    try {
      await Api.post('/ideas/${widget.idea['id']}/messages', {'body': t, if (_tag != null) 'tag': _tag});
      _msg.clear();
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Widget _tagChip(String? tag, String label) {
    final sel = _tag == tag;
    return GestureDetector(
      onTap: () => setState(() => _tag = tag),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? tagColor(tag) : tagColor(tag).withAlpha(context.isDark ? 70 : 110),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? context.ink : Colors.transparent, width: 1.4),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.isDark && !sel ? context.ink : C.dark)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.idea;
    final st = '${i['status'] ?? 'idea'}';
    final desc = '${i['description'] ?? ''}'.trim();
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: RoundBtn(Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop())),
        title: const Text('Idea'),
      ),
      body: Column(children: [
        Expanded(
          child: AsyncList(
            key: _key,
            load: () async => items(await Api.get('/ideas/${i['id']}/messages')),
            empty: 'No discussion yet. Start one below.',
            header: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Pastel(
                color: statusColor(st),
                radius: 32,
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Tag(st, icon: statusIcon(st)),
                  const SizedBox(height: 14),
                  Text('${i['title']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  if (desc.isNotEmpty) ...[const SizedBox(height: 8), Text(desc)],
                ]),
              ),
            ),
            row: (c, m, reload) {
              final tag = m['tag'];
              return Pastel(
                color: tag == null ? c.cardBg : tagColor(tag).withAlpha(c.isDark ? 90 : 255),
                radius: 24,
                padding: const EdgeInsets.all(14),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: tag == null ? c.ink : (c.isDark ? c.ink : C.dark)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (tag != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('$tag'.toUpperCase(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1))),
                    Text('${m['body'] ?? ''}'),
                    const SizedBox(height: 6),
                    Row(children: [
                      Avatar(id: '${m['owner_id']}', name: '${m['owner_name'] ?? '?'}', url: m['owner_avatar'] as String?, size: 20),
                      const SizedBox(width: 6),
                      Text('${m['owner_name'] ?? m['author_name'] ?? ''}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Column(children: [
              SizedBox(
                height: 38,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  _tagChip(null, 'Note'),
                  _tagChip('problem', 'Problem'),
                  _tagChip('solution', 'Solution'),
                  _tagChip('conclusion', 'Conclusion'),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _msg,
                        decoration: const InputDecoration(hintText: 'Add to the discussion…'))),
                const SizedBox(width: 8),
                RoundBtn(Icons.send_rounded, onTap: _send, size: 50),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
