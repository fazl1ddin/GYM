import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';
import '../../theme.dart';

/// Результат выбора геозоны на карте.
class GeoZone {
  final double lat;
  final double lng;
  final int radiusM;
  const GeoZone(this.lat, this.lng, this.radiusM);
}

/// Полноэкранный выбор геозоны: карта OSM (без API-ключа), центральный пин =
/// выбранная точка, окружность радиуса в метрах и слайдер радиуса.
/// Возвращает [GeoZone] через Navigator.pop.
class MapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final int initialRadius;
  const MapPickerScreen({super.key, this.initialLat, this.initialLng, this.initialRadius = 150});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _ctrl = MapController();
  // Ташкент по умолчанию, если координаты ещё не заданы.
  static const _fallback = LatLng(41.3110, 69.2797);

  late LatLng _center;
  late double _radius;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _center = (widget.initialLat != null && widget.initialLng != null)
        ? LatLng(widget.initialLat!, widget.initialLng!)
        : _fallback;
    _radius = widget.initialRadius.toDouble().clamp(50, 1000);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onMove(MapCamera camera, bool hasGesture) {
    if (hasGesture) setState(() => _center = camera.center);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final g = await LocationService.current();
      if (!mounted) return;
      final p = LatLng(g.lat, g.lng);
      _ctrl.move(p, 16.5);
      setState(() => _center = p);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось получить геопозицию: $e')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Геозона места')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _ctrl,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 16,
                    minZoom: 3,
                    maxZoom: 19,
                    onPositionChanged: _onMove,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.fazliddin.faceclock',
                    ),
                    CircleLayer(circles: [
                      CircleMarker(
                        point: _center,
                        radius: _radius,
                        useRadiusInMeter: true,
                        color: AppColors.accent.withValues(alpha: 0.14),
                        borderColor: AppColors.accent,
                        borderStrokeWidth: 2,
                      ),
                    ]),
                  ],
                ),
                // Центральный пин: остаётся в центре, карта движется под ним.
                const IgnorePointer(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: Icon(Icons.location_on, color: AppColors.accent, size: 40),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.touch_app, size: 16, color: AppColors.accent),
                      SizedBox(width: 7),
                      Text('Двигайте карту, чтобы поставить точку',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton.small(
                    heroTag: 'loc',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.accent,
                    onPressed: _locating ? null : _useMyLocation,
                    child: _locating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          _controls(),
        ],
      ),
    );
  }

  Widget _controls() => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        decoration: const BoxDecoration(
          color: AppColors.panel,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Радиус геозоны',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                const Spacer(),
                Text('${_radius.round()} м',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accent)),
              ],
            ),
            Slider(
              value: _radius,
              min: 50,
              max: 1000,
              divisions: 95,
              activeColor: AppColors.accent,
              onChanged: (v) => setState(() => _radius = v),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Широта ${_center.latitude.toStringAsFixed(5)}   ·   Долгота ${_center.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  context, GeoZone(_center.latitude, _center.longitude, _radius.round())),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
}
