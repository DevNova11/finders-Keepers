// PLACEHOLDER — regenerate with:  flutterfire configure
//
// While these placeholder values are present the app runs in offline
// DEMO MODE (all data stored on the device). Once `flutterfire configure`
// overwrites this file with your project's real options the app switches to
// Firebase Auth + Cloud Firestore + Firebase Storage automatically.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDYPPoI3ycY8pNH1dD4XRLuoqRDkwahCOg',
    appId: '1:210305882359:android:d731b0b760a862704a1bf2',
    messagingSenderId: '210305882359',
    projectId: 'finders-keepers-9b78c',
    storageBucket: 'finders-keepers-9b78c.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBlCSpQU1HDHqIqduPqhBjepryRPvqpLQ4',
    appId: '1:210305882359:ios:43d5a4b53202e7034a1bf2',
    messagingSenderId: '210305882359',
    projectId: 'finders-keepers-9b78c',
    storageBucket: 'finders-keepers-9b78c.firebasestorage.app',
    iosBundleId: 'com.campus.finderskeepers.findersKeepers',
  );
}
