import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../providers.dart';
import '../services/local_backend.dart';
import '../widgets/common.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final e = (v ?? '').trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      return 'Enter a valid e-mail';
    }
    if (_register && AppConfig.allowedEmailDomains.isNotEmpty) {
      final ok = AppConfig.allowedEmailDomains.any((d) => e.endsWith('@$d'));
      if (!ok) {
        return 'Use your campus e-mail (${AppConfig.allowedEmailDomains.join(', ')})';
      }
    }
    return null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final b = ref.read(backendProvider);
    await _run(
      () => _register
          ? b.register(_name.text, _email.text, _password.text)
          : b.signIn(_email.text, _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.travel_explore, size: 72, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      AppConfig.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Campus lost & found — verified handovers, '
                      'no phone numbers shared.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (backend is LocalBackend) ...[
                      _DemoAccounts(
                        backend: backend,
                        busy: _busy,
                        onPick: (email) => _run(
                          () => backend.signIn(email, LocalBackend.demoPassword),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('or use an account'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          helperText: 'Others only see "First L."',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v ?? '').trim().length < 2
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Campus e-mail',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) => (v ?? '').length < 6
                          ? 'At least 6 characters'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_register ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _register = !_register),
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoAccounts extends StatelessWidget {
  final LocalBackend backend;
  final bool busy;
  final void Function(String email) onPick;
  const _DemoAccounts({
    required this.backend,
    required this.busy,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const InfoBox(
        icon: Icons.science_outlined,
        text:
            'Demo mode: Firebase is not configured, so all data stays on '
            'this device. Switch between demo students to try the full '
            'claim → verify → handover flow.',
      ),
      const SizedBox(height: 8),
      for (final u in backend.demoUsers.take(4))
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(child: Text(u.displayName[0])),
            title: Text(u.displayName),
            subtitle: Text(u.email),
            trailing: const Icon(Icons.login),
            enabled: !busy,
            onTap: () => onPick(u.email),
          ),
        ),
    ],
  );
}
