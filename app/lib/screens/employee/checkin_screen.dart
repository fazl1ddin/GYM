import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/device_service.dart';
import '../../services/face_service.dart';
import '../../services/location_service.dart';
import '../../services/offline_queue.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../widgets/face_scan.dart';
import 'qr_scan_screen.dart';

/// Отметка прихода/ухода. Порядок (раздел 6 ТЗ):
/// сервер выдаёт случайный liveness-челлендж + nonce → пользователь выполняет
/// именно его → кадры действия + фото + гео (+ QR) отправляются на сервер, где
/// сервер сам проверяет живость, распознаёт лицо и принимает решение.
class CheckinScreen extends StatefulWidget {
  final String type; // 'in' | 'out'
  const CheckinScreen({super.key, required this.type});
  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _scanKey = GlobalKey<FaceScanViewState>();
  CameraController? _controller;
  CheckinChallenge? _challenge;
  LivenessTracker? _tracker;
  LocationResult? _geo;
  String? _geoError;
  final List<String> _frames = []; // кадры для серверной проверки живости
  String? _qr;
  bool _offline = false; // сети нет — отметка уйдёт в офлайн-очередь
  String _prompt = 'Подготовка…';
  bool _capturing = false;
  bool _done = false;

  bool get _needQr => _challenge?.workplace?['requireQr'] == true && _qr == null;

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
    _fetchGeo();
    try {
      final ch = await ApiClient.instance.challenge(widget.type);
      if (!mounted) return;
      setState(() {
        _challenge = ch;
        _tracker = LivenessTracker(ch.challenge);
        _prompt = challengeLabel(ch.challenge);
      });
    } on ApiException catch (e) {
      // нет связи → офлайн-режим: локальное действие, отметка уйдёт в очередь
      if (e.status == null) {
        final actions = ['blink', 'turn_left', 'turn_right', 'smile'];
        final local = actions[Random().nextInt(actions.length)];
        if (!mounted) return;
        setState(() {
          _offline = true;
          _challenge = CheckinChallenge(nonce: '', challenge: local, type: widget.type, serverTime: 0, expiresAt: 0);
          _tracker = LivenessTracker(local);
          _prompt = challengeLabel(local);
        });
      } else {
        _snack(e.toString());
        if (mounted) Navigator.pop(context, false);
      }
    }
  }

  Future<void> _scanQr() async {
    final v = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (v != null) setState(() => _qr = v);
  }

  void _onFace(Face? face) {
    if (_capturing || _done || _tracker == null || _needQr) return;
    if (face == null) {
      setState(() => _prompt = 'Лицо не видно');
      return;
    }
    // нейтральный кадр — до выполнения действия
    if (_frames.isEmpty) {
      final f = _scanKey.currentState?.snapshotDataUrl();
      if (f != null) _frames.add(f);
    }
    final hint = _tracker!.update(face);
    setState(() => _prompt = hint);
    if (_tracker!.passed) {
      final f = _scanKey.currentState?.snapshotDataUrl(); // кадр действия
      if (f != null) _frames.add(f);
      _capture();
    }
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null) return;
    _capturing = true;
    setState(() => _prompt = 'Готово! Снимаем…');
    try {
      await _controller!.stopImageStream();
      final shot = await _controller!.takePicture();
      final faces = await FaceService.detectFromInputImage(
          InputImage.fromFilePath(shot.path));
      if (faces.isEmpty) throw 'Лицо не найдено, повторите';
      // Распознаёт сервер по фото; вектор с устройства — опционально.
      List<double>? embedding;
      if (FaceService.modelReady) {
        try { embedding = await FaceService.embedFromFile(shot.path, faces.first); } catch (_) {}
      }
      final photo = base64Encode(await File(shot.path).readAsBytes());

      // Офлайн: сохраняем в очередь и досылаем при связи (№8)
      if (_offline) {
        await OfflineQueue.enqueue({
          'type': widget.type,
          'photo': 'data:image/jpeg;base64,$photo',
          'livenessFrames': _frames,
          'livenessChallenge': _tracker!.challenge,
          'geo': _geo?.toJson(),
          'deviceId': DeviceService.deviceId,
          'capturedAt': DateTime.now().millisecondsSinceEpoch,
        });
        _done = true;
        if (mounted) {
          await showDialog(context: context, builder: (_) => AlertDialog(
            icon: const Icon(Icons.cloud_off, color: AppColors.warning, size: 44),
            title: const Text('Сохранено офлайн', textAlign: TextAlign.center),
            content: const Text('Нет связи. Отметка отправится автоматически, когда появится интернет.',
                textAlign: TextAlign.center),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ОК'))],
          ));
        }
        if (mounted) Navigator.pop(context, true);
        return;
      }

      final result = await ApiClient.instance.checkin(
        type: widget.type,
        nonce: _challenge!.nonce,
        embedding: embedding,
        photoBase64: 'data:image/jpeg;base64,$photo',
        liveness: _tracker!.toJson(),
        livenessFrames: _frames,
        qr: _qr,
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
          : _needQr
              ? _qrGate()
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
                                        ? (_qr != null ? 'Геопозиция и QR получены' : 'Геопозиция получена')
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
                          key: _scanKey,
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

  Widget _qrGate() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            const Text('Сначала отсканируйте QR на проходной',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Это подтверждает, что вы физически на рабочем месте',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              label: const Text('Сканировать QR'),
            ),
          ],
        ),
      );
}
