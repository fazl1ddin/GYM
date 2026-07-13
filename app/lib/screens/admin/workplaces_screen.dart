import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
import 'map_picker_screen.dart';
import 'qr_terminal_screen.dart';

class WorkplacesScreen extends StatefulWidget {
  const WorkplacesScreen({super.key});
  @override
  State<WorkplacesScreen> createState() => _WorkplacesScreenState();
}

class _WorkplacesScreenState extends State<WorkplacesScreen> {
  List<Workplace> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await ApiClient.instance.workplaces();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      builder: (_) => const _WorkplaceForm(),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(Workplace w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить рабочее место?'),
        content: Text('«${w.name}» будет удалено. Отметки сотрудников сохранятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.deleteWorkplace(w.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('Добавить', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                      SizedBox(height: 60),
                      EmptyState(
                        icon: Icons.location_off_outlined,
                        title: 'Пока нет рабочих мест',
                        subtitle: 'Добавьте первое место кнопкой «Добавить» и задайте геозону на карте',
                      ),
                    ])
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final w = _items[i];
                  return SoftCard(
                    child: Row(
                      children: [
                        const Icon(Icons.place, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(w.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (w.address != null)
                                Text(w.address!, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                              Text(
                                w.lat != null
                                    ? 'радиус ${w.radiusM} м · ${w.lat!.toStringAsFixed(4)}, ${w.lng!.toStringAsFixed(4)}'
                                    : 'координаты не заданы',
                                style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Показать QR терминала',
                          icon: const Icon(Icons.qr_code_2, color: AppColors.accent),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => QrTerminalScreen(workplaceId: w.id, workplaceName: w.name))),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          onPressed: () => _delete(w),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _WorkplaceForm extends StatefulWidget {
  const _WorkplaceForm();
  @override
  State<_WorkplaceForm> createState() => _WorkplaceFormState();
}

class _WorkplaceFormState extends State<_WorkplaceForm> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  double? _lat;
  double? _lng;
  int _radius = 150;
  bool _requireQr = false;
  bool _saving = false;
  String? _error;

  bool get _hasGeo => _lat != null && _lng != null;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    FocusScope.of(context).unfocus();
    final zone = await Navigator.push<GeoZone>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLat: _lat,
          initialLng: _lng,
          initialRadius: _radius,
        ),
      ),
    );
    if (zone != null) {
      setState(() {
        _lat = zone.lat;
        _lng = zone.lng;
        _radius = zone.radiusM;
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus(); // прячем клавиатуру перед закрытием листа
    setState(() { _saving = true; _error = null; });
    try {
      await ApiClient.instance.createWorkplace({
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'lat': _lat,
        'lng': _lng,
        'radiusM': _radius,
        'requireQr': _requireQr,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
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
            const Text('Новое рабочее место',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 12),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Адрес')),
            const SizedBox(height: 12),
            _geoCard(),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Требовать QR проходной'),
              subtitle: const Text('Отметка только после сканирования кода терминала'),
              value: _requireQr,
              activeThumbColor: AppColors.accent,
              onChanged: (v) => setState(() => _requireQr = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Создать'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _geoCard() => InkWell(
        onTap: _pickOnMap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hasGeo ? AppColors.accent : AppColors.line),
          ),
          child: Row(
            children: [
              Icon(_hasGeo ? Icons.location_on : Icons.add_location_alt,
                  color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_hasGeo ? 'Геозона задана' : 'Выбрать геозону на карте',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      _hasGeo
                          ? 'радиус $_radius м · ${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}'
                          : 'Точка и радиус зоны отметки',
                      style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.inkSoft),
            ],
          ),
        ),
      );
}
