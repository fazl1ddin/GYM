import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../api/api_client.dart';
import '../../theme.dart';

/// Табель: отработанные часы, опоздания, переработки за период (улучшение №6).
/// Экспорт в CSV — кнопкой «Поделиться».
class TimesheetScreen extends StatefulWidget {
  const TimesheetScreen({super.key});
  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await ApiClient.instance.timesheet(from: _fmt(_range.start), to: _fmt(_range.end));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (r != null) { _range = r; _load(); }
  }

  Future<void> _export() async {
    try {
      final csv = await ApiClient.instance.timesheetCsv(from: _fmt(_range.start), to: _fmt(_range.end));
      await Share.share(csv, subject: 'Табель ${_fmt(_range.start)}—${_fmt(_range.end)}.csv');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text('${_fmt(_range.start)} — ${_fmt(_range.end)}'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _rows.isEmpty ? null : _export,
                icon: const Icon(Icons.ios_share, size: 18, color: Colors.white),
                label: const Text('CSV'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const Center(child: Text('Нет данных за период', style: TextStyle(color: AppColors.inkSoft)))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: DataTable(
                          columnSpacing: 20,
                          headingRowColor: WidgetStatePropertyAll(AppColors.accentSoft),
                          columns: const [
                            DataColumn(label: Text('Сотрудник')),
                            DataColumn(label: Text('Дата')),
                            DataColumn(label: Text('Приход')),
                            DataColumn(label: Text('Уход')),
                            DataColumn(label: Text('Часы')),
                            DataColumn(label: Text('Опозд., мин')),
                            DataColumn(label: Text('Перераб., ч')),
                          ],
                          rows: _rows.map((r) => DataRow(cells: [
                                DataCell(Text('${r['name']}')),
                                DataCell(Text('${r['date']}')),
                                DataCell(Text('${r['firstIn'] ?? ''}')),
                                DataCell(Text('${r['lastOut'] ?? ''}')),
                                DataCell(Text('${r['workedHours']}')),
                                DataCell(Text('${r['lateMin']}',
                                    style: TextStyle(color: (r['lateMin'] ?? 0) > 0 ? AppColors.warning : null))),
                                DataCell(Text('${r['overtimeHours']}')),
                              ])).toList(),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}
