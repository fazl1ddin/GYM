import 'package:flutter/material.dart';
import '../../api/models.dart';
import '../../theme.dart';
import '../../utils.dart';

class HistoryScreen extends StatelessWidget {
  final List<AttendanceRecord> records;
  const HistoryScreen({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История отметок')),
      body: records.isEmpty
          ? const Center(child: Text('Пока нет отметок', style: TextStyle(color: AppColors.inkSoft)))
          : ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = records[i];
                return SoftCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(r.type == 'in' ? Icons.login : Icons.logout,
                          color: r.type == 'in' ? AppColors.success : AppColors.ink),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.type == 'in' ? 'Приход' : 'Уход',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(fmtDateTime(r.time),
                                style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                            if (r.riskFlags.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(r.riskFlags.join(', '),
                                    style: const TextStyle(color: AppColors.warning, fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                      StatusPill(statusLabel(r.status), statusColor(r.status)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
