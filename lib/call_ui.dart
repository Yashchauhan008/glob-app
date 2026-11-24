import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

final Set<String> _shown = {};

CallKitParams callParams(Map<String, dynamic> d) {
  final kind = '${d['kind']}';
  final group = '${d['scope']}' == 'group';
  final avatar = '${d['from_avatar'] ?? ''}';
  return CallKitParams(
    id: '${d['call_id']}',
    nameCaller: '${d['from_name'] ?? 'Glob'}',
    appName: 'Glob',
    avatar: avatar.isEmpty || avatar == 'null' ? null : avatar,
    handle: group
        ? 'Group ${kind == 'video' ? 'video' : 'voice'} call${'${d['team_name'] ?? ''}'.isEmpty ? '' : ' · ${d['team_name']}'}'
        : (kind == 'video' ? 'Video call' : 'Voice call'),
    type: kind == 'video' ? 1 : 0,
    duration: 30000,
    extra: Map<String, dynamic>.from(d),
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#2F55FF',
      actionColor: '#30C36B',
      textColor: '#ffffff',
      incomingCallNotificationChannelName: 'Incoming calls',
      missedCallNotificationChannelName: 'Missed calls',
      isShowCallID: false,
      isShowFullLockedScreen: true,
      textAccept: 'Answer',
      textDecline: 'Decline',
    ),
  );
}

/// Rings: a full-screen call over the lock screen, or a notification with Answer / Decline when the phone is in use.
Future<void> showIncomingCall(Map<String, dynamic> d) async {
  final id = '${d['call_id']}';
  if (id.isEmpty || id == 'null' || _shown.contains(id)) return;
  _shown.add(id);
  try {
    await FlutterCallkitIncoming.showCallkitIncoming(callParams(d));
  } catch (_) {
    _shown.remove(id);
  }
}

/// Stops the ringing (answered elsewhere, cancelled, or nobody picked up).
Future<void> endIncomingCall(String id) async {
  _shown.remove(id);
  try {
    await FlutterCallkitIncoming.endCall(id);
  } catch (_) {}
}
