import 'package:flutter/material.dart';
import '../api.dart';
import '../chat_service.dart';
import '../theme.dart';
import 'common.dart';
import 'conversation_page.dart';

/// The "Message" screen: people on top, then the workspace chat and your personal chats.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final svc = ChatService.I;

  @override
  void initState() {
    super.initState();
    svc.addListener(_r);
    svc.loadInbox();
  }

  @override
  void dispose() {
    svc.removeListener(_r);
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  Future<void> _open(Map<String, dynamic>? peer) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationPage(peer: peer)));
    svc.loadInbox();
  }

  void _newMessage() {
    final search = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final q = search.text.trim().toLowerCase();
          final list = svc.members.where((m) => q.isEmpty || '${m['name']}'.toLowerCase().contains(q)).toList();
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(c).size.height * 0.6,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('New message', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(
                    controller: search,
                    onChanged: (_) => set(() {}),
                    decoration: const InputDecoration(hintText: 'Search people', prefixIcon: Icon(Icons.search))),
                const SizedBox(height: 8),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('Nobody matches.'))
                      : ListView(children: [
                          for (final m in list)
                            ListTile(
                              tileColor: Colors.transparent,
                              leading: Avatar(
                                  id: '${m['id']}', name: '${m['name']}', url: m['avatar_url'] as String?, size: 44,
                                  online: svc.online.contains('${m['id']}')),
                              title: Text('${m['name']}'),
                              subtitle: Text('${m['email'] ?? ''}'),
                              onTap: () {
                                Navigator.pop(c);
                                _open(m);
                              },
                            ),
                        ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _card({required Widget leading, required String title, required String sub, required String time, required int unread, required VoidCallback onTap}) {
    return FadeIn(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Row(children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.muted, fontSize: 13)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(time, style: TextStyle(color: context.muted, fontSize: 12)),
                const SizedBox(height: 6),
                if (unread > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: C.coral, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: Text('$unread',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.dark)),
                  )
                else
                  const SizedBox(height: 22),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ib = svc.inbox;
    if (ib == null) return const Center(child: CircularProgressIndicator());
    final team = ib['team'] is Map ? Map<String, dynamic>.from(ib['team'] as Map) : <String, dynamic>{};
    final ws = ib['workspace'] is Map ? Map<String, dynamic>.from(ib['workspace'] as Map) : <String, dynamic>{};
    final wsLast = ws['last_message'] is Map ? Map<String, dynamic>.from(ws['last_message'] as Map) : null;
    final dms = (ib['dms'] is List ? ib['dms'] as List : []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final me = Api.user ?? <String, dynamic>{'id': '', 'name': 'You'};

    return RefreshIndicator(
      onRefresh: svc.loadInbox,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(children: [
            Expanded(
                child: Text(svc.connected ? 'Create a message' : 'Connecting…',
                    style: TextStyle(color: context.muted, fontSize: 14))),
            GestureDetector(
              onTap: _newMessage,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: context.ink,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 8))],
                ),
                child: Icon(Icons.add, color: context.bg, size: 28),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            height: 92,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              GestureDetector(
                onTap: _newMessage,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Avatar(id: '${me['id']}', name: '${me['name']}', url: me['avatar_url'] as String?, size: 60),
                      Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                  color: context.ink, shape: BoxShape.circle, border: Border.all(color: context.bg, width: 2)),
                              child: Icon(Icons.add, size: 14, color: context.bg))),
                    ]),
                    const SizedBox(height: 6),
                    const Text('You', style: TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
              for (final m in svc.members)
                GestureDetector(
                  onTap: () => _open(m),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: svc.online.contains('${m['id']}') ? const Color(0xFF4CC38A) : Colors.transparent,
                                width: 2)),
                        child: Avatar(id: '${m['id']}', name: '${m['name']}', url: m['avatar_url'] as String?, size: 52),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                          width: 60,
                          child: Text('${m['name']}'.split(' ').first,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11))),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          _card(
            leading: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: C.blue, shape: BoxShape.circle),
                child: const Icon(Icons.groups_rounded, color: C.dark, size: 28)),
            title: '${team['name'] ?? 'Workspace'} · everyone',
            sub: wsLast == null
                ? '${ws['members'] ?? ''} members'
                : '${wsLast['name'] ?? ''}: ${previewOf(wsLast)}',
            time: wsLast == null ? '' : whenOf(wsLast['created_at']),
            unread: (ws['unread'] as num?)?.toInt() ?? 0,
            onTap: () => _open(null),
          ),
          for (final d in dms)
            _card(
              leading: Avatar(
                  id: '${d['user']['id']}',
                  name: '${d['user']['name']}',
                  url: d['user']['avatar_url'] as String?,
                  size: 54,
                  online: svc.online.contains('${d['user']['id']}')),
              title: '${d['user']['name']}',
              sub: '${'${d['last_message']['sender_id']}' != '${d['user']['id']}' ? 'You: ' : ''}${previewOf(d['last_message'] as Map?)}',
              time: whenOf(d['last_message']['created_at']),
              unread: (d['unread'] as num?)?.toInt() ?? 0,
              onTap: () => _open(Map<String, dynamic>.from(d['user'] as Map)),
            ),
          if (dms.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text('No personal chats yet.\nTap + or pick someone above.',
                      textAlign: TextAlign.center, style: TextStyle(color: context.muted))),
            ),
        ],
      ),
    );
  }
}
