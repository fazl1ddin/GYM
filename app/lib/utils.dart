import 'theme.dart';
import 'package:flutter/material.dart';

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${two(d.hour)}:${two(d.minute)}';
}

String fmtDateTime(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

/// Длительность от момента прихода до сейчас в формате Ч:ММ.
String fmtDuration(int fromMs) {
  final mins = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(fromMs)).inMinutes;
  return '${mins ~/ 60}:${two(mins % 60)}';
}

String statusLabel(String s) => switch (s) {
      'confirmed' => 'Подтверждено',
      'pending' => 'На проверке',
      'rejected' => 'Отклонено',
      _ => s,
    };

Color statusColor(String s) => switch (s) {
      'confirmed' => AppColors.success,
      'pending' => AppColors.warning,
      'rejected' => AppColors.danger,
      _ => AppColors.inkSoft,
    };

String challengeLabel(String c) => switch (c) {
      'blink' => 'Моргните',
      'turn_left' => 'Поверните голову влево',
      'turn_right' => 'Поверните голову вправо',
      'smile' => 'Улыбнитесь',
      _ => 'Смотрите в камеру',
    };
