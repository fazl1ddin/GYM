import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

/// Очередь офлайн-отметок (улучшение №8). Если сети нет, отметка сохраняется
/// локально и досылается на /api/checkin/offline при появлении связи.
class OfflineQueue {
  static const _key = 'offlineCheckins';

  static Future<List<Map<String, dynamic>>> _read() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> _write(List<Map<String, dynamic>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(list));
  }

  static Future<int> count() async => (await _read()).length;

  static Future<void> enqueue(Map<String, dynamic> payload) async {
    final list = await _read();
    list.add(payload);
    await _write(list);
  }

  /// Пытается дослать все отметки. Возвращает число успешно отправленных.
  static Future<int> flush() async {
    final list = await _read();
    if (list.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    var sent = 0;
    for (final item in list) {
      try {
        await ApiClient.instance.checkinOffline(item);
        sent++;
      } catch (_) {
        remaining.add(item); // сеть/сервер недоступны — оставляем на потом
      }
    }
    await _write(remaining);
    return sent;
  }
}
