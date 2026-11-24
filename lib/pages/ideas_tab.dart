import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';

class IdeasTab extends StatefulWidget {
  const IdeasTab({super.key});
  @override
  State<IdeasTab> createState() => _IdeasTabState();
}

class _IdeasTabState extends State<IdeasTab> {
  final _key = GlobalKey<AsyncListState>();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncList(
        key: _key,
        load: () async => items(await Api.get('/ideas')),
        empty: 'No ideas yet. Add one!',
        row: (c, i, reload) => ListTile(
          leading: const Icon(Icons.lightbulb_outline),
          title: Text('${i['title']}'),
          subtitle: Text('${i['status']} · ${i['owner_name'] ?? ''}'),
          trailing: i['feasibility'] != null ? Text('${i['feasibility']}/5') : null,
          onTap: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => IdeaPage(idea: i))),
        ),
      ),
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

  Future<void> _send() async {
    final t = _msg.text.trim();
    if (t.isEmpty) return;
    try {
      await Api.post('/ideas/${widget.idea['id']}/messages', {'body': t, 'kind': 'note'});
      _msg.clear();
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.idea;
    return Scaffold(
      appBar: AppBar(title: Text('${i['title']}')),
      body: Column(children: [
        Expanded(
          child: AsyncList(
            key: _key,
            load: () async => items(await Api.get('/ideas/${i['id']}/messages')),
            empty: 'No discussion yet.',
            header: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${i['description'] ?? ''}')),
            row: (c, m, reload) => ListTile(
              title: Text('${m['body'] ?? ''}'),
              subtitle: Text('${m['kind'] ?? ''} · ${m['owner_name'] ?? m['author_name'] ?? ''}'),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: _msg,
                      decoration: const InputDecoration(
                          hintText: 'Add a note…'))),
              IconButton(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
