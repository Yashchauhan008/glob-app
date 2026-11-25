import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'api.dart';
import 'notify.dart';
import 'widget_sync.dart';

Map<String, dynamic> normMap(dynamic d) {
  try {
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(d)) as Map);
  } catch (_) {
    return {};
  }
}

/// A personal message from the server, in the same shape as a workspace one.
Map<String, dynamic> fromDm(Map<String, dynamic> m) => {
      'id': m['id'],
      'client_id': m['client_id'],
      'user_id': m['sender_id'],
      'name': m['sender_name'],
      'avatar_url': m['sender_avatar'],
      'body': m['body'] ?? '',
      'kind': m['kind'] ?? 'text',
      'file_url': m['file_url'],
      'file_name': m['file_name'],
      'mime': m['mime'],
      'duration_ms': m['duration_ms'],
      'created_at': m['created_at'],
      'status': m['status'],
      'to': m['recipient_id'],
      'reply_to_id': m['reply_to_id'],
      'reply': m['reply'],
      'reactions': m['reactions'] ?? [],
    };

/// The live connection: messages, delivery ticks, typing, who is online and notifications.
class ChatService extends ChangeNotifier with WidgetsBindingObserver {
  static final ChatService I = ChatService();

  sio.Socket? _s;
  bool connected = false;
  bool foreground = true;
  String? activeConv; // 'workspace' or a person's id: the chat on screen right now
  Map<String, dynamic>? inbox;
  Set<String> online = {};
  int notifUnread = 0;
  Timer? _debounce;
  Timer? _tick;
  String lastError = '';

  final _ev = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _ev.stream;

  int get unread {
    final ib = inbox;
    if (ib == null) return 0;
    var n = 0;
    final ws = ib['workspace'];
    if (ws is Map) n += (ws['unread'] as num?)?.toInt() ?? 0;
    final dms = ib['dms'];
    if (dms is List) {
      for (final d in dms) {
        if (d is Map) n += (d['unread'] as num?)?.toInt() ?? 0;
      }
    }
    return n;
  }

  List<Map<String, dynamic>> get members {
    final m = inbox?['members'];
    if (m is! List) return [];
    return m.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic>? personById(String id) {
    if ('${Api.user?['id']}' == id) return Api.user;
    for (final m in members) {
      if ('${m['id']}' == id) return m;
    }
    return null;
  }

  /// Starts everything: the live connection, and the counts that do not need it.
  /// Unread labels and notification counts load straight away and refresh every 20 seconds and whenever the app
  /// comes back, so they are right even when the live connection is slow or down.
  void start() {
    connect();
    loadInbox();
    loadNotifUnread();
    _tick ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (_s != null && !connected) _s!.connect();
      loadInbox();
      loadNotifUnread();
    });
  }

  void connect() {
    if (_s != null || Api.token == null || Api.teamId == null) return;
    WidgetsBinding.instance.addObserver(this);
    final s = sio.io(
      kApiUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': 'Bearer ${Api.token}', 'teamId': Api.teamId})
          .enableForceNew()
          .enableReconnection()
          .setReconnectionDelay(1500)
          .setReconnectionDelayMax(8000)
          .setTimeout(10000)
          .build(),
    );
    _s = s;
    s.onConnect((_) {
      connected = true;
      lastError = '';
      s.emit('presence:route', {'route': '/messages'});
      loadInbox();
      loadNotifUnread();
      notifyListeners();
    });
    s.onDisconnect((_) {
      connected = false;
      notifyListeners();
    });
    s.onConnectError((e) {
      connected = false;
      lastError = '$e';
      notifyListeners();
    });
    s.onError((e) {
      lastError = '$e';
    });
    s.on('presence:hello', (_) => s.emit('presence:route', {'route': '/messages'}));
    s.on('presence:roster', (d) {
      if (d is List) {
        online = d.whereType<Map>().map((e) => '${e['user_id']}').toSet();
        notifyListeners();
        WidgetSync.soon(only: {'online'});
      }
    });
    s.on('dm:message', (d) {
      _ev.add({'t': 'dm', 'm': normMap(d)});
      _soon();
      WidgetSync.soon(only: {'unread', 'quickcall'});
    });
    s.on('chat:message', (d) {
      _ev.add({'t': 'chat', 'm': normMap(d)});
      _soon();
      WidgetSync.soon(only: {'unread'});
    });
    s.on('dm:status', (d) {
      _ev.add({'t': 'status', 'm': normMap(d)});
      _soon();
    });
    s.on('message:reaction', (d) {
      _ev.add({'t': 'reaction', 'm': normMap(d)});
    });
    s.on('dm:typing', (d) => _ev.add({'t': 'dmtyping', 'm': normMap(d)}));
    s.on('chat:typing', (d) => _ev.add({'t': 'chattyping', 'm': normMap(d)}));
    s.on('call:incoming', (d) => _ev.add({'t': 'call_incoming', 'm': normMap(d)}));
    s.on('call:handled', (d) => _ev.add({'t': 'call_handled', 'm': normMap(d)}));
    s.on('call:state', (d) {
      _ev.add({'t': 'call_state', 'm': normMap(d)});
      WidgetSync.soon(only: {'call'});
    });
    s.on('notification', (d) {
      final n = normMap(d);
      loadNotifUnread();
      final data = n['data'] is Map ? Map<String, dynamic>.from(n['data'] as Map) : <String, dynamic>{};
      final type = '${n['type']}';
      final conv = type == 'dm' ? '${data['from_id']}' : (type == 'chat' ? 'workspace' : null);
      // no pop-up for the chat you are already looking at
      if (foreground && conv != null && activeConv == conv) return;
      Notify.I.show(
        id: '${n['id']}',
        channel: type == 'dm' || type == 'call' ? 'dm' : (type == 'chat' ? 'workspace' : 'general'),
        title: '${n['title'] ?? 'Glob'}',
        body: '${n['body'] ?? ''}',
        data: {
          'type': type == 'call' ? 'dm' : type,
          'team_id': '${n['team_id'] ?? ''}',
          'team_name': '${data['team_name'] ?? ''}',
          'from_id': '${data['from_id'] ?? ''}',
          'question_id': '${data['question_id'] ?? ''}',
        },
      );
    });
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), loadInbox);
  }

  Future<void> loadInbox() async {
    try {
      final r = await Api.get('/chat/inbox');
      inbox = normMap(r);
      final me = inbox?['me'];
      if (me is Map && Api.user != null) {
        Api.user!['avatar_url'] = me['avatar_url'];
        Api.user!['name'] = me['name'];
        Api.persistUser();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadNotifUnread() async {
    try {
      final r = await Api.get('/notifications');
      notifUnread = (r is Map ? (r['unread'] as num?)?.toInt() : null) ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  /// Sends over the live connection (the server's answer is the "sent" tick), or the ordinary way when offline.
  /// Returns the saved message, or null when it did not go through.
  Future<Map<String, dynamic>?> send(Map<String, dynamic> payload, {String? to}) async {
    final dm = to != null;
    if (connected && _s != null) {
      final c = Completer<Map<String, dynamic>?>();
      _s!.emitWithAck(dm ? 'dm:send' : 'chat:send', {...payload, if (dm) 'to': to}, ack: (r) {
        final m = normMap(r);
        if (!c.isCompleted) c.complete(m['ok'] == true ? normMap(m['message']) : null);
      });
      return c.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    }
    try {
      final r = await Api.post(dm ? '/chat/dm/$to' : '/chat', payload);
      return normMap(r);
    } catch (_) {
      return null;
    }
  }

  /// Sets (or with a null emoji, takes back) my reaction on a message. Returns false when it did not go through.
  Future<bool> react(String messageId, String? emoji) async {
    if (connected && _s != null) {
      final c = Completer<bool>();
      _s!.emitWithAck('message:react', {'id': messageId, 'emoji': emoji}, ack: (r) {
        if (!c.isCompleted) c.complete(normMap(r)['ok'] == true);
      });
      return c.future.timeout(const Duration(seconds: 8), onTimeout: () => false);
    }
    try {
      await Api.post('/chat/react', {'message_id': messageId, 'emoji': emoji});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The chat on screen was read. Uses an ordinary request (the live connection may be down) and clears the
  /// count on screen immediately, so the label never lingers.
  Future<void> markRead({String? dmWith}) async {
    _clearUnreadLocally(dmWith);
    try {
      await Api.post(dmWith != null ? '/chat/dm/$dmWith/read' : '/chat/read');
    } catch (_) {}
    loadInbox();
    loadNotifUnread();
  }

  void _clearUnreadLocally(String? dmWith) {
    final ib = inbox;
    if (ib == null) return;
    if (dmWith == null) {
      final ws = ib['workspace'];
      if (ws is Map) ws['unread'] = 0;
    } else {
      final dms = ib['dms'];
      if (dms is List) {
        for (final d in dms) {
          if (d is Map && d['user'] is Map && '${d['user']['id']}' == dmWith) d['unread'] = 0;
        }
      }
    }
    notifyListeners();
  }

  void typing({String? to}) {
    if (to != null) {
      _s?.emit('dm:typing', {'to': to});
    } else {
      _s?.emit('chat:typing');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && _s != null) {
      if (!connected) _s!.connect();
      loadInbox();
      loadNotifUnread();
      WidgetSync.soon();
    }
  }

  void disconnect() {
    _tick?.cancel();
    _tick = null;
    WidgetsBinding.instance.removeObserver(this);
    _s?.dispose();
    _s = null;
    connected = false;
    inbox = null;
    online = {};
    activeConv = null;
    notifUnread = 0;
    notifyListeners();
  }
}
