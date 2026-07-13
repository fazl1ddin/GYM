import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';

/// Модальная форма добавления/редактирования сотрудника.
class EmployeeForm extends StatefulWidget {
  final AppUser? user;
  final List<Workplace> workplaces;
  const EmployeeForm({super.key, this.user, required this.workplaces});
  @override
  State<EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<EmployeeForm> {
  late final TextEditingController _name;
  late final TextEditingController _login;
  final _pass = TextEditingController();
  late bool _isAdmin;
  late bool _active;
  int? _workplaceId;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _name = TextEditingController(text: u?.name ?? '');
    _login = TextEditingController(text: u?.login ?? '');
    _isAdmin = u?.isAdmin ?? false;
    _active = u?.active ?? true;
    _workplaceId = u?.workplaceId;
  }

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus(); // прячем клавиатуру перед закрытием формы
    setState(() { _saving = true; _error = null; });
    try {
      if (_editing) {
        await ApiClient.instance.updateEmployee(widget.user!.id, {
          'name': _name.text.trim(),
          'role': _isAdmin ? 'admin' : 'employee',
          'workplaceId': _workplaceId,
          'active': _active,
          if (_pass.text.isNotEmpty) 'password': _pass.text,
        });
      } else {
        await ApiClient.instance.createEmployee({
          'name': _name.text.trim(),
          'login': _login.text.trim(),
          'password': _pass.text,
          'role': _isAdmin ? 'admin' : 'employee',
          'workplaceId': _workplaceId,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset(String field) async {
    try {
      await ApiClient.instance.updateEmployee(widget.user!.id, {field: true});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(field == 'resetFace' ? 'Регистрация лица сброшена' : 'Привязка устройства сброшена')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: AppColors.line, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(_editing ? 'Редактирование' : 'Новый сотрудник',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Имя')),
            const SizedBox(height: 12),
            TextField(
              controller: _login,
              enabled: !_editing,
              decoration: const InputDecoration(labelText: 'Логин'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              decoration: InputDecoration(
                  labelText: _editing ? 'Новый пароль (если менять)' : 'Пароль'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _workplaceId,
              decoration: const InputDecoration(labelText: 'Рабочее место'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не указано')),
                ...widget.workplaces.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))),
              ],
              onChanged: (v) => setState(() => _workplaceId = v),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Роль администратора'),
              value: _isAdmin,
              activeThumbColor: AppColors.accent,
              onChanged: (v) => setState(() => _isAdmin = v),
            ),
            if (_editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Активен'),
                value: _active,
                activeThumbColor: AppColors.success,
                onChanged: (v) => setState(() => _active = v),
              ),
            if (_editing)
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => _reset('resetFace'),
                  icon: const Icon(Icons.face_retouching_off, size: 18),
                  label: const Text('Сбросить лицо'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _reset('resetDevice'),
                  icon: const Icon(Icons.phonelink_erase, size: 18),
                  label: const Text('Сбросить устройство'),
                ),
              ]),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_editing ? 'Сохранить' : 'Создать'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
