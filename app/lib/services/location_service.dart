import 'package:geolocator/geolocator.dart';

/// Геолокация для проверки геозоны (раздел 6 ТЗ, уровень 3).
class LocationResult {
  final double lat;
  final double lng;
  final double accuracy;
  final bool mocked;
  LocationResult(this.lat, this.lng, this.accuracy, this.mocked);

  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lng': lng, 'accuracy': accuracy};
}

class LocationService {
  /// Запрашивает разрешение и возвращает текущую позицию.
  /// Бросает исключение с понятным текстом, если геолокация недоступна.
  static Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Включите геолокацию на устройстве';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw 'Нет доступа к геолокации';
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LocationResult(pos.latitude, pos.longitude, pos.accuracy, pos.isMocked);
  }
}
