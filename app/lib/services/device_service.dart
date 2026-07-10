import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Идентификация устройства и признаки целостности (для привязки устройства
/// и риск-скоринга: эмулятор/root — раздел 6 ТЗ, уровни 2 и 4).
class DeviceService {
  static String? _deviceId;
  static Map<String, dynamic> _flags = {};

  static Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _deviceId = sp.getString('deviceId');
    if (_deviceId == null) {
      _deviceId = _generateId();
      await sp.setString('deviceId', _deviceId!);
    }
    await _collectFlags();
  }

  static String get deviceId => _deviceId ?? 'unknown';
  static Map<String, dynamic> get clientFlags => _flags;

  static String _generateId() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  static Future<void> _collectFlags() async {
    final info = DeviceInfoPlugin();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await info.androidInfo;
        _flags = {'emulator': !a.isPhysicalDevice, 'model': a.model};
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await info.iosInfo;
        _flags = {'emulator': !i.isPhysicalDevice, 'model': i.utsname.machine};
      }
    } catch (_) {
      _flags = {};
    }
  }
}
