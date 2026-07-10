import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils.dart';
import 'checkin_screen.dart';
import 'enroll_screen.dart';
import 'history_screen.dart';

class EmployeeHome extends StatefulWidget {
  const EmployeeHome({super.key});
  @override
  State<EmployeeHome> createState() => _EmployeeHomeState();
}

class _EmployeeHomeState extends State<EmployeeHome> {
  ShiftStatus? _status;
  List<AttendanceRecord> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final (st, recs) = await ApiClient.instance.myAttendance();
      setState(() { _status = st; _records = recs; });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkin(String type) async {
    final user = context.read<Session>().user!;
    if (!user.enrolled) {
      final done = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => const EnrollScreen()));
      if (done == true) await context.read<Session>().refresh();
      return;
    }
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => CheckinScreen(type: type)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    final onShift = _status?.onShift ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FaceClock'),
        actions: [
          IconButton(
            tooltip: 'История',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => HistoryScreen(records: _records))),
          ),
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<Session>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Здравствуйте', style: TextStyle(color: AppColors.inkSoft)),
                      Text(user.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.accentSoft,
                  child: Text(user.name.isNotEmpty ? user.name[0] : '?',
                      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!user.enrolled) _enrollBanner(),
            _statusCard(onShift),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loading ? null : () => _checkin(onShift ? 'out' : 'in'),
              style: ElevatedButton.styleFrom(
                backgroundColor: onShift ? AppColors.ink : AppColors.accent,
              ),
              icon: const Icon(Icons.face, color: Colors.white),
              label: Text(onShift ? 'Отметить уход' : 'Отметить приход'),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text('Нажмите и подтвердите лицо в камере',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
            ),
            const SizedBox(height: 22),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const Text('Последние отметки',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            if (_loading && _records.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (_records.isEmpty)
              const Text('Пока нет отметок', style: TextStyle(color: AppColors.inkSoft))
            else
              ..._records.take(6).map(_recordTile),
          ],
        ),
      ),
    );
  }

  Widget _enrollBanner() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SoftCard(
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.accent),
              const SizedBox(width: 12),
              const Expanded(child: Text('Зарегистрируйте лицо, чтобы отмечаться')),
              TextButton(
                onPressed: () async {
                  final done = await Navigator.push<bool>(context,
                      MaterialPageRoute(builder: (_) => const EnrollScreen()));
                  if (done == true) await context.read<Session>().refresh();
                },
                child: const Text('Начать'),
              ),
            ],
          ),
        ),
      );

  Widget _statusCard(bool onShift) => SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                    color: onShift ? AppColors.success : AppColors.inkSoft, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(onShift ? 'Вы на смене' : 'Не на смене',
                    style: TextStyle(
                        color: onShift ? AppColors.success : AppColors.inkSoft,
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              onShift && _status?.since != null ? fmtDuration(_status!.since!) : '—',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
            ),
            Text(
              onShift && _status?.since != null
                  ? 'Приход в ${fmtTime(_status!.since!)}'
                  : 'Отметьте приход, чтобы начать смену',
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
            ),
          ],
        ),
      );

  Widget _recordTile(AttendanceRecord r) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(r.type == 'in' ? Icons.login : Icons.logout,
                color: r.type == 'in' ? AppColors.success : AppColors.ink, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(r.type == 'in' ? 'Приход' : 'Уход',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(fmtDateTime(r.time),
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
            const SizedBox(width: 10),
            StatusPill(statusLabel(r.status), statusColor(r.status)),
          ],
        ),
      );
}
