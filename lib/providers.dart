import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/models.dart';
import 'services/backend.dart';
import 'services/local_backend.dart';

/// Overridden in main() with either FirebaseBackend or LocalBackend.
final backendProvider = Provider<Backend>(
  (ref) => throw UnimplementedError('backendProvider not overridden'),
);

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(backendProvider).authChanges(),
);

final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authStateProvider).value,
);

// ---- Connectivity ----

final _deviceOnlineProvider = StreamProvider<bool>((ref) async* {
  bool has(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);
  final c = Connectivity();
  yield has(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(has);
});

/// Demo-mode switch that makes every network operation fail, to show the
/// offline outbox and retry behaviour without toggling airplane mode.
final simulateOfflineProvider = NotifierProvider<SimulateOffline, bool>(
  SimulateOffline.new,
);

class SimulateOffline extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    final b = ref.read(backendProvider);
    if (b is LocalBackend) b.simulateOffline = value;
    state = value;
  }
}

final onlineProvider = Provider<bool>((ref) {
  final device = ref.watch(_deviceOnlineProvider).value ?? true;
  return device && !ref.watch(simulateOfflineProvider);
});

// ---- Data ----

final recentItemsProvider = StreamProvider<List<Item>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(backendProvider).watchRecentItems();
});

final itemProvider = StreamProvider.autoDispose.family<Item?, String>(
  (ref, id) => ref.watch(backendProvider).watchItem(id),
);

final myItemsProvider = StreamProvider<List<Item>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.watch(backendProvider).watchItemsByReporter(user.uid);
});

final myClaimsProvider = StreamProvider<List<Claim>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.watch(backendProvider).watchClaimsByClaimant(user.uid);
});

final incomingClaimsProvider = StreamProvider<List<Claim>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.watch(backendProvider).watchIncomingClaims(user.uid);
});

final claimsForItemProvider = StreamProvider.autoDispose
    .family<List<Claim>, String>((ref, itemId) {
      ref.watch(currentUserProvider);
      return ref.watch(backendProvider).watchClaimsForItem(itemId);
    });

final claimProvider = StreamProvider.autoDispose.family<Claim?, String>(
  (ref, id) => ref.watch(backendProvider).watchClaim(id),
);

final linkedItemsProvider = StreamProvider.autoDispose
    .family<List<Item>, String>(
      (ref, id) => ref.watch(backendProvider).watchLinkedItems(id),
    );

final messagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>(
      (ref, claimId) => ref.watch(backendProvider).watchMessages(claimId),
    );

final secretProvider = FutureProvider.autoDispose.family<ItemSecret?, String>(
  (ref, itemId) => ref.watch(backendProvider).getSecret(itemId),
);
