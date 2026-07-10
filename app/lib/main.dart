import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'state/session.dart';
import 'services/device_service.dart';
import 'services/face_service.dart';
import 'screens/login_screen.dart';
import 'screens/employee/home_screen.dart';
import 'screens/admin/admin_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceService.init();
  await FaceService.loadModel(); // модель может отсутствовать — не критично для запуска
  runApp(
    ChangeNotifierProvider(
      create: (_) => Session()..bootstrap(),
      child: const FaceClockApp(),
    ),
  );
}

class FaceClockApp extends StatelessWidget {
  const FaceClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceClock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _Root(),
    );
  }
}

/// Маршрутизация по состоянию сессии и роли.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (s.booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!s.isAuthed) return const LoginScreen();
    return s.isAdmin ? const AdminHome() : const EmployeeHome();
  }
}
