import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<Session>().login(_login.text.trim(), _pass.text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _serverSettings() async {
    final ctrl = TextEditingController(text: ApiClient.instance.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Адрес сервера'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'http://10.0.2.2:3000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('ОК')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) await ApiClient.instance.setBaseUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFF57C8FF)]),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.face_retouching_natural, color: Colors.white, size: 34),
                  ),
                  const SizedBox(height: 18),
                  const Text('FaceClock',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  const Text('Учёт времени по лицу',
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
                  const SizedBox(height: 28),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _login,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Логин', prefixIcon: Icon(Icons.person_outline)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          obscureText: true,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(labelText: 'Пароль', prefixIcon: Icon(Icons.lock_outline)),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: AppColors.danger)),
                        ],
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Войти'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: _serverSettings,
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Настройка сервера'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
