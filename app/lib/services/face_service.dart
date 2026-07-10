import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Детекция лица, проверка живости и вычисление эмбеддинга.
/// Эмбеддинг сравнивается на сервере (клиенту не доверяем — раздел 6 ТЗ).
class FaceService {
  static final FaceDetector detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // вероятность улыбки, открытости глаз
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  static Interpreter? _interpreter;
  static const int _embSize = 112; // вход MobileFaceNet 112x112

  /// Загрузка TFLite-модели эмбеддинга (положите файл в assets/models/).
  static Future<bool> loadModel() async {
    if (_interpreter != null) return true;
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      return true;
    } catch (_) {
      return false; // модели нет — экран покажет инструкцию
    }
  }

  static bool get modelReady => _interpreter != null;

  // ---------- Конвертация кадра камеры в InputImage для ML Kit ----------
  static InputImage? inputImageFromCamera(
      CameraImage image, CameraDescription camera, int sensorOrientation) {
    final rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
            InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  static Future<List<Face>> detectFromInputImage(InputImage input) =>
      detector.processImage(input);

  /// Кадр камеры → JPEG (data-URL) для серверной проверки живости.
  /// Поддерживает NV21 (Android) и BGRA8888 (iOS). Возвращает null при сбое.
  static String? cameraImageToDataUrl(CameraImage image) {
    try {
      final w = image.width, h = image.height;
      final out = img.Image(width: w, height: h);
      if (image.format.group == ImageFormatGroup.bgra8888) {
        final bytes = image.planes.first.bytes;
        final rowStride = image.planes.first.bytesPerRow;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final i = y * rowStride + x * 4;
            out.setPixelRgb(x, y, bytes[i + 2], bytes[i + 1], bytes[i]);
          }
        }
      } else {
        // NV21: Y-плоскость + чередующиеся V,U
        final nv21 = image.planes.first.bytes;
        final frameSize = w * h;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final yv = nv21[y * w + x] & 0xff;
            final uvIndex = frameSize + (y >> 1) * w + (x & ~1);
            final v = (nv21[uvIndex] & 0xff) - 128;
            final u = (nv21[uvIndex + 1] & 0xff) - 128;
            var r = (yv + 1.370705 * v).round();
            var g = (yv - 0.337633 * u - 0.698001 * v).round();
            var b = (yv + 1.732446 * u).round();
            out.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
          }
        }
      }
      final jpg = img.encodeJpg(out, quality: 80);
      return 'data:image/jpeg;base64,${base64Encode(jpg)}';
    } catch (_) {
      return null;
    }
  }

  // ---------- Эмбеддинг из готового снимка (файла) ----------
  static Future<List<double>> embedFromFile(String path, Face face) async {
    if (_interpreter == null) {
      throw 'Модель распознавания не загружена. Добавьте assets/models/mobilefacenet.tflite';
    }
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw 'Не удалось прочитать снимок';

    // обрезаем по рамке лица с небольшим отступом
    final r = face.boundingBox;
    final pad = r.width * 0.15;
    final x = (r.left - pad).clamp(0, decoded.width - 1).toInt();
    final y = (r.top - pad).clamp(0, decoded.height - 1).toInt();
    final w = (r.width + pad * 2).clamp(1, decoded.width - x).toInt();
    final h = (r.height + pad * 2).clamp(1, decoded.height - y).toInt();
    final crop = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    final resized = img.copyResize(crop, width: _embSize, height: _embSize);

    // нормализация [-1, 1]
    final input = List.generate(1, (_) => List.generate(_embSize,
        (yy) => List.generate(_embSize, (xx) {
          final p = resized.getPixel(xx, yy);
          return [(p.r - 127.5) / 128, (p.g - 127.5) / 128, (p.b - 127.5) / 128];
        })));

    final outLen = _interpreter!.getOutputTensor(0).shape.last;
    final output = [List<double>.filled(outLen, 0.0)]; // форма [1, outLen]
    _interpreter!.run(input, output);

    // L2-нормализация выходного вектора
    final vec = List<double>.from(output[0]);
    double norm = sqrt(vec.fold(0.0, (s, v) => s + v * v));
    if (norm == 0) norm = 1;
    return vec.map((v) => v / norm).toList();
  }

  static void dispose() {
    detector.close();
    _interpreter?.close();
  }
}

/// Проверка живости: пользователь должен выполнить ИМЕННО то действие,
/// которое случайно назначил сервер (blink / turn_left / turn_right / smile).
/// Это защищает от заранее записанного видео и фото (раздел 6 ТЗ, уровень 1).
class LivenessTracker {
  final String challenge;
  LivenessTracker(this.challenge);

  bool _eyesWereOpen = false;
  bool passed = false;
  double score = 0;

  /// Возвращает подсказку/прогресс. Обновляет passed/score.
  String update(Face face) {
    switch (challenge) {
      case 'blink':
        final l = face.leftEyeOpenProbability ?? 1;
        final r = face.rightEyeOpenProbability ?? 1;
        final open = l > 0.6 && r > 0.6;
        final closed = l < 0.25 && r < 0.25;
        if (open) _eyesWereOpen = true;
        if (_eyesWereOpen && closed) { passed = true; score = 0.95; }
        return passed ? 'Готово' : 'Моргните';
      case 'turn_left':
        final y = face.headEulerAngleY ?? 0;
        score = (y / 30).clamp(0, 1).toDouble();
        if (y > 22) { passed = true; score = 0.95; }
        return passed ? 'Готово' : 'Поверните голову влево';
      case 'turn_right':
        final y = face.headEulerAngleY ?? 0;
        score = (-y / 30).clamp(0, 1).toDouble();
        if (y < -22) { passed = true; score = 0.95; }
        return passed ? 'Готово' : 'Поверните голову вправо';
      case 'smile':
        final s = face.smilingProbability ?? 0;
        score = s;
        if (s > 0.8) { passed = true; score = 0.95; }
        return passed ? 'Готово' : 'Улыбнитесь :)';
      default:
        return 'Смотрите в камеру';
    }
  }

  Map<String, dynamic> toJson() =>
      {'challenge': challenge, 'passed': passed, 'score': score};
}
