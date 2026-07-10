import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
import 'employee_form.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<AppUser> _employees = [];
  List<Workplace> _workplaces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _employees = await ApiClient.instance.employees();
      _workplaces = await ApiClient.instance.workplaces();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openForm([AppUser? user]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      builder: (_) => EmployeeForm(user: user, workplaces: _workplaces),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить сотрудника?'),
        content: Text('${u.name} будет удалён вместе с отметками.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiClient.instance.deleteEmployee(u.id);
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Добавить', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                itemCount: _employees.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final u = _employees[i];
                  return SoftCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: u.isAdmin ? AppColors.accentSoft : AppColors.line,
                          child: Icon(u.isAdmin ? Icons.shield : Icons.person,
                              color: u.isAdmin ? AppColors.accent : AppColors.inkSoft, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(child: Text(u.name,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis)),
                                  if (!u.active) ...[
                                    const SizedBox(width: 6),
                                    const StatusPill('отключён', AppColors.danger),
                                  ],
                                ],
                              ),
                              Text('@${u.login}${u.isAdmin ? ' · админ' : ''}',
                                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                              Row(children: [
                                _tag(u.enrolled ? 'лицо ✓' : 'лицо —', u.enrolled),
                                const SizedBox(width: 6),
                                _tag(u.deviceBound ? 'устр. ✓' : 'устр. —', u.deviceBound),
                              ]),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _openForm(u);
                            if (v == 'delete') _delete(u);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Изменить')),
                            PopupMenuItem(value: 'delete', child: Text('Удалить')),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _tag(String t, bool on) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(t,
            style: TextStyle(fontSize: 11.5, color: on ? AppColors.success : AppColors.inkSoft)),
      );
}
