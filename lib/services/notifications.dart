import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers.dart';
import 'matching.dart';

class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static var _id = 0;
  static bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'matches',
    'Matches & claims',
    channelDescription: 'Possible matches for your items and claim updates',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  static Future<void> show(String title, String body) async {
    if (!_ready) return;
    await _plugin.show(
      id: _id++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Registers this device for server-sent push (Cloud Functions send a push
  /// when a potentially matching item is reported while the app is closed).
  static Future<void> initPush(Future<void> Function(String) saveToken) async {
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      // Registration tokens still work with the Admin SDK's
      // sendEachForMulticast used by functions/index.js. Migrate to
      // register()/onRegistered (FID direct-send) when the functions do.
      // ignore: deprecated_member_use
      final token = await fm.getToken();
      if (token != null) await saveToken(token);
      // ignore: deprecated_member_use
      fm.onTokenRefresh.listen(saveToken);
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) show(n.title ?? 'Finders Keepers', n.body ?? '');
      });
    } catch (e) {
      debugPrint('Push unavailable: $e');
    }
  }
}

/// While the app is running, watches the live item feed and claim streams
/// and raises local notifications for:
///  * a newly reported item that potentially matches one of my open items
///  * a new claim on an item I found
///  * a status change on a claim I submitted
/// Kept alive by being watched from the home shell.
final matchWatcherProvider = Provider<void>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;
  final seenItems = <String>{};
  final claimStates = <String, ClaimStatus>{};
  var itemsSeeded = false, incomingSeeded = false, mineSeeded = false;

  ref.listen<AsyncValue<List<Item>>>(recentItemsProvider, (_, next) {
    final items = next.value;
    if (items == null) return;
    final fresh = items.where((i) => seenItems.add(i.id)).toList();
    if (!itemsSeeded) {
      itemsSeeded = true;
      return;
    }
    final mine = items
        .where((i) => i.reporterId == user.uid && i.status.isOpen)
        .toList();
    for (final n in fresh.where((i) => i.reporterId != user.uid)) {
      for (final m in mine) {
        final r = scoreMatch(m, n);
        if (n.type != m.type && r.score >= 0.45) {
          Notifications.show(
            'Possible match for "${m.title}"',
            '${n.type == ItemType.found ? 'Found' : 'Lost'}: ${n.title} '
                'near ${n.locationName} (${(r.score * 100).round()}% match)',
          );
          break;
        }
      }
    }
  }, fireImmediately: true);

  ref.listen<AsyncValue<List<Claim>>>(incomingClaimsProvider, (_, next) {
    final claims = next.value;
    if (claims == null) return;
    for (final c in claims) {
      final prev = claimStates[c.id];
      claimStates[c.id] = c.status;
      if (incomingSeeded && prev == null && c.status == ClaimStatus.pending) {
        Notifications.show(
          'New ownership claim',
          '${c.claimantAlias} claims "${c.itemTitle}". Review their answers.',
        );
      }
    }
    incomingSeeded = true;
  }, fireImmediately: true);

  ref.listen<AsyncValue<List<Claim>>>(myClaimsProvider, (_, next) {
    final claims = next.value;
    if (claims == null) return;
    for (final c in claims) {
      final key = 'mine_${c.id}';
      final prev = claimStates[key];
      claimStates[key] = c.status;
      if (mineSeeded && prev != null && prev != c.status) {
        Notifications.show('Claim update: ${c.itemTitle}', c.status.label);
      }
    }
    mineSeeded = true;
  }, fireImmediately: true);
});
