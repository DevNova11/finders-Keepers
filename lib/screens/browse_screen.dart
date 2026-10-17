import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../providers.dart';
import '../services/location.dart';
import '../services/matching.dart';
import '../widgets/common.dart';
import 'item_detail_screen.dart';

enum TypeFilter { all, lost, found }

/// Pure filtering logic, shared with tests.
List<Item> filterItems(
  List<Item> items, {
  String query = '',
  TypeFilter type = TypeFilter.all,
  String? category,
  bool includeResolved = false,
}) {
  final tokens = query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  return items.where((i) {
    if (type == TypeFilter.lost && i.type != ItemType.lost) return false;
    if (type == TypeFilter.found && i.type != ItemType.found) return false;
    if (category != null && i.category != category) return false;
    if (!includeResolved && !i.status.isOpen) return false;
    if (tokens.isEmpty) return true;
    final haystack =
        '${i.title} ${i.description} ${i.locationName} ${i.color} '
                '${i.categoryInfo.label}'
            .toLowerCase();
    return tokens.every(
      (t) => haystack.contains(t) || i.keywords.any((k) => k.startsWith(t)),
    );
  }).toList();
}

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _search = TextEditingController();
  TypeFilter _type = TypeFilter.all;
  String? _category;
  bool _includeResolved = false;
  bool _nearestFirst = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(recentItemsProvider);
    final location = ref.watch(userLocationProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SearchBar(
            controller: _search,
            hintText: 'Search "black wallet", "library"…',
            leading: const Icon(Icons.search),
            trailing: [
              if (_search.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(_search.clear),
                ),
            ],
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<TypeFilter>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: TypeFilter.all, label: Text('All')),
                    ButtonSegment(value: TypeFilter.lost, label: Text('Lost')),
                    ButtonSegment(
                      value: TypeFilter.found,
                      label: Text('Found'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
              ),
              IconButton(
                tooltip: 'Nearest first',
                isSelected: _nearestFirst,
                icon: const Icon(Icons.near_me_outlined),
                selectedIcon: const Icon(Icons.near_me),
                onPressed: () {
                  if (!location.available) {
                    ref.read(userLocationProvider.notifier).request();
                  }
                  setState(() => _nearestFirst = !_nearestFirst);
                },
              ),
              IconButton(
                tooltip: _includeResolved
                    ? 'Hide returned/closed'
                    : 'Show returned/closed',
                isSelected: _includeResolved,
                icon: const Icon(Icons.history),
                onPressed: () =>
                    setState(() => _includeResolved = !_includeResolved),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final c in ItemCategory.all)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: Icon(c.icon, size: 16),
                    label: Text(c.label),
                    selected: _category == c.id,
                    onSelected: (s) =>
                        setState(() => _category = s ? c.id : null),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load items',
              subtitle: friendlyError(e),
            ),
            data: (all) {
              final list = filterItems(
                all,
                query: _search.text,
                type: _type,
                category: _category,
                includeResolved: _includeResolved,
              );
              final here = location.point;
              double? dist(Item i) => here == null
                  ? null
                  : const Distance().as(
                      LengthUnit.Meter,
                      here,
                      LatLng(i.lat, i.lng),
                    );
              if (_nearestFirst && here != null) {
                list.sort((a, b) => dist(a)!.compareTo(dist(b)!));
              }
              final showNearYou =
                  _search.text.isEmpty &&
                  _category == null &&
                  _type == TypeFilter.all;
              if (list.isEmpty && !showNearYou) {
                return const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No matching items',
                  subtitle: 'Try another search, or report what you lost.',
                );
              }
              final offset = showNearYou ? 1 : 0;
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(allItemsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96, top: 4),
                  itemCount: list.length + offset,
                  itemBuilder: (_, index) {
                    if (index < offset) return NearYouSection(items: all);
                    final item = list[index - offset];
                    final d = _nearestFirst ? dist(item) : null;
                    return ItemCard(
                      item: item,
                      onTap: () => openItem(context, item.id),
                      trailing: d == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(formatDistance(d)),
                            ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

void openItem(BuildContext context, String id) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: id)),
);

/// Location-based recommendations: open items around the student, with
/// items relevant to their own reports ranked first. GPS stays on device.
class NearYouSection extends ConsumerWidget {
  final List<Item> items;
  const NearYouSection({super.key, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(userLocationProvider);
    final uid = ref.watch(currentUserProvider)?.uid ?? '';
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Widget header(String subtitle, {Widget? action}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Icon(Icons.near_me, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Near you', style: t.titleSmall),
                Text(subtitle, style: t.bodySmall),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );

    switch (location.status) {
      case LocationStatus.unknown:
      case LocationStatus.denied:
        return Card(
          child: ListTile(
            leading: const Icon(Icons.near_me_outlined),
            title: const Text('See lost & found items near you'),
            subtitle: Text(
              location.status == LocationStatus.denied
                  ? 'Location is off. Enable it to get recommendations.'
                  : 'Your location stays on this phone.',
            ),
            trailing: FilledButton.tonal(
              onPressed: () =>
                  ref.read(userLocationProvider.notifier).request(),
              child: const Text('Enable'),
            ),
          ),
        );
      case LocationStatus.loading:
        if (!location.available) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          );
        }
      case LocationStatus.onCampus:
      case LocationStatus.offCampus:
        break;
    }

    final recs = recommendNearby(items, location.point!, uid: uid);
    final subtitle = location.status == LocationStatus.offCampus
        ? "You're off campus - showing items around the campus centre"
        : 'Open items within 1.5 km, most relevant first';
    final refresh = IconButton(
      tooltip: 'Refresh location',
      icon: const Icon(Icons.my_location, size: 20),
      onPressed: () => ref.read(userLocationProvider.notifier).refresh(),
    );
    if (recs.isEmpty) {
      return header('No open items nearby right now.', action: refresh);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header(subtitle, action: refresh),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: recs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _NearCard(rec: recs[i]),
          ),
        ),
        const Divider(height: 24),
      ],
    );
  }
}

class _NearCard extends StatelessWidget {
  final NearbyRecommendation rec;
  const _NearCard({required this.rec});

  @override
  Widget build(BuildContext context) {
    final item = rec.item;
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => openItem(context, item.id),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(item.categoryInfo.icon, size: 18),
                    const SizedBox(width: 6),
                    StatusChip(item.status, dense: true),
                    const Spacer(),
                    Text(formatDistance(rec.metres), style: t.labelMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  style: t.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.locationName,
                  style: t.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                if (rec.reason != null)
                  Text(
                    rec.reason!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
