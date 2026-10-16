import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../providers.dart';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat.yMMMd().format(t);
}

String formatDateTime(DateTime t) => DateFormat('d MMM y, h:mm a').format(t);

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? scheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('permission-denied')) {
    return 'Not allowed. Make sure your e-mail is verified.';
  }
  if (s.contains('network') || s.contains('Network') || s.contains('offline')) {
    return 'You appear to be offline. Please try again when connected.';
  }
  return s.replaceFirst('Exception: ', '');
}

class StatusChip extends StatelessWidget {
  final ItemStatus status;
  final bool dense;
  const StatusChip(this.status, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: dense ? 6 : 10,
      vertical: dense ? 2 : 4,
    ),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: status.color.withValues(alpha: 0.6)),
    ),
    child: Text(
      status.label.toUpperCase(),
      style: TextStyle(
        color: status.color,
        fontWeight: FontWeight.w700,
        fontSize: dense ? 10 : 12,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class ClaimStatusChip extends StatelessWidget {
  final ClaimStatus status;
  const ClaimStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.label,
      style: TextStyle(color: status.color, fontWeight: FontWeight.w600),
    ),
  );
}

/// Shows a network URL (Firebase Storage) or a local file (demo / pending).
class ItemImage extends StatelessWidget {
  final String? url;
  final IconData fallbackIcon;
  final BoxFit fit;
  const ItemImage(
    this.url, {
    super.key,
    this.fallbackIcon = Icons.image_outlined,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        fallbackIcon,
        size: 36,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    final u = url;
    if (u == null || u.isEmpty) return placeholder;
    if (u.startsWith('http')) {
      return Image.network(
        u,
        fit: fit,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (c, child, p) => p == null ? child : placeholder,
      );
    }
    return Image.file(File(u), fit: fit, errorBuilder: (_, _, _) => placeholder);
  }
}

class ItemCard extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;
  final Widget? trailing;
  const ItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: ItemImage(
                item.imageUrls.firstOrNull,
                fallbackIcon: item.categoryInfo.icon,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(item.status, dense: true),
                        const SizedBox(width: 6),
                        Text(
                          item.isFound ? 'FOUND REPORT' : 'LOST REPORT',
                          style: t.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      style: t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 14),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            '${item.locationName} · ${timeAgo(item.occurredAt)}',
                            style: t.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

/// Shown at the top of the app whenever the device (or demo) is offline.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: online
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: Colors.grey.shade800,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline – showing cached data. New reports are saved '
                      'and will upload automatically.',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const InfoBox({super.key, required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
