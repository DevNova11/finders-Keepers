import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'providers.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/verify_email_screen.dart';

class FindersKeepersApp extends StatelessWidget {
  const FindersKeepersApp({super.key});

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00796B),
      brightness: b,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppConfig.appName,
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const AuthGate(),
  );
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final backend = ref.watch(backendProvider);
    return auth.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (user) {
        if (user == null) return const AuthScreen();
        if (!backend.isDemo &&
            AppConfig.requireEmailVerification &&
            !user.emailVerified) {
          return const VerifyEmailScreen();
        }
        if (ref.watch(isSuspendedProvider).value ?? false) {
          return const _SuspendedScreen();
        }
        return const HomeShell();
      },
    );
  }
}

/// Shown to accounts a moderator suspended (rules also block their writes).
class _SuspendedScreen extends ConsumerWidget {
  const _SuspendedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 72, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Account suspended',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'A moderator suspended this account after a report. Contact '
              'the campus lost & found office if you think this is a mistake.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: ref.read(backendProvider).signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}
