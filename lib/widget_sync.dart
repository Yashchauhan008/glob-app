import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'api.dart';
import 'chat_service.dart';
import 'pages/common.dart';

const _pkg = 'pro.yashchauhan.glob_app';

/// A tap on a widget that wants to do something once the app is open ("New task", "New idea").
class WidgetActions {
  static String? pending;
  static bool take(String key) {
    if (pending == key) {
      pending = null;
      return true;
    }
    return false;
  }
}

/// Runs in the background when something on a widget is pressed without opening the app (ticking a task).
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  if (Api.token == null) return;
  try {
    if (uri.host == 'task' && uri.pathSegments.length >= 2 && uri.pathSegments[1] == 'done') {
      await Api.patch('/todos/${uri.pathSegments[0]}', {'done': true});
      await WidgetSync.refresh(only: {'tasks', 'nextup', 'pulse'});
    }
  } catch (_) {}
}

/// Fills the home-screen widgets: fetches what each one shows, saves it as JSON, and asks Android to redraw.
/// The native side (android_overlay/kotlin/GlobWidgets.kt) only draws what is saved here.
class WidgetSync {
  static Timer? _timer;
  static Timer? _debounce;
  static bool _busy = false;
  static const _blue = '#BFE4EE', _green = '#D0E8B5', _yellow = '#F8E58F', _coral = '#F0A48C', _lilac = '#D9CCF2', _pink = '#F9D2E4', _grey = '#E4E4E8';

  /// Refresh now, then every 5 minutes while the app is alive.
  static void start() {
    _timer?.cancel();
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
  }

  /// A short delay lets a burst of changes become one refresh.
  static void soon({Set<String>? only}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => refresh(only: only));
  }

  static void stop() {
    _timer?.cancel();
    _debounce?.cancel();
  }

  /// Signed out: widgets ask the person to open the app.
  static Future<void> clear() async {
    stop();
    const names = {
      'unread': 'Messages', 'tasks': "Today's tasks", 'quickcall': 'Quick call', 'nextup': 'Next up', 'call': 'Call in progress',
      'pulse': 'Team pulse', 'ideas': 'Ideas', 'online': "Who's online", 'crm': 'CRM follow-ups', 'products': 'Products',
    };
    for (final e in names.entries) {
      await _put(e.key, {'title': e.value, 'count': '', 'empty': 'Open Glob and sign in', 'rows': [], 'people': [], 'tiles': []});
    }
  }

  static Future<dynamic> _try(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _put(String key, Map<String, dynamic> data) async {
    try {
      await HomeWidget.saveWidgetData<String>('w_$key', jsonEncode(data));
      final cls = const {
        'unread': 'UnreadWidget', 'tasks': 'TasksWidget', 'quickcall': 'QuickCallWidget', 'nextup': 'NextUpWidget',
        'call': 'CallWidget', 'pulse': 'PulseWidget', 'ideas': 'IdeasWidget', 'online': 'OnlineWidget', 'crm': 'CrmWidget',
        'products': 'ProductsWidget',
      }[key];
      if (cls != null) await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.$cls');
    } catch (_) {}
  }

  /// A person's photo saved on the phone (the widget draws it from a file). Refetched every 12 hours.
  static Future<String?> _photo(String dir, String id, dynamic url) async {
    final u = '$url';
    if (url == null || u.isEmpty || u == 'null') return null;
    try {
      final f = File('$dir/wa_$id.img');
      if (await f.exists() && DateTime.now().difference(await f.lastModified()).inHours < 12) return f.path;
      final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty && r.bodyBytes.length < 2000000) {
        await f.writeAsBytes(r.bodyBytes);
        return f.path;
      }
    } catch (_) {}
    return null;
  }

  static String _hex(String id) {
    final c = avatarColor(id);
    String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${h(c.r)}${h(c.g)}${h(c.b)}';
  }

  static String _first(String s) => s.trim().isEmpty ? '?' : s.trim().characters.first.toUpperCase();

  static const _month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  static bool _today(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  static String _when(DateTime d, {bool time = true}) {
    if (_today(d)) return time ? _hm(d) : 'Today';
    final n = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
    if (diff == 1) return 'Tomorrow';
    if (diff > 1 && diff < 7) return _wd[d.weekday - 1];
    return '${d.day} ${_month[d.month - 1]}';
  }

  static Future<void> refresh({Set<String>? only}) async {
    if (Api.token == null || Api.teamId == null || _busy) return;
    _busy = true;
    try {
      bool want(String k) => only == null || only.contains(k);
      final dir = (await getApplicationSupportDirectory()).path;

      // fetch what is needed, all at once
      final needInbox = want('unread') || want('quickcall') || want('online');
      final needTodos = want('tasks') || want('nextup');
      final res = await Future.wait<dynamic>([
        needInbox ? _try(Api.get('/chat/inbox')) : Future.value(null),
        needTodos ? _try(Api.get('/todos?filter=open')) : Future.value(null),
        want('nextup') ? _try(Api.get('/events?from=${Uri.encodeComponent(DateTime.now().toUtc().toIso8601String())}&to=${Uri.encodeComponent(DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String())}')) : Future.value(null),
        want('pulse') ? _try(Api.get('/dashboard')) : Future.value(null),
        want('ideas') ? _try(Api.get('/ideas')) : Future.value(null),
        want('crm') ? _try(Api.get('/leads')) : Future.value(null),
        want('products') ? _try(Api.get('/products')) : Future.value(null),
        want('call') ? _try(Api.get('/calls/active')) : Future.value(null),
      ]);
      final inbox = res[0], todos = res[1], events = res[2], dash = res[3], ideas = res[4], leads = res[5], products = res[6], calls = res[7];

      if (inbox is Map) {
        final team = inbox['team'] is Map ? '${inbox['team']['name']}' : 'Workspace';
        final ws = inbox['workspace'] is Map ? Map<String, dynamic>.from(inbox['workspace'] as Map) : <String, dynamic>{};
        final dms = (inbox['dms'] is List ? inbox['dms'] as List : []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final members = (inbox['members'] is List ? inbox['members'] as List : []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

        if (want('unread')) {
          final rows = <Map<String, dynamic>>[];
          final wsUnread = (ws['unread'] as num?)?.toInt() ?? 0;
          var total = wsUnread;
          final wsLast = ws['last_message'] is Map ? Map<String, dynamic>.from(ws['last_message'] as Map) : null;
          if (wsUnread > 0) {
            rows.add({'title': '$team · everyone', 'sub': wsLast == null ? '' : '${wsLast['name'] ?? ''}: ${previewOf(wsLast)}', 'trail': '$wsUnread', 'color': _blue, 'initial': 'W', 'link': 'glob://chat/workspace'});
          }
          final unreadDms = dms.where((d) => ((d['unread'] as num?)?.toInt() ?? 0) > 0).toList();
          final readDms = dms.where((d) => ((d['unread'] as num?)?.toInt() ?? 0) == 0).toList();
          for (final d in unreadDms) {
            total += (d['unread'] as num?)?.toInt() ?? 0;
          }
          for (final d in [...unreadDms, ...readDms]) {
            if (rows.length >= 5) break;
            if (readDms.contains(d) && rows.length >= 3 && unreadDms.isNotEmpty) break;
            final u = Map<String, dynamic>.from(d['user'] as Map);
            final n = (d['unread'] as num?)?.toInt() ?? 0;
            final last = d['last_message'] is Map ? Map<String, dynamic>.from(d['last_message'] as Map) : null;
            rows.add({
              'title': '${u['name']}',
              'sub': previewOf(last),
              'trail': n > 0 ? '$n' : whenOf(last?['created_at']),
              'color': _hex('${u['id']}'),
              'initial': _first('${u['name']}'),
              'photo': await _photo(dir, '${u['id']}', u['avatar_url']),
              'link': 'glob://chat/dm/${u['id']}',
            });
          }
          await _put('unread', {'title': 'Messages', 'count': total > 0 ? '$total unread' : 'All read', 'empty': 'No chats yet', 'rows': rows});
        }

        if (want('quickcall')) {
          final pool = [...dms.map((d) => Map<String, dynamic>.from(d['user'] as Map)), ...members.where((m) => !dms.any((d) => '${d['user']['id']}' == '${m['id']}'))];
          final people = <Map<String, dynamic>>[];
          for (final m in pool.take(5)) {
            people.add({
              'name': '${m['name']}'.split(' ').first,
              'color': _hex('${m['id']}'),
              'initial': _first('${m['name']}'),
              'photo': await _photo(dir, '${m['id']}', m['avatar_url']),
              'link': 'glob://chat/dm/${m['id']}',
              'buttons': [
                {'icon': 'phone', 'link': 'glob://call/${m['id']}/voice'},
                {'icon': 'video', 'link': 'glob://call/${m['id']}/video'},
              ],
            });
          }
          await _put('quickcall', {'title': 'Quick call', 'count': '', 'empty': 'No one to call yet', 'people': people});
        }

        // online status only exists while the app is connected; otherwise keep what the widget already shows
        if (want('online') && ChatService.I.connected) {
          final online = ChatService.I.online;
          final people = <Map<String, dynamic>>[];
          for (final m in members.where((m) => online.contains('${m['id']}')).take(5)) {
            people.add({
              'name': '${m['name']}'.split(' ').first,
              'color': _hex('${m['id']}'),
              'initial': _first('${m['name']}'),
              'photo': await _photo(dir, '${m['id']}', m['avatar_url']),
              'link': 'glob://chat/dm/${m['id']}',
              'buttons': [
                {'icon': 'chat', 'link': 'glob://chat/dm/${m['id']}'},
                {'icon': 'phone', 'link': 'glob://call/${m['id']}/voice'},
              ],
            });
          }
          final n = members.where((m) => online.contains('${m['id']}')).length;
          await _put('online', {'title': "Who's online", 'count': n == 0 ? '' : '$n active', 'empty': 'Nobody else is online right now', 'people': people});
        }
      }

      if (todos is Map && want('tasks')) {
        final open = items(todos).where((t) => t['done'] != true).toList();
        open.sort((a, b) {
          final x = '${a['due_date'] ?? '9999'}', y = '${b['due_date'] ?? '9999'}';
          return x.compareTo(y);
        });
        final rows = <Map<String, dynamic>>[];
        for (final t in open.take(5)) {
          final due = t['due_date'] == null ? null : DateTime.tryParse('${t['due_date']}'.substring(0, 10));
          final late = due != null && due.isBefore(DateTime.now().subtract(const Duration(days: 1)));
          rows.add({
            'title': '${t['title']}',
            'sub': due != null ? (late ? 'Overdue · ${_when(due, time: false)}' : 'Due ${_when(due, time: false)}') : '${t['idea_title'] ?? t['lead_name'] ?? ''}',
            'trail': '',
            'color': late ? _coral : _yellow,
            'initial': _first('${t['title']}'),
            'link': 'glob://tasks',
            'action': {'icon': 'tick', 'link': 'glob://task/${t['id']}/done', 'bg': true},
          });
        }
        await _put('tasks', {'title': "Today's tasks", 'count': '${open.length} open', 'empty': 'All clear. Nothing to do.', 'rows': rows});
      }

      if (want('nextup') && (events is Map || todos is Map)) {
        final entries = <Map<String, dynamic>>[];
        if (events is Map) {
          for (final e in items(events)) {
            final d = DateTime.tryParse('${e['starts_at']}')?.toLocal();
            if (d == null) continue;
            final kind = '${e['kind'] ?? 'meeting'}';
            entries.add({'at': d, 'title': '${e['title']}', 'sub': kind[0].toUpperCase() + kind.substring(1), 'trail': _when(d), 'color': {'meeting': _blue, 'appointment': _lilac, 'task': _yellow, 'reminder': _green}[kind] ?? _blue, 'initial': _first(kind)});
          }
        }
        if (todos is Map) {
          for (final t in items(todos)) {
            final due = t['due_date'] == null ? null : DateTime.tryParse('${t['due_date']}'.substring(0, 10));
            if (due == null || due.isAfter(DateTime.now().add(const Duration(days: 7)))) continue;
            entries.add({'at': due, 'title': '${t['title']}', 'sub': 'Task', 'trail': _when(due, time: false), 'color': _yellow, 'initial': 'T'});
          }
          final fu = todos['follow_ups'] is List ? todos['follow_ups'] as List : [];
          for (final f in fu.whereType<Map>()) {
            final d = DateTime.tryParse('${f['next_follow_up_at']}')?.toLocal();
            if (d == null || d.isAfter(DateTime.now().add(const Duration(days: 7)))) continue;
            entries.add({'at': d, 'title': 'Follow up: ${f['lead_name']}', 'sub': 'Lead', 'trail': _when(d), 'color': _pink, 'initial': 'F'});
          }
        }
        entries.sort((a, b) => (a['at'] as DateTime).compareTo(b['at'] as DateTime));
        final rows = entries.take(5).map((e) => {...e, 'at': null, 'link': 'glob://calendar'}..remove('at')).toList();
        await _put('nextup', {'title': 'Next up', 'count': 'Next 7 days', 'empty': 'Nothing coming up', 'rows': rows});
      }

      if (dash is Map && want('pulse')) {
        final t = dash['team'] is Map ? Map<String, dynamic>.from(dash['team'] as Map) : <String, dynamic>{};
        final done = int.tryParse('${t['todos_done'] ?? 0}') ?? 0;
        final total = int.tryParse('${t['todos_total'] ?? 0}') ?? 0;
        final pct = total == 0 ? 0 : (done * 100 / total).round();
        final feas = double.tryParse('${t['feasibility']}');
        await _put('pulse', {
          'title': 'Team pulse',
          'count': '${t['ideas'] ?? 0} ideas',
          'tiles': [
            {'label': 'Tasks done', 'value': '$pct%', 'progress': pct, 'color': _blue, 'link': 'glob://tasks'},
            {'label': 'Open questions', 'value': '${t['open_questions'] ?? 0}', 'color': _yellow, 'link': 'glob://home'},
            {'label': 'Feasibility', 'value': feas == null ? '–' : '${feas.toStringAsFixed(1)}/5', 'progress': feas == null ? 0 : (feas * 20).round(), 'color': _green, 'link': 'glob://ideas'},
          ],
        });
      }

      if (ideas is Map && want('ideas')) {
        final list = items(ideas);
        const colors = {'idea': _yellow, 'planning': _blue, 'building': _lilac, 'paused': _grey, 'dropped': _coral, 'shipped': _green};
        final rows = list.take(5).map((i) {
          final st = '${i['status'] ?? 'idea'}';
          final f = i['feasibility'];
          return {
            'title': '${i['title']}',
            'sub': '$st · ${i['owner_name'] ?? ''}',
            'trail': f == null ? '' : '$f★',
            'color': colors[st] ?? _yellow,
            'initial': _first(st),
            'link': 'glob://ideas',
          };
        }).toList();
        await _put('ideas', {'title': 'Ideas', 'count': '${list.length} total', 'empty': 'No ideas yet', 'rows': rows});
      }

      if (leads is Map && want('crm')) {
        final end = DateTime.now().add(const Duration(days: 1));
        final due = items(leads).where((l) {
          final d = DateTime.tryParse('${l['next_follow_up_at']}')?.toLocal();
          return d != null && d.isBefore(DateTime(end.year, end.month, end.day)) && '${l['stage']}' != 'won' && '${l['stage']}' != 'lost';
        }).toList();
        due.sort((a, b) => '${a['next_follow_up_at']}'.compareTo('${b['next_follow_up_at']}'));
        final rows = due.take(5).map((l) {
          final d = DateTime.tryParse('${l['next_follow_up_at']}')?.toLocal();
          final phone = '${l['phone'] ?? ''}'.trim();
          return {
            'title': '${l['name']}',
            'sub': '${l['company'] ?? l['stage'] ?? ''}',
            'trail': d == null ? '' : (d.isBefore(DateTime.now()) && !_today(d) ? 'Overdue' : _hm(d)),
            'color': _pink,
            'initial': _first('${l['name']}'),
            'link': 'glob://leads',
            if (phone.isNotEmpty && phone != 'null') 'action': {'icon': 'phone', 'dial': 'tel:$phone'},
          };
        }).toList();
        await _put('crm', {'title': 'CRM follow-ups', 'count': due.isEmpty ? '' : '${due.length} due', 'empty': 'No follow-ups due today', 'rows': rows});
      }

      if (products is Map && want('products')) {
        final list = items(products);
        const colors = {'up': _green, 'down': _coral, 'building': _yellow};
        final down = list.where((p) => '${p['status']}' == 'down').length;
        final rows = list.take(5).map((p) {
          final st = '${p['status'] ?? 'building'}';
          var host = '${p['url'] ?? ''}'.replaceAll(RegExp(r'^https?://(www\.)?'), '');
          if (host.contains('/')) host = host.split('/').first;
          return {
            'title': '${p['name']}',
            'sub': host.isEmpty ? st : '$st · $host',
            'trail': st == 'up' ? '' : st.toUpperCase(),
            'color': colors[st] ?? _yellow,
            'initial': _first('${p['name']}'),
            'link': 'glob://products',
          };
        }).toList();
        await _put('products', {'title': 'Products', 'count': list.isEmpty ? '' : (down > 0 ? '$down down' : 'All up'), 'empty': 'No products yet', 'rows': rows});
      }

      if (calls is Map && want('call')) {
        final open = items(calls).where((c) => '${c['scope']}' == 'group' && c['ended_at'] == null).toList();
        final rows = open.take(3).map((c) {
          final n = (c['participants'] is List ? c['participants'] as List : []).whereType<Map>().where((p) => '${p['state']}' == 'joined').length;
          final video = '${c['kind']}' == 'video';
          return {
            'title': 'Group ${video ? 'video' : 'voice'} call',
            'sub': '$n in the call',
            'trail': '',
            'color': _green,
            'initial': 'G',
            'link': 'glob://chat/workspace',
            'action': {'icon': 'join', 'link': 'glob://call/join/${c['id']}'},
          };
        }).toList();
        await _put('call', {'title': 'Call in progress', 'count': rows.isEmpty ? '' : 'Live', 'empty': 'No call right now', 'rows': rows});
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}
