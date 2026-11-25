import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../call_service.dart';
import '../chat_service.dart';
import '../theme.dart';
import 'common.dart';

/// One chat: the workspace chat (peer == null) or a personal chat.
class ConversationPage extends StatefulWidget {
  final Map<String, dynamic>? peer;
  const ConversationPage({super.key, this.peer});
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final svc = ChatService.I;
  final _text = TextEditingController();
  final _rec = AudioRecorder();
  final List<Map<String, dynamic>> _msgs = [];
  final Map<String, Map<String, dynamic>> _pending = {};
  final Map<String, Map<String, dynamic>> _replySnap = {}; // the quote on a message that is still sending
  Map<String, dynamic>? _replyTo; // the message the person is answering
  final _input = FocusNode();
  StreamSubscription? _sub;
  Timer? _typingOff;
  Timer? _recTick;
  Timer? _poll;
  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loaded = false;
  bool _more = false;
  bool _typing = false;
  bool _uploading = false;
  bool _recording = false;
  DateTime? _recStart;
  int _recMs = 0;
  String _err = '';
  int _seq = 0;

  bool get dm => widget.peer != null;
  String get peerId => '${widget.peer?['id']}';
  String get convId => dm ? peerId : 'workspace';
  String get _path => dm ? '/chat/dm/$peerId' : '/chat';

  @override
  void initState() {
    super.initState();
    svc.activeConv = convId;
    _sub = svc.events.listen(_onEvent);
    svc.addListener(_r);
    CallService.I.addListener(_r);
    CallService.I.loadOpen();
    _load();
    // when the live connection is down (or just as a safety net) ask the server for what is new
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!svc.connected) _refresh();
    });
  }

  @override
  void dispose() {
    if (svc.activeConv == convId) svc.activeConv = null;
    _sub?.cancel();
    _typingOff?.cancel();
    _recTick?.cancel();
    _poll?.cancel();
    svc.removeListener(_r);
    CallService.I.removeListener(_r);
    _rec.dispose();
    _text.dispose();
    _input.dispose();
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _norm(Map<String, dynamic> m) {
    if (dm) return fromDm(m);
    return {...m, 'status': '${m['user_id']}' == '${Api.user?['id']}' ? 'sent' : null};
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('$_path?limit=40');
      final list = items(r).map(_norm).toList();
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(list);
        _more = r is Map && r['has_more'] == true;
        _loaded = true;
      });
      _markRead();
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '$e';
          _loaded = true;
        });
      }
    }
  }

  /// Brings in anything new (messages, delivered / seen changes) without the live connection.
  Future<void> _refresh() async {
    if (!_loaded) return;
    try {
      final r = await Api.get('$_path?limit=40');
      final list = items(r).map(_norm).toList();
      if (!mounted) return;
      var fromPeer = false;
      setState(() {
        for (final m in list) {
          final i = _msgs.indexWhere((x) =>
              '${x['id']}' == '${m['id']}' || (m['client_id'] != null && '${x['client_id']}' == '${m['client_id']}'));
          if (i >= 0) {
            _msgs[i] = {..._msgs[i], ...m};
          } else {
            _msgs.add(m);
            if ('${m['user_id']}' != '${Api.user?['id']}') fromPeer = true;
          }
        }
        _msgs.sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
      });
      if (fromPeer) _markRead();
    } catch (_) {}
  }

  Future<void> _older() async {
    if (_msgs.isEmpty) return;
    final first = _msgs.firstWhere((m) => !'${m['id']}'.startsWith('local-'), orElse: () => _msgs.first);
    try {
      final r = await Api.get('$_path?limit=40&before=${Uri.encodeComponent('${first['created_at']}')}');
      final list = items(r).map(_norm).toList();
      if (!mounted) return;
      setState(() {
        _msgs.insertAll(0, list);
        _more = r is Map && r['has_more'] == true;
      });
    } catch (_) {}
  }

  void _markRead() {
    if (!svc.foreground) return;
    svc.markRead(dmWith: dm ? peerId : null);
  }

  void _merge(Map<String, dynamic> m) {
    final i = _msgs.indexWhere((x) =>
        '${x['id']}' == '${m['id']}' || (m['client_id'] != null && '${x['client_id']}' == '${m['client_id']}'));
    setState(() {
      if (i >= 0) {
        _msgs[i] = {..._msgs[i], ...m};
      } else {
        _msgs.add(m);
      }
    });
  }

  void _onEvent(Map<String, dynamic> e) {
    final m = e['m'] is Map ? Map<String, dynamic>.from(e['m'] as Map) : <String, dynamic>{};
    switch (e['t']) {
      case 'dm':
        if (!dm) return;
        final n = fromDm(m);
        if ('${n['user_id']}' != peerId && '${n['to']}' != peerId) return;
        _merge(n);
        if ('${n['user_id']}' == peerId) {
          setState(() => _typing = false);
          _markRead();
        }
        break;
      case 'chat':
        if (dm) return;
        final mine = '${m['user_id']}' == '${Api.user?['id']}';
        _merge({...m, 'status': mine ? 'sent' : null});
        if (!mine) {
          setState(() => _typing = false);
          _markRead();
        }
        break;
      case 'status':
        final ids = (m['ids'] is List ? m['ids'] as List : []).map((x) => '$x').toSet();
        final st = '${m['status']}';
        setState(() {
          for (var i = 0; i < _msgs.length; i++) {
            if (ids.contains('${_msgs[i]['id']}') && _msgs[i]['status'] != 'read') {
              _msgs[i] = {..._msgs[i], 'status': st};
            }
          }
        });
        break;
      case 'reaction':
        final id = '${m['id']}';
        final list = m['reactions'] is List ? m['reactions'] as List : [];
        final i = _msgs.indexWhere((x) => '${x['id']}' == id);
        if (i >= 0) setState(() => _msgs[i] = {..._msgs[i], 'reactions': list});
        break;
      case 'dmtyping':
        if (dm && '${m['from']}' == peerId) _showTyping();
        break;
      case 'chattyping':
        if (!dm && '${m['user_id']}' != '${Api.user?['id']}') _showTyping();
        break;
    }
  }

  void _showTyping() {
    setState(() => _typing = true);
    _typingOff?.cancel();
    _typingOff = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _typing = false);
    });
  }

  void _patch(String cid, Map<String, dynamic> change) {
    final i = _msgs.indexWhere((m) => '${m['client_id']}' == cid);
    if (i >= 0) setState(() => _msgs[i] = {..._msgs[i], ...change});
  }

  /// Shows the message at once, then sends it. The server's answer is the "sent" tick; no answer is a failure.
  Future<void> _deliver(Map<String, dynamic> p, {bool shown = false}) async {
    final cid = '${p['client_id']}';
    _pending[cid] = p;
    if (!shown) {
      setState(() => _msgs.add({
            'id': 'local-$cid',
            'client_id': cid,
            'user_id': Api.user?['id'],
            'name': Api.user?['name'],
            'avatar_url': Api.user?['avatar_url'],
            'body': p['body'] ?? '',
            'kind': p['kind'],
            'file_url': p['file_url'],
            'file_name': p['file_name'],
            'mime': p['mime'],
            'duration_ms': p['duration_ms'],
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'sending',
            'reply_to_id': p['reply_to_id'],
            'reply': _replySnap[cid],
            'reactions': [],
          }));
    } else {
      _patch(cid, {'status': 'sending'});
    }
    final saved = await svc.send(p, to: dm ? peerId : null);
    if (!mounted) return;
    if (saved == null || saved['id'] == null) {
      _patch(cid, {'status': 'failed'});
    } else {
      _pending.remove(cid);
      _replySnap.remove(cid);
      final n = _norm(saved);
      _patch(cid, {...n, 'status': dm ? (n['status'] ?? 'sent') : 'sent'});
    }
  }

  String _cid() {
    final id = '${Api.user?['id']}'.replaceAll('-', '');
    final tail = id.length > 8 ? id.substring(0, 8) : id;
    return '${DateTime.now().microsecondsSinceEpoch}-${_seq++}-$tail';
  }

  void _sendText() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    final cid = _cid();
    final reply = _takeReply(cid);
    setState(() {});
    _deliver({'body': t, 'kind': 'text', 'client_id': cid, if (reply != null) 'reply_to_id': reply});
  }

  /// The reply being written goes with the next message; returns its id (and remembers the quote to show meanwhile).
  String? _takeReply(String cid) {
    final r = _replyTo;
    if (r == null || '${r['id']}'.startsWith('local-')) {
      _replyTo = null;
      return null;
    }
    _replySnap[cid] = {
      'id': r['id'],
      'user_id': r['user_id'],
      'name': r['name'],
      'body': r['body'],
      'kind': r['kind'],
      'file_name': r['file_name'],
      'duration_ms': r['duration_ms'],
    };
    _replyTo = null;
    return '${r['id']}';
  }

  void _startReply(Map<String, dynamic> m) {
    if ('${m['id']}'.startsWith('local-') || '${m['kind']}' == 'call') return;
    HapticFeedback.selectionClick();
    setState(() => _replyTo = m);
    _input.requestFocus();
  }

  /// Taps the same emoji again to take it back. Shown at once; the server's answer is the truth.
  Future<void> _react(Map<String, dynamic> m, String emoji) async {
    final id = '${m['id']}';
    if (id.startsWith('local-') || '${m['kind']}' == 'call') return;
    final me = '${Api.user?['id']}';
    final old = (m['reactions'] is List ? m['reactions'] as List : []).whereType<Map>().toList();
    final had = old.where((r) => '${r['user_id']}' == me).map((r) => '${r['emoji']}').firstOrNull;
    final next = had == emoji ? null : emoji;
    void apply(List list) {
      final i = _msgs.indexWhere((x) => '${x['id']}' == id);
      if (i >= 0) setState(() => _msgs[i] = {..._msgs[i], 'reactions': list});
    }

    apply([
      ...old.where((r) => '${r['user_id']}' != me),
      if (next != null) {'user_id': me, 'emoji': next},
    ]);
    HapticFeedback.lightImpact();
    final ok = await svc.react(id, next);
    if (!ok && mounted) apply(old);
  }

  /// Press and hold on a message: pick an emoji, reply or copy.
  void _menu(Map<String, dynamic> m) {
    if ('${m['kind']}' == 'call' || '${m['id']}'.startsWith('local-')) return;
    HapticFeedback.mediumImpact();
    final me = '${Api.user?['id']}';
    final mineNow = (m['reactions'] is List ? m['reactions'] as List : [])
        .whereType<Map>()
        .where((r) => '${r['user_id']}' == me)
        .map((r) => '${r['emoji']}')
        .firstOrNull;
    const quick = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    const more = ['🔥', '🎉', '👏', '😍', '🤔', '👀', '✅', '💯', '😅', '🙌'];
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              for (final e in quick)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(c);
                    _react(m, e);
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: mineNow == e ? C.lilac.withAlpha(120) : Colors.transparent),
                    child: Text(e, style: const TextStyle(fontSize: 27)),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, children: [
              for (final e in more)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(c);
                    _react(m, e);
                  },
                  child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 24))),
                ),
            ]),
            const Divider(height: 18),
            ListTile(
              tileColor: Colors.transparent,
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(c);
                _startReply(m);
              },
            ),
            if ('${m['kind']}' == 'text' || ('${m['body'] ?? ''}').isNotEmpty)
              ListTile(
                tileColor: Colors.transparent,
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(c);
                  Clipboard.setData(ClipboardData(text: '${m['body'] ?? ''}'));
                  toast(context, 'Copied');
                },
              ),
          ]),
        ),
      ),
    );
  }

  void _onChanged(String _) {
    setState(() {});
    final now = DateTime.now();
    if (now.difference(_lastTyping).inMilliseconds < 1500) return;
    _lastTyping = now;
    svc.typing(to: dm ? peerId : null);
  }

  Future<void> _sendFile(String path, String name, {int? durationMs}) async {
    setState(() {
      _uploading = true;
      _err = '';
    });
    try {
      final up = await Api.upload(path, name);
      final cid = _cid();
      final reply = _takeReply(cid);
      await _deliver({
        'kind': up['kind'],
        'file_url': up['url'],
        'file_name': up['name'],
        'mime': up['mime'],
        if (durationMs != null) 'duration_ms': durationMs,
        'client_id': cid,
        if (reply != null) 'reply_to_id': reply,
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickImage(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, imageQuality: 88, maxWidth: 2200);
      if (x != null) await _sendFile(x.path, x.name);
    } catch (e) {
      if (mounted) setState(() => _err = 'Could not open the picture: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (x != null) await _sendFile(x.path, x.name);
    } catch (e) {
      if (mounted) setState(() => _err = 'Could not open the video: $e');
    }
  }

  Future<void> _pickDoc() async {
    try {
      final r = await FilePicker.platform.pickFiles();
      final f = r?.files.single;
      if (f != null && f.path != null) await _sendFile(f.path!, f.name);
    } catch (e) {
      if (mounted) setState(() => _err = 'Could not open the file: $e');
    }
  }

  void _attach() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(children: [
            _sheetItem(c, Icons.photo_outlined, 'Photo from gallery', C.blue, () => _pickImage(ImageSource.gallery)),
            _sheetItem(c, Icons.photo_camera_outlined, 'Take a photo', C.green, () => _pickImage(ImageSource.camera)),
            _sheetItem(c, Icons.videocam_outlined, 'Video', C.lilac, _pickVideo),
            _sheetItem(c, Icons.insert_drive_file_outlined, 'Document or any file', C.yellow, _pickDoc),
          ]),
        ),
      ),
    );
  }

  Widget _sheetItem(BuildContext c, IconData icon, String label, Color color, VoidCallback run) => ListTile(
        tileColor: Colors.transparent,
        leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: C.dark)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () {
          Navigator.pop(c);
          run();
        },
      );

  // ---- voice notes
  Future<void> _startRec() async {
    setState(() => _err = '');
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _err = 'Allow the microphone in app settings to send voice messages.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      _recStart = DateTime.now();
      _recTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _recStart != null) setState(() => _recMs = DateTime.now().difference(_recStart!).inMilliseconds);
      });
      setState(() {
        _recording = true;
        _recMs = 0;
      });
    } catch (e) {
      setState(() => _err = 'Could not start recording: $e');
    }
  }

  Future<void> _stopRec({required bool send}) async {
    _recTick?.cancel();
    final ms = _recStart == null ? 0 : DateTime.now().difference(_recStart!).inMilliseconds;
    setState(() => _recording = false);
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (path == null) return;
    if (!send || ms < 700) {
      try {
        await File(path).delete();
      } catch (_) {}
      return;
    }
    await _sendFile(path, 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a', durationMs: ms);
  }

  Future<void> _call(String kind) async {
    final err = await CallService.I.start(scope: 'dm', kind: kind, to: peerId, toName: '${widget.peer!['name']}');
    if (err != null && mounted) toast(context, err);
  }

  /// Group call: choose who to ring (everyone, or just some people).
  void _groupCall() {
    final members = svc.members;
    final chosen = <String>{};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final all = members.isNotEmpty && chosen.length == members.length;
          Future<void> go(String kind) async {
            Navigator.pop(c);
            final err = await CallService.I.start(
                scope: 'group', kind: kind, userIds: all ? null : chosen.toList(), all: all);
            if (err != null && mounted) toast(context, err);
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: SizedBox(
              height: MediaQuery.of(c).size.height * 0.62,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Start a group call', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Choose who to ring. Anyone else in the workspace can still join from the call banner.',
                    style: TextStyle(color: c.muted, fontSize: 12.5)),
                const SizedBox(height: 8),
                CheckboxListTile(
                  tileColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                  value: all,
                  title: const Text('Select everyone', style: TextStyle(fontWeight: FontWeight.w700)),
                  onChanged: (v) => set(() {
                    chosen
                      ..clear()
                      ..addAll(v == true ? members.map((m) => '${m['id']}') : <String>[]);
                  }),
                ),
                Expanded(
                  child: ListView(children: [
                    for (final m in members)
                      CheckboxListTile(
                        tileColor: Colors.transparent,
                        contentPadding: EdgeInsets.zero,
                        value: chosen.contains('${m['id']}'),
                        secondary: Avatar(id: '${m['id']}', name: '${m['name']}', url: m['avatar_url'] as String?, size: 38),
                        title: Text('${m['name']}'),
                        onChanged: (v) => set(() {
                          if (v == true) {
                            chosen.add('${m['id']}');
                          } else {
                            chosen.remove('${m['id']}');
                          }
                        }),
                      ),
                  ]),
                ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => go('voice'),
                        icon: const Icon(Icons.call_rounded),
                        label: Padding(padding: const EdgeInsets.all(12), child: Text('Voice${chosen.isEmpty ? '' : ' · ${chosen.length}'}'))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                        onPressed: () => go('video'),
                        icon: const Icon(Icons.videocam_rounded),
                        label: Padding(padding: const EdgeInsets.all(12), child: Text('Video${chosen.isEmpty ? '' : ' · ${chosen.length}'}'))),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _callBanner() {
    final calls = CallService.I.openGroupCalls;
    if (dm || calls.isEmpty || CallService.I.inCall) return const SizedBox.shrink();
    final c = calls.first;
    final n = ((c['participants'] as List?) ?? []).whereType<Map>().where((p) => '${p['state']}' == 'joined').length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        const Icon(Icons.graphic_eq_rounded, color: C.dark),
        const SizedBox(width: 10),
        Expanded(
            child: Text('Group ${c['kind']} call in progress · $n in the call',
                style: const TextStyle(color: C.dark, fontWeight: FontWeight.w700, fontSize: 13))),
        FilledButton(
          onPressed: () async {
            final err = await CallService.I.joinGroup(c, video: '${c['kind']}' == 'video');
            if (err != null && mounted) toast(context, err);
          },
          child: const Text('Join'),
        ),
      ]),
    );
  }

  Widget _header() {
    final online = dm && svc.online.contains(peerId);
    final name = dm ? '${widget.peer!['name']}' : 'Everyone';
    String sub;
    if (_typing) {
      sub = 'typing…';
    } else if (!svc.connected) {
      sub = 'Connecting…';
    } else if (dm) {
      sub = online ? 'Active now' : 'Offline';
    } else {
      sub = '${svc.online.length + 1} active';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(children: [
        RoundBtn(Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        if (dm)
          Avatar(id: peerId, name: name, url: widget.peer!['avatar_url'] as String?, size: 44, online: online)
        else
          Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: C.blue, shape: BoxShape.circle),
              child: const Icon(Icons.groups_rounded, color: C.dark)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dm ? name : '${svc.inbox?['team']?['name'] ?? 'Workspace'} · everyone',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(sub,
                style: TextStyle(
                    color: _typing || (online && svc.connected) ? const Color(0xFF4CC38A) : context.muted,
                    fontSize: 12.5)),
          ]),
        ),
        if (dm) ...[
          RoundBtn(Icons.call_outlined, onTap: () => _call('voice')),
          const SizedBox(width: 8),
          RoundBtn(Icons.videocam_outlined, onTap: () => _call('video')),
        ] else
          RoundBtn(Icons.videocam_outlined, onTap: _groupCall),
      ]),
    );
  }

  DateTime? _t(Map<String, dynamic> m) => DateTime.tryParse('${m['created_at']}')?.toLocal();

  bool _same(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return false;
    if ('${a['user_id']}' != '${b['user_id']}') return false;
    final x = _t(a), y = _t(b);
    if (x == null || y == null) return false;
    return y.difference(x).inMinutes.abs() < 4 && x.day == y.day;
  }

  /// "Today 01:12", "Yesterday 22:10", "12 Nov 18:20"
  String _stamp(DateTime d) {
    final n = DateTime.now();
    final diff = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Today $hm';
    if (diff == 1) return 'Yesterday $hm';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} $hm';
  }

  String? _statusText(Map<String, dynamic> m, {required bool isLastMine}) {
    final st = '${m['status']}';
    if (st == 'sending') return 'Sending…';
    if (!dm || !isLastMine) return null; // like Instagram: the status sits under your last message only
    if (st == 'read') return 'Seen';
    if (st == 'delivered') return 'Delivered';
    if (st == 'sent') return 'Sent';
    return null;
  }

  Widget _list() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final n = _msgs.length;
    final extra = (_more ? 1 : 0) + (_typing ? 1 : 0);
    if (n == 0 && !_more) {
      return Center(child: Text('No messages yet. Say hi 👋', style: TextStyle(color: context.muted)));
    }
    final myId = '${Api.user?['id']}';
    var lastMine = -1;
    for (var i = n - 1; i >= 0; i--) {
      if ('${_msgs[i]['user_id']}' == myId) {
        lastMine = i;
        break;
      }
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: n + extra,
      itemBuilder: (c, i) {
        // reversed list: 0 is the bottom (newest)
        if (_typing && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              if (dm)
                Avatar(id: peerId, name: '${widget.peer!['name']}', url: widget.peer!['avatar_url'] as String?, size: 28)
              else
                const SizedBox(width: 28),
              const SizedBox(width: 8),
              const _TypingDots(),
            ]),
          );
        }
        final k = i - (_typing ? 1 : 0);
        if (k >= n) {
          return Center(child: TextButton(onPressed: _older, child: const Text('Load earlier messages')));
        }
        final idx = n - 1 - k;
        final m = _msgs[idx];
        final prev = idx > 0 ? _msgs[idx - 1] : null;
        final next = idx < n - 1 ? _msgs[idx + 1] : null;
        final mine = '${m['user_id']}' == myId;
        final prevSame = _same(prev, m);
        final nextSame = _same(m, next);
        final d = _t(m);
        final pd = prev == null ? null : _t(prev);
        final showStamp = d != null && (pd == null || d.difference(pd).inMinutes > 25 || d.day != pd.day);
        final status = mine ? _statusText(m, isLastMine: idx == lastMine) : null;
        final failed = mine && '${m['status']}' == 'failed';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showStamp)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(child: Text(_stamp(d), style: TextStyle(fontSize: 11.5, color: context.muted, fontWeight: FontWeight.w600))),
            ),
          Padding(
            padding: EdgeInsets.only(top: prevSame ? 2 : 8),
            child: MsgBubble(
              key: ValueKey('${m['client_id'] ?? m['id']}'),
              m: m,
              mine: mine,
              joinedAbove: prevSame,
              joinedBelow: nextSame,
              showAvatar: !mine && !nextSame,
              showName: !dm && !mine && !prevSame,
              myId: myId,
              onReply: () => _startReply(m),
              onMenu: () => _menu(m),
              onLike: () => _react(m, '❤️'),
              onReact: (e) => _react(m, e),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: failed
                ? Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {
                        final p = _pending['${m['client_id']}'];
                        if (p != null) _deliver(p, shown: true);
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(top: 3, right: 4),
                        child: Text('Not delivered · Tap to retry',
                            style: TextStyle(color: Color(0xFFD64545), fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  )
                : (status == null
                    ? const SizedBox(width: double.infinity)
                    : Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3, right: 4),
                          child: Text(status, style: TextStyle(color: context.muted, fontSize: 11.5)),
                        ),
                      )),
          ),
        ]);
      },
    );
  }

  Widget _inputBar() {
    if (_recording) {
      final s = _recMs ~/ 1000;
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(30)),
        child: Row(children: [
          IconButton(onPressed: () => _stopRec(send: false), icon: const Icon(Icons.delete_outline, color: Color(0xFFD64545))),
          const Icon(Icons.fiber_manual_record, color: Color(0xFFD64545), size: 14),
          const SizedBox(width: 8),
          Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text('Recording…', style: TextStyle(color: context.muted)),
          const Spacer(),
          GestureDetector(
            onTap: () => _stopRec(send: true),
            child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: context.ink, shape: BoxShape.circle),
                child: Icon(Icons.send_rounded, color: context.bg, size: 20)),
          ),
        ]),
      );
    }
    final hasText = _text.text.trim().isNotEmpty;
    final reply = _replyTo;
    final bar = Container(
      margin: EdgeInsets.fromLTRB(12, reply == null ? 4 : 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(30)),
      child: Row(children: [
        IconButton(onPressed: _uploading ? null : _attach, icon: const Icon(Icons.attach_file_rounded)),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _input,
            onChanged: _onChanged,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _uploading ? 'Uploading…' : (dm ? 'Message ${'${widget.peer!['name']}'.split(' ').first}' : 'Message everyone'),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            ),
          ),
        ),
        GestureDetector(
          onTap: hasText ? _sendText : _startRec,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Container(
              key: ValueKey(hasText),
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: context.ink, shape: BoxShape.circle),
              child: Icon(hasText ? Icons.send_rounded : Icons.mic_rounded, color: context.bg, size: 21),
            ),
          ),
        ),
      ]),
    );
    if (reply == null) return bar;
    final mineReply = '${reply['user_id']}' == '${Api.user?['id']}';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Container(width: 3, height: 34, decoration: BoxDecoration(color: const Color(0xFF7B61FF), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Replying to ${mineReply ? 'yourself' : reply['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF7B61FF))),
              Text(previewOf(reply), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted, fontSize: 13)),
            ]),
          ),
          IconButton(onPressed: () => setState(() => _replyTo = null), icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      ),
      bar,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(),
          _callBanner(),
          Expanded(child: _list()),
          if (_uploading) const LinearProgressIndicator(minHeight: 2),
          if (_err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_err, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          _inputBar(),
        ]),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: theirBubble(context), borderRadius: BorderRadius.circular(20)),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: context.muted.withAlpha(((0.35 + 0.65 * ((_c.value * 3 - i).clamp(0, 1))) * 255).round()),
                    shape: BoxShape.circle),
              ),
          ]),
        ),
      );
}

Color theirBubble(BuildContext c) => c.isDark ? const Color(0xFF2A2A30) : const Color(0xFFE8E8EE);

const _mineGradient = LinearGradient(
  colors: [Color(0xFF7B61FF), Color(0xFF3F6DFF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// One message in the Instagram style: a bubble that fits its text, tight when the same person sends several,
/// their picture only beside the last one of a group.
class MsgBubble extends StatelessWidget {
  final Map<String, dynamic> m;
  final bool mine;
  final bool joinedAbove;
  final bool joinedBelow;
  final bool showAvatar;
  final bool showName;
  final String myId;
  final VoidCallback? onReply;
  final VoidCallback? onMenu;
  final VoidCallback? onLike;
  final void Function(String emoji)? onReact;
  const MsgBubble({
    super.key,
    required this.m,
    required this.mine,
    required this.joinedAbove,
    required this.joinedBelow,
    required this.showAvatar,
    required this.showName,
    this.myId = '',
    this.onReply,
    this.onMenu,
    this.onLike,
    this.onReact,
  });

  Widget _content(BuildContext c, Color fg, {required bool bare}) {
    final kind = '${m['kind']}';
    final url = '${m['file_url'] ?? ''}';
    final body = '${m['body'] ?? ''}';
    switch (kind) {
      case 'image':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => _PhotoPage(url: url))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(url, width: 220, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 120, child: Icon(Icons.broken_image_outlined))),
            ),
          ),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Text(body, style: TextStyle(color: fg, fontSize: 15)),
            ),
        ]);
      case 'video':
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(
            width: 220,
            height: 124,
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(18)),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 44),
              SizedBox(height: 4),
              Text('Play video', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        );
      case 'audio':
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          child: _VoiceBubble(url: url, durationMs: (m['duration_ms'] as num?)?.toInt() ?? 0, color: fg),
        );
      case 'file':
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: 200,
              child: Row(children: [
                Icon(Icons.insert_drive_file_rounded, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${m['file_name'] ?? 'Document'}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                Icon(Icons.download_rounded, color: fg, size: 18),
              ]),
            ),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(body, style: TextStyle(color: fg, fontSize: 15.5, height: 1.25)),
        );
    }
  }

  Widget _callLine(BuildContext context) {
    final body = '${m['body'] ?? ''}';
    final missed = body.startsWith('missed') || body.startsWith('declined');
    final video = body.contains(':video');
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: theirBubble(context), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(missed ? Icons.call_missed_rounded : (video ? Icons.videocam_rounded : Icons.call_rounded),
              size: 17, color: missed ? const Color(0xFFD64545) : context.ink),
          const SizedBox(width: 8),
          Text(callText(body), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: missed ? const Color(0xFFD64545) : context.ink)),
          const SizedBox(width: 8),
          Text(clockOf(m['created_at']), style: TextStyle(fontSize: 11, color: context.muted)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if ('${m['kind']}' == 'call') return _callLine(context);
    final kind = '${m['kind']}';
    final reply = m['reply'] is Map ? Map<String, dynamic>.from(m['reply'] as Map) : null;
    final gone = reply == null && m['reply_to_id'] != null;
    final bareMedia = reply == null && !gone && ((kind == 'image' && '${m['body'] ?? ''}'.isEmpty) || kind == 'video');
    final fg = mine ? Colors.white : context.ink;
    const big = Radius.circular(22);
    const small = Radius.circular(6);
    // the corner that touches the neighbouring bubble of the same person gets tighter
    final radius = BorderRadius.only(
      topLeft: !mine && joinedAbove ? small : big,
      bottomLeft: !mine && joinedBelow ? small : big,
      topRight: mine && joinedAbove ? small : big,
      bottomRight: mine && joinedBelow ? small : big,
    );
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
      child: Container(
        decoration: bareMedia
            ? null
            : BoxDecoration(
                color: mine ? null : theirBubble(context),
                gradient: mine ? _mineGradient : null,
                borderRadius: radius,
              ),
        child: ClipRRect(
          borderRadius: radius,
          child: reply == null && !gone
              ? _content(context, fg, bare: bareMedia)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  _quote(context, reply, fg),
                  _content(context, fg, bare: false),
                ]),
        ),
      ),
    );
    final reactions = (m['reactions'] is List ? m['reactions'] as List : []).whereType<Map>().toList();
    final row = Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          SizedBox(
            width: 28,
            child: showAvatar
                ? Avatar(id: '${m['user_id']}', name: '${m['name'] ?? '?'}', url: m['avatar_url'] as String?, size: 28)
                : null,
          ),
          const SizedBox(width: 8),
        ],
        Flexible(child: bubble),
      ],
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child)),
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (showName)
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 3),
            child: Text('${m['name'] ?? ''}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: context.muted)),
          ),
        _SwipeToReply(
          mine: mine,
          onReply: onReply,
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onLongPress: onMenu,
            onDoubleTap: onLike,
            child: row,
          ),
        ),
        if (reactions.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: mine ? 0 : 44, right: mine ? 10 : 0),
            child: Transform.translate(offset: const Offset(0, -7), child: _chips(context, reactions)),
          ),
      ]),
    );
  }

  /// The quoted message at the top of a reply.
  Widget _quote(BuildContext context, Map<String, dynamic>? reply, Color fg) {
    final accent = mine ? Colors.white : const Color(0xFF7B61FF);
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: (mine ? Colors.black : context.ink).withAlpha(mine ? 40 : 18),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: reply == null
          ? Text('Original message unavailable',
              style: TextStyle(color: fg.withAlpha(170), fontSize: 12.5, fontStyle: FontStyle.italic))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${'${reply['user_id']}' == myId ? 'You' : reply['name']}',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
              Text(previewOf(reply),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withAlpha(200), fontSize: 13)),
            ]),
    );
  }

  /// Emoji under the bubble, grouped with a count; yours is outlined, tap to take it back.
  Widget _chips(BuildContext context, List<Map> reactions) {
    final groups = <String, int>{};
    final mineSet = <String>{};
    for (final r in reactions) {
      final e = '${r['emoji']}';
      groups[e] = (groups[e] ?? 0) + 1;
      if ('${r['user_id']}' == myId) mineSet.add(e);
    }
    return Wrap(spacing: 4, children: [
      for (final g in groups.entries)
        GestureDetector(
          onTap: () => onReact?.call(g.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: mineSet.contains(g.key) ? const Color(0xFF7B61FF) : context.muted.withAlpha(60), width: mineSet.contains(g.key) ? 1.5 : 1),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(g.key, style: const TextStyle(fontSize: 14)),
              if (g.value > 1) ...[
                const SizedBox(width: 3),
                Text('${g.value}', style: TextStyle(fontSize: 11.5, color: context.muted, fontWeight: FontWeight.w700)),
              ],
            ]),
          ),
        ),
    ]);
  }
}

class _VoiceBubble extends StatefulWidget {
  final String url;
  final int durationMs;
  final Color color;
  const _VoiceBubble({required this.url, required this.durationMs, required this.color});
  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final AudioPlayer _p = AudioPlayer();
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration? _dur;
  StreamSubscription? _a, _b, _c, _d;

  @override
  void initState() {
    super.initState();
    _a = _p.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _b = _p.onPositionChanged.listen((d) {
      if (mounted) setState(() => _pos = d);
    });
    _c = _p.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    });
    _d = _p.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _pos = Duration.zero);
    });
  }

  @override
  void dispose() {
    _a?.cancel();
    _b?.cancel();
    _c?.cancel();
    _d?.cancel();
    _p.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = _dur ?? Duration(milliseconds: widget.durationMs);
    final prog = total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 200,
      child: Row(children: [
        GestureDetector(
          onTap: () async {
            if (_playing) {
              await _p.pause();
            } else {
              await _p.play(UrlSource(widget.url));
            }
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: widget.color.withAlpha(30), shape: BoxShape.circle),
            child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: widget.color),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: prog, minHeight: 4, backgroundColor: widget.color.withAlpha(40), color: widget.color),
            ),
            const SizedBox(height: 4),
            Text(_playing || _pos > Duration.zero ? _fmt(_pos) : _fmt(total),
                style: TextStyle(fontSize: 11, color: widget.color.withAlpha(170))),
          ]),
        ),
      ]),
    );
  }
}

class _PhotoPage extends StatelessWidget {
  final String url;
  const _PhotoPage({required this.url});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
        body: Center(child: InteractiveViewer(child: Image.network(url))),
      );
}

/// Drag a message sideways to reply to it (like WhatsApp and Instagram).
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final bool mine;
  final VoidCallback? onReply;
  const _SwipeToReply({required this.child, required this.mine, this.onReply});
  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dx = 0;
  bool _drag = false;
  bool _fired = false;
  static const _max = 64.0;

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() {
        _drag = true;
        _fired = false;
      }),
      onHorizontalDragUpdate: (d) {
        // swipe toward the middle of the screen: right for their messages, left for mine
        final v = widget.mine ? -d.delta.dx : d.delta.dx;
        final next = (_dx + v).clamp(0.0, _max);
        if (next >= _max * 0.85 && !_fired) {
          _fired = true;
          HapticFeedback.selectionClick();
        }
        setState(() => _dx = next);
      },
      onHorizontalDragEnd: (_) {
        final go = _dx >= _max * 0.85;
        setState(() {
          _drag = false;
          _dx = 0;
        });
        if (go) widget.onReply!();
      },
      onHorizontalDragCancel: () => setState(() {
        _drag = false;
        _dx = 0;
      }),
      child: Stack(alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft, children: [
        Opacity(
          opacity: (_dx / _max).clamp(0.0, 1.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.reply_rounded, color: context.muted, size: 22),
          ),
        ),
        AnimatedContainer(
          duration: _drag ? Duration.zero : const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(widget.mine ? -_dx : _dx, 0, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}
