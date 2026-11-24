import 'package:flutter/material.dart';
import '../api.dart';
import '../chat_service.dart';
import '../notify.dart';
import '../theme.dart';
import 'common.dart';

/// Everything that needs your attention, each with a label saying where it came from.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async => items(await Api.get('/notifications'));

  void _reload() {
    setState(() => _f = _load());
    ChatService.I.loadNotifUnread();
  }

  String _ago(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '';
    final s = DateTime.now().difference(d).inSeconds;
    if (s < 60) return 'now';
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h';
    return '${s ~/ 86400}d';
  }

  Color _color(String t) => t == 'dm' ? C.blue : (t == 'chat' ? C.green : C.yellow);
  IconData _icon(String t) => t == 'dm' ? Icons.chat_bubble_outline : (t == 'chat' ? Icons.groups_outlined : Icons.help_outline);

  Future<void> _open(Map<String, dynamic> n) async {
    try {
      await Api.post('/notifications/read', {'ids': ['${n['id']}']});
    } catch (_) {}
    ChatService.I.loadNotifUnread();
    final data = n['data'] is Map ? Map<String, dynamic>.from(n['data'] as Map) : <String, dynamic>{};
    if (!mounted) return;
    Navigator.of(context).pop();
    NavIntent.pending = {
      'type': '${n['type']}',
      'team_id': '${n['team_id'] ?? ''}',
      'from_id': '${data['from_id'] ?? ''}',
      'question_id': '${data['question_id'] ?? ''}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            child: Row(children: [
              RoundBtn(Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 14),
              const Expanded(child: Text('Notifications', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
              RoundBtn(Icons.done_all_rounded, onTap: () async {
                try {
                  await Api.post('/notifications/read', {});
                } catch (_) {}
                _reload();
              }),
              const SizedBox(width: 8),
              RoundBtn(Icons.delete_outline, onTap: () async {
                if (!await confirmDelete(context, 'all notifications')) return;
                try {
                  await Api.del('/notifications');
                } catch (_) {}
                _reload();
              }),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _f,
              builder: (c, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.hasError) return Center(child: Text('${s.error}'));
                final list = s.data ?? [];
                if (list.isEmpty) return Center(child: Text('You are all caught up.', style: TextStyle(color: context.muted)));
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _f;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final n = list[i];
                      final unread = n['read_at'] == null;
                      final data = n['data'] is Map ? Map<String, dynamic>.from(n['data'] as Map) : <String, dynamic>{};
                      final count = (data['count'] as num?)?.toInt() ?? 1;
                      return FadeIn(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: GestureDetector(
                            onTap: () => _open(n),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.cardBg,
                                borderRadius: BorderRadius.circular(26),
                                border: unread ? Border.all(color: C.coral, width: 1.5) : null,
                                boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 14, offset: Offset(0, 5))],
                              ),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(color: _color('${n['type']}'), shape: BoxShape.circle),
                                    child: Icon(_icon('${n['type']}'), color: C.dark, size: 22)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${n['label']}'.toUpperCase(),
                                        style: TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: context.muted)),
                                    const SizedBox(height: 2),
                                    Text('${n['title']}${count > 1 ? '  ·  $count new' : ''}',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                    const SizedBox(height: 2),
                                    Text('${n['body']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: context.muted, fontSize: 13)),
                                  ]),
                                ),
                                const SizedBox(width: 8),
                                Text(_ago(n['created_at']), style: TextStyle(color: context.muted, fontSize: 12)),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
