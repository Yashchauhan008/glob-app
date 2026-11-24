import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Set when someone taps a notification; the main screen opens the right chat or page.
class NavIntent {
  static final ValueNotifier<Map<String, String>?> notifier = ValueNotifier(null);
  static Map<String, String>? get pending => notifier.value;
  static set pending(Map<String, String>? v) => notifier.value = v;
}

/// Notifications with proper labels: each kind has its own channel, so the phone's settings list them by name.
class Notify {
  static final Notify I = Notify._();
  Notify._();

  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _dm = AndroidNotificationChannel('dm', 'Direct messages',
      description: 'Personal messages sent to you', importance: Importance.high);
  static const _ws = AndroidNotificationChannel('workspace', 'Workspace chat',
      description: 'Messages in your workspace chat', importance: Importance.high);
  static const _gen = AndroidNotificationChannel('general', 'Updates',
      description: 'Answers to your questions and other updates', importance: Importance.defaultImportance);

  AndroidNotificationChannel _channel(String id) => id == 'dm' ? _dm : (id == 'workspace' ? _ws : _gen);

  Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _p.initialize(settings, onDidReceiveNotificationResponse: (r) => _tap(r.payload));
    final android = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final c in [_dm, _ws, _gen]) {
      await android?.createNotificationChannel(c);
    }
    _ready = true;
  }

  Future<void> requestPermission() async {
    await _p
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// The app was opened by tapping a notification while it was closed.
  Future<void> launchIntent() async {
    try {
      final d = await _p.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp == true) _tap(d!.notificationResponse?.payload);
    } catch (_) {}
  }

  void _tap(String? payload) {
    if (payload == null) return;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      NavIntent.pending = m.map((k, v) => MapEntry(k, '$v'));
    } catch (_) {}
  }

  Future<void> show({
    required String id,
    required String channel,
    required String label,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    await init();
    final c = _channel(channel);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        c.id,
        c.name,
        channelDescription: c.description,
        importance: c.importance,
        priority: Priority.high,
        subText: label,
        category: AndroidNotificationCategory.message,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
    // the same id replaces the earlier notification, so a busy chat is one entry, not thirty
    await _p.show(id.hashCode & 0x7fffffff, title, body, details, payload: jsonEncode(data));
  }

  /// From a push message (data fields are all strings).
  Future<void> showPush(Map<String, dynamic> d) => show(
        id: '${d['notification_id'] ?? DateTime.now().millisecondsSinceEpoch}',
        channel: '${d['channel'] ?? 'general'}',
        label: '${d['label'] ?? ''}',
        title: '${d['title'] ?? 'Glob'}',
        body: '${d['body'] ?? ''}',
        data: {
          'type': '${d['type'] ?? ''}',
          'team_id': '${d['team_id'] ?? ''}',
          'from_id': '${d['from_id'] ?? ''}',
          'question_id': '${d['question_id'] ?? ''}',
        },
      );
}
