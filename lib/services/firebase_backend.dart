import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'backend.dart';
import 'verification.dart';

class FirebaseBackend implements Backend {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  late final _storage = FirebaseStorage.instance;

  FirebaseBackend() {
    // Offline-first: Firestore keeps a persistent local cache, serves reads
    // from it while offline and queues writes until connectivity returns.
    _db.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  @override
  bool get isDemo => false;

  @override
  bool get supportsPhotoUpload => AppConfig.uploadPhotosToFirebase;

  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('items');
  CollectionReference<Map<String, dynamic>> get _claims =>
      _db.collection('claims');

  String get _uid => _auth.currentUser!.uid;

  AppUser? _map(User? u) => u == null
      ? null
      : AppUser(
          uid: u.uid,
          email: u.email ?? '',
          displayName: u.displayName ?? (u.email ?? '').split('@').first,
          emailVerified: u.emailVerified,
        );

  List<T> _docs<T>(
    QuerySnapshot<Map<String, dynamic>> s,
    T Function(Map<String, dynamic>) f,
  ) => s.docs.map((d) => f({...d.data(), 'id': d.id})).toList();

  // ---- Auth ----

  @override
  Stream<AppUser?> authChanges() => _auth.userChanges().map(_map);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  @override
  Future<void> register(String name, String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user!.updateDisplayName(name.trim());
    await cred.user!.sendEmailVerification();
    await _db.collection('users').doc(cred.user!.uid).set({
      'displayName': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await cred.user!.reload();
  }

  @override
  Future<void> sendVerificationEmail() async =>
      _auth.currentUser?.sendEmailVerification();

  @override
  Future<void> refreshUser() async {
    await _auth.currentUser?.reload();
    // Force a fresh ID token so the email_verified claim reaches the rules.
    await _auth.currentUser?.getIdToken(true);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  // ---- Items ----

  @override
  Stream<List<Item>> watchRecentItems() => _items
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => _docs(s, Item.fromMap));

  @override
  Stream<Item?> watchItem(String id) => _items
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Item.fromMap({...d.data()!, 'id': d.id}) : null);

  @override
  Stream<List<Item>> watchItemsByReporter(String uid) => _items
      .where('reporterId', isEqualTo: uid)
      .snapshots()
      .map(
        (s) =>
            _docs(s, Item.fromMap)
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  @override
  Stream<List<Item>> watchLinkedItems(String lostItemId) => _items
      .where('linkedItemId', isEqualTo: lostItemId)
      .snapshots()
      .map((s) => _docs(s, Item.fromMap));

  @override
  Future<String> uploadImage(String storagePath, Uint8List jpeg) async {
    final ref = _storage.ref(storagePath);
    await ref.putData(jpeg, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// True if a previous attempt already reached the server, so a retried
  /// outbox submission doesn't turn into a (rule-rejected) overwrite.
  Future<bool> _existsOnServer(DocumentReference ref) async {
    try {
      return (await ref.get(const GetOptions(source: Source.server))).exists;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> createItem(Item item, ItemSecret? secret) async {
    final ref = _items.doc(item.id);
    if (await _existsOnServer(ref)) return;
    final batch = _db.batch();
    batch.set(ref, {
      ...item.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (secret != null) {
      batch.set(ref.collection('private').doc('secret'), secret.toMap());
    }
    await batch.commit();
  }

  @override
  Future<ItemSecret?> getSecret(String itemId) async {
    final d = await _items
        .doc(itemId)
        .collection('private')
        .doc('secret')
        .get();
    return d.exists ? ItemSecret.fromMap(d.data()!) : null;
  }

  Map<String, dynamic> _statusUpdate(ItemStatus status, String note) => {
    'status': status.name,
    'updatedAt': FieldValue.serverTimestamp(),
    'history': FieldValue.arrayUnion([
      StatusEvent(status, DateTime.now(), note).toMap(),
    ]),
  };

  @override
  Future<void> setItemStatus(Item item, ItemStatus status, String note) =>
      _items.doc(item.id).update(_statusUpdate(status, note));

  @override
  Future<void> reportAbuse(Item item, String reason) {
    final ref = _db.collection('reports').doc();
    return ref.set({
      ...AbuseReport(
        id: ref.id,
        itemId: item.id,
        itemTitle: item.title,
        itemReporterId: item.reporterId,
        itemReporterAlias: item.reporterAlias,
        reporterId: _uid,
        reason: reason,
        status: ReportStatus.open,
        createdAt: DateTime.now(),
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- Moderation ----

  Stream<bool> _exists(String collection) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _db
        .collection(collection)
        .doc(uid)
        .snapshots()
        .map((d) => d.exists)
        .handleError((_) => false);
  }

  @override
  Stream<bool> watchIsAdmin() => _exists('admins');

  @override
  Stream<bool> watchIsSuspended() => _exists('suspended');

  @override
  Stream<List<AbuseReport>> watchReports() => _db
      .collection('reports')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => _docs(s, AbuseReport.fromMap));

  @override
  Future<void> resolveReport(
    AbuseReport report,
    ReportStatus status,
    String resolution,
  ) => _db.collection('reports').doc(report.id).update({
    'status': status.name,
    'resolution': resolution,
    'resolvedBy': _uid,
    'resolvedAt': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> moderateItem(Item item, {required bool hidden, String? note}) =>
      _items.doc(item.id).update({
        'hidden': hidden,
        'moderationNote': note,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> suspendUser(String uid, String reason) => _db
      .collection('suspended')
      .doc(uid)
      .set({'reason': reason, 'by': _uid, 'at': FieldValue.serverTimestamp()});

  // ---- Claims ----
  // Every query includes the field the security rules check, otherwise
  // Firestore rejects the listen.

  @override
  Stream<List<Claim>> watchClaimsForItem(String itemId) => _claims
      .where('itemId', isEqualTo: itemId)
      .where('itemReporterId', isEqualTo: _uid)
      .snapshots()
      .map(
        (s) =>
            _docs(s, Claim.fromMap)
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  @override
  Stream<List<Claim>> watchClaimsByClaimant(String uid) => _claims
      .where('claimantId', isEqualTo: uid)
      .snapshots()
      .map(
        (s) =>
            _docs(s, Claim.fromMap)
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );

  @override
  Stream<List<Claim>> watchIncomingClaims(String reporterUid) => _claims
      .where('itemReporterId', isEqualTo: reporterUid)
      .snapshots()
      .map(
        (s) =>
            _docs(s, Claim.fromMap)
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );

  @override
  Stream<Claim?> watchClaim(String id) => _claims
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Claim.fromMap({...d.data()!, 'id': d.id}) : null);

  @override
  Future<bool> claimExists(String claimId) async {
    try {
      return (await _claims.doc(claimId).get()).exists;
    } on FirebaseException catch (e) {
      // Non-existent docs the user may not read come back as permission
      // errors only if rules can't evaluate; treat as "doesn't exist".
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

  @override
  Future<void> createClaim(Claim claim) async {
    final ref = _claims.doc(claim.id);
    if (await _existsOnServer(ref)) return;
    await ref.set({
      ...claim.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> approveClaim(Claim claim, Item item) async {
    final others = await _claims
        .where('itemId', isEqualTo: item.id)
        .where('itemReporterId', isEqualTo: _uid)
        .where('status', isEqualTo: ClaimStatus.pending.name)
        .get();
    final batch = _db.batch();
    batch.update(_claims.doc(claim.id), {
      'status': ClaimStatus.approved.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final d in others.docs.where((d) => d.id != claim.id)) {
      batch.update(d.reference, {
        'status': ClaimStatus.rejected.name,
        'rejectionReason': 'Another claim for this item was verified.',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(_items.doc(item.id), {
      ..._statusUpdate(ItemStatus.claimed, 'Ownership verified'),
      'approvedClaimId': claim.id,
    });
    await batch.commit();
  }

  @override
  Future<void> rejectClaim(Claim claim, String reason) =>
      _claims.doc(claim.id).update({
        'status': ClaimStatus.rejected.name,
        'rejectionReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> withdrawClaim(Claim claim) => _claims.doc(claim.id).update({
    'status': ClaimStatus.withdrawn.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> setHandoverHash(Claim claim, String hash, String salt) =>
      _claims.doc(claim.id).update({
        'handoverCodeHash': hash,
        'handoverSalt': salt,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> saveHandoverCode(String claimId, String code) => _claims
      .doc(claimId)
      .collection('private')
      .doc('handover')
      .set({'code': code});

  @override
  Future<String?> getHandoverCode(String claimId) async {
    final d = await _claims
        .doc(claimId)
        .collection('private')
        .doc('handover')
        .get();
    return d.data()?['code'] as String?;
  }

  @override
  Future<void> completeHandover(Claim claim, Item item, String code) async {
    final salt = claim.handoverSalt;
    if (salt == null ||
        Verification.handoverHash(code, salt) != claim.handoverCodeHash) {
      throw WrongHandoverCode();
    }
    final batch = _db.batch();
    // The rules re-verify the code server-side (see firestore.rules).
    batch.update(_claims.doc(claim.id), {
      'status': ClaimStatus.completed.name,
      'handoverCodeEntered': code.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(
      _items.doc(item.id),
      _statusUpdate(ItemStatus.returned, 'Handed over to verified owner'),
    );
    await batch.commit();
  }

  // ---- Messages ----

  @override
  Stream<List<ChatMessage>> watchMessages(String claimId) => _claims
      .doc(claimId)
      .collection('messages')
      .orderBy('createdAt')
      .snapshots()
      .map((s) => _docs(s, ChatMessage.fromMap));

  @override
  Future<void> sendMessage(String claimId, ChatMessage message) => _claims
      .doc(claimId)
      .collection('messages')
      .doc(message.id)
      .set({...message.toMap(), 'createdAt': FieldValue.serverTimestamp()});

  @override
  Future<void> saveFcmToken(String token) =>
      _db.collection('users').doc(_uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
}
