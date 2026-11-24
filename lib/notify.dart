import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api.dart';

/// Set when someone taps a notification; the main screen opens the right chat or page.
class NavIntent {
  static final ValueNotifier<Map<String, String>?> notifier = ValueNotifier(null);
  static Map<String, String>? get pending => notifier.value;
  static set pending(Map<String, String>? v) => notifier.value = v;
}

/// Runs when a notification button (Reply, Mark as read) is pressed while the app is closed.
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  await Notify.handleResponse(r);
}

/// Message notifications look like a messenger's: the sender's name, the message, and Reply / Mark as read buttons.
class Notify {
  static final Notify I = Notify._();
  Notify._();

  static final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
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
    await _p.initialize(
      settings,
      onDidReceiveNotificationResponse: (r) => handleResponse(r),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
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
      if (d?.didNotificationLaunchApp == true && d!.notificationResponse != null) {
        await handleResponse(d.notificationResponse!);
      }
    } catch (_) {}
  }

  /// A tap on the notification, or on one of its buttons.
  static Future<void> handleResponse(NotificationResponse r) async {
    final payload = r.payload;
    if (payload == null) return;
    Map<String, dynamic> d;
    try {
      d = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    } catch (_) {
      return;
    }
    final type = '${d['type']}';
    final team = '${d['team_id'] ?? ''}';
    final from = '${d['from_id'] ?? ''}';
    final action = r.actionId;

    if (action == 'reply' || action == 'read') {
      if (Api.token == null) return;
      if (team.isNotEmpty) Api.teamId = team;
      try {
        if (action == 'reply') {
          final text = (r.input ?? '').trim();
          if (text.isNotEmpty) {
            await Api.post(type == 'dm' ? '/chat/dm/$from' : '/chat', {
              'body': text,
              'kind': 'text',
              'client_id': 'n-${DateTime.now().microsecondsSinceEpoch}',
            });
          }
        } else {
          await Api.post(type == 'dm' ? '/chat/dm/$from/read' : '/chat/read');
        }
      } catch (_) {}
      final id = r.id;
      if (id != null) {
        try {
          await _p.cancel(id);
        } catch (_) {}
      }
      return;
    }
    NavIntent.pending = d.map((k, v) => MapEntry(k, '$v'));
  }

  Future<void> show({
    required String id,
    required String channel,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    await init();
    final c = _channel(channel);
    final type = data['type'] ?? '';
    final isMessage = type == 'dm' || type == 'chat';
    final isGroup = type == 'chat';
    final teamName = data['team_name'] ?? '';

    final AndroidNotificationDetails android;
    if (isMessage) {
      final sender = Person(name: title, key: data['from_id']);
      android = AndroidNotificationDetails(
        c.id,
        c.name,
        channelDescription: c.description,
        importance: c.importance,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        styleInformation: MessagingStyleInformation(
          const Person(name: 'You'),
          conversationTitle: isGroup && teamName.isNotEmpty ? teamName : null,
          groupConversation: isGroup,
          messages: [Message(body, DateTime.now(), sender)],
        ),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'reply',
            'Reply',
            inputs: <AndroidNotificationActionInput>[AndroidNotificationActionInput(label: 'Reply…')],
            showsUserInterface: false,
            cancelNotification: false,
          ),
          AndroidNotificationAction('read', 'Mark as read', showsUserInterface: false, cancelNotification: true),
        ],
      );
    } else {
      android = AndroidNotificationDetails(
        c.id,
        c.name,
        channelDescription: c.description,
        importance: c.importance,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
      );
    }
    // the same id replaces the earlier notification, so a busy chat is one entry, not thirty
    await _p.show(id.hashCode & 0x7fffffff, title, body, NotificationDetails(android: android), payload: jsonEncode(data));
  }

  /// From a push message (data fields are all strings).
  Future<void> showPush(Map<String, dynamic> d) => show(
        id: '${d['notification_id'] ?? DateTime.now().millisecondsSinceEpoch}',
        channel: '${d['channel'] ?? 'general'}',
        title: '${d['title'] ?? 'Glob'}',
        body: '${d['body'] ?? ''}',
        data: {
          'type': '${d['type'] ?? ''}',
          'team_id': '${d['team_id'] ?? ''}',
          'team_name': '${d['team_name'] ?? ''}',
          'from_id': '${d['from_id'] ?? ''}',
          'question_id': '${d['question_id'] ?? ''}',
        },
      );
}
