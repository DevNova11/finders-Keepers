import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers.dart';
import 'backend.dart';
import 'local_store.dart';

enum SubmissionKind { item, claim }

/// A report or claim that has been accepted by the app but not yet
/// confirmed by the server. Survives app restarts, so an interrupted
/// submission (app killed, network dropped mid-upload) is never lost and is
/// resumed from the last image successfully uploaded.
class PendingSubmission {
  final String id;
  final SubmissionKind kind;
  final Map<String, dynamic> payload; // Item or Claim map
  final Map<String, dynamic>? secret; // ItemSecret map
  final List<String> localImages; // processed JPEG paths
  final Map<String, String> uploadedUrls; // index → url
  final int attempts;
  final String? lastError;
  final DateTime createdAt;

  const PendingSubmission({
    required this.id,
    required this.kind,
    required this.payload,
    this.secret,
    this.localImages = const [],
    this.uploadedUrls = const {},
    this.attempts = 0,
    this.lastError,
    required this.createdAt,
  });

  String get title =>
      (payload['title'] ?? payload['itemTitle'] ?? 'Submission') as String;

  PendingSubmission copyWith({
    Map<String, String>? uploadedUrls,
    int? attempts,
    String? lastError,
  }) => PendingSubmission(
    id: id,
    kind: kind,
    payload: payload,
    secret: secret,
    localImages: localImages,
    uploadedUrls: uploadedUrls ?? this.uploadedUrls,
    attempts: attempts ?? this.attempts,
    lastError: lastError,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'payload': payload,
    'secret': secret,
    'localImages': localImages,
    'uploadedUrls': uploadedUrls,
    'attempts': attempts,
    'lastError': lastError,
    'createdAt': createdAt,
  };

  factory PendingSubmission.fromJson(Map<String, dynamic> m) =>
      PendingSubmission(
        id: m['id'],
        kind: SubmissionKind.values.byName(m['kind']),
        payload: Map<String, dynamic>.from(m['payload']),
        secret: m['secret'] == null
            ? null
            : Map<String, dynamic>.from(m['secret']),
        localImages: List<String>.from(m['localImages'] ?? const []),
        uploadedUrls: Map<String, String>.from(m['uploadedUrls'] ?? const {}),
        attempts: m['attempts'] ?? 0,
        lastError: m['lastError'],
        createdAt: parseDate(m['createdAt']) ?? DateTime.now(),
      );
}

final outboxProvider = NotifierProvider<Outbox, List<PendingSubmission>>(
  Outbox.new,
);

class Outbox extends Notifier<List<PendingSubmission>> {
  static const _folder = 'outbox';
  static const _key = 'queue';
  bool _running = false;
  Timer? _retryTimer;

  @override
  List<PendingSubmission> build() {
    _restore();
    ref.listen<bool>(onlineProvider, (prev, online) {
      if (online && prev != true) flush();
    });
    ref.onDispose(() => _retryTimer?.cancel());
    return const [];
  }

  Backend get _backend => ref.read(backendProvider);

  Future<void> _restore() async {
    final raw = await LocalStore.read(_folder, _key);
    if (raw is List) {
      state = raw
          .map((e) => PendingSubmission.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      unawaited(flush());
    }
  }

  Future<void> _persist() =>
      LocalStore.write(_folder, _key, state.map((e) => e.toJson()).toList());

  void _replace(PendingSubmission s) {
    state = [for (final e in state) e.id == s.id ? s : e];
  }

  Future<void> enqueue(PendingSubmission s) async {
    state = [...state.where((e) => e.id != s.id), s];
    await _persist();
    unawaited(flush());
  }

  Future<void> discard(String id) async {
    final s = state.where((e) => e.id == id).firstOrNull;
    state = state.where((e) => e.id != id).toList();
    await _persist();
    if (s != null) await _deleteFiles(s);
  }

  Future<void> _deleteFiles(PendingSubmission s) async {
    for (final p in s.localImages) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }

  /// Uploads everything still pending, oldest first. Safe to call often.
  Future<void> flush() async {
    if (_running || state.isEmpty) return;
    if (!ref.read(onlineProvider)) return;
    _running = true;
    _retryTimer?.cancel();
    try {
      for (final s in List.of(state)) {
        if (!ref.read(onlineProvider)) break;
        await _process(s);
      }
    } finally {
      _running = false;
    }
    if (state.isNotEmpty) {
      final attempts = state.map((e) => e.attempts).reduce(max);
      final delay = Duration(seconds: min(300, 5 * pow(2, attempts).toInt()));
      _retryTimer = Timer(delay, flush);
    }
  }

  Future<void> _process(PendingSubmission s) async {
    var current = s;
    try {
      // 1. Upload images not yet uploaded (resumable). Skipped when the
      //    backend has no photo storage: the dHash fingerprints are already
      //    in the payload, so image matching still works.
      final upload = _backend.supportsPhotoUpload;
      final urls = Map<String, String>.from(current.uploadedUrls);
      for (var i = 0; upload && i < current.localImages.length; i++) {
        if (urls.containsKey('$i')) continue;
        final bytes = await File(current.localImages[i]).readAsBytes();
        final path = current.kind == SubmissionKind.item
            ? 'items/${current.id}/$i.jpg'
            : 'claims/${current.id}/proof.jpg';
        urls['$i'] = await _backend
            .uploadImage(path, bytes)
            .timeout(const Duration(seconds: 60));
        current = current.copyWith(uploadedUrls: urls);
        _replace(current);
        await _persist();
      }
      final ordered = [
        if (upload)
          for (var i = 0; i < current.localImages.length; i++) urls['$i']!,
      ];

      // 2. Write the document. Ids are client-generated → idempotent.
      final write = switch (current.kind) {
        SubmissionKind.item => _backend.createItem(
          Item.fromMap(current.payload).copyWith(imageUrls: ordered),
          current.secret == null ? null : ItemSecret.fromMap(current.secret!),
        ),
        SubmissionKind.claim => _backend.createClaim(
          Claim.fromMap({
            ...current.payload,
            'proofImageUrl': ordered.isEmpty ? null : ordered.first,
          }),
        ),
      };
      try {
        await write.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        // Firestore has persisted the write in its local cache and will
        // deliver it when the connection recovers; demo mode has no cache.
        if (_backend.isDemo) rethrow;
      }

      state = state.where((e) => e.id != current.id).toList();
      await _persist();
      await _deleteFiles(current);
    } catch (e) {
      final failed = current.copyWith(
        attempts: current.attempts + 1,
        lastError: e is NetworkUnavailable ? e.message : e.toString(),
      );
      _replace(failed);
      await _persist();
    }
  }
}
