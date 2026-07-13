import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
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
  bool _ready = false; // живость пройдена — ждём ручного нажатия «Отметить»
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
    if (_tracker!.passed && !_ready) {
      final f = _scanKey.currentState?.snapshotDataUrl(); // кадр действия
      if (f != null) _frames.add(f);
      setState(() { _ready = true; _prompt = 'Живость подтверждена'; });
    } else {
      setState(() => _prompt = hint);
    }
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null) return;
    _capturing = true;
    setState(() => _prompt = 'Готово! Снимаем…');
    try {
      await _controller!.stopImageStream();
      final shot = await _controller!.takePicture();
      // «Выпрямляем» снимок по EXIF (фронтальная камера iOS иначе даёт ориентацию,
      // на которой лицо не находится). Авторитетно лицо проверяет сервер.
      final raw = await File(shot.path).readAsBytes();
      final decoded = img.decodeImage(raw);
      final upright = decoded != null ? img.bakeOrientation(decoded) : null;
      if (upright != null) {
        await File(shot.path).writeAsBytes(img.encodeJpg(upright, quality: 90));
      }
      // Клиентская детекция не фатальна — нужна лишь для опционального эмбеддинга.
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
                      _statusRow(),
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
                      ElevatedButton.icon(
                        onPressed: (_ready && !_capturing) ? _capture : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.type == 'in' ? AppColors.accent : AppColors.ink,
                          disabledBackgroundColor: (widget.type == 'in' ? AppColors.accent : AppColors.ink).withValues(alpha: 0.4),
                          disabledForegroundColor: Colors.white,
                        ),
                        icon: _capturing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, color: Colors.white),
                        label: Text(_capturing
                            ? 'Отправляем…'
                            : (_ready
                                ? (widget.type == 'in' ? 'Отметить приход' : 'Отметить уход')
                                : 'Выполните действие на экране')),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Метка/цвет чипа геозоны: проверяем расстояние до места и подмену.
  /// Итоговое решение принимает сервер — это лишь подсказка пользователю.
  (String, Color) _geoStatus() {
    if (_geoError != null) return ('Ошибка', AppColors.danger);
    final g = _geo;
    if (g == null) return ('Поиск…', AppColors.warning);
    if (g.mocked) return ('Подмена?', AppColors.danger);
    final wp = _challenge?.workplace;
    final lat = (wp?['lat'] as num?)?.toDouble();
    final lng = (wp?['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return ('Определена', AppColors.success);
    final radius = (wp?['radiusM'] as num?)?.toDouble() ?? 150;
    final dist = Geolocator.distanceBetween(g.lat, g.lng, lat, lng);
    return dist <= radius ? ('В зоне', AppColors.success) : ('Вне зоны', AppColors.warning);
  }

  Widget _statusRow() {
    final requireQr = _challenge?.workplace?['requireQr'] == true;
    final live = _tracker?.passed ?? false;
    final (geoVal, geoColor) = _geoStatus();
    return Row(
      children: [
        _miniChip('Геозона', geoVal, geoColor),
        const SizedBox(width: 8),
        _miniChip('QR проходной',
            !requireQr ? 'Не нужен' : (_qr != null ? 'Готово' : 'Нужен скан'),
            !requireQr ? AppColors.inkSoft : (_qr != null ? AppColors.success : AppColors.warning)),
        const SizedBox(width: 8),
        _miniChip('Живость', live ? 'Пройдена' : 'Проверка…',
            live ? AppColors.success : AppColors.warning),
      ],
    );
  }

  Widget _miniChip(String key, String val, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(val,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
        ),
      );

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
