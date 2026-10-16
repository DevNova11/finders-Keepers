import 'dart:typed_data';

import '../models/models.dart';

/// Thrown when an operation needs the network and none is available.
class NetworkUnavailable implements Exception {
  final String message;
  const NetworkUnavailable([this.message = 'No network connection']);
  @override
  String toString() => message;
}

class WrongHandoverCode implements Exception {
  @override
  String toString() => 'The handover code does not match.';
}

/// Everything the UI needs from a backend. Implemented by
/// [FirebaseBackend] (production) and [LocalBackend] (offline demo mode,
/// used automatically when Firebase has not been configured).
abstract class Backend {
  bool get isDemo;

  /// Whether photos can be uploaded (demo mode stores them on the device).
  bool get supportsPhotoUpload;

  // ---- Auth ----
  Stream<AppUser?> authChanges();
  AppUser? get currentUser;
  Future<void> signIn(String email, String password);
  Future<void> register(String name, String email, String password);
  Future<void> sendVerificationEmail();
  Future<void> refreshUser();
  Future<void> signOut();

  // ---- Items ----
  Stream<List<Item>> watchRecentItems();
  Stream<Item?> watchItem(String id);
  Stream<List<Item>> watchItemsByReporter(String uid);

  /// Found reports filed in response to a lost report.
  Stream<List<Item>> watchLinkedItems(String lostItemId);
  Future<String> uploadImage(String storagePath, Uint8List jpeg);

  /// Idempotent: item ids are generated on the client, so a retried
  /// submission overwrites itself instead of creating a duplicate.
  Future<void> createItem(Item item, ItemSecret? secret);
  Future<ItemSecret?> getSecret(String itemId);
  Future<void> setItemStatus(Item item, ItemStatus status, String note);
  Future<void> reportAbuse(String itemId, String reason);

  // ---- Claims ----
  Stream<List<Claim>> watchClaimsForItem(String itemId);
  Stream<List<Claim>> watchClaimsByClaimant(String uid);
  Stream<List<Claim>> watchIncomingClaims(String reporterUid);
  Stream<Claim?> watchClaim(String id);
  Future<bool> claimExists(String claimId);
  Future<void> createClaim(Claim claim);
  Future<void> approveClaim(Claim claim, Item item);
  Future<void> rejectClaim(Claim claim, String reason);
  Future<void> withdrawClaim(Claim claim);
  Future<void> setHandoverHash(Claim claim, String hash, String salt);

  /// Private copy of the plain handover code, readable only by the claimant.
  Future<void> saveHandoverCode(String claimId, String code);
  Future<String?> getHandoverCode(String claimId);

  /// Verifies [code] against the stored hash and marks claim completed and
  /// item returned atomically. Throws [WrongHandoverCode].
  Future<void> completeHandover(Claim claim, Item item, String code);

  // ---- Messages ----
  Stream<List<ChatMessage>> watchMessages(String claimId);
  Future<void> sendMessage(String claimId, ChatMessage message);

  // ---- Notifications ----
  Future<void> saveFcmToken(String token);
}
