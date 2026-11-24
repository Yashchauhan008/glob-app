import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../api.dart';
import '../call_service.dart';
import '../chat_service.dart';
import '../theme.dart';
import 'common.dart';

/// The call screen: voices make a glow along the top; mute, camera, speaker, screen share, raise hand, hang up.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  final svc = CallService.I;
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  StreamSubscription<String>? _toastSub;
  Timer? _clock;
  String? _toast;
  Timer? _toastOff;
  bool _wasInCall = true;

  @override
  void initState() {
    super.initState();
    svc.addListener(_r);
    _toastSub = svc.toasts.listen((t) {
      setState(() => _toast = t);
      _toastOff?.cancel();
      _toastOff = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _toast = null);
      });
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    svc.removeListener(_r);
    _toastSub?.cancel();
    _toastOff?.cancel();
    _clock?.cancel();
    _drift.dispose();
    super.dispose();
  }

  void _r() {
    if (!mounted) return;
    if (!svc.inCall && _wasInCall) {
      _wasInCall = false;
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  String get _timer {
    final s = svc.since;
    if (s == null) return '';
    final d = DateTime.now().difference(s);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$sec' : '$m:$sec';
  }

  List<Participant> get _people {
    final r = svc.room;
    if (r == null) return [];
    return [if (r.localParticipant != null) r.localParticipant!, ...r.remoteParticipants.values];
  }

  VideoTrack? _video(Participant p, {required bool screen}) {
    for (final pub in p.videoTrackPublications) {
      if (pub.isScreenShare != screen) continue;
      final t = pub.track;
      if (t is VideoTrack && !pub.muted) return t;
    }
    return null;
  }

  Widget _tile(Participant p, {double? size, bool big = false}) {
    final isMe = p.identity == '${Api.user?['id']}';
    final name = isMe ? 'You' : (p.name.isNotEmpty ? p.name : 'Guest');
    final v = _video(p, screen: false);
    final info = ChatService.I.personById(p.identity);
    final Map<String, dynamic>? who = isMe ? Api.user : info;
    final dynamic rawUrl = who == null ? null : who['avatar_url'];
    final String? url = rawUrl is String ? rawUrl : null;
    final hand = p.attributes['hand'] == '1';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E3A),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.isSpeaking ? const Color(0xFF4CC38A) : Colors.white12, width: p.isSpeaking ? 3 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (v != null)
          VideoTrackRenderer(v, fit: VideoViewFit.cover)
        else
          Center(child: Avatar(id: p.identity, name: name, url: url, size: big ? 110 : 64)),
        Positioned(
          left: 10,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              if (!p.isMicrophoneEnabled()) ...[
                const SizedBox(width: 5),
                const Icon(Icons.mic_off, color: Colors.white70, size: 13),
              ],
            ]),
          ),
        ),
        if (hand)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(color: Color(0xFFF8E58F), shape: BoxShape.circle),
              child: const Icon(Icons.back_hand_rounded, size: 17, color: C.dark),
            ),
          ),
      ]),
    );
  }

  Widget _stage() {
    final people = _people;
    final c = svc.call;
    // not connected yet, or alone: show who is being called
    if (people.isEmpty || (people.length == 1 && !svc.cam && !svc.screen)) {
      final others = ((c?['participants'] as List?) ?? [])
          .whereType<Map>()
          .where((p) => '${p['user_id']}' != '${Api.user?['id']}' && '${p['state']}' != 'declined' && '${p['state']}' != 'missed' && '${p['state']}' != 'busy')
          .toList();
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (others.length == 1 || '${c?['scope']}' == 'dm')
            Avatar(
                id: others.isEmpty ? '' : '${others.first['user_id']}',
                name: svc.title,
                url: others.isEmpty ? null : others.first['avatar_url'] as String?,
                size: 132)
          else
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
              for (final p in others.take(8)) Avatar(id: '${p['user_id']}', name: '${p['name']}', url: p['avatar_url'] as String?, size: 64),
            ]),
          const SizedBox(height: 18),
          Text(svc.title, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(svc.connected ? 'Ringing…' : 'Connecting…', style: const TextStyle(color: Colors.white70, fontSize: 15)),
        ]),
      );
    }

    // someone is sharing their screen: it takes the stage, people go in a strip
    Participant? presenter;
    for (final p in people) {
      if (_video(p, screen: true) != null) {
        presenter = p;
        break;
      }
    }
    if (presenter != null) {
      final track = _video(presenter, screen: true)!;
      return Column(children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(22)),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              VideoTrackRenderer(track, fit: VideoViewFit.contain),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                      presenter.identity == '${Api.user?['id']}' ? 'You are presenting' : '${presenter.name} is presenting',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [for (final p in people) Padding(padding: const EdgeInsets.only(right: 8), child: _tile(p, size: 92))]),
        ),
      ]);
    }

    final anyVideo = people.any((p) => _video(p, screen: false) != null);
    if (!anyVideo && people.length <= 2) {
      // voice call: big avatars
      return Center(
        child: Wrap(spacing: 18, runSpacing: 18, alignment: WrapAlignment.center, children: [
          for (final p in people) SizedBox(width: 150, height: 150, child: _tile(p, big: true)),
        ]),
      );
    }
    final cols = people.length <= 1 ? 1 : (people.length <= 4 ? 2 : 3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: LayoutBuilder(builder: (c, box) {
        final rows = (people.length / cols).ceil();
        final w = (box.maxWidth - (cols - 1) * 8) / cols;
        final h = ((box.maxHeight - (rows - 1) * 8) / rows).clamp(80.0, 420.0);
        return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          for (final p in people) SizedBox(width: w, height: h, child: _tile(p)),
        ]);
      }),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap, {bool on = false, Color? bg, Color? fg, String? tip}) => Tooltip(
        message: tip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: bg ?? (on ? Colors.white : Colors.white24), shape: BoxShape.circle),
            child: Icon(icon, color: fg ?? (on ? C.dark : Colors.white), size: 24),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = svc.call;
    final video = '${c?['kind']}' == 'video';
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E1C),
      body: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF15173A), Color(0xFF0A0B16)]),
            ),
          ),
        ),
        // the glow along the top, alive with every voice
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 300,
          child: IgnorePointer(
            child: CustomPaint(painter: _AuroraPainter(_drift, svc.level)),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                  tooltip: 'Back to the app (the call keeps going)',
                ),
                Expanded(
                  child: Column(children: [
                    Text(svc.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(svc.connected ? (svc.room != null && svc.room!.remoteParticipants.isEmpty ? 'Waiting…' : _timer) : 'Connecting…',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ]),
                ),
                const SizedBox(width: 48),
              ]),
            ),
            if (_toast != null)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.back_hand_rounded, size: 17, color: Color(0xFFE0A800)),
                  const SizedBox(width: 8),
                  Text(_toast!, style: const TextStyle(color: C.dark, fontWeight: FontWeight.w700, fontSize: 13.5)),
                ]),
              ),
            Expanded(child: _stage()),
            if (svc.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(svc.error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(34)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _btn(svc.mic ? Icons.mic_rounded : Icons.mic_off_rounded, svc.toggleMic, on: svc.mic, tip: svc.mic ? 'Mute' : 'Unmute'),
                  _btn(svc.cam ? Icons.videocam_rounded : Icons.videocam_off_rounded, svc.toggleCam, on: svc.cam, tip: 'Camera'),
                  _btn(svc.speaker ? Icons.volume_up_rounded : Icons.hearing_rounded, svc.toggleSpeaker, on: svc.speaker, tip: 'Speaker'),
                  _btn(svc.screen ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded, svc.toggleScreen, on: svc.screen, tip: 'Share screen'),
                  _btn(Icons.back_hand_rounded, svc.toggleHand, on: svc.handUp, bg: svc.handUp ? const Color(0xFFF8E58F) : null, tip: 'Raise hand'),
                  _btn(Icons.call_end_rounded, () => svc.hangUp(), bg: const Color(0xFFE5484D), fg: Colors.white, tip: 'Hang up'),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // video flag kept for future layouts
  // ignore: unused_element
  bool get _isVideo => '${svc.call?['kind']}' == 'video';
}

/// Three soft blobs of colour that drift along the top edge and swell with the loudest voice in the call.
class _AuroraPainter extends CustomPainter {
  final Animation<double> drift;
  final ValueListenable<double> level;
  _AuroraPainter(this.drift, this.level) : super(repaint: Listenable.merge([drift, level]));

  static const _colors = [Color(0xFF6C5BFF), Color(0xFF29D3C2), Color(0xFFFF7AC6)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = drift.value * 2 * math.pi;
    final l = level.value.clamp(0.0, 1.0);
    for (var i = 0; i < 3; i++) {
      final cx = size.width * (0.16 + 0.34 * i) + math.sin(t + i * 2.1) * size.width * 0.09;
      final h = 120 + 230 * l + math.sin(t * 1.3 + i) * 14;
      final w = size.width * (0.42 + 0.12 * l);
      final rect = Rect.fromCenter(center: Offset(cx, -10), width: w * 2, height: h * 2);
      final a = (0.30 + 0.62 * l).clamp(0.0, 1.0);
      final paint = Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [_colors[i].withAlpha((a * 255).round()), _colors[i].withAlpha(0)],
        ).createShader(rect);
      canvas.drawOval(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => false;
}
