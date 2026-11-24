import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart' as bg;
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart';
import 'api.dart';
import 'call_ui.dart';
import 'chat_service.dart';
import 'nav.dart';
import 'pages/call_screen.dart';

/// Calls: ringing, answering, and the call itself (voice, video, screen share, raised hands).
/// One call at a time. The server decides who is rung and who is in the call; this talks to it and to LiveKit.
class CallService extends ChangeNotifier {
  static final CallService I = CallService();

  Map<String, dynamic>? call; // the call I am in, or dialling
  List<Map<String, dynamic>> open = []; // calls going on in this workspace (the "join" banner)
  Room? room;
  EventsListener<RoomEvent>? _l;
  String status = 'idle'; // idle | connecting | connected
  String error = '';
  bool mic = false, cam = false, screen = false, handUp = false, speaker = false;
  Set<String> hands = {};
  DateTime? since;
  String title = '';
  final ValueNotifier<double> level = ValueNotifier(0); // 0..1: how loud anyone is right now (drives the aurora)
  final StreamController<String> _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;
  Timer? _lvl;
  StreamSubscription? _chatSub;
  StreamSubscription? _ckSub;
  bool _inited = false;
  String? _handled;

  bool get inCall => call != null;
  bool get connected => status == 'connected';
  String get callId => '${call?['id']}';

  /// Group calls going on that I am not in.
  List<Map<String, dynamic>> get openGroupCalls =>
      open.where((c) => '${c['scope']}' == 'group' && '${c['id']}' != (call == null ? '' : callId) && c['ended_at'] == null).toList();

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    _chatSub = ChatService.I.events.listen(_onChat);
    _ckSub = FlutterCallkitIncoming.onEvent.listen(_onCallkit);
    loadOpen();
    _resumeAccepted();
    try {
      if (!await FlutterCallkitIncoming.canUseFullScreenIntent()) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (_) {}
  }

  Future<void> loadOpen() async {
    try {
      final r = await Api.get('/calls/active');
      open = items(r);
      notifyListeners();
    } catch (_) {}
  }

  // ------------------------------------------------------------- what the server tells us

  void _onChat(Map<String, dynamic> e) {
    final m = e['m'] is Map ? Map<String, dynamic>.from(e['m'] as Map) : <String, dynamic>{};
    switch (e['t']) {
      case 'call_incoming':
        if (inCall) return;
        final c = m['call'] is Map ? Map<String, dynamic>.from(m['call'] as Map) : <String, dynamic>{};
        final from = m['from'] is Map ? Map<String, dynamic>.from(m['from'] as Map) : <String, dynamic>{};
        showIncomingCall({
          'call_id': c['id'],
          'kind': c['kind'],
          'scope': c['scope'],
          'team_id': c['team_id'],
          'team_name': ChatService.I.inbox?['team']?['name'] ?? '',
          'from_id': from['id'],
          'from_name': from['name'],
          'from_avatar': from['avatar_url'] ?? '',
        });
        break;
      case 'call_handled':
        endIncomingCall('${m['call_id']}');
        break;
      case 'call_state':
        open = [
          ...open.where((c) => '${c['id']}' != '${m['id']}'),
          if ('${m['status']}' != 'ended') m,
        ];
        if (inCall && '${m['id']}' == callId) {
          if ('${m['status']}' == 'ended') {
            _cleanup();
          } else {
            call = m;
            notifyListeners();
          }
        }
        notifyListeners();
        break;
    }
  }

  void _onCallkit(CallEvent? e) {
    if (e is CallEventActionCallAccept) {
      _accept('${e.callKitParams.id}', extra: e.callKitParams.extra);
    } else if (e is CallEventActionCallDecline) {
      _decline('${e.callKitParams.id}');
    }
  }

  /// The phone was woken by a call and the person pressed Answer before the app was running.
  Future<void> _resumeAccepted() async {
    try {
      for (final c in await FlutterCallkitIncoming.activeCalls()) {
        if (c.isAccepted) await _accept(c.id, extra: c.extra);
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------- actions

  Future<void> _accept(String id, {Map<String, dynamic>? extra}) async {
    if (_handled == id || inCall) return;
    _handled = id;
    final team = '${extra?['team_id'] ?? ''}';
    try {
      if (team.isNotEmpty && team != Api.teamId) {
        await Api.setTeam(team);
        ChatService.I.disconnect();
        ChatService.I.start();
      }
      final r = await Api.post('/calls/$id/accept');
      call = Map<String, dynamic>.from(r['call'] as Map);
      title = _titleOf(call!, extra);
      await _connect(Map<String, dynamic>.from(r['token'] as Map), video: '${call!['kind']}' == 'video', ringing: false);
      _openScreen();
    } catch (e) {
      error = '$e';
      await endIncomingCall(id);
      _cleanup();
    }
  }

  Future<void> _decline(String id) async {
    _handled = id;
    try {
      await Api.post('/calls/$id/decline');
    } catch (_) {}
    await endIncomingCall(id);
  }

  /// Starts a call. Returns an error message, or null when it went through (the call screen opens by itself).
  Future<String?> start({
    required String scope,
    required String kind,
    String? to,
    String? toName,
    List<String>? userIds,
    bool all = false,
  }) async {
    if (inCall) return 'You are already in a call';
    error = '';
    try {
      final r = await Api.post('/calls', {
        'scope': scope,
        'kind': kind,
        if (to != null) 'to': to,
        if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds,
        if (all) 'all': true,
      });
      call = Map<String, dynamic>.from(r['call'] as Map);
      title = scope == 'dm' ? (toName ?? 'Call') : 'Group call';
      await _connect(Map<String, dynamic>.from(r['token'] as Map), video: kind == 'video', ringing: true);
      _openScreen();
      return null;
    } catch (e) {
      _cleanup();
      return '$e';
    }
  }

  Future<String?> joinGroup(Map<String, dynamic> c, {bool video = false}) async {
    if (inCall) return 'You are already in a call';
    try {
      final r = await Api.post('/calls/${c['id']}/join');
      call = Map<String, dynamic>.from(r['call'] as Map);
      title = 'Group call';
      await _connect(Map<String, dynamic>.from(r['token'] as Map), video: video, ringing: true);
      _openScreen();
      return null;
    } catch (e) {
      _cleanup();
      return '$e';
    }
  }

  void _openScreen() {
    navKey.currentState?.push(MaterialPageRoute(builder: (_) => const CallScreen()));
  }

  String _titleOf(Map<String, dynamic> c, Map<String, dynamic>? extra) {
    if ('${c['scope']}' == 'group') return 'Group call';
    final me = '${Api.user?['id']}';
    final ps = c['participants'] is List ? c['participants'] as List : [];
    for (final p in ps) {
      if (p is Map && '${p['user_id']}' != me) return '${p['name']}';
    }
    return '${extra?['from_name'] ?? 'Call'}';
  }

  // ------------------------------------------------------------- the call itself

  Future<void> _connect(Map<String, dynamic> t, {required bool video, required bool ringing}) async {
    status = 'connecting';
    notifyListeners();
    final r = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
    r.addListener(notifyListeners);
    _l = r.createListener()
      ..on<RoomDisconnectedEvent>((_) => _lost())
      ..on<ParticipantAttributesChanged>((_) => _readHands())
      ..on<LocalTrackUnpublishedEvent>((_) {
        if (screen && !(r.localParticipant?.isScreenShareEnabled() ?? false)) {
          screen = false;
          notifyListeners();
        }
      });
    try {
      await r.connect('${t['url']}', '${t['token']}');
    } catch (e) {
      r.removeListener(notifyListeners);
      await _l?.dispose();
      _l = null;
      status = 'idle';
      rethrow;
    }
    room = r;
    status = 'connected';
    since = DateTime.now();
    try {
      await r.localParticipant?.setMicrophoneEnabled(true);
      mic = true;
    } catch (_) {
      error = 'Microphone unavailable. Allow it in app settings.';
    }
    if (video) {
      try {
        await r.localParticipant?.setCameraEnabled(true);
        cam = true;
      } catch (_) {
        error = 'Camera unavailable. Allow it in app settings.';
      }
    }
    speaker = video;
    try {
      await Hardware.instance.setSpeakerphoneOn(speaker);
    } catch (_) {}
    _lvl = Timer.periodic(const Duration(milliseconds: 90), (_) => _tickLevel());
    // tells Android this is a live call, so the microphone keeps working with the screen off
    final id = callId;
    try {
      if (ringing) {
        await FlutterCallkitIncoming.startCall(CallKitParams(
          id: id,
          nameCaller: title,
          appName: 'Glob',
          handle: video ? 'Video call' : 'Voice call',
          type: video ? 1 : 0,
        ));
      }
      await FlutterCallkitIncoming.setCallConnected(id);
    } catch (_) {}
    notifyListeners();
  }

  void _tickLevel() {
    final r = room;
    if (r == null) return;
    var target = r.localParticipant?.audioLevel ?? 0;
    for (final p in r.remoteParticipants.values) {
      if (p.audioLevel > target) target = p.audioLevel;
    }
    final goal = (target * 2.4).clamp(0.0, 1.0);
    level.value = level.value + (goal - level.value) * 0.3;
  }

  void _readHands() {
    final r = room;
    if (r == null) return;
    final now = <String>{};
    final all = <Participant>[if (r.localParticipant != null) r.localParticipant!, ...r.remoteParticipants.values];
    for (final p in all) {
      if (p.attributes['hand'] == '1') now.add(p.identity);
    }
    for (final id in now) {
      if (!hands.contains(id) && id != r.localParticipant?.identity) {
        final p = r.remoteParticipants.values.where((x) => x.identity == id).toList();
        _toasts.add('${p.isNotEmpty && p.first.name.isNotEmpty ? p.first.name : 'Someone'} raised a hand');
      }
    }
    hands = now;
    notifyListeners();
  }

  Future<void> toggleMic() async {
    final lp = room?.localParticipant;
    if (lp == null) return;
    try {
      await lp.setMicrophoneEnabled(!mic);
      mic = !mic;
    } catch (_) {
      error = 'Microphone unavailable. Allow it in app settings.';
    }
    notifyListeners();
  }

  Future<void> toggleCam() async {
    final lp = room?.localParticipant;
    if (lp == null) return;
    try {
      await lp.setCameraEnabled(!cam);
      cam = !cam;
    } catch (_) {
      error = 'Camera unavailable. Allow it in app settings.';
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    try {
      await Hardware.instance.setSpeakerphoneOn(speaker);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggleHand() async {
    final lp = room?.localParticipant;
    if (lp == null) return;
    handUp = !handUp;
    notifyListeners();
    try {
      await lp.setAttributes({'hand': handUp ? '1' : ''});
    } catch (_) {
      handUp = !handUp;
      notifyListeners();
    }
  }

  /// Shares the phone's screen. Android needs the person's permission and a notification while it runs.
  Future<void> toggleScreen() async {
    final lp = room?.localParticipant;
    if (lp == null) return;
    try {
      if (!screen) {
        final ok = await webrtc.Helper.requestCapturePermission();
        if (!ok) return;
        const cfg = bg.FlutterBackgroundAndroidConfig(
          notificationTitle: 'Glob',
          notificationText: 'You are sharing your screen',
          notificationImportance: bg.AndroidNotificationImportance.normal,
          notificationIcon: bg.AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        );
        if (await bg.FlutterBackground.initialize(androidConfig: cfg) && !bg.FlutterBackground.isBackgroundExecutionEnabled) {
          await bg.FlutterBackground.enableBackgroundExecution();
        }
        await lp.setScreenShareEnabled(true);
        screen = true;
      } else {
        await lp.setScreenShareEnabled(false);
        screen = false;
        try {
          if (bg.FlutterBackground.isBackgroundExecutionEnabled) await bg.FlutterBackground.disableBackgroundExecution();
        } catch (_) {}
      }
    } catch (e) {
      screen = false;
      error = 'Could not share the screen: $e';
    }
    notifyListeners();
  }

  Future<void> hangUp() async {
    final id = call == null ? null : callId;
    _cleanup();
    if (id != null) {
      await endIncomingCall(id);
      try {
        await Api.post('/calls/$id/leave');
      } catch (_) {}
    }
  }

  /// The connection to the call was lost without anyone pressing hang up.
  void _lost() {
    final id = call == null ? null : callId;
    _cleanup();
    if (id != null) {
      endIncomingCall(id);
      Api.post('/calls/$id/leave').catchError((_) {});
    }
  }

  void _cleanup() {
    _lvl?.cancel();
    _lvl = null;
    final r = room;
    room = null;
    _l?.dispose();
    _l = null;
    if (r != null) {
      r.removeListener(notifyListeners);
      r.disconnect();
    }
    if (screen) {
      try {
        bg.FlutterBackground.disableBackgroundExecution();
      } catch (_) {}
    }
    call = null;
    status = 'idle';
    mic = cam = screen = handUp = speaker = false;
    hands = {};
    since = null;
    level.value = 0;
    _handled = null;
    notifyListeners();
  }
}
