import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/local_backend.dart';
import '../services/notifications.dart';
import '../widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;
    final backend = ref.watch(backendProvider);
    final items = ref.watch(myItemsProvider).value ?? const <Item>[];
    final returned = items
        .where((i) => i.isFound && i.status == ItemStatus.returned)
        .length;

    return ListView(
      children: [
        const SizedBox(height: 16),
        CircleAvatar(
          radius: 36,
          child: Text(user.displayName.isEmpty ? '?' : user.displayName[0],
              style: const TextStyle(fontSize: 28)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            user.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Center(child: Text(user.email)),
        Center(
          child: Text(
            'Others see you as "${user.alias}"',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Stat(label: 'Reports', value: '${items.length}'),
            _Stat(label: 'Items returned', value: '$returned'),
          ],
        ),
        if (backend is LocalBackend) ...[
          const SectionTitle('DEMO MODE'),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_off),
            title: const Text('Simulate offline'),
            subtitle: const Text(
              'Submissions queue locally and upload when switched back on.',
            ),
            value: ref.watch(simulateOfflineProvider),
            onChanged: (v) => ref.read(simulateOfflineProvider.notifier).set(v),
          ),
          ListTile(
            leading: const Icon(Icons.switch_account),
            title: const Text('Switch demo account'),
            subtitle: const Text('Act as the finder or the owner'),
            onTap: () => backend.signOut(),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Test notification'),
            onTap: () => Notifications.show(
              'Possible match for "White wireless earbuds"',
              'Found: white earbuds case near Central Cafeteria (82% match)',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset demo data'),
            onTap: () async {
              await backend.reset();
              if (context.mounted) showSnack(context, 'Demo data reset.');
            },
          ),
        ],
        const SectionTitle('PRIVACY & SAFETY'),
        const ListTile(
          leading: Icon(Icons.shield_outlined),
          title: Text('Your e-mail and full name are never shown'),
          subtitle: Text('Listings use your alias; chats replace phone numbers.'),
        ),
        const ListTile(
          leading: Icon(Icons.location_searching),
          title: Text('Locations are approximate'),
          subtitle: Text('Public pins are snapped to a ~100 m grid.'),
        ),
        const ListTile(
          leading: Icon(Icons.photo_outlined),
          title: Text('Photo metadata is stripped'),
          subtitle: Text('GPS/EXIF removed; sensitive items blurred.'),
        ),
        const ListTile(
          leading: Icon(Icons.handshake_outlined),
          title: Text('Safe handover'),
          subtitle: Text('Meet at ${AppConfig.recommendedHandoverPoint}.'),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: backend.signOut,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${AppConfig.appName} · ${backend.isDemo ? 'Demo mode (on-device)' : 'Connected to Firebase'}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
