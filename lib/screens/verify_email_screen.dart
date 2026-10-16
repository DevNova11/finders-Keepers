import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/common.dart';

/// Unverified accounts cannot post or claim (also enforced in the rules),
/// so every claimant is tied to a real campus mailbox.
class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendProvider);
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your e-mail')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mark_email_unread_outlined, size: 72),
            const SizedBox(height: 16),
            Text(
              'We sent a verification link to ${user?.email}. Open it, then '
              'tap "I\'ve verified".',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Verified campus accounts are required to report or claim '
              'items — it keeps fraudulent claims traceable.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                await backend.refreshUser();
                if (context.mounted &&
                    !(backend.currentUser?.emailVerified ?? false)) {
                  showSnack(context, 'Not verified yet.');
                }
              },
              child: const Text("I've verified"),
            ),
            TextButton(
              onPressed: () async {
                await backend.sendVerificationEmail();
                if (context.mounted) showSnack(context, 'E-mail sent again.');
              },
              child: const Text('Resend e-mail'),
            ),
            TextButton(
              onPressed: backend.signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
