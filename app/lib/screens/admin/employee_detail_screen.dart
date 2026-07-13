import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../widgets/ui_kit.dart';

/// Детализация сотрудника: профиль + подробный журнал отметок
/// (время, тип, место, дистанция, метод, статус, риск).
class EmployeeDetailScreen extends StatefulWidget {
  final AppUser user;
  const EmployeeDetailScreen({super.key, required this.user});
  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  List<AttendanceRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _records = await ApiClient.instance.attendanceLog(employeeId: widget.user.id);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(u.name, showBack: true),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                        children: [
                          _profile(u),
                          const SizedBox(height: 18),
                          const Text('Журнал отметок',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          if (_records.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: EmptyState(
                                icon: Icons.history_toggle_off,
                                title: 'Отметок пока нет',
                              ),
                            )
                          else
                            ..._records.map(_recordTile),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profile(AppUser u) {
    final ins = _records.where((r) => r.type == 'in').length;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: u.isAdmin ? AppColors.accentSoft : AppColors.line,
                child: Icon(u.isAdmin ? Icons.shield : Icons.person,
                    color: u.isAdmin ? AppColors.accent : AppColors.inkSoft),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('@${u.login}${u.isAdmin ? ' · админ' : ''}',
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                  ],
                ),
              ),
              if (!u.active) const StatusPill('отключён', AppColors.danger),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _mini('Приходов', '$ins', AppColors.accent),
              const SizedBox(width: 10),
              _mini('Лицо', u.enrolled ? 'есть' : 'нет', u.enrolled ? AppColors.success : AppColors.inkSoft),
              const SizedBox(width: 10),
              _mini('Устройство', u.deviceBound ? 'привязано' : 'нет', u.deviceBound ? AppColors.success : AppColors.inkSoft),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String k, String v, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
              const SizedBox(height: 2),
              Text(k, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
            ],
          ),
        ),
      );

  Widget _recordTile(AttendanceRecord r) {
    final chips = <Widget>[
      if (r.workplaceName != null) _chip(Icons.place, r.workplaceName!),
      if (r.distanceM != null) _chip(Icons.social_distance, '${r.distanceM!.round()} м'),
      if (r.qrOk == true) _chip(Icons.qr_code, 'QR'),
      if (r.offline) _chip(Icons.cloud_off, 'офлайн'),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(r.type == 'in' ? Icons.login : Icons.logout,
                  color: r.type == 'in' ? AppColors.success : AppColors.ink, size: 20),
              const SizedBox(width: 10),
              Text(r.type == 'in' ? 'Приход' : 'Уход',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(fmtDateTime(r.time),
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
              const SizedBox(width: 8),
              StatusPill(statusLabel(r.status), statusColor(r.status)),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          if (r.riskScore > 0 || r.riskFlags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Риск ${r.riskScore}${r.riskFlags.isNotEmpty ? ' · ${r.riskFlags.join(', ')}' : ''}',
                style: TextStyle(
                    fontSize: 12,
                    color: r.riskScore >= 60 ? AppColors.danger : AppColors.warning)),
          ],
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.inkSoft),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
