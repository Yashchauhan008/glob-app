import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kApiUrl =
    String.fromEnvironment('API_URL', defaultValue: 'https://api.glob.yashchauhan.pro');

class ApiError implements Exception {
  final String message;
  final int status;
  ApiError(this.message, this.status);
  @override
  String toString() => message;
}

class Api {
  static SharedPreferences? _p;
  static String? token;
  static String? teamId;
  static Map<String, dynamic>? user;

  /// Called when the server says the session is no longer valid.
  static void Function()? onSignedOut;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    token = _p!.getString('token');
    teamId = _p!.getString('team');
    final u = _p!.getString('user');
    if (u != null) {
      try {
        user = jsonDecode(u) as Map<String, dynamic>;
      } catch (_) {}
    }
  }

  static Future<void> signIn(String t, Map<String, dynamic> u) async {
    token = t;
    user = u;
    await _p!.setString('token', t);
    await _p!.setString('user', jsonEncode(u));
  }

  static Future<void> setTeam(String? id) async {
    teamId = id;
    if (id == null) {
      await _p!.remove('team');
    } else {
      await _p!.setString('team', id);
    }
  }

  static Future<void> signOut() async {
    token = null;
    teamId = null;
    user = null;
    await _p!.remove('token');
    await _p!.remove('team');
    await _p!.remove('user');
  }

  static Map<String, String> _headers(bool body) => {
        if (body) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (teamId != null) 'X-Team-Id': teamId!,
      };

  static Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse(kApiUrl + path);
    final h = _headers(body != null);
    http.Response r;
    try {
      switch (method) {
        case 'POST':
          r = await http.post(uri, headers: h, body: jsonEncode(body ?? {}));
          break;
        case 'PATCH':
          r = await http.patch(uri, headers: h, body: jsonEncode(body ?? {}));
          break;
        case 'PUT':
          r = await http.put(uri, headers: h, body: jsonEncode(body ?? {}));
          break;
        case 'DELETE':
          r = await http.delete(uri, headers: h);
          break;
        default:
          r = await http.get(uri, headers: h);
      }
    } catch (_) {
      throw ApiError('Cannot reach the server. Check your internet.', 0);
    }
    if (r.statusCode == 401 && token != null && !path.startsWith('/auth')) {
      await signOut();
      onSignedOut?.call();
      throw ApiError('Please sign in again.', 401);
    }
    if (r.statusCode == 204 || r.body.isEmpty) return null;
    dynamic data;
    try {
      data = jsonDecode(r.body);
    } catch (_) {
      data = r.body;
    }
    if (r.statusCode >= 400) {
      final msg = data is Map && data['message'] != null ? '${data['message']}' : 'Request failed';
      throw ApiError(msg, r.statusCode);
    }
    return data;
  }

  static Future<dynamic> get(String p) => _send('GET', p);
  static Future<dynamic> post(String p, [Object? b]) => _send('POST', p, b ?? {});
  static Future<dynamic> patch(String p, Object b) => _send('PATCH', p, b);
  static Future<dynamic> put(String p, Object b) => _send('PUT', p, b);
  static Future<dynamic> del(String p) => _send('DELETE', p);
}

List<Map<String, dynamic>> items(dynamic res) {
  final l = (res is Map ? res['items'] : null);
  if (l is! List) return [];
  return l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
