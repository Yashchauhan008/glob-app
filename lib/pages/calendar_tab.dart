import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';

class _Item {
  final String type; // event | todo | followup
  final String id;
  final String title;
  final String kind;
  final DateTime when;
  final bool hasTime;
  final String notes;
  _Item(this.type, this.id, this.title, this.kind, this.when, this.hasTime, [this.notes = '']);
}

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});
  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late Future<List<_Item>> _f = _load();

  Future<List<_Item>> _load() async {
    final from = DateTime.now().subtract(const Duration(days: 1));
    final to = DateTime.now().add(const Duration(days: 90));
    final ev = await Api.get(
        '/events?from=${Uri.encodeComponent(from.toUtc().toIso8601String())}&to=${Uri.encodeComponent(to.toUtc().toIso8601String())}');
    final td = await Api.get('/todos?filter=open');
    final out = <_Item>[];
    for (final e in items(ev)) {
      final d = DateTime.tryParse('${e['starts_at']}')?.toLocal();
      if (d == null) continue;
      out.add(_Item('event', '${e['id']}', '${e['title']}', '${e['kind'] ?? 'meeting'}', d, true,
          '${e['notes'] ?? ''}'));
    }
    for (final t in items(td)) {
      if (t['due_date'] == null) continue;
      final d = DateTime.tryParse('${t['due_date']}'.substring(0, 10));
      if (d == null || d.isBefore(DateTime(from.year, from.month, from.day)) || d.isAfter(to)) continue;
      out.add(_Item('todo', '${t['id']}', '${t['title']}', 'task', d, false));
    }
    final fu = (td is Map && td['follow_ups'] is List) ? td['follow_ups'] as List : [];
    for (final f in fu) {
      final d = DateTime.tryParse('${f['next_follow_up_at']}')?.toLocal();
      if (d == null) continue;
      out.add(_Item('followup', '${f['lead_id']}', 'Follow up: ${f['lead_name']}', 'followup', d, true));
    }
    out.sort((a, b) => a.when.compareTo(b.when));
    return out;
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _add() async {
    final title = TextEditingController();
    final notes = TextEditingController();
    var kind = 'meeting';
    var date = DateTime.now();
    var time = const TimeOfDay(hour: 9, minute: 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('New event'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              DropdownButtonFormField<String>(
                value: kind,
                items: const ['meeting', 'appointment', 'task', 'reminder']
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => set(() => kind = v ?? kind),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date: ${date.toString().substring(0, 10)}'),
                onTap: () async {
                  final d = await showDatePicker(
                      context: c,
                      initialDate: date,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 3650)));
                  if (d != null) set(() => date = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Time: ${time.format(c)}'),
                onTap: () async {
                  final t = await showTimePicker(context: c, initialTime: time);
                  if (t != null) set(() => time = t);
                },
              ),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await Api.post('/events', {
        'title': title.text.trim(),
        'kind': kind,
        'starts_at': start.toUtc().toIso8601String(),
        'notes': notes.text.trim(),
      });
      _reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  IconData _icon(String t) =>
      t == 'event' ? Icons.event : (t == 'todo' ? Icons.check_circle_outline : Icons.phone_callback_outlined);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<_Item>>(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${s.error}'),
              TextButton(onPressed: _reload, child: const Text('Retry'))
            ]));
          }
          final list = s.data ?? [];
          if (list.isEmpty) return const Center(child: Text('Nothing scheduled.'));
          final children = <Widget>[];
          String? last;
          for (final i in list) {
            final day = i.when.toString().substring(0, 10);
            if (day != last) {
              last = day;
              children.add(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(day, style: Theme.of(c).textTheme.titleSmall)));
            }
            final hh = i.hasTime
                ? '${i.when.hour.toString().padLeft(2, '0')}:${i.when.minute.toString().padLeft(2, '0')}'
                : 'all day';
            children.add(ListTile(
              leading: Icon(_icon(i.type)),
              title: Text(i.title),
              subtitle: Text('$hh · ${i.kind}${i.notes.isNotEmpty ? ' · ${i.notes}' : ''}'),
              trailing: i.type == 'event'
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        try {
                          await Api.del('/events/${i.id}');
                        } catch (e) {
                          if (c.mounted) toast(c, '$e');
                        }
                        _reload();
                      })
                  : null,
            ));
          }
          return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _f;
              },
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [...children, const SizedBox(height: 80)]));
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}
