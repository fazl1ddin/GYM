import '../api/api_client.dart';

/// Push-напоминания (улучшение №7).
///
/// Отправку напоминаний («вы не отметили приход/уход») выполняет сервер
/// (см. server/push.js). Клиенту нужно получить FCM-токен устройства и
/// зарегистрировать его через [registerToken].
///
/// Полноценный приём push требует настройки Firebase (google-services.json /
/// GoogleService-Info.plist) и пакета firebase_messaging — это делается в вашем
/// проекте. Ниже — точка интеграции:
///
/// ```dart
/// // после flutter pub add firebase_core firebase_messaging и firebase init:
/// await Firebase.initializeApp();
/// final token = await FirebaseMessaging.instance.getToken();
/// if (token != null) await NotificationService.registerToken(token);
/// ```
class NotificationService {
  /// Регистрирует FCM-токен на сервере (привязывается к текущему сотруднику).
  static Future<void> registerToken(String token) async {
    try {
      await ApiClient.instance.registerPushToken(token);
    } catch (_) {
      // не критично — повторим при следующем входе
    }
  }
}
