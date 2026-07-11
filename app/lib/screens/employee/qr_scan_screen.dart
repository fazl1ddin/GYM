import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../../services/face_service.dart';
import '../../theme.dart';

/// Сканирование динамического QR на проходной (улучшение №3).
/// Использует тот же ML Kit, что и распознавание лица (общий GoogleMLKit —
/// без конфликта версий подов). Возвращает payload вида FCLK:<id>:<code> или null.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final BarcodeScanner _scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  CameraController? _controller;
  CameraDescription? _camera;
  bool _busy = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cams = await availableCameras();
    _camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    final controller = CameraController(
      _camera!,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    if (!mounted) return;
    _controller = controller;
    await controller.startImageStream(_onFrame);
    setState(() {});
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _handled) return;
    _busy = true;
    try {
      final input = FaceService.inputImageFromCamera(
          image, _camera!, _camera!.sensorOrientation);
      if (input != null) {
        final codes = await _scanner.processImage(input);
        for (final b in codes) {
          final v = b.rawValue;
          if (v != null && v.startsWith('FCLK:')) {
            _handled = true;
            await _controller?.stopImageStream();
            if (mounted) Navigator.pop(context, v);
            return;
          }
        }
      }
    } catch (_) {
      // отдельные кадры могут не конвертироваться — пропускаем
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Сканируйте QR на проходной')),
      body: ctrl == null || !ctrl.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(child: CameraPreview(ctrl)),
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.accent, width: 3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const Positioned(
                  left: 0, right: 0, bottom: 40,
                  child: Center(
                    child: Text('Наведите камеру на код терминала',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
    );
  }
}
