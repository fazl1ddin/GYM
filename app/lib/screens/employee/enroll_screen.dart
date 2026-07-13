import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../api/api_client.dart';
import '../../services/device_service.dart';
import '../../services/face_service.dart';
import '../../theme.dart';
import '../../widgets/face_scan.dart';

/// Регистрация лица: направляемый процесс. Пользователь центрирует лицо в овале,
/// держит ровно ~1 сек (кольцо прогресса заполняется) — снимок делается сам.
/// Регистрируется один раз, лучше — под контролем HR.
class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});
  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  final _scanKey = GlobalKey<FaceScanViewState>();
  CameraController? _controller;
  Face? _face;
  bool _capturing = false;
  bool _done = false;
  double _progress = 0;
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

  /// Пока лицо ровно в кадре — заполняем прогресс; при полном — снимаем.
  void _tick() {
    if (_capturing || _done) return;
    if (_faceOk) {
      final next = (_progress + 0.09).clamp(0.0, 1.0);
      setState(() => _progress = next);
      if (next >= 1.0) _capture();
    } else if (_progress != 0) {
      setState(() => _progress = 0);
    }
  }

  String get _prompt {
    if (_capturing) return 'Обработка…';
    if (_face == null) return 'Поместите лицо в овал';
    if (!_faceOk) return 'Придвиньтесь ближе';
    return 'Держите ровно…';
  }

  Future<void> _capture() async {
    if (_controller == null || !_faceOk || _capturing) return;
    _hold?.cancel();
    setState(() { _capturing = true; _progress = 1; });
    try {
      await _scanKey.currentState?.stopStream();
      final shot = await _controller!.takePicture();
      final faces = await FaceService.detectFromInputImage(
          InputImage.fromFilePath(shot.path));
      if (faces.isEmpty) throw 'Лицо не найдено, попробуйте ещё раз';
      // Эмбеддинг считает сервер из фото; если на устройстве есть модель —
      // добавим вектор дополнительно (не обязателен).
      List<double>? embedding;
      if (FaceService.modelReady) {
        try { embedding = await FaceService.embedFromFile(shot.path, faces.first); } catch (_) {}
      }
      final photo = base64Encode(await File(shot.path).readAsBytes());
      await ApiClient.instance.enroll(embedding, 'data:image/jpeg;base64,$photo',
          DeviceService.deviceId);
      _done = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString());
      if (mounted) {
        // Возобновляем поток детекции: без этого onFace не вызывается,
        // _face остаётся «залипшим» и авто-захват уходит в бесконечный цикл.
        await _scanKey.currentState?.resumeStream();
        if (!mounted) return;
        setState(() { _capturing = false; _progress = 0; _face = null; });
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
      appBar: AppBar(title: const Text('Регистрация лица')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text('Смотрите прямо в камеру при хорошем освещении и держите лицо в овале.',
                style: TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 12),
            Expanded(
              child: FaceScanView(
                key: _scanKey,
                onReady: (c) => _controller = c,
                onFace: (f) {
                  if (_capturing) return;
                  setState(() => _face = f);
                },
                prompt: _prompt,
                success: _faceOk,
                progress: _progress,
              ),
            ),
            const SizedBox(height: 14),
            _steps(),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _faceOk && !_capturing ? _capture : null,
              icon: _capturing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt, color: Colors.white),
              label: Text(_capturing ? 'Регистрируем…' : 'Снять и зарегистрировать'),
            ),
            const SizedBox(height: 8),
            const Text('Снимок сделается автоматически, когда лицо будет ровно в кадре',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _steps() {
    final centered = _faceOk || _capturing;
    final holding = _faceOk && !_capturing;
    return Row(
      children: [
        _stepChip('Наведите', done: centered, active: !centered),
        const SizedBox(width: 8),
        _stepChip('Держите ровно', done: _capturing, active: holding),
        const SizedBox(width: 8),
        _stepChip('Готово', done: _done, active: _capturing),
      ],
    );
  }

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
