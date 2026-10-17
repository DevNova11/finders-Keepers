import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'browse_screen.dart';

/// Moderator dashboard. Only reachable when `admins/{uid}` exists; every
/// action is also enforced by firestore.rules (isAdmin()).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsProvider).value ?? const <AbuseReport>[];
    final open = reports.where((r) => r.status == ReportStatus.open).toList();
    final resolved = reports
        .where((r) => r.status != ReportStatus.open)
        .toList();
    final hidden = (ref.watch(allItemsProvider).value ?? const <Item>[])
        .where((i) => i.hidden)
        .toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Moderation'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Open reports (${open.length})'),
              const Tab(text: 'Overview'),
              Tab(text: 'Hidden posts (${hidden.length})'),
              Tab(text: 'Resolved (${resolved.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReportList(reports: open, empty: 'No open reports. All clear!'),
            const _Overview(),
            _HiddenPosts(items: hidden),
            _ReportList(reports: resolved, empty: 'Nothing resolved yet.'),
          ],
        ),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  final List<AbuseReport> reports;
  final String empty;
  const _ReportList({required this.reports, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return EmptyState(icon: Icons.verified_user_outlined, title: empty);
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [for (final r in reports) _ReportCard(report: r)],
    );
  }
}

class _ReportCard extends ConsumerStatefulWidget {
  final AbuseReport report;
  const _ReportCard({required this.report});

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askNote(String title, String hint) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              ctrl.text.trim().isEmpty ? hint : ctrl.text.trim(),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final backend = ref.read(backendProvider);
    final item = ref.watch(itemProvider(r.itemId)).value;
    final isOpen = r.status == ReportStatus.open;
    final t = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_outlined, color: Colors.red, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.itemTitle,
                    style: t.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(timeAgo(r.createdAt), style: t.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text('Reason: ${r.reason}'),
            const SizedBox(height: 4),
            Text(
              'Posted by ${r.itemReporterAlias}'
              '${item?.hidden == true ? ' · currently HIDDEN' : ''}',
              style: t.bodySmall,
            ),
            if (!isOpen) ...[
              const SizedBox(height: 4),
              Text(
                '${r.status == ReportStatus.actioned ? 'Actioned' : 'Dismissed'}'
                ': ${r.resolution ?? ''}',
                style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('View post'),
                  onPressed: () => openItem(context, r.itemId),
                ),
                if (isOpen && item != null && !item.hidden)
                  FilledButton.icon(
                    icon: const Icon(Icons.visibility_off, size: 18),
                    label: const Text('Hide post'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final note = await _askNote(
                              'Hide this post?',
                              'Removed for violating community guidelines',
                            );
                            if (note == null) return;
                            await _run(() async {
                              await backend.moderateItem(
                                item,
                                hidden: true,
                                note: note,
                              );
                              await backend.resolveReport(
                                r,
                                ReportStatus.actioned,
                                'Post hidden: $note',
                              );
                            }, 'Post hidden');
                          },
                  ),
                if (isOpen)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final note = await _askNote(
                              'Dismiss report?',
                              'No violation found',
                            );
                            if (note == null) return;
                            await _run(
                              () => backend.resolveReport(
                                r,
                                ReportStatus.dismissed,
                                note,
                              ),
                              'Report dismissed',
                            );
                          },
                    child: const Text('Dismiss'),
                  ),
                if (isOpen)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Suspend poster'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final note = await _askNote(
                              'Suspend ${r.itemReporterAlias}?',
                              'Fraudulent post',
                            );
                            if (note == null) return;
                            await _run(() async {
                              await backend.suspendUser(r.itemReporterId, note);
                              if (item != null && !item.hidden) {
                                await backend.moderateItem(
                                  item,
                                  hidden: true,
                                  note: note,
                                );
                              }
                              await backend.resolveReport(
                                r,
                                ReportStatus.actioned,
                                'Poster suspended: $note',
                              );
                            }, 'User suspended and post hidden');
                          },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenPosts extends ConsumerWidget {
  final List<Item> items;
  const _HiddenPosts({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.visibility_outlined,
        title: 'No hidden posts',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final i in items)
          ItemCard(
            item: i,
            onTap: () => openItem(context, i.id),
            trailing: IconButton(
              tooltip: 'Restore post',
              icon: const Icon(Icons.restore),
              onPressed: () async {
                try {
                  await ref
                      .read(backendProvider)
                      .moderateItem(i, hidden: false, note: null);
                  if (context.mounted) showSnack(context, 'Post restored');
                } catch (e) {
                  if (context.mounted) {
                    showSnack(context, friendlyError(e), error: true);
                  }
                }
              },
            ),
          ),
      ],
    );
  }
}

/// Live campus statistics computed from the item feed.
class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(allItemsProvider).value ?? const <Item>[];
    final reports = ref.watch(reportsProvider).value ?? const <AbuseReport>[];
    int count(bool Function(Item) f) => items.where(f).length;

    final byStatus = {
      for (final s in ItemStatus.values) s: count((i) => i.status == s),
    };
    final returned = byStatus[ItemStatus.returned]!;
    final resolvable = items.where((i) => i.status != ItemStatus.closed).length;
    final rate = resolvable == 0 ? 0 : (returned * 100 / resolvable).round();

    final byLocation = <String, int>{};
    for (final i in items.where((i) => i.status.isOpen)) {
      byLocation[i.locationName] = (byLocation[i.locationName] ?? 0) + 1;
    }
    final hotspots = byLocation.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatTile(
              'Open lost',
              '${byStatus[ItemStatus.lost]}',
              ItemStatus.lost.color,
            ),
            _StatTile(
              'Open found',
              '${byStatus[ItemStatus.found]}',
              ItemStatus.found.color,
            ),
            _StatTile(
              'Awaiting handover',
              '${byStatus[ItemStatus.claimed]}',
              ItemStatus.claimed.color,
            ),
            _StatTile('Returned', '$returned', ItemStatus.returned.color),
            _StatTile('Return rate', '$rate%', Colors.teal),
            _StatTile(
              'Open reports',
              '${reports.where((r) => r.status == ReportStatus.open).length}',
              Colors.red,
            ),
          ],
        ),
        const SectionTitle('LOSS HOTSPOTS (OPEN ITEMS)'),
        if (hotspots.isEmpty) const Text('No open items.'),
        for (final e in hotspots.take(6))
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(e.key),
            trailing: Text('${e.value}'),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
    width: 160,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
        Text(label),
      ],
    ),
  );
}
