import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/ui_kit.dart';
import 'employees_screen.dart';
import 'anomalies_screen.dart';
import 'workplaces_screen.dart';
import 'timesheet_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      _OverviewTab(),
      EmployeesScreen(),
      AnomaliesScreen(),
      TimesheetScreen(),
      WorkplacesScreen(),
    ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader('Администрирование', actions: [
              HeaderAction(Icons.logout, () => context.read<Session>().logout()),
            ]),
            Expanded(child: IndexedStack(index: _tab, children: pages)),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          NavItem(Icons.dashboard_outlined, 'Обзор'),
          NavItem(Icons.people_outline, 'Сотрудники'),
          NavItem(Icons.warning_amber_rounded, 'Аномалии'),
          NavItem(Icons.grid_view_rounded, 'Табель'),
          NavItem(Icons.place_outlined, 'Места'),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _stats = await ApiClient.instance.stats();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final s = _stats ?? {};
    String v(String k) => '${s[k] ?? 0}';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
        children: [
          _section('Сегодня', [
            _stat('Приходов', v('checkinsToday'), Icons.login, AppColors.accent),
            _stat('На смене', v('onShift'), Icons.badge, AppColors.success),
            _stat('Опоздали', v('lateToday'), Icons.timer_off, AppColors.warning),
            _stat('Отсутствуют', v('absentToday'), Icons.person_off, AppColors.danger),
            _stat('На проверке', v('pending'), Icons.hourglass_bottom, AppColors.warning),
            _stat('Событий', v('todayEvents'), Icons.event_note, AppColors.ink),
          ]),
          _section('Проверки сегодня', [
            _stat('Подтверждено', v('confirmedToday'), Icons.check_circle, AppColors.success),
            _stat('Отклонено', v('rejectedToday'), Icons.cancel, AppColors.danger),
            _stat('Высокий риск', v('highRiskToday'), Icons.gpp_maybe, AppColors.warning),
            _stat('Офлайн', v('offlineToday'), Icons.cloud_off, AppColors.ink),
          ]),
          _section('Всего', [
            _stat('Сотрудников', v('employees'), Icons.people, AppColors.accent),
            _stat('Лицо зарег.', v('enrolled'), Icons.face_retouching_natural, AppColors.success),
            _stat('Рабочих мест', v('workplaces'), Icons.place, AppColors.ink),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> cards) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 0, 12),
            child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cards.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 132, // фикс-высота карточки — не зависит от ширины экрана
            ),
            itemBuilder: (_, i) => cards[i],
          ),
        ],
      );

  Widget _stat(String label, String value, IconData icon, Color color) => SoftCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
