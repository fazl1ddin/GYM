import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../../api/api_client.dart';
import '../../services/device_service.dart';
import '../../services/face_service.dart';
import '../../theme.dart';
import '../../widgets/face_scan.dart';

/// Регистрация лица — направляемый многоракурсный процесс с проверкой живости:
/// 1) «Центр» — держите лицо ровно в овале; 2) «Поворот» — поверните голову;
/// 3) «Моргните» — моргните. После этого делается фронтальный снимок и
/// отправляется на сервер. Регистрируется один раз, лучше под контролем HR.
class EnrollScreen extends StatefulWidget {
  /// Если заданы — админ регистрирует лицо этого сотрудника (HR-режим).
  /// Иначе сотрудник регистрирует своё лицо сам.
  final int? employeeId;
  final String? employeeName;
  const EnrollScreen({super.key, this.employeeId, this.employeeName});
  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  final _scanKey = GlobalKey<FaceScanViewState>();
  CameraController? _controller;
  Face? _face;

  int _step = 0;          // 0 центр · 1 поворот · 2 моргните
  double _progress = 0;   // заполнение шага «центр» (по времени удержания)
  double _ring = 0;       // значение кольца прогресса под текущий шаг
  bool _eyesWereOpen = false;
  bool _blinkClosed = false;
  bool _submitting = false;
  bool _done = false;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _hold = Timer.periodic(const Duration(milliseconds: 90), (_) => _tick());
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  bool get _faceOk {
    final f = _face;
    if (f == null) return false;
    return f.boundingBox.width > 120; // лицо достаточно крупное/близко
  }

  /// Шаг «центр» — по таймеру заполняем прогресс, пока лицо ровно в кадре.
  void _tick() {
    if (_submitting || _done || _step != 0) return;
    if (_faceOk) {
      final n = (_progress + 0.08).clamp(0.0, 1.0);
      setState(() { _progress = n; _ring = n; });
      if (n >= 1.0) setState(() { _step = 1; _progress = 0; _ring = 0; });
    } else if (_progress != 0) {
      setState(() { _progress = 0; _ring = 0; });
    }
  }

  /// Шаги «поворот» и «моргните» — по сигналам детектора лица.
  void _onFace(Face? f) {
    if (_submitting || _done) return;
    _face = f;
    if (f != null) {
      if (_step == 1) {
        final y = f.headEulerAngleY ?? 0;
        _ring = (y.abs() / 22).clamp(0.0, 1.0);
        if (y.abs() > 22) { _step = 2; _ring = 0; _eyesWereOpen = false; _blinkClosed = false; }
      } else if (_step == 2) {
        final l = f.leftEyeOpenProbability ?? 1;
        final r = f.rightEyeOpenProbability ?? 1;
        final open = l > 0.6 && r > 0.6;
        final closed = l < 0.25 && r < 0.25;
        if (open) {
          // моргнули и снова открыли глаза → снимаем фронтальный кадр
          if (_blinkClosed) { _submit(); return; }
          _eyesWereOpen = true;
        }
        if (closed && _eyesWereOpen) _blinkClosed = true;
        _ring = _blinkClosed ? 0.9 : (_eyesWereOpen ? 0.5 : 0.2);
      }
    }
    if (mounted) setState(() {});
  }

  String get _prompt {
    if (_submitting) return 'Обработка…';
    switch (_step) {
      case 0:
        return _face == null ? 'Поместите лицо в овал' : (!_faceOk ? 'Придвиньтесь ближе' : 'Держите ровно…');
      case 1:
        return 'Медленно поверните голову в сторону';
      case 2:
        return 'Теперь моргните';
      default:
        return 'Готово';
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    _hold?.cancel();
    setState(() { _submitting = true; _ring = 1; });
    try {
      await _scanKey.currentState?.stopStream();
      final shot = await _controller!.takePicture();
      // «Выпрямляем» снимок по EXIF — иначе фронтальная камера iOS отдаёт кадр
      // с ориентацией, на которой детектор (и сервер) может не найти лицо.
      final raw = await File(shot.path).readAsBytes();
      final decoded = img.decodeImage(raw);
      final upright = decoded != null ? img.bakeOrientation(decoded) : null;
      if (upright != null) {
        await File(shot.path).writeAsBytes(img.encodeJpg(upright, quality: 90));
      }
      // Клиентская детекция — не фатальна: авторитетно лицо проверяет сервер.
      // Локально она нужна лишь для опционального эмбеддинга (если есть модель).
      List<double>? embedding;
      if (FaceService.modelReady) {
        try {
          final faces = await FaceService.detectFromInputImage(InputImage.fromFilePath(shot.path));
          if (faces.isNotEmpty) {
            embedding = await FaceService.embedFromFile(shot.path, faces.first);
          }
        } catch (_) {}
      }
      final photo = base64Encode(await File(shot.path).readAsBytes());
      final dataUrl = 'data:image/jpeg;base64,$photo';
      if (widget.employeeId != null) {
        await ApiClient.instance.enrollFor(widget.employeeId!, embedding, dataUrl);
      } else {
        await ApiClient.instance.enroll(embedding, dataUrl, DeviceService.deviceId);
      }
      _done = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString());
      if (mounted) {
        // Возобновляем поток детекции и начинаем заново с шага «центр»,
        // иначе onFace не вызывается и процесс завис бы.
        await _scanKey.currentState?.resumeStream();
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _step = 0;
          _progress = 0;
          _ring = 0;
          _eyesWereOpen = false;
          _blinkClosed = false;
          _face = null;
        });
        _hold = Timer.periodic(const Duration(milliseconds: 90), (_) => _tick());
      }
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.employeeName != null ? 'Лицо · ${widget.employeeName}' : 'Регистрация лица')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text('Смотрите в камеру при хорошем освещении и выполняйте подсказки — это подтверждает, что вы живой человек.',
                style: TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 12),
            Expanded(
              child: FaceScanView(
                key: _scanKey,
                onReady: (c) => _controller = c,
                onFace: _onFace,
                prompt: _prompt,
                success: _step >= 1,
                progress: _ring,
              ),
            ),
            const SizedBox(height: 14),
            _steps(),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white,
              ),
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, color: Colors.white),
              label: Text(_submitting ? 'Регистрируем…' : 'Идёт проверка живости'),
            ),
            const SizedBox(height: 8),
            const Text('Снимок и регистрация произойдут автоматически после всех шагов',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _steps() => Row(
        children: [
          _stepChip('Центр', done: _step > 0, active: _step == 0),
          const SizedBox(width: 8),
          _stepChip('Поворот', done: _step > 1, active: _step == 1),
          const SizedBox(width: 8),
          _stepChip('Моргните', done: _step > 2 || _submitting || _done, active: _step == 2),
        ],
      );

  Widget _stepChip(String label, {required bool done, required bool active}) {
    final Color bg, fg;
    if (done) {
      bg = AppColors.success.withValues(alpha: 0.12);
      fg = AppColors.success;
    } else if (active) {
      bg = AppColors.accentSoft;
      fg = AppColors.accent;
    } else {
      bg = AppColors.panel;
      fg = AppColors.inkSoft;
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done || active ? Colors.transparent : AppColors.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(done ? Icons.check_circle : Icons.circle,
                size: 14, color: done ? AppColors.success : (active ? AppColors.accent : AppColors.line)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}
