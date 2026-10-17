import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'image_processing.dart';

const _stopWords = {
  'the',
  'a',
  'an',
  'and',
  'or',
  'of',
  'in',
  'on',
  'at',
  'to',
  'my',
  'is',
  'it',
  'with',
  'for',
  'near',
  'lost',
  'found',
  'was',
  'i',
  'this',
  'that',
};

/// Search tokens stored on each item (`keywords` array) so Firestore can
/// serve `array-contains` queries without a full-text index.
List<String> extractKeywords(Iterable<String> fields) {
  final out = <String>{};
  for (final f in fields) {
    for (final t in f.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      if (t.length >= 2 && !_stopWords.contains(t)) out.add(t);
    }
  }
  return out.take(40).toList();
}

/// Snaps a coordinate to a coarse grid so the published location is
/// approximate (≈110 m at 3 decimals).
double approximate(double v) {
  final f = pow(10, AppConfig.publicLocationPrecision);
  return (v * f).roundToDouble() / f;
}

class MatchResult {
  final Item item;
  final double score;
  final List<String> reasons;
  const MatchResult(this.item, this.score, this.reasons);
}

/// Scores how likely a lost report and a found report describe the same
/// object. Same logic is mirrored in `functions/index.js` for push alerts.
MatchResult scoreMatch(Item a, Item b) {
  final reasons = <String>[];
  var score = 0.0;

  if (a.category == b.category) {
    score += 0.30;
    reasons.add('Same category');
  }

  final ka = a.keywords.toSet(), kb = b.keywords.toSet();
  if (ka.isNotEmpty && kb.isNotEmpty) {
    final jaccard = ka.intersection(kb).length / ka.union(kb).length;
    score += 0.30 * min(1.0, jaccard * 2.5);
    if (jaccard > 0.15) reasons.add('Similar description');
  }

  if (a.color.isNotEmpty &&
      b.color.isNotEmpty &&
      a.color.toLowerCase().trim() == b.color.toLowerCase().trim()) {
    score += 0.10;
    reasons.add('Same colour');
  }

  final metres = const Distance().as(
    LengthUnit.Meter,
    LatLng(a.lat, a.lng),
    LatLng(b.lat, b.lng),
  );
  if (metres < 600) {
    score += 0.15 * (1 - metres / 600);
    if (metres < 250) reasons.add('Nearby location');
  }

  final days = a.occurredAt.difference(b.occurredAt).inHours.abs() / 24;
  if (days < 7) score += 0.05 * (1 - days / 7);

  var bestImage = 0.0;
  for (final ha in a.imageHashes) {
    for (final hb in b.imageHashes) {
      bestImage = max(bestImage, ImageProcessing.similarity(ha, hb));
    }
  }
  // dHash similarity of unrelated photos hovers around 0.5; rescale.
  if (bestImage > 0.6) {
    score += 0.25 * ((bestImage - 0.6) / 0.4);
    if (bestImage > 0.8) reasons.add('Photos look alike');
  }

  return MatchResult(b, min(1.0, score), reasons);
}

/// Open items of the opposite type, ranked by match score.
List<MatchResult> findMatches(Item item, Iterable<Item> candidates) {
  final results =
      candidates
          .where(
            (c) =>
                c.id != item.id &&
                c.type != item.type &&
                c.status.isOpen &&
                c.reporterId != item.reporterId,
          )
          .map((c) => scoreMatch(item, c))
          .where((m) => m.score >= AppConfig.matchThreshold)
          .toList()
        ..sort((x, y) => y.score.compareTo(x.score));
  return results.take(5).toList();
}

/// A location-based recommendation for the "Near you" section.
class NearbyRecommendation {
  final Item item;
  final double metres;

  /// Why it is recommended beyond being close, e.g. "Could be your keys".
  final String? reason;
  const NearbyRecommendation(this.item, this.metres, [this.reason]);
}

/// Open items close to [here] posted by others, ranked so that items
/// relevant to the user's own open reports come first (a found item in the
/// same category as something they lost, or a lost item matching something
/// they found), then by distance.
List<NearbyRecommendation> recommendNearby(
  Iterable<Item> items,
  LatLng here, {
  required String uid,
  double radiusMetres = 1500,
  int limit = 10,
}) {
  final all = items.toList();
  final mine = all.where((i) => i.reporterId == uid && i.status.isOpen);
  const distance = Distance();
  final recs = <NearbyRecommendation>[];
  for (final i in all) {
    if (i.reporterId == uid || !i.status.isOpen || i.hidden) continue;
    final m = distance.as(LengthUnit.Meter, here, LatLng(i.lat, i.lng));
    if (m > radiusMetres) continue;
    String? reason;
    for (final own in mine.where((o) => o.type != i.type)) {
      if (scoreMatch(own, i).score >= AppConfig.matchThreshold ||
          own.category == i.category) {
        reason = own.type == ItemType.lost
            ? 'Could be your "${own.title}"'
            : 'May be looking for what you found';
        break;
      }
    }
    recs.add(NearbyRecommendation(i, m, reason));
  }
  recs.sort((a, b) {
    final r = (a.reason == null ? 1 : 0).compareTo(b.reason == null ? 1 : 0);
    return r != 0 ? r : a.metres.compareTo(b.metres);
  });
  return recs.take(limit).toList();
}

String formatDistance(double metres) => metres < 1000
    ? '${(metres / 10).round() * 10} m'
    : '${(metres / 1000).toStringAsFixed(1)} km';
