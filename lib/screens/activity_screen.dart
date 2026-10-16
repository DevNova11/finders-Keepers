import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers.dart';
import '../services/outbox.dart';
import '../widgets/common.dart';
import 'browse_screen.dart';
import 'claim_review_screen.dart';
import 'my_claim_screen.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incomingPending =
        ref
            .watch(incomingClaimsProvider)
            .value
            ?.where((c) => c.status == ClaimStatus.pending)
            .length ??
        0;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              const Tab(text: 'My reports'),
              const Tab(text: 'My claims'),
              Tab(
                child: Badge(
                  isLabelVisible: incomingPending > 0,
                  label: Text('$incomingPending'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('To review'),
                  ),
                ),
              ),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [_MyReports(), _MyClaims(), _Incoming()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyReports extends ConsumerWidget {
  const _MyReports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(outboxProvider);
    final items = ref.watch(myItemsProvider).value ?? const <Item>[];
    final pendingIds = pending.map((p) => p.id).toSet();
    final synced = items.where((i) => !pendingIds.contains(i.id)).toList();
    if (pending.isEmpty && synced.isEmpty) {
      return const EmptyState(
        icon: Icons.post_add,
        title: 'Nothing reported yet',
        subtitle: 'Use the Report button to post a lost or found item.',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (pending.isNotEmpty) ...[
          const SectionTitle('WAITING TO UPLOAD'),
          for (final p in pending) _PendingTile(p),
        ],
        if (synced.isNotEmpty) const SectionTitle('POSTED'),
        for (final i in synced)
          ItemCard(item: i, onTap: () => openItem(context, i.id)),
      ],
    );
  }
}

class _PendingTile extends ConsumerWidget {
  final PendingSubmission p;
  const _PendingTile(this.p);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider);
    final outbox = ref.read(outboxProvider.notifier);
    final uploaded = p.uploadedUrls.length;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text(
          '${p.kind == SubmissionKind.claim ? 'Claim: ' : ''}${p.title}',
        ),
        subtitle: Text(
          [
            if (!online) 'Offline — will upload when connected',
            if (online && p.attempts == 0) 'Uploading…',
            if (p.localImages.isNotEmpty)
              'Photos $uploaded/${p.localImages.length}',
            if (p.attempts > 0) 'Attempt ${p.attempts} failed: ${p.lastError}',
          ].join(' · '),
        ),
        isThreeLine: p.attempts > 0,
        trailing: PopupMenuButton<String>(
          onSelected: (v) => v == 'retry' ? outbox.flush() : outbox.discard(p.id),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'retry', child: Text('Retry now')),
            PopupMenuItem(value: 'discard', child: Text('Discard')),
          ],
        ),
      ),
    );
  }
}

class _MyClaims extends ConsumerWidget {
  const _MyClaims();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(myClaimsProvider).value ?? const <Claim>[];
    if (claims.isEmpty) {
      return const EmptyState(
        icon: Icons.assignment_outlined,
        title: 'No claims',
        subtitle: 'Found your item in the listings? Open it and tap "Claim".',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final c in claims)
          Card(
            child: ListTile(
              title: Text(c.itemTitle),
              subtitle: Text('Updated ${timeAgo(c.updatedAt)}'),
              trailing: ClaimStatusChip(c.status),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => MyClaimScreen(claimId: c.id)),
              ),
            ),
          ),
      ],
    );
  }
}

class _Incoming extends ConsumerWidget {
  const _Incoming();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(incomingClaimsProvider).value ?? const <Claim>[];
    if (claims.isEmpty) {
      return const EmptyState(
        icon: Icons.fact_check_outlined,
        title: 'No claims to review',
        subtitle: 'Claims on items you found will appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final c in claims)
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(c.itemTitle),
              subtitle: Text('${c.claimantAlias} · ${timeAgo(c.createdAt)}'),
              trailing: ClaimStatusChip(c.status),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClaimReviewScreen(claimId: c.id),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
