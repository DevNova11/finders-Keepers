import 'package:finders_keepers/models/models.dart';
import 'package:finders_keepers/screens/browse_screen.dart';
import 'package:finders_keepers/services/image_processing.dart';
import 'package:finders_keepers/services/matching.dart';
import 'package:finders_keepers/services/verification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

Item _item(
  String id,
  ItemType type, {
  String title = 'Black wallet',
  String desc = 'leather wallet near library',
  String category = 'wallet',
  String color = 'black',
  double lat = 13.0115,
  double lng = 80.2360,
  String reporter = 'u1',
  ItemStatus? status,
  List<String> hashes = const [],
}) {
  final now = DateTime(2026, 10, 1);
  return Item(
    id: id,
    type: type,
    title: title,
    description: desc,
    category: category,
    color: color,
    status:
        status ?? (type == ItemType.lost ? ItemStatus.lost : ItemStatus.found),
    locationName: 'Main Library',
    lat: lat,
    lng: lng,
    occurredAt: now,
    createdAt: now,
    updatedAt: now,
    reporterId: reporter,
    reporterAlias: 'A B.',
    keywords: extractKeywords([title, desc, color]),
    imageHashes: hashes,
  );
}

Claim _claim(List<String> answers) => Claim(
  id: 'i_u2',
  itemId: 'i',
  itemTitle: 'Wallet',
  itemReporterId: 'u1',
  claimantId: 'u2',
  claimantAlias: 'C D.',
  answers: answers,
  description: 'Mine',
  status: ClaimStatus.pending,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group('Verification', () {
    final secret = Verification.buildSecret(
      expectedAnswers: ['Woodland', '3|three'],
    );

    test('answers are stored only as hashes', () {
      final all = secret.answerHashes.values.expand((e) => e).join();
      expect(all.toLowerCase(), isNot(contains('woodland')));
      expect(secret.answerHashes['1'], hasLength(2));
    });

    test('normalisation tolerates case, punctuation and articles', () {
      expect(
        Verification.score(_claim(['  the WOODLAND!! ', 'Three']), secret),
        1.0,
      );
    });

    test('wrong answers lower the score', () {
      expect(Verification.score(_claim(['Nike', '3']), secret), 0.5);
      expect(Verification.evaluate(_claim(['Nike', '4']), secret), [
        false,
        false,
      ]);
    });

    test('salt makes identical answers hash differently per item', () {
      final other = Verification.buildSecret(expectedAnswers: ['Woodland']);
      expect(other.answerHashes['0'], isNot(secret.answerHashes['0']));
    });

    test('handover code is 6 digits and verifies only with the right code', () {
      final code = Verification.newHandoverCode();
      expect(code, matches(RegExp(r'^\d{6}$')));
      final salt = Verification.newSalt(8);
      final h = Verification.handoverHash(code, salt);
      expect(Verification.handoverHash(code, salt), h);
      final wrong = code == '000000' ? '000001' : '000000';
      expect(Verification.handoverHash(wrong, salt), isNot(h));
    });

    test('claim ids enforce one claim per user per item', () {
      expect(Claim.idFor('item1', 'userA'), 'item1_userA');
    });
  });

  group('Privacy', () {
    test('public coordinates are snapped to ~110 m grid', () {
      expect(approximate(13.011876), 13.012);
      expect(approximate(80.235449), 80.235);
    });

    test('alias hides surname and e-mail', () {
      const u = AppUser(
        uid: 'x',
        email: 'asha.raman@campus.edu',
        displayName: 'Asha Raman',
        emailVerified: true,
      );
      expect(u.alias, 'Asha R.');
    });
  });

  group('Matching', () {
    test('similar lost and found reports score highly', () {
      final lost = _item('l', ItemType.lost);
      final found = _item('f', ItemType.found, reporter: 'u2');
      expect(scoreMatch(lost, found).score, greaterThan(0.7));
      expect(findMatches(lost, [found]), hasLength(1));
    });

    test('unrelated items, own items and same-type items are excluded', () {
      final lost = _item('l', ItemType.lost);
      final unrelated = _item(
        'f',
        ItemType.found,
        title: 'Blue umbrella',
        desc: 'umbrella at sports complex',
        category: 'other',
        color: 'blue',
        lat: 13.0,
        lng: 80.22,
        reporter: 'u2',
      );
      final own = _item('f2', ItemType.found);
      final sameType = _item('l2', ItemType.lost, reporter: 'u3');
      expect(findMatches(lost, [unrelated, own, sameType]), isEmpty);
    });

    test('identical photos boost the score', () {
      final lost = _item(
        'l',
        ItemType.lost,
        title: 'thing',
        desc: 'item',
        category: 'other',
        color: '',
        hashes: ['ffff0000ffff0000'],
      );
      final withPhoto = _item(
        'f',
        ItemType.found,
        title: 'object',
        desc: 'misc',
        category: 'bag',
        color: '',
        reporter: 'u2',
        hashes: ['ffff0000ffff0000'],
      );
      final noPhoto = _item(
        'g',
        ItemType.found,
        title: 'object',
        desc: 'misc',
        category: 'bag',
        color: '',
        reporter: 'u2',
      );
      expect(
        scoreMatch(lost, withPhoto).score - scoreMatch(lost, noPhoto).score,
        closeTo(0.25, 0.001),
      );
    });
  });

  group('Image processing', () {
    img.Image gradient(bool flip) {
      final im = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final v = ((flip ? 63 - x : x) * 4) % 256;
          im.setPixelRgb(x, y, v, (y * 4) % 256, 128);
        }
      }
      return im;
    }

    test('dHash is stable and distinguishes different images', () {
      final a = ImageProcessing.dHash(gradient(false));
      final b = ImageProcessing.dHash(gradient(false));
      final c = ImageProcessing.dHash(gradient(true));
      expect(a, hasLength(16));
      expect(ImageProcessing.similarity(a, b), 1.0);
      expect(ImageProcessing.similarity(a, c), lessThan(0.5));
    });

    test('processing strips EXIF and returns a JPEG', () {
      final src = gradient(false)..exif.imageIfd['Make'] = 'SpyCam';
      final out = ImageProcessing.processBytes(img.encodeJpg(src), blur: true);
      final decoded = img.decodeJpg(out.jpeg)!;
      expect(decoded.exif.imageIfd['Make'], isNull);
    });
  });

  group('Search', () {
    final items = [
      _item('1', ItemType.lost),
      _item(
        '2',
        ItemType.found,
        title: 'Red keys',
        desc: 'keychain',
        category: 'keys',
        color: 'red',
      ),
      _item(
        '3',
        ItemType.found,
        title: 'Old wallet',
        status: ItemStatus.returned,
      ),
    ];

    test('free-text search matches title, description and prefixes', () {
      expect(filterItems(items, query: 'wall').map((i) => i.id), ['1']);
      expect(filterItems(items, query: 'red key').map((i) => i.id), ['2']);
    });

    test('type, category and resolved filters', () {
      expect(filterItems(items, type: TypeFilter.found).map((i) => i.id), [
        '2',
      ]);
      expect(filterItems(items, category: 'keys').map((i) => i.id), ['2']);
      expect(filterItems(items, includeResolved: true), hasLength(3));
    });
  });

  group('Near-you recommendations', () {
    const here = LatLng(13.0115, 80.2360);

    test('only nearby open items by others, nearest first', () {
      final near = _item(
        'n',
        ItemType.found,
        title: 'Umbrella',
        desc: 'blue',
        category: 'other',
        reporter: 'u2',
        lat: 13.0116,
        lng: 80.2361,
      );
      final farther = _item(
        'm',
        ItemType.found,
        title: 'Bottle',
        desc: 'steel',
        category: 'bottle',
        reporter: 'u2',
        lat: 13.0150,
        lng: 80.2360,
      );
      final tooFar = _item('x', ItemType.found, reporter: 'u2', lat: 13.05);
      final returned = _item(
        'r',
        ItemType.found,
        reporter: 'u2',
        status: ItemStatus.returned,
      );
      final own = _item('o', ItemType.found, reporter: 'me');
      final recs = recommendNearby(
        [farther, near, tooFar, returned, own],
        here,
        uid: 'me',
      );
      expect(recs.map((r) => r.item.id), ['n', 'm']);
      expect(recs.first.metres, lessThan(50));
    });

    test('items relevant to my lost report are ranked first', () {
      final myLost = _item('l', ItemType.lost, reporter: 'me');
      final closeUnrelated = _item(
        'u',
        ItemType.found,
        title: 'Umbrella',
        desc: 'blue',
        category: 'other',
        reporter: 'u2',
        lat: 13.0115,
      );
      final fartherWallet = _item(
        'w',
        ItemType.found,
        reporter: 'u2',
        lat: 13.0140,
      );
      final recs = recommendNearby(
        [closeUnrelated, fartherWallet, myLost],
        here,
        uid: 'me',
      );
      expect(recs.first.item.id, 'w');
      expect(recs.first.reason, contains('Black wallet'));
      expect(recs[1].reason, isNull);
    });

    test('hidden (moderated) posts are never recommended', () {
      final hidden = _item(
        'h',
        ItemType.found,
        reporter: 'u2',
      ).copyWith(hidden: true);
      expect(recommendNearby([hidden], here, uid: 'me'), isEmpty);
    });

    test('distance formatting', () {
      expect(formatDistance(123), '120 m');
      expect(formatDistance(2340), '2.3 km');
    });
  });

  group('Moderation model', () {
    test('report round-trips through a map', () {
      final r = AbuseReport(
        id: 'r1',
        itemId: 'i1',
        itemTitle: 'Scam post',
        itemReporterId: 'u9',
        itemReporterAlias: 'Sam S.',
        reporterId: 'u1',
        reason: 'asks for money',
        status: ReportStatus.open,
        createdAt: DateTime(2026, 10, 1),
      );
      final back = AbuseReport.fromMap(r.toMap());
      expect(back.status, ReportStatus.open);
      expect(back.itemReporterId, 'u9');
    });

    test('hidden flag survives serialisation and defaults to false', () {
      final i = _item('i', ItemType.found);
      expect(Item.fromMap(i.toMap()).hidden, isFalse);
      final h = i.copyWith(hidden: true, moderationNote: 'spam');
      final back = Item.fromMap(h.toMap());
      expect(back.hidden, isTrue);
      expect(back.moderationNote, 'spam');
    });
  });
}
