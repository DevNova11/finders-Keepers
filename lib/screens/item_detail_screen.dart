import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../providers.dart';
import '../services/matching.dart';
import '../widgets/common.dart';
import 'browse_screen.dart';
import 'claim_review_screen.dart';
import 'claim_screen.dart';
import 'map_screen.dart';
import 'my_claim_screen.dart';
import 'report_screen.dart';

class ItemDetailScreen extends ConsumerWidget {
  final String itemId;
  const ItemDetailScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemProvider(itemId));
    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(icon: Icons.error_outline, title: friendlyError(e)),
      ),
      data: (item) => item == null
          ? Scaffold(
              appBar: AppBar(),
              body: const EmptyState(
                icon: Icons.search_off,
                title: 'This item no longer exists',
              ),
            )
          : _ItemView(item: item),
    );
  }
}

class _ItemView extends ConsumerWidget {
  final Item item;
  const _ItemView({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;
    final isMine = item.reporterId == user.uid;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.isFound ? 'Found item' : 'Lost item'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'close'
                ? _close(context, ref)
                : _reportAbuse(context, ref),
            itemBuilder: (_) => [
              if (isMine && item.status.isOpen)
                const PopupMenuItem(value: 'close', child: Text('Close report')),
              if (!isMine)
                const PopupMenuItem(
                  value: 'abuse',
                  child: Text('Report suspicious post'),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _Gallery(item: item),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusChip(item.status),
                    const SizedBox(width: 8),
                    Icon(item.categoryInfo.icon, size: 18),
                    const SizedBox(width: 4),
                    Text(item.categoryInfo.label, style: t.bodySmall),
                  ],
                ),
                const SizedBox(height: 10),
                Text(item.title, style: t.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  '${item.isFound ? 'Found' : 'Lost'} ${formatDateTime(item.occurredAt)}'
                  ' · reported by ${isMine ? 'you' : item.reporterAlias}',
                  style: t.bodySmall,
                ),
                if (item.color.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Colour: ${item.color}', style: t.bodyMedium),
                ],
                const SizedBox(height: 12),
                Text(item.description, style: t.bodyLarge),
              ],
            ),
          ),
          ..._actions(context, ref, isMine, user),
          const SectionTitle('APPROXIMATE LOCATION'),
          _MiniMap(item: item),
          if (item.isFound && item.verificationQuestions.isNotEmpty) ...[
            const SectionTitle('OWNERSHIP QUESTIONS'),
            for (final (i, q) in item.verificationQuestions.indexed)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
                title: Text(q),
              ),
          ],
          if (isMine) _PrivateDetails(item: item),
          const SectionTitle('STATUS HISTORY'),
          _Timeline(item: item),
          if (isMine && item.status.isOpen) _Matches(item: item),
        ],
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    bool isMine,
    AppUser user,
  ) {
    final widgets = <Widget>[];
    Widget button(Widget b) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(width: double.infinity, child: b),
    );

    if (!isMine) {
      if (item.isFound) {
        final claimId = Claim.idFor(item.id, user.uid);
        final mine = ref
            .watch(myClaimsProvider)
            .value
            ?.where((c) => c.id == claimId)
            .firstOrNull;
        if (mine != null) {
          widgets.add(
            button(
              OutlinedButton.icon(
                icon: const Icon(Icons.assignment_outlined),
                label: Text('Your claim: ${mine.status.label}'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyClaimScreen(claimId: mine.id),
                  ),
                ),
              ),
            ),
          );
        } else if (item.status == ItemStatus.found) {
          widgets.add(
            button(
              FilledButton.icon(
                icon: const Icon(Icons.front_hand_outlined),
                label: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('This is mine — claim it'),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ClaimScreen(item: item)),
                ),
              ),
            ),
          );
        }
      } else if (item.status == ItemStatus.lost) {
        widgets.add(
          button(
            FilledButton.icon(
              icon: const Icon(Icons.volunteer_activism),
              label: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('I found this'),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ReportScreen(type: ItemType.found, linkedLostItem: item),
                ),
              ),
            ),
          ),
        );
        widgets.add(
          const InfoBox(
            icon: Icons.info_outline,
            text:
                'You will file a found report with secret questions. The '
                'owner then claims it through the normal verification flow — '
                'no personal contact details are exchanged.',
          ),
        );
      }
      return widgets;
    }

    // Reporter's own item.
    if (item.isFound) {
      widgets.add(_ClaimsList(item: item));
    } else {
      widgets.add(_LinkedFoundReports(item: item));
      if (item.status == ItemStatus.lost || item.status == ItemStatus.claimed) {
        widgets.add(
          button(
            OutlinedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('I got it back'),
              onPressed: () => _setStatus(
                context,
                ref,
                ItemStatus.returned,
                'Owner marked as recovered',
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    ItemStatus status,
    String note,
  ) async {
    try {
      await ref.read(backendProvider).setItemStatus(item, status, note);
      if (context.mounted) showSnack(context, 'Marked as ${status.label}');
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close this report?'),
        content: const Text(
          'It will be hidden from the open listings. Use this if the item '
          'was handed to campus security or is no longer relevant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Close report'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _setStatus(context, ref, ItemStatus.closed, 'Closed by reporter');
    }
  }

  Future<void> _reportAbuse(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Report suspicious post'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'e.g. fake listing, asking for money, personal data',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      await ref.read(backendProvider).reportAbuse(item.id, reason);
      if (context.mounted) showSnack(context, 'Thanks — moderators will review it.');
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }
}

class _Gallery extends StatelessWidget {
  final Item item;
  const _Gallery({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.imageUrls.isEmpty) {
      return SizedBox(
        height: 160,
        child: ItemImage(null, fallbackIcon: item.categoryInfo.icon),
      );
    }
    return SizedBox(
      height: 260,
      child: PageView(
        children: [
          for (final u in item.imageUrls)
            ItemImage(u, fallbackIcon: item.categoryInfo.icon),
        ],
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  final Item item;
  const _MiniMap({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = LatLng(item.lat, item.lng);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 170,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: p,
                  initialZoom: 16.5,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                ),
                children: [
                  osmTiles(),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: p,
                        radius: 110,
                        useRadiusInMeter: true,
                        color: item.status.color.withValues(alpha: 0.18),
                        borderColor: item.status.color,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.place_outlined),
          title: Text(item.locationName),
          subtitle: const Text('Shown as a ~100 m area to protect privacy'),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final Item item;
  const _Timeline({required this.item});

  @override
  Widget build(BuildContext context) {
    final steps = item.isFound
        ? [ItemStatus.found, ItemStatus.claimed, ItemStatus.returned]
        : [ItemStatus.lost, ItemStatus.claimed, ItemStatus.returned];
    final reached = item.history.map((e) => e.status).toSet();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final (i, s) in steps.indexed) ...[
                if (i > 0)
                  Expanded(
                    child: Divider(
                      thickness: 2,
                      color: reached.contains(s) ? s.color : null,
                    ),
                  ),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: reached.contains(s)
                          ? s.color
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        reached.contains(s) ? Icons.check : Icons.circle_outlined,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(s.label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final e in item.history.reversed)
          ListTile(
            dense: true,
            leading: Icon(Icons.circle, size: 12, color: e.status.color),
            title: Text('${e.status.label} — ${e.note}'),
            subtitle: Text(formatDateTime(e.at)),
          ),
      ],
    );
  }
}

class _PrivateDetails extends ConsumerWidget {
  final Item item;
  const _PrivateDetails({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secret = ref.watch(secretProvider(item.id)).value;
    if (secret == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('PRIVATE (ONLY YOU)'),
        if (secret.exactLat != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.gps_fixed),
            title: const Text('Exact location'),
            subtitle: Text(
              '${secret.exactLat!.toStringAsFixed(5)}, '
              '${secret.exactLng!.toStringAsFixed(5)}',
            ),
          ),
        if (secret.privateNotes.isNotEmpty)
          ListTile(
            dense: true,
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: const Text('Notes'),
            subtitle: Text(secret.privateNotes),
          ),
        if (item.isFound)
          ListTile(
            dense: true,
            leading: const Icon(Icons.lock_outline),
            title: Text('${secret.answerHashes.length} secret answer(s) stored'),
            subtitle: const Text(
              'Stored as salted hashes — not even shown to you again.',
            ),
          ),
      ],
    );
  }
}

class _ClaimsList extends ConsumerWidget {
  final Item item;
  const _ClaimsList({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(claimsForItemProvider(item.id)).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('OWNERSHIP CLAIMS (${claims.length})'),
        if (claims.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('No claims yet. You will be notified when someone claims it.'),
          ),
        for (final c in claims)
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(c.claimantAlias),
              subtitle: Text('Submitted ${timeAgo(c.createdAt)}'),
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

class _LinkedFoundReports extends ConsumerWidget {
  final Item item;
  const _LinkedFoundReports({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked = ref.watch(linkedItemsProvider(item.id)).value ?? const [];
    if (linked.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('SOMEONE MAY HAVE FOUND THIS!'),
        const InfoBox(
          icon: Icons.celebration_outlined,
          text:
              'Open the found report and claim it by answering the finder\'s '
              'questions.',
        ),
        for (final f in linked)
          ItemCard(item: f, onTap: () => openItem(context, f.id)),
      ],
    );
  }
}

class _Matches extends ConsumerWidget {
  final Item item;
  const _Matches({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(recentItemsProvider).value ?? const <Item>[];
    final matches = findMatches(item, all);
    if (matches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('POSSIBLE MATCHES'),
        for (final m in matches)
          ItemCard(
            item: m.item,
            onTap: () => openItem(context, m.item.id),
            trailing: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(m.score * 100).round()}%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text('match', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
