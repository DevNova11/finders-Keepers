import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'providers.dart';
import 'services/backend.dart';
import 'services/firebase_backend.dart';
import 'services/local_backend.dart';
import 'services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();

  Backend backend;
  final options = DefaultFirebaseOptions.currentPlatform;
  // `flutter build apk --dart-define=DEMO=true` forces the on-device demo
  // backend (sample accounts, no sign-up) even when Firebase is configured.
  const forceDemo = bool.fromEnvironment('DEMO');
  if (forceDemo || options.apiKey.startsWith('REPLACE')) {
    backend = await LocalBackend.open();
  } else {
    try {
      await Firebase.initializeApp(options: options);
      backend = FirebaseBackend();
    } catch (e) {
      debugPrint('Firebase init failed, using demo mode: $e');
      backend = await LocalBackend.open();
    }
  }

  runApp(
    ProviderScope(
      overrides: [backendProvider.overrideWithValue(backend)],
      child: const FindersKeepersApp(),
    ),
  );
}
