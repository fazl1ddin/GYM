import 'package:flutter/material.dart';
import '../theme.dart';

/// Набор кастомных виджетов, повторяющих дизайн-макет 1:1 — без «материального»
/// вида (без ripple/AppBar/NavigationBar). Каркас MaterialApp остаётся только
/// как инфраструктура навигации.

/// Кастомная шапка экрана (замена AppBar).
class AppHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final bool showBack;
  const AppHeader(this.title, {super.key, this.actions = const [], this.showBack = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 14, 10),
      child: Row(
        children: [
          if (showBack)
            _TapIcon(
              icon: Icons.arrow_back_ios_new,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          if (showBack) const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Иконка-кнопка без ripple.
class _TapIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TapIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: 40, height: 40, child: Icon(icon, color: AppColors.ink, size: 22)),
    );
  }
}

/// Публичная иконка-действие для шапки.
class HeaderAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const HeaderAction(this.icon, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => _TapIcon(icon: icon, onTap: onTap);
}

/// Пункт нижней навигации.
class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Кастомная нижняя навигация (замена NavigationBar): активный пункт — иконка
/// в мягкой акцентной пилюле + акцентная подпись.
class AppBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<NavItem> items;
  const AppBottomNav({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(items.length, (i) {
              final on = i == index;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(items[i].icon, size: 24, color: on ? AppColors.accent : AppColors.inkSoft),
                      const SizedBox(height: 5),
                      Text(items[i].label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: on ? AppColors.accent : AppColors.inkSoft,
                          )),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Первичная кнопка (замена ElevatedButton) — акцентная, скругление 15, w800.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final Color color;
  final IconData? icon;
  const PrimaryButton(this.label, {super.key, this.onTap, this.loading = false, this.color = AppColors.accent, this.icon});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: enabled ? color : color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else ...[
              if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 10)],
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Кастомный тумблер (замена Switch).
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const AppToggle({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.accent : const Color(0xFFCBD5E3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2))],
            ),
          ),
        ),
      ),
    );
  }
}
