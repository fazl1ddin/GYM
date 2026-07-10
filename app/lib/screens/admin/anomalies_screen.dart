import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
import '../../utils.dart';

/// Очередь аномалий: спорные отметки (risk-score выше порога) не засчитываются
/// автоматически и ждут решения руководителя (раздел 6 ТЗ, уровень 4).
class AnomaliesScreen extends StatefulWidget {
  const AnomaliesScreen({super.key});
  @override
  State<AnomaliesScreen> createState() => _AnomaliesScreenState();
}

class _AnomaliesScreenState extends State<AnomaliesScreen> {
  List<AttendanceRecord> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await ApiClient.instance.anomalies();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(AttendanceRecord r, String decision) async {
    String? comment;
    if (decision == 'reject') {
      final c = TextEditingController();
      comment = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Отклонить отметку'),
          content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Причина (необязательно)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Отклонить')),
          ],
        ),
      );
      if (comment == null) return;
    }
    try {
      await ApiClient.instance.decide(r.id, decision, comment);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 120),
          Icon(Icons.verified, size: 56, color: AppColors.success),
          SizedBox(height: 12),
          Center(child: Text('Спорных отметок нет', style: TextStyle(color: AppColors.inkSoft))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(18),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _card(_items[i]),
      ),
    );
  }

  Widget _card(AttendanceRecord r) => SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (r.photoRef != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      ApiClient.instance.photoUrl(r.photoRef!),
                      headers: ApiClient.instance.imageHeaders,
                      width: 64, height: 64, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _photoStub(),
                    ),
                  )
                else
                  _photoStub(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.employeeName ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text('${r.type == 'in' ? 'Приход' : 'Уход'} · ${fmtDateTime(r.time)}',
                          style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                    ],
                  ),
                ),
                _riskBadge(r.riskScore),
              ],
            ),
            const SizedBox(height: 12),
            if (r.riskFlags.isNotEmpty)
              Wrap(
                spacing: 6, runSpacing: 6,
                children: r.riskFlags
                    .map((f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(f, style: const TextStyle(color: AppColors.warning, fontSize: 12)),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _decide(r, 'reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger)),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Отклонить'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _decide(r, 'confirm'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                    icon: const Icon(Icons.check, size: 18, color: Colors.white),
                    label: const Text('Подтвердить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _photoStub() => Container(
        width: 64, height: 64,
        decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.person, color: AppColors.inkSoft),
      );

  Widget _riskBadge(int score) {
    final color = score >= 60 ? AppColors.danger : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text('$score', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          const Text('риск', style: TextStyle(color: AppColors.inkSoft, fontSize: 10)),
        ],
      ),
    );
  }
}
