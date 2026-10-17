import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/location.dart';
import '../widgets/common.dart';
import 'browse_screen.dart';

TileLayer osmTiles() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.campus.finderskeepers',
);

Widget osmAttribution() =>
    const SimpleAttributionWidget(source: Text('OpenStreetMap contributors'));

/// Map of open items. Markers sit on the *approximate* (grid-snapped)
/// location with a translucent radius, so the exact spot is never revealed.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  TypeFilter _type = TypeFilter.all;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(recentItemsProvider).value ?? const <Item>[];
    final items = filterItems(all, type: _type);
    final me = ref.watch(userLocationProvider);
    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: AppConfig.campusCenter,
            initialZoom: AppConfig.campusZoom,
          ),
          children: [
            osmTiles(),
            CircleLayer(
              circles: [
                for (final i in items)
                  CircleMarker(
                    point: LatLng(i.lat, i.lng),
                    radius: 60,
                    useRadiusInMeter: true,
                    color: i.status.color.withValues(alpha: 0.12),
                    borderColor: i.status.color.withValues(alpha: 0.4),
                    borderStrokeWidth: 1,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final i in items)
                  Marker(
                    point: LatLng(i.lat, i.lng),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _preview(i),
                      child: CircleAvatar(
                        backgroundColor: i.status.color,
                        child: Icon(
                          i.categoryInfo.icon,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (me.status == LocationStatus.onCampus)
              MarkerLayer(
                markers: [
                  Marker(
                    point: me.point!,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            osmAttribution(),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: SegmentedButton<TypeFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TypeFilter.all, label: Text('All open')),
                  ButtonSegment(value: TypeFilter.lost, label: Text('Lost')),
                  ButtonSegment(value: TypeFilter.found, label: Text('Found')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _preview(Item item) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ItemCard(
              item: item,
              onTap: () {
                Navigator.pop(c);
                openItem(context, item.id);
              },
            ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Location shown is approximate (±100 m) to protect privacy.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
