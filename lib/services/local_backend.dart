import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'backend.dart';
import 'matching.dart';
import 'verification.dart';

/// Fully on-device backend used when Firebase is not configured. It mirrors
/// the Firebase backend's behaviour (including access rules) so the complete
/// lost → claim → verify → handover flow can be demonstrated on one phone by
/// switching between demo accounts. "Simulate offline" makes every write
/// fail with [NetworkUnavailable] to demonstrate the offline outbox.
class LocalBackend implements Backend {
  LocalBackend._(this._file);

  final File _file;
  final _changes = StreamController<void>.broadcast();
  final _auth = StreamController<AppUser?>.broadcast();

  final Map<String, AppUser> _users = {};
  final Map<String, String> _passwords = {};
  final Map<String, Item> _items = {};
  final Map<String, ItemSecret> _secrets = {};
  final Map<String, Claim> _claims = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, String> _handoverCodes = {};
  String? _currentUid;

  bool simulateOffline = false;

  static const demoPassword = 'demo1234';

  static Future<LocalBackend> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final b = LocalBackend._(File('${dir.path}/demo_db.json'));
    await b._load();
    return b;
  }

  @override
  bool get isDemo => true;

  List<AppUser> get demoUsers => _users.values.toList();

  // ---- persistence ----

  Future<void> _load() async {
    if (await _file.exists()) {
      try {
        final m = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        for (final u in (m['users'] as List)) {
          final um = Map<String, dynamic>.from(u as Map);
          _users[um['uid']] = AppUser(
            uid: um['uid'],
            email: um['email'],
            displayName: um['displayName'],
            emailVerified: true,
          );
          _passwords[um['uid']] = um['password'] ?? demoPassword;
        }
        for (final i in (m['items'] as List)) {
          final it = Item.fromMap(Map<String, dynamic>.from(i as Map));
          _items[it.id] = it;
        }
        (m['secrets'] as Map).forEach((k, v) {
          _secrets[k] = ItemSecret.fromMap(Map<String, dynamic>.from(v));
        });
        for (final c in (m['claims'] as List)) {
          final cl = Claim.fromMap(Map<String, dynamic>.from(c as Map));
          _claims[cl.id] = cl;
        }
        (m['messages'] as Map).forEach((k, v) {
          _messages[k] = (v as List)
              .map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e)))
              .toList();
        });
        (m['handoverCodes'] as Map).forEach((k, v) => _handoverCodes[k] = v);
        _currentUid = m['currentUid'] as String?;
        return;
      } catch (_) {
        // Corrupt file: fall through and reseed.
      }
    }
    _seed();
    await _save();
  }

  Future<void> _save() async {
    final data = {
      'users': _users.values
          .map((u) => {
                'uid': u.uid,
                'email': u.email,
                'displayName': u.displayName,
                'password': _passwords[u.uid],
              })
          .toList(),
      'items': _items.values.map((e) => e.toMap()).toList(),
      'secrets': _secrets.map((k, v) => MapEntry(k, v.toMap())),
      'claims': _claims.values.map((e) => e.toMap()).toList(),
      'messages': _messages.map(
        (k, v) => MapEntry(k, v.map((e) => e.toMap()).toList()),
      ),
      'handoverCodes': _handoverCodes,
      'currentUid': _currentUid,
    };
    final json = jsonEncode(
      data,
      toEncodable: (o) => o is DateTime ? o.toIso8601String() : o.toString(),
    );
    // Write-then-rename so a crash mid-write never corrupts the database.
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(_file.path);
  }

  Future<void> _commit() async {
    await _save();
    _changes.add(null);
  }

  void _requireOnline() {
    if (simulateOffline) throw const NetworkUnavailable('Simulated offline');
  }

  Stream<T> _watch<T>(T Function() compute) async* {
    yield compute();
    await for (final _ in _changes.stream) {
      yield compute();
    }
  }

  void _seed() {
    final now = DateTime.now();
    const users = [
      ('u_asha', 'Asha Raman', 'asha@campus.edu'),
      ('u_ben', 'Ben Thomas', 'ben@campus.edu'),
      ('u_chen', 'Chen Li', 'chen@campus.edu'),
    ];
    for (final (uid, name, email) in users) {
      _users[uid] = AppUser(
        uid: uid,
        email: email,
        displayName: name,
        emailVerified: true,
      );
      _passwords[uid] = demoPassword;
    }

    Item mk(
      String id,
      ItemType type,
      String title,
      String desc,
      String cat,
      String color,
      int landmark,
      int hoursAgo,
      String uid, {
      List<String> questions = const [],
    }) {
      final lm = AppConfig.landmarks[landmark];
      final at = now.subtract(Duration(hours: hoursAgo));
      final status = type == ItemType.lost ? ItemStatus.lost : ItemStatus.found;
      return Item(
        id: id,
        type: type,
        title: title,
        description: desc,
        category: cat,
        color: color,
        status: status,
        locationName: lm.name,
        lat: approximate(lm.position.latitude),
        lng: approximate(lm.position.longitude),
        occurredAt: at,
        createdAt: at,
        updatedAt: at,
        reporterId: uid,
        reporterAlias: _users[uid]!.alias,
        keywords: extractKeywords([title, desc, color, lm.name]),
        verificationQuestions: questions,
        history: [StatusEvent(status, at, 'Reported')],
      );
    }

    final seed = [
      mk('seed_wallet', ItemType.found, 'Brown leather wallet',
          'Found on a table near the window seats, second floor.',
          'wallet', 'brown', 0, 3, 'u_ben',
          questions: ['What brand is the wallet?', 'Name one card (not cash) that is inside it.']),
      mk('seed_earbuds', ItemType.lost, 'White wireless earbuds in case',
          'Lost my white earbuds case, has a small blue sticker on the back.',
          'earphones', 'white', 1, 20, 'u_asha'),
      mk('seed_keys', ItemType.found, 'Bunch of 3 keys with red keychain',
          'Three keys on a ring with a red plastic keychain, found by the bench.',
          'keys', 'red', 4, 30, 'u_chen',
          questions: ['How many keys are on the ring?', 'What shape is the keychain?']),
      mk('seed_idcard', ItemType.found, 'Student ID card',
          'Student ID card found at the main gate. Photo blurred for privacy.',
          'id_card', 'blue', 6, 6, 'u_chen',
          questions: ['What name is printed on the card?', 'What is your department?']),
      mk('seed_bottle', ItemType.lost, 'Steel water bottle',
          'Silver steel bottle with mountain stickers, left in the gym.',
          'bottle', 'silver', 4, 50, 'u_ben'),
    ];
    for (final i in seed) {
      _items[i.id] = i;
    }
    _secrets['seed_wallet'] = Verification.buildSecret(
      expectedAnswers: ['Woodland', 'library card|student id|metro card'],
    );
    _secrets['seed_keys'] = Verification.buildSecret(
      expectedAnswers: ['3|three', 'heart'],
    );
    _secrets['seed_idcard'] = Verification.buildSecret(
      expectedAnswers: ['Asha Raman', 'ECE|electronics'],
    );
  }

  /// Wipes demo data back to the seeded state.
  Future<void> reset() async {
    _items.clear();
    _secrets.clear();
    _claims.clear();
    _messages.clear();
    _handoverCodes.clear();
    _users.clear();
    _passwords.clear();
    final uid = _currentUid;
    _seed();
    _currentUid = _users.containsKey(uid) ? uid : null;
    await _commit();
    _auth.add(currentUser);
  }

  String get _uid => _currentUid ?? (throw StateError('Not signed in'));

  // ---- Auth ----

  @override
  Stream<AppUser?> authChanges() async* {
    yield currentUser;
    yield* _auth.stream;
  }

  @override
  AppUser? get currentUser => _currentUid == null ? null : _users[_currentUid];

  @override
  Future<void> signIn(String email, String password) async {
    final user = _users.values.where(
      (u) => u.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (user.isEmpty || _passwords[user.first.uid] != password) {
      throw Exception('Invalid e-mail or password.');
    }
    _currentUid = user.first.uid;
    await _save();
    _auth.add(currentUser);
  }

  @override
  Future<void> register(String name, String email, String password) async {
    if (_users.values.any((u) => u.email == email.trim().toLowerCase())) {
      throw Exception('An account with this e-mail already exists.');
    }
    final uid = 'u_${DateTime.now().microsecondsSinceEpoch}';
    _users[uid] = AppUser(
      uid: uid,
      email: email.trim().toLowerCase(),
      displayName: name.trim(),
      emailVerified: true,
    );
    _passwords[uid] = password;
    _currentUid = uid;
    await _save();
    _auth.add(currentUser);
  }

  @override
  Future<void> sendVerificationEmail() async {}

  @override
  Future<void> refreshUser() async {}

  @override
  Future<void> signOut() async {
    _currentUid = null;
    await _save();
    _auth.add(null);
  }

  // ---- Items ----

  @override
  Stream<List<Item>> watchRecentItems() => _watch(
    () => _items.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  @override
  Stream<Item?> watchItem(String id) => _watch(() => _items[id]);

  @override
  Stream<List<Item>> watchItemsByReporter(String uid) => _watch(
    () => _items.values.where((i) => i.reporterId == uid).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  @override
  Stream<List<Item>> watchLinkedItems(String lostItemId) => _watch(
    () => _items.values.where((i) => i.linkedItemId == lostItemId).toList(),
  );

  @override
  Future<String> uploadImage(String storagePath, Uint8List jpeg) async {
    _requireOnline();
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/demo_storage/$storagePath');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(jpeg, flush: true);
    return f.path;
  }

  @override
  Future<void> createItem(Item item, ItemSecret? secret) async {
    _requireOnline();
    if (item.reporterId != _uid) throw StateError('permission-denied');
    _items[item.id] = item;
    if (secret != null) _secrets[item.id] = secret;
    await _commit();
  }

  @override
  Future<ItemSecret?> getSecret(String itemId) async {
    final item = _items[itemId];
    if (item == null || item.reporterId != _uid) return null;
    return _secrets[itemId];
  }

  Item _withStatus(Item item, ItemStatus status, String note) {
    final now = DateTime.now();
    return item.copyWith(
      status: status,
      updatedAt: now,
      history: [...item.history, StatusEvent(status, now, note)],
    );
  }

  @override
  Future<void> setItemStatus(Item item, ItemStatus status, String note) async {
    _requireOnline();
    final current = _items[item.id]!;
    if (current.reporterId != _uid) throw StateError('permission-denied');
    _items[item.id] = _withStatus(current, status, note);
    await _commit();
  }

  @override
  Future<void> reportAbuse(String itemId, String reason) async {
    _requireOnline();
  }

  // ---- Claims ----

  @override
  Stream<List<Claim>> watchClaimsForItem(String itemId) => _watch(
    () => _claims.values
        .where((c) => c.itemId == itemId && c.itemReporterId == _currentUid)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  @override
  Stream<List<Claim>> watchClaimsByClaimant(String uid) => _watch(
    () => _claims.values.where((c) => c.claimantId == uid).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );

  @override
  Stream<List<Claim>> watchIncomingClaims(String reporterUid) => _watch(
    () => _claims.values.where((c) => c.itemReporterId == reporterUid).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );

  @override
  Stream<Claim?> watchClaim(String id) => _watch(() {
    final c = _claims[id];
    if (c == null) return null;
    final allowed = c.claimantId == _currentUid || c.itemReporterId == _currentUid;
    return allowed ? c : null;
  });

  @override
  Future<bool> claimExists(String claimId) async => _claims.containsKey(claimId);

  @override
  Future<void> createClaim(Claim claim) async {
    _requireOnline();
    final item = _items[claim.itemId];
    if (item == null ||
        claim.claimantId != _uid ||
        item.reporterId == _uid ||
        item.status != ItemStatus.found ||
        _claims.containsKey(claim.id)) {
      throw StateError('permission-denied');
    }
    _claims[claim.id] = claim;
    await _commit();
  }

  Claim _updateClaim(
    Claim c, {
    ClaimStatus? status,
    String? reason,
    String? hash,
    String? salt,
  }) => Claim.fromMap({
    ...c.toMap(),
    'status': (status ?? c.status).name,
    'rejectionReason': reason ?? c.rejectionReason,
    'handoverCodeHash': hash ?? c.handoverCodeHash,
    'handoverSalt': salt ?? c.handoverSalt,
    'updatedAt': DateTime.now(),
  });

  @override
  Future<void> approveClaim(Claim claim, Item item) async {
    _requireOnline();
    if (item.reporterId != _uid) throw StateError('permission-denied');
    for (final c in _claims.values.toList()) {
      if (c.itemId == item.id && c.id != claim.id && c.status == ClaimStatus.pending) {
        _claims[c.id] = _updateClaim(
          c,
          status: ClaimStatus.rejected,
          reason: 'Another claim for this item was verified.',
        );
      }
    }
    _claims[claim.id] = _updateClaim(claim, status: ClaimStatus.approved);
    _items[item.id] = _withStatus(
      _items[item.id]!,
      ItemStatus.claimed,
      'Ownership verified',
    ).copyWith(approvedClaimId: claim.id);
    await _commit();
  }

  @override
  Future<void> rejectClaim(Claim claim, String reason) async {
    _requireOnline();
    _claims[claim.id] = _updateClaim(
      claim,
      status: ClaimStatus.rejected,
      reason: reason,
    );
    await _commit();
  }

  @override
  Future<void> withdrawClaim(Claim claim) async {
    _requireOnline();
    _claims[claim.id] = _updateClaim(claim, status: ClaimStatus.withdrawn);
    await _commit();
  }

  @override
  Future<void> setHandoverHash(Claim claim, String hash, String salt) async {
    _requireOnline();
    _claims[claim.id] = _updateClaim(_claims[claim.id]!, hash: hash, salt: salt);
    await _commit();
  }

  @override
  Future<void> saveHandoverCode(String claimId, String code) async {
    _handoverCodes['${_uid}_$claimId'] = code;
    await _save();
  }

  @override
  Future<String?> getHandoverCode(String claimId) async =>
      _handoverCodes['${_currentUid}_$claimId'];

  @override
  Future<void> completeHandover(Claim claim, Item item, String code) async {
    _requireOnline();
    final c = _claims[claim.id]!;
    if (c.handoverSalt == null ||
        Verification.handoverHash(code, c.handoverSalt!) != c.handoverCodeHash) {
      throw WrongHandoverCode();
    }
    _claims[c.id] = _updateClaim(c, status: ClaimStatus.completed);
    _items[item.id] = _withStatus(
      _items[item.id]!,
      ItemStatus.returned,
      'Handed over to verified owner',
    );
    await _commit();
  }

  // ---- Messages ----

  @override
  Stream<List<ChatMessage>> watchMessages(String claimId) =>
      _watch(() => List.of(_messages[claimId] ?? const <ChatMessage>[]));

  @override
  Future<void> sendMessage(String claimId, ChatMessage message) async {
    _requireOnline();
    (_messages[claimId] ??= []).add(message);
    await _commit();
  }

  @override
  Future<void> saveFcmToken(String token) async {}

  /// Lets the demo show a "new item" arriving for match notifications.
  void notifyChanged() => _changes.add(null);
}
