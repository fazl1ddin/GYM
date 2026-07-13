// Базовые тесты FaceClock: чистые утилиты форматирования/статусов и рендер
// компонента StatusPill. Запуск: `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:faceclock/utils.dart';
import 'package:faceclock/theme.dart';

void main() {
  group('utils', () {
    test('two() дополняет нулём', () {
      expect(two(0), '00');
      expect(two(5), '05');
      expect(two(42), '42');
    });

    test('fmtTime форматирует час:минуты', () {
      final ms = DateTime(2026, 1, 2, 9, 5).millisecondsSinceEpoch;
      expect(fmtTime(ms), '09:05');
    });

    test('statusLabel переводит известные статусы', () {
      expect(statusLabel('confirmed'), 'Подтверждено');
      expect(statusLabel('pending'), 'На проверке');
      expect(statusLabel('rejected'), 'Отклонено');
      expect(statusLabel('unknown'), 'unknown');
    });

    test('challengeLabel даёт подсказку живости', () {
      expect(challengeLabel('blink'), 'Моргните');
      expect(challengeLabel('smile'), 'Улыбнитесь');
      expect(challengeLabel('???'), 'Смотрите в камеру');
    });
  });

  testWidgets('StatusPill показывает текст', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatusPill('Подтверждено', AppColors.success)),
    ));
    expect(find.text('Подтверждено'), findsOneWidget);
  });
}
