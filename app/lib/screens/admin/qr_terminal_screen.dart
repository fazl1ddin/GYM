import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../api/api_client.dart';
import '../../theme.dart';

/// Терминал проходной: показывает QR-код рабочего места, который сам
/// обновляется каждые ~30 секунд (улучшение №3). Экран открывают на планшете
/// или мониторе у входа; сотрудник сканирует свежий код при отметке.
class QrTerminalScreen extends StatefulWidget {
  final int workplaceId;
  final String workplaceName;
  const QrTerminalScreen({super.key, required this.workplaceId, required this.workplaceName});
  @override
  State<QrTerminalScreen> createState() => _QrTerminalScreenState();
}

class _QrTerminalScreenState extends State<QrTerminalScreen> {
  String? _payload;
  int _secondsLeft = 0;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _refresh() async {
    try {
      final d = await ApiClient.instance.workplaceQr(widget.workplaceId);
      if (mounted) setState(() { _payload = d['payload']; _secondsLeft = d['secondsLeft'] ?? 0; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _tick() {
    if (_secondsLeft <= 1) {
      _refresh();
    } else {
      setState(() => _secondsLeft--);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Терминал · ${widget.workplaceName}')),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: AppColors.danger))
            : _payload == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: QrImageView(data: _payload!, size: 240),
                      ),
                      const SizedBox(height: 20),
                      Text('Код обновится через $_secondsLeft с',
                          style: const TextStyle(color: AppColors.inkSoft)),
                      const SizedBox(height: 8),
                      const Text('Сканируйте этот код в приложении при отметке',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
      ),
    );
  }
}
