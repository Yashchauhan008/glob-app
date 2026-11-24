import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../api.dart';
import '../call.dart';
import '../chat_service.dart';
import 'common.dart';

class CallTab extends StatefulWidget {
  const CallTab({super.key});
  @override
  State<CallTab> createState() => _CallTabState();
}

class _CallTabState extends State<CallTab> {
  final call = CallService.I;
  Map<dynamic, dynamic> _live = {};

  @override
  void initState() {
    super.initState();
    call.addListener(_r);
    _loadLive();
  }

  @override
  void dispose() {
    call.removeListener(_r);
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLive() async {
    try {
      final r = await Api.get('/voice/status');
      if (mounted && r is Map) setState(() => _live = r);
    } catch (_) {}
  }

  VideoTrack? _video(Participant p) {
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t is VideoTrack && !pub.muted) return t;
    }
    return null;
  }

  Widget _person(Participant p, {bool me = false}) {
    final v = _video(p);
    final name = (p.name.isNotEmpty ? p.name : p.identity) + (me ? ' (you)' : '');
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: p.isSpeaking ? Colors.green : Colors.transparent, width: 2),
      ),
      child: Column(children: [
        if (v != null)
          SizedBox(height: 180, width: double.infinity, child: VideoTrackRenderer(v))
        else
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Avatar(
                  id: p.identity,
                  name: name,
                  url: ChatService.I.personById(p.identity)?['avatar_url'] as String?,
                  size: 60)),
        Padding(padding: const EdgeInsets.all(10), child: Text(name)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!call.connected) {
      final people = (_live['participants'] is List) ? _live['participants'] as List : [];
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.headset_mic, size: 64),
            const SizedBox(height: 12),
            Text(
                people.isEmpty
                    ? 'Nobody is in the team call right now.'
                    : 'In the call: ${people.map((p) => p['name']).join(', ')}',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: call.status == 'connecting' ? null : () => call.join(),
              icon: const Icon(Icons.call),
              label: Text(call.status == 'connecting' ? 'Connecting…' : 'Join voice'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: call.status == 'connecting' ? null : () => call.join(video: true),
              icon: const Icon(Icons.videocam),
              label: const Text('Join with video'),
            ),
            TextButton(onPressed: _loadLive, child: const Text('Refresh')),
            if (call.error.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(call.error,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center)),
          ]),
        ),
      );
    }
    final room = call.room!;
    final remotes = room.remoteParticipants.values.toList();
    return Column(children: [
      if (call.error.isNotEmpty)
        Padding(
            padding: const EdgeInsets.all(8),
            child: Text(call.error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (room.localParticipant != null) _person(room.localParticipant!, me: true),
          for (final p in remotes) _person(p),
          if (remotes.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Waiting for others to join…'))),
        ]),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton.filledTonal(
                onPressed: call.toggleMic,
                icon: Icon(call.mic ? Icons.mic : Icons.mic_off)),
            IconButton.filledTonal(
                onPressed: call.toggleCam,
                icon: Icon(call.cam ? Icons.videocam : Icons.videocam_off)),
            IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.red),
                onPressed: call.leave,
                icon: const Icon(Icons.call_end)),
          ]),
        ),
      ),
    ]);
  }
}
