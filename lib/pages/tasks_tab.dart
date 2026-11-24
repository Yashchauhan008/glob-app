import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';

class TasksTab extends StatefulWidget {
  const TasksTab({super.key});
  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  final _key = GlobalKey<AsyncListState>();
  String _filter = 'open';

  Future<void> _add() async {
    final r = await askFields(context, 'New task', ['Title', 'Due date (YYYY-MM-DD, optional)']);
    if (r == null || r['Title']!.isEmpty) return;
    final due = r['Due date (YYYY-MM-DD, optional)'] ?? '';
    try {
      await Api.post('/todos', {'title': r['Title'], if (due.isNotEmpty) 'due_date': due});
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'open', label: Text('Open')),
              ButtonSegment(value: 'done', label: Text('Done')),
              ButtonSegment(value: 'all', label: Text('All')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) {
              setState(() => _filter = s.first);
              WidgetsBinding.instance.addPostFrameCallback((_) => _key.currentState?.reload());
            },
          ),
        ),
        Expanded(
          child: AsyncList(
            key: _key,
            load: () async => items(await Api.get('/todos?filter=$_filter')),
            empty: 'No tasks here.',
            row: (c, t, reload) => ListTile(
              leading: Checkbox(
                value: t['done'] == true,
                onChanged: (v) async {
                  try {
                    await Api.patch('/todos/${t['id']}', {'done': v == true});
                  } catch (e) {
                    if (c.mounted) toast(c, '$e');
                  }
                  reload();
                },
              ),
              title: Text('${t['title']}',
                  style: t['done'] == true
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : null),
              subtitle: Text([
                if (t['idea_title'] != null) '${t['idea_title']}',
                if (t['lead_name'] != null) '${t['lead_name']}',
                if (t['due_date'] != null) 'due ${shortDate(t['due_date'])}',
              ].join(' · ')),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  try {
                    await Api.del('/todos/${t['id']}');
                  } catch (e) {
                    if (c.mounted) toast(c, '$e');
                  }
                  reload();
                },
              ),
            ),
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}
