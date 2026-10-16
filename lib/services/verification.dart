import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/models.dart';

/// Ownership-verification primitives.
///
/// Finders attach private questions to a found item. The *answers* are never
/// stored in plain text: each acceptable answer is normalised and hashed with
/// a per-item random salt. A claimant's answers are hashed the same way on the
/// reviewer's device and compared, giving an objective score the finder uses
/// alongside the claimant's free-text description and optional proof photo.
class Verification {
  Verification._();

  static final _rng = Random.secure();

  static String newSalt([int bytes = 16]) {
    final b = List<int>.generate(bytes, (_) => _rng.nextInt(256));
    return base64Url.encode(b);
  }

  /// Lower-cases, strips punctuation/diacritics-ish noise and collapses
  /// whitespace so "Black, Nike!" and "black nike" compare equal.
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\b(the|a|an|my|its|it is|is)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String hash(String answer, String salt) =>
      sha256.convert(utf8.encode('$salt|${normalize(answer)}')).toString();

  /// The finder may enter alternatives separated by `|`, e.g. "black|dark grey".
  static List<String> hashAlternatives(String expected, String salt) => expected
      .split('|')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => hash(e, salt))
      .toList();

  static ItemSecret buildSecret({
    required List<String> expectedAnswers,
    double? exactLat,
    double? exactLng,
    String privateNotes = '',
  }) {
    final salt = newSalt();
    return ItemSecret(
      salt: salt,
      answerHashes: {
        for (var i = 0; i < expectedAnswers.length; i++)
          '$i': hashAlternatives(expectedAnswers[i], salt),
      },
      exactLat: exactLat,
      exactLng: exactLng,
      privateNotes: privateNotes,
    );
  }

  /// Per-question match result for a claim, evaluated by the reviewer.
  static List<bool> evaluate(Claim claim, ItemSecret secret) {
    final results = <bool>[];
    for (var i = 0; i < claim.answers.length; i++) {
      final expected = secret.answerHashes['$i'] ?? const [];
      results.add(expected.contains(hash(claim.answers[i], secret.salt)));
    }
    return results;
  }

  static double score(Claim claim, ItemSecret secret) {
    final r = evaluate(claim, secret);
    if (r.isEmpty) return 0;
    return r.where((e) => e).length / r.length;
  }

  // ---- Handover -----------------------------------------------------------

  /// 6-digit one-time code generated on the *claimant's* device once a claim
  /// is approved. Only its salted hash is stored on the claim. At the
  /// physical handover the claimant reads the code out and the finder types
  /// it in; the item is only marked returned when the hashes match, proving
  /// the person collecting the item is the approved claimant.
  static String newHandoverCode() =>
      List.generate(6, (_) => _rng.nextInt(10)).join();

  /// Must stay identical to the check in firestore.rules:
  ///   hashing.sha256(code + salt).toHexString().lower()
  static String handoverHash(String code, String salt) =>
      sha256.convert(utf8.encode('${code.trim()}$salt')).toString();
}
