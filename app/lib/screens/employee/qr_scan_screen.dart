import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../../services/face_service.dart';

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
      backgroundColor: Colors.black,
      body: ctrl == null || !ctrl.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(child: CameraPreview(ctrl)),
                const Center(
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: CustomPaint(painter: _BracketPainter()),
                  ),
                ),
                Positioned(
                  left: 0, right: 0, bottom: 44,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('Наведите камеру на код терминала',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Уголки-брекеты рамки сканирования QR (как в дизайне).
class _BracketPainter extends CustomPainter {
  const _BracketPainter();

  static const _len = 34.0;
  static const _r = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    // верх-лево
    canvas.drawPath(
        Path()
          ..moveTo(0, _len + _r)
          ..lineTo(0, _r)
          ..arcToPoint(const Offset(_r, 0), radius: const Radius.circular(_r))
          ..lineTo(_len + _r, 0),
        p);
    // верх-право
    canvas.drawPath(
        Path()
          ..moveTo(w - _len - _r, 0)
          ..lineTo(w - _r, 0)
          ..arcToPoint(Offset(w, _r), radius: const Radius.circular(_r))
          ..lineTo(w, _len + _r),
        p);
    // низ-лево
    canvas.drawPath(
        Path()
          ..moveTo(0, h - _len - _r)
          ..lineTo(0, h - _r)
          ..arcToPoint(Offset(_r, h), radius: const Radius.circular(_r), clockwise: false)
          ..lineTo(_len + _r, h),
        p);
    // низ-право
    canvas.drawPath(
        Path()
          ..moveTo(w - _len - _r, h)
          ..lineTo(w - _r, h)
          ..arcToPoint(Offset(w, h - _r), radius: const Radius.circular(_r), clockwise: false)
          ..lineTo(w, h - _len - _r),
        p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
