import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';
import 'call_ui.dart';
import 'chat_service.dart';
import 'notify.dart';
import 'widget_sync.dart';

/// Firebase settings come in at build time (GitHub secrets). Without them, push is simply off and
/// everything else (live chat, in-app notifications) still works.
class PushConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get enabled =>
      apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
      apiKey: apiKey, appId: appId, messagingSenderId: senderId, projectId: projectId);
}

/// Runs when a push arrives while the app is closed or in the background.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage m) async {
  if (!PushConfig.enabled) return;
  try {
    await Firebase.initializeApp(options: PushConfig.options);
  } catch (_) {}
  final t = '${m.data['type']}';
  if (t == 'call_incoming') {
    await showIncomingCall(Map<String, dynamic>.from(m.data));
  } else if (t == 'call_cancel') {
    await endIncomingCall('${m.data['call_id']}');
  } else {
    await Notify.I.showPush(m.data);
  }
  // the widgets on the home screen should show the new message too
  try {
    await Api.init();
    await WidgetSync.refresh(only: {'unread', 'quickcall', 'call'});
  } catch (_) {}
}

class Push {
  static bool _started = false;
  static String? _token;

  /// Call once at start-up.
  static Future<void> bootstrap() async {
    if (!PushConfig.enabled) return;
    try {
      await Firebase.initializeApp(options: PushConfig.options);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    } catch (_) {}
  }

  /// Call after sign-in: asks permission and tells the server which phone to notify.
  static Future<void> register() async {
    if (!PushConfig.enabled || _started) return;
    _started = true;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      _token = await fm.getToken();
      if (_token != null) await Api.post('/notifications/devices', {'token': _token, 'platform': 'android'});
      fm.onTokenRefresh.listen((t) async {
        _token = t;
        try {
          await Api.post('/notifications/devices', {'token': t, 'platform': 'android'});
        } catch (_) {}
      });
      // while the app is open the live connection shows notifications itself
      FirebaseMessaging.onMessage.listen((m) {
        final t = '${m.data['type']}';
        if (t == 'call_incoming') {
          showIncomingCall(Map<String, dynamic>.from(m.data));
        } else if (t == 'call_cancel') {
          endIncomingCall('${m.data['call_id']}');
        } else if (!ChatService.I.connected) {
          Notify.I.showPush(m.data);
        }
      });
    } catch (_) {
      _started = false;
    }
  }

  /// Call on sign-out so this phone stops getting this person's notifications.
  static Future<void> unregister() async {
    final t = _token;
    if (t == null) return;
    try {
      await Api.post('/notifications/devices/remove', {'token': t});
    } catch (_) {}
    _started = false;
  }
}
