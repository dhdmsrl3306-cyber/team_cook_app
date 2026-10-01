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
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB1hWu72ocbG-dlwtN8sXCZywZM20bKSt4',
    appId: '1:203535497666:android:4574e07046a6173461fe5b',
    messagingSenderId: '203535497666',
    projectId: 'cook-manager-5b78f',
    storageBucket: 'cook-manager-5b78f.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCBZvaUapsCoftAONhTb8-ZHjIUw5xNnQw',
    appId: '1:203535497666:ios:c3ec7dbf15beca0261fe5b',
    messagingSenderId: '203535497666',
    projectId: 'cook-manager-5b78f',
    storageBucket: 'cook-manager-5b78f.appspot.com',
    iosBundleId: 'com.example.teamCookApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: '여기에 macOS API Key',
    appId: '1:203535497666:ios:c3ec7dbf15beca0261fe5b',
    messagingSenderId: '203535497666',
    projectId: 'cook-manager-5b78f',
    storageBucket: 'cook-manager-5b78f.appspot.com',
    iosBundleId: 'com.example.teamCookApp',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCKqkTKT5LWmL3K4WbNPIS2gvFYqZtFq6Y',
    appId: '1:203535497666:web:77a58fbf64eb111661fe5b',
    messagingSenderId: '203535497666',
    projectId: 'cook-manager-5b78f',
    storageBucket: 'cook-manager-5b78f.appspot.com',
  );
}