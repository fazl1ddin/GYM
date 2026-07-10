import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/device_service.dart';
import '../../services/face_service.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../widgets/face_scan.dart';

/// Отметка прихода/ухода. Порядок (раздел 6 ТЗ):
/// сервер выдаёт случайный liveness-челлендж + nonce → пользователь выполняет
/// именно его → снимаем кадр → эмбеддинг + гео + флаги отправляем на сервер.
class CheckinScreen extends StatefulWidget {
  final String type; // 'in' | 'out'
  const CheckinScreen({super.key, required this.type});
  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  CameraController? _controller;
  CheckinChallenge? _challenge;
  LivenessTracker? _tracker;
  LocationResult? _geo;
  String? _geoError;
  String _prompt = 'Подготовка…';
  bool _capturing = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _fetchGeo() async {
    try {
      _geo = await LocationService.current();
    } catch (e) {
      _geoError = e.toString();
    }
    if (mounted) setState(() {});
  }

  Future<void> _prepare() async {
    _fetchGeo(); // геолокация параллельно, не блокирует камеру
    try {
      final ch = await ApiClient.instance.challenge(widget.type);
      if (!mounted) return;
      setState(() {
        _challenge = ch;
        _tracker = LivenessTracker(ch.challenge);
        _prompt = challengeLabel(ch.challenge);
      });
    } catch (e) {
      _snack(e.toString());
      if (mounted) Navigator.pop(context, false);
    }
  }

  void _onFace(Face? face) {
    if (_capturing || _done || _tracker == null) return;
    if (face == null) {
      setState(() => _prompt = 'Лицо не видно');
      return;
    }
    final hint = _tracker!.update(face);
    setState(() => _prompt = hint);
    if (_tracker!.passed) _capture();
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null) return;
    _capturing = true;
    setState(() => _prompt = 'Готово! Снимаем…');
    try {
      if (!FaceService.modelReady) {
        throw 'Модель распознавания не загружена (assets/models/mobilefacenet.tflite)';
      }
      await _controller!.stopImageStream();
      final shot = await _controller!.takePicture();
      final faces = await FaceService.detectFromInputImage(
          InputImage.fromFilePath(shot.path));
      if (faces.isEmpty) throw 'Лицо не найдено, повторите';
      final embedding = await FaceService.embedFromFile(shot.path, faces.first);
      final photo = base64Encode(await File(shot.path).readAsBytes());

      final result = await ApiClient.instance.checkin(
        type: widget.type,
        nonce: _challenge!.nonce,
        embedding: embedding,
        photoBase64: 'data:image/jpeg;base64,$photo',
        liveness: _tracker!.toJson(),
        geo: _geo?.toJson(),
        deviceId: DeviceService.deviceId,
        clientFlags: {
          ...DeviceService.clientFlags,
          'mockLocation': _geo?.mocked ?? false,
        },
      );
      _done = true;
      if (mounted) await _showResult(result);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString());
      if (mounted) Navigator.pop(context, false);
    }
  }

  Future<void> _showResult(CheckinResult r) async {
    final ok = r.confirmed;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(ok ? Icons.check_circle : Icons.hourglass_top,
            color: ok ? AppColors.success : AppColors.warning, size: 48),
        title: Text(r.message, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!ok && r.riskFlags.isNotEmpty)
              Text('Причины проверки: ${r.riskFlags.join(', ')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.inkSoft)),
            if (r.distanceM != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Расстояние до места: ${r.distanceM} м',
                    style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ОК')),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == 'in' ? 'Отметить приход' : 'Отметить уход';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _challenge == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  SoftCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user, color: AppColors.accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _geoError != null
                                ? 'Геолокация недоступна: $_geoError'
                                : _geo != null
                                    ? 'Геопозиция получена'
                                    : 'Определяем геопозицию…',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: FaceScanView(
                      onReady: (c) => _controller = c,
                      onFace: _onFace,
                      prompt: _prompt,
                      success: _tracker?.passed ?? false,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Выполните действие, которое просит приложение',
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                ],
              ),
            ),
    );
  }
}
