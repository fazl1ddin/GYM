import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/face_service.dart';
import '../theme.dart';

/// Превью фронтальной камеры с потоковой детекцией лица и овалом-подсказкой.
/// Родитель получает контроллер через [onReady] (чтобы сделать снимок),
/// а найденные лица — через [onFace].
class FaceScanView extends StatefulWidget {
  final void Function(CameraController controller) onReady;
  final void Function(Face? face) onFace;
  final String prompt;
  final bool success;

  /// Прогресс удержания лица 0..1 — рисует кольцо вокруг овала (0 = скрыто).
  final double progress;

  const FaceScanView({
    super.key,
    required this.onReady,
    required this.onFace,
    required this.prompt,
    this.success = false,
    this.progress = 0,
  });

  @override
  State<FaceScanView> createState() => FaceScanViewState();
}

class FaceScanViewState extends State<FaceScanView> {
  CameraController? _controller;
  CameraDescription? _camera;
  CameraImage? _lastImage;
  bool _busy = false;
  bool _streaming = false;
  DateTime _lastProc = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(milliseconds: 150);

  /// JPEG текущего кадра (data-URL) для серверной проверки живости.
  String? snapshotDataUrl() =>
      _lastImage != null ? FaceService.cameraImageToDataUrl(_lastImage!) : null;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    _camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    final controller = CameraController(
      _camera!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    if (!mounted) return;
    _controller = controller;
    widget.onReady(controller);
    await _startStream();
    setState(() {});
  }

  Future<void> _startStream() async {
    if (_streaming || _controller == null) return;
    _streaming = true;
    await _controller!.startImageStream((image) async {
      _lastImage = image;
      if (_busy) return;
      // Троттлинг: не чаще ~6 кадров/сек — детекция тяжёлая, поток отдаёт кадры
      // намного чаще, чем нужно для плавной проверки живости.
      final now = DateTime.now();
      if (now.difference(_lastProc) < _minInterval) return;
      _lastProc = now;
      _busy = true;
      try {
        final input = FaceService.inputImageFromCamera(
            image, _camera!, _camera!.sensorOrientation);
        if (input != null) {
          final faces = await FaceService.detectFromInputImage(input);
          if (mounted) widget.onFace(faces.isNotEmpty ? faces.first : null);
        }
      } catch (_) {
        // отдельные кадры могут не конвертироваться — пропускаем
      } finally {
        _busy = false;
      }
    });
  }

  /// Останавливает поток (перед снимком).
  Future<void> stopStream() async {
    if (_streaming && _controller != null) {
      await _controller!.stopImageStream();
      _streaming = false;
    }
  }

  /// Возобновляет поток детекции (после снимка или ошибки).
  Future<void> resumeStream() => _startStream();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final color = widget.success ? AppColors.success : AppColors.accent;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(ctrl),
                    // овал-маска
                    Center(
                      child: Container(
                        width: 220,
                        height: 280,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(160),
                          border: Border.all(color: color, width: 3),
                        ),
                      ),
                    ),
                    // кольцо прогресса удержания
                    if (widget.progress > 0)
                      Center(
                        child: SizedBox(
                          width: 264,
                          height: 264,
                          child: CircularProgressIndicator(
                            value: widget.progress.clamp(0, 1),
                            strokeWidth: 5,
                            color: color,
                            backgroundColor: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
          child: Text(widget.prompt,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
