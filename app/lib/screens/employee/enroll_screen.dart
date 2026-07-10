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

/// Регистрация лица: делается один раз (лучше — под контролем HR).
class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});
  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  CameraController? _controller;
  Face? _face;
  bool _capturing = false;
  String _prompt = 'Поместите лицо в овал';

  bool get _faceOk {
    final f = _face;
    if (f == null) return false;
    return f.boundingBox.width > 120; // лицо достаточно крупное/близко
  }

  Future<void> _capture() async {
    if (_controller == null || !_faceOk || _capturing) return;
    if (!FaceService.modelReady) {
      _snack('Модель распознавания не загружена (assets/models/mobilefacenet.tflite)');
      return;
    }
    setState(() { _capturing = true; _prompt = 'Обработка…'; });
    try {
      await _controller!.stopImageStream();
      final shot = await _controller!.takePicture();
      final faces = await FaceService.detectFromInputImage(
          InputImage.fromFilePath(shot.path));
      if (faces.isEmpty) throw 'Лицо не найдено, попробуйте ещё раз';
      final embedding = await FaceService.embedFromFile(shot.path, faces.first);
      final photo = base64Encode(await File(shot.path).readAsBytes());
      await ApiClient.instance.enroll(embedding, 'data:image/jpeg;base64,$photo',
          DeviceService.deviceId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString());
      if (mounted) setState(() { _capturing = false; _prompt = 'Поместите лицо в овал'; });
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
            const Text('Смотрите прямо в камеру при хорошем освещении.',
                style: TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 12),
            Expanded(
              child: FaceScanView(
                onReady: (c) => _controller = c,
                onFace: (f) {
                  if (_capturing) return;
                  setState(() {
                    _face = f;
                    _prompt = f == null
                        ? 'Лицо не видно'
                        : (_faceOk ? 'Отлично! Нажмите «Снять»' : 'Придвиньтесь ближе');
                  });
                },
                prompt: _prompt,
                success: _faceOk,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _faceOk && !_capturing ? _capture : null,
              icon: _capturing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text('Снять и зарегистрировать'),
            ),
          ],
        ),
      ),
    );
  }
}
