import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Клиент REST API FaceClock. Хранит cookie сессии между запросами.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// Адрес backend. Меняется в настройках (экран логина).
  /// Для эмулятора Android localhost хоста доступен как 10.0.2.2.
  String baseUrl = 'http://10.0.2.2:3000';
  String? _cookie;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    baseUrl = sp.getString('baseUrl') ?? baseUrl;
    _cookie = sp.getString('sessionCookie');
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setString('baseUrl', baseUrl);
  }

  Future<void> _saveCookie(String? raw) async {
    if (raw == null) return;
    _cookie = raw.split(';').first;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('sessionCookie', _cookie!);
  }

  Future<void> clearSession() async {
    _cookie = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('sessionCookie');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_cookie != null) 'Cookie': _cookie!,
      };

  Future<dynamic> _request(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      final b = body != null ? jsonEncode(body) : null;
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: _headers, body: b);
          break;
        case 'PATCH':
          res = await http.patch(uri, headers: _headers, body: b);
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: _headers, body: b);
          break;
        default:
          res = await http.get(uri, headers: _headers);
      }
    } catch (e) {
      throw ApiException('Нет связи с сервером. Проверьте адрес и сеть.');
    }
    await _saveCookie(res.headers['set-cookie']);
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode >= 400) {
      throw ApiException(data?['error'] ?? 'Ошибка (${res.statusCode})', res.statusCode);
    }
    return data;
  }

  // ---- auth ----
  Future<AppUser> login(String login, String password) async {
    final d = await _request('POST', '/api/login', {'login': login, 'password': password});
    return AppUser.fromJson(d['user']);
  }

  Future<AppUser?> me() async {
    try {
      final d = await _request('GET', '/api/me');
      return AppUser.fromJson(d['user']);
    } on ApiException catch (e) {
      if (e.status == 401) return null;
      rethrow;
    }
  }

  Future<void> logout() async {
    await _request('POST', '/api/logout');
    await clearSession();
  }

  Future<Map<String, dynamic>> config() async =>
      Map<String, dynamic>.from(await _request('GET', '/api/config'));

  // ---- enrollment / check-in ----
  Future<void> enroll(List<double>? embedding, String? photoBase64, String deviceId) =>
      _request('POST', '/api/enroll',
          {'embedding': embedding, 'photo': photoBase64, 'deviceId': deviceId});

  Future<CheckinChallenge> challenge(String type) async =>
      CheckinChallenge.fromJson(await _request('POST', '/api/checkin/challenge', {'type': type}));

  Future<CheckinResult> checkin({
    required String type,
    required String nonce,
    List<double>? embedding,
    String? photoBase64,
    required Map<String, dynamic> liveness,
    List<String>? livenessFrames,
    String? qr,
    Map<String, dynamic>? geo,
    required String deviceId,
    Map<String, dynamic>? clientFlags,
  }) async {
    final d = await _request('POST', '/api/checkin', {
      'type': type, 'nonce': nonce, 'embedding': embedding, 'photo': photoBase64,
      'liveness': liveness, 'livenessFrames': livenessFrames, 'qr': qr,
      'geo': geo, 'deviceId': deviceId, 'clientFlags': clientFlags,
    });
    return CheckinResult.fromJson(d);
  }

  Future<(ShiftStatus, List<AttendanceRecord>)> myAttendance() async {
    final d = await _request('GET', '/api/attendance/me');
    final recs = (d['records'] as List).map((e) => AttendanceRecord.fromJson(e)).toList();
    return (ShiftStatus.fromJson(d['status']), recs);
  }

  // ---- admin ----
  Future<List<AppUser>> employees() async {
    final d = await _request('GET', '/api/admin/employees');
    return (d['employees'] as List).map((e) => AppUser.fromJson(e)).toList();
  }

  Future<AppUser> createEmployee(Map<String, dynamic> body) async {
    final d = await _request('POST', '/api/admin/employees', body);
    return AppUser.fromJson(d['employee']);
  }

  Future<void> updateEmployee(int id, Map<String, dynamic> body) =>
      _request('PATCH', '/api/admin/employees/$id', body);

  Future<void> deleteEmployee(int id) => _request('DELETE', '/api/admin/employees/$id');

  Future<List<Workplace>> workplaces() async {
    final d = await _request('GET', '/api/admin/workplaces');
    return (d['workplaces'] as List).map((e) => Workplace.fromJson(e)).toList();
  }

  Future<void> createWorkplace(Map<String, dynamic> body) =>
      _request('POST', '/api/admin/workplaces', body);
  Future<void> deleteWorkplace(int id) => _request('DELETE', '/api/admin/workplaces/$id');
  Future<Map<String, dynamic>> workplaceQr(int id) async =>
      Map<String, dynamic>.from(await _request('GET', '/api/admin/workplaces/$id/qr'));

  Future<List<AttendanceRecord>> anomalies() async {
    final d = await _request('GET', '/api/admin/anomalies');
    return (d['records'] as List).map((e) => AttendanceRecord.fromJson(e)).toList();
  }

  Future<List<AttendanceRecord>> attendanceLog({String? status}) async {
    final q = status != null ? '?status=$status' : '';
    final d = await _request('GET', '/api/admin/attendance$q');
    return (d['records'] as List).map((e) => AttendanceRecord.fromJson(e)).toList();
  }

  Future<void> decide(int id, String decision, String? comment) =>
      _request('POST', '/api/admin/attendance/$id/decision',
          {'decision': decision, 'comment': comment});

  Future<Map<String, dynamic>> stats() async =>
      Map<String, dynamic>.from(await _request('GET', '/api/admin/stats'));

  String photoUrl(String ref) => '$baseUrl/api/admin/photo/$ref';

  /// Заголовки для загрузки защищённых изображений (Image.network).
  Map<String, String> get imageHeaders => {if (_cookie != null) 'Cookie': _cookie!};
}
