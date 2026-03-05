// File generated from Firebase project config (astra-488209).
// Do not edit manually.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios; // reuse iOS config
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAJZQzFlaweePDoOoOiGMm6pDk6QrrBRm4',
    appId: '1:612024885391:web:0ae5e2f6b00575b97790fa',
    messagingSenderId: '612024885391',
    projectId: 'astra-488209',
    authDomain: 'astra-488209.firebaseapp.com',
    storageBucket: 'astra-488209.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDZxp6dr-a_0tSufbF5C2egEki03iQhBrU',
    appId: '1:612024885391:android:7309cdd64a9ecb037790fa',
    messagingSenderId: '612024885391',
    projectId: 'astra-488209',
    storageBucket: 'astra-488209.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCk5e16xYEHYGs4E_BYO86PxqRbc4ZoChE',
    appId: '1:612024885391:ios:18457affd91d1c557790fa',
    messagingSenderId: '612024885391',
    projectId: 'astra-488209',
    storageBucket: 'astra-488209.firebasestorage.app',
    iosClientId: '612024885391-pg88jhm3s6s5c6tqvopmeg218915hvvp.apps.googleusercontent.com',
    androidClientId: '612024885391-5k78j2qhbqd38u09t9b440l10chhomp7.apps.googleusercontent.com',
    iosBundleId: 'za.co.nexiontech.coupleschedule',
  );

}