import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
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
  StreamSubscription? _sub;
  Timer? _typingOff;
  Timer? _recTick;
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
    _load();
  }

  @override
  void dispose() {
    if (svc.activeConv == convId) svc.activeConv = null;
    _sub?.cancel();
    _typingOff?.cancel();
    _recTick?.cancel();
    svc.removeListener(_r);
    _rec.dispose();
    _text.dispose();
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
    setState(() {});
    _deliver({'body': t, 'kind': 'text', 'client_id': _cid()});
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
      await _deliver({
        'kind': up['kind'],
        'file_url': up['url'],
        'file_name': up['name'],
        'mime': up['mime'],
        if (durationMs != null) 'duration_ms': durationMs,
        'client_id': _cid(),
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

  Widget _header() {
    final online = dm && svc.online.contains(peerId);
    final name = dm ? '${widget.peer!['name']}' : 'Everyone';
    final sub = _typing ? 'typing…' : (dm ? (online ? 'online' : 'offline') : '${svc.online.length + 1} online');
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
            Text(sub, style: TextStyle(color: _typing ? const Color(0xFF4CC38A) : context.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  String _day(DateTime d) {
    final n = DateTime.now();
    final t = DateTime(n.year, n.month, n.day);
    final diff = t.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Widget _list() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final n = _msgs.length;
    final extra = (_more ? 1 : 0) + (_typing ? 1 : 0);
    if (n == 0 && !_more) {
      return Center(child: Text('No messages yet. Say hi 👋', style: TextStyle(color: context.muted)));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: n + extra,
      itemBuilder: (c, i) {
        // reversed list: 0 is the bottom (newest)
        if (_typing && i == 0) {
          return const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.all(8), child: _TypingDots()));
        }
        final k = i - (_typing ? 1 : 0);
        if (k >= n) {
          return Center(child: TextButton(onPressed: _older, child: const Text('Load earlier messages')));
        }
        final idx = n - 1 - k;
        final m = _msgs[idx];
        final d = DateTime.tryParse('${m['created_at']}')?.toLocal();
        final prev = idx > 0 ? DateTime.tryParse('${_msgs[idx - 1]['created_at']}')?.toLocal() : null;
        final newDay = d != null && (prev == null || prev.day != d.day || prev.month != d.month || prev.year != d.year);
        final mine = '${m['user_id']}' == '${Api.user?['id']}';
        return Column(children: [
          if (newDay)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
                child: Text(_day(d), style: TextStyle(fontSize: 11, color: context.muted, fontWeight: FontWeight.w700)),
              ),
            ),
          MsgBubble(
            key: ValueKey('${m['client_id'] ?? m['id']}'),
            m: m,
            mine: mine,
            showName: !dm && !mine,
            onRetry: () {
              final p = _pending['${m['client_id']}'];
              if (p != null) _deliver(p, shown: true);
            },
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(30)),
      child: Row(children: [
        IconButton(onPressed: _uploading ? null : _attach, icon: const Icon(Icons.attach_file_rounded)),
        Expanded(
          child: TextField(
            controller: _text,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(18)),
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

/// One message: picture, video, voice note, document or text, with WhatsApp-style ticks.
class MsgBubble extends StatelessWidget {
  final Map<String, dynamic> m;
  final bool mine;
  final bool showName;
  final VoidCallback onRetry;
  const MsgBubble({super.key, required this.m, required this.mine, required this.showName, required this.onRetry});

  Widget _ticks(BuildContext c) {
    final s = '${m['status']}';
    const grey = Color(0x99000000);
    switch (s) {
      case 'sending':
        return const Icon(Icons.access_time, size: 13, color: grey);
      case 'sent':
        return const Icon(Icons.done, size: 16, color: grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: grey);
      case 'read':
        return const Icon(Icons.done_all, size: 16, color: Color(0xFF2F8FE8));
      case 'failed':
        return GestureDetector(
          onTap: onRetry,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 15, color: Color(0xFFD64545)),
            SizedBox(width: 2),
            Text('Retry', style: TextStyle(color: Color(0xFFD64545), fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _content(BuildContext c, Color fg) {
    final kind = '${m['kind']}';
    final url = '${m['file_url'] ?? ''}';
    final body = '${m['body'] ?? ''}';
    switch (kind) {
      case 'image':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => _PhotoPage(url: url))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(url, width: 230, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 230, height: 120, child: Icon(Icons.broken_image_outlined))),
            ),
          ),
          if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(body, style: TextStyle(color: fg))),
        ]);
      case 'video':
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(
            width: 230,
            height: 130,
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 46),
              SizedBox(height: 4),
              Text('Play video', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        );
      case 'audio':
        return _VoiceBubble(url: url, durationMs: (m['duration_ms'] as num?)?.toInt() ?? 0, color: fg);
      case 'file':
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.black.withAlpha(18), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.insert_drive_file_rounded, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${m['file_name'] ?? 'Document'}', maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('Tap to open', style: TextStyle(color: fg.withAlpha(150), fontSize: 11)),
                ]),
              ),
              Icon(Icons.download_rounded, color: fg, size: 18),
            ]),
          ),
        );
      default:
        return Text(body, style: TextStyle(color: fg, fontSize: 15, height: 1.3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = mine ? C.blue : context.cardBg;
    final fg = mine ? C.dark : context.ink;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(mine ? 22 : 6),
          bottomRight: Radius.circular(mine ? 6 : 22),
        ),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (showName)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('${m['name'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF7A6AE0))),
          ),
        _content(context, fg),
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(clockOf(m['created_at']), style: TextStyle(fontSize: 10.5, color: fg.withAlpha(140))),
            if (mine) ...[const SizedBox(width: 4), _ticks(context)],
          ]),
        ),
      ]),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              Avatar(id: '${m['user_id']}', name: '${m['name'] ?? '?'}', url: m['avatar_url'] as String?, size: 30),
              const SizedBox(width: 8),
            ],
            bubble,
            if (mine) ...[
              const SizedBox(width: 8),
              Avatar(id: '${m['user_id']}', name: '${m['name'] ?? '?'}',
                  url: (m['avatar_url'] ?? Api.user?['avatar_url']) as String?, size: 30),
            ],
          ],
        ),
      ),
    );
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
