import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';

class QaTab extends StatefulWidget {
  const QaTab({super.key});
  @override
  State<QaTab> createState() => _QaTabState();
}

class _QaTabState extends State<QaTab> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _ask() async {
    final r = await askFields(context, 'Ask the team', ['Question', 'Details (optional)']);
    if (r == null || r['Question']!.isEmpty) return;
    try {
      await Api.post('/questions', {'title': r['Question'], 'body': r['Details (optional)'] ?? ''});
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
        load: () async => items(await Api.get('/questions')),
        empty: 'No questions yet. Ask something!',
        row: (c, q, reload) {
          final solved = q['accepted_answer_id'] != null;
          return ListTile(
            leading: Icon(solved ? Icons.check_circle : Icons.help_outline,
                color: solved ? Colors.green : null),
            title: Text('${q['title']}'),
            subtitle: Text('${q['owner_name'] ?? ''} · ${q['answers_count'] ?? 0} answers'),
            onTap: () async {
              await Navigator.of(c).push(MaterialPageRoute(builder: (_) => QuestionPage(q: q)));
              reload();
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _ask, child: const Icon(Icons.add)),
    );
  }
}

class QuestionPage extends StatefulWidget {
  final Map<String, dynamic> q;
  const QuestionPage({super.key, required this.q});
  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  late Future<dynamic> _f = Api.get('/questions/${widget.q['id']}');
  final _ans = TextEditingController();

  void _reload() => setState(() => _f = Api.get('/questions/${widget.q['id']}'));

  Future<void> _send() async {
    final t = _ans.text.trim();
    if (t.isEmpty) return;
    try {
      await Api.post('/questions/${widget.q['id']}/answers', {'body': t});
      _ans.clear();
      _reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = '${widget.q['owner_id']}' == '${Api.user?['id']}';
    return Scaffold(
      appBar: AppBar(title: const Text('Question'), actions: [
        if (mine)
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                try {
                  await Api.del('/questions/${widget.q['id']}');
                  nav.pop();
                } catch (e) {
                  if (mounted) toast(context, '$e');
                }
              })
      ]),
      body: Column(children: [
        Expanded(
          child: FutureBuilder<dynamic>(
            future: _f,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) return Center(child: Text('${s.error}'));
              final d = s.data is Map ? s.data as Map : {};
              final answers = d['answers'] is List ? d['answers'] as List : [];
              final accepted = d['accepted_answer_id'] ?? widget.q['accepted_answer_id'];
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text('${widget.q['title']}', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('${d['body'] ?? widget.q['body'] ?? ''}'),
                const Divider(height: 32),
                if (answers.isEmpty) const Text('No answers yet.'),
                for (final a in answers)
                  Card(
                    color: '${a['id']}' == '$accepted'
                        ? Theme.of(c).colorScheme.primaryContainer
                        : null,
                    child: ListTile(
                      title: Text('${a['body']}'),
                      subtitle: Text('${a['owner_name'] ?? ''}'),
                      trailing: '${a['id']}' == '$accepted'
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : (mine
                              ? TextButton(
                                  onPressed: () async {
                                    try {
                                      await Api.post(
                                          '/questions/${widget.q['id']}/accept/${a['id']}');
                                      _reload();
                                    } catch (e) {
                                      if (mounted) toast(context, '$e');
                                    }
                                  },
                                  child: const Text('Accept'))
                              : null),
                    ),
                  ),
              ]);
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: _ans,
                      decoration: const InputDecoration(
                          hintText: 'Write an answer…', border: OutlineInputBorder()))),
              IconButton(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
