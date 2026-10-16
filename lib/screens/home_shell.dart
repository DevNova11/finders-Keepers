import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers.dart';
import '../services/notifications.dart';
import '../services/outbox.dart';
import '../widgets/common.dart';
import 'activity_screen.dart';
import 'browse_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'report_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    final backend = ref.read(backendProvider);
    if (!backend.isDemo) Notifications.initPush(backend.saveFcmToken);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(matchWatcherProvider);
    final pending = ref.watch(outboxProvider).length;
    final incoming =
        ref
            .watch(incomingClaimsProvider)
            .value
            ?.where((c) => c.status == ClaimStatus.pending)
            .length ??
        0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: const [
                  BrowseScreen(),
                  MapScreen(),
                  ActivityScreen(),
                  ProfileScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tab <= 1
          ? FloatingActionButton.extended(
              onPressed: () => showReportChooser(context),
              icon: const Icon(Icons.add),
              label: const Text('Report'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Browse',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: incoming + pending > 0,
              label: Text('${incoming + pending}'),
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: const Icon(Icons.inbox),
            label: 'Activity',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

Future<void> showReportChooser(BuildContext context) async {
  final type = await showModalBottomSheet<ItemType>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: ItemStatus.lost.color,
              child: const Icon(Icons.search_off, color: Colors.white),
            ),
            title: const Text('I lost something'),
            subtitle: const Text('Post it so finders can reach you'),
            onTap: () => Navigator.pop(c, ItemType.lost),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: ItemStatus.found.color,
              child: const Icon(Icons.volunteer_activism, color: Colors.white),
            ),
            title: const Text('I found something'),
            subtitle: const Text(
              'Set secret questions only the owner can answer',
            ),
            onTap: () => Navigator.pop(c, ItemType.found),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (type != null && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReportScreen(type: type)),
    );
  }
}
