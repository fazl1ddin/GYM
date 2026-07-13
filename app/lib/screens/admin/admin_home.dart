import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../state/session.dart';
import '../../theme.dart';
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
      appBar: AppBar(
        title: const Text('Администрирование'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<Session>().logout(),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Обзор'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Сотрудники'),
          NavigationDestination(icon: Icon(Icons.warning_amber_outlined), selectedIcon: Icon(Icons.warning), label: 'Аномалии'),
          NavigationDestination(icon: Icon(Icons.table_chart_outlined), selectedIcon: Icon(Icons.table_chart), label: 'Табель'),
          NavigationDestination(icon: Icon(Icons.place_outlined), selectedIcon: Icon(Icons.place), label: 'Места'),
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Сегодня', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.28,
            children: [
              _stat('На смене', '${s['onShift'] ?? 0}', Icons.badge, AppColors.success),
              _stat('Сотрудников', '${s['employees'] ?? 0}', Icons.people, AppColors.accent),
              _stat('На проверке', '${s['pending'] ?? 0}', Icons.warning_amber, AppColors.warning),
              _stat('Событий за день', '${s['todayEvents'] ?? 0}', Icons.event_note, AppColors.ink),
            ],
          ),
        ],
      ),
    );
  }

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
