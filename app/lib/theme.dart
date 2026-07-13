import 'package:flutter/material.dart';

/// Дизайн-система «Вариант A — Ясный день»: светлый корпоративный стиль,
/// уверенный синий акцент, много воздуха, аккуратные карточки.
class AppColors {
  static const bg = Color(0xFFF5F7FB);
  static const panel = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A2233);
  static const inkSoft = Color(0xFF7A8699);
  static const line = Color(0xFFE7ECF3);
  static const accent = Color(0xFF2B5CFF);
  static const accentSoft = Color(0xFFEAF0FF);
  static const success = Color(0xFF16A06A);
  static const warning = Color(0xFFE8912B);
  static const danger = Color(0xFFE24C4C);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        surface: AppColors.panel,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w800),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink, displayColor: AppColors.ink),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.panel,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
        ),
      ),
    );
  }
}

/// Скруглённая карточка с мягкой тенью — базовый строительный блок UI.
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(color: Color(0x14203A5A), blurRadius: 22, offset: Offset(0, 12)),
        ],
      ),
      child: child,
    );
  }
}

/// Пустое состояние списка: иконка + заголовок + подпись. Оборачивать в
/// прокручиваемый контейнер, чтобы работал pull-to-refresh.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color ?? AppColors.inkSoft),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Цветной статус-бейдж (подтверждено / на проверке / отклонено).
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
