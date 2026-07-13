import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/models.dart';

/// Глобальное состояние: текущий пользователь и его роль.
class Session extends ChangeNotifier {
  AppUser? user;
  bool booting = true;

  bool get isAuthed => user != null;
  bool get isAdmin => user?.isAdmin ?? false;

  Future<void> bootstrap() async {
    await ApiClient.instance.init();
    // Без сохранённой сессии в сеть не ходим — сразу показываем экран логина.
    if (ApiClient.instance.hasSession) {
      try {
        user = await ApiClient.instance.me();
      } catch (_) {
        user = null;
      }
    }
    booting = false;
    notifyListeners();
  }

  Future<void> login(String login, String password) async {
    user = await ApiClient.instance.login(login, password);
    notifyListeners();
  }

  Future<void> refresh() async {
    user = await ApiClient.instance.me();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await ApiClient.instance.logout();
    } catch (_) {}
    user = null;
    notifyListeners();
  }
}
