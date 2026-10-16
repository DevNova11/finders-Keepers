import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers.dart';
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(recentItemsProvider);
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
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No matching items',
                  subtitle: 'Try another search, or report what you lost.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(recentItemsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96, top: 4),
                  itemCount: list.length,
                  itemBuilder: (_, i) => ItemCard(
                    item: list[i],
                    onTap: () => openItem(context, list[i].id),
                  ),
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
