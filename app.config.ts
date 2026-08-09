import * as fs from 'fs';
import type { ExpoConfig } from 'expo/config';

// API_BASE_URL and GOOGLE_WEB_CLIENT_ID come from the environment (see .env.example). Neither gets a
// default: a missing value has to fail loudly where it is read, not silently point at localhost or
// start a Google sign-in that never resolves.

// The iOS Google Sign-In URL scheme is REVERSED_CLIENT_ID from GoogleService-Info.plist (pulled by
// scripts/pull-secrets.sh). Read it at config time so it never drifts and is never hardcoded. Absent
// on Android-only checkouts and in CI — the sign-in plugin then stays bare (Android needs no scheme).
const iosReversedClientId = ((): string | undefined => {
  try {
    const plist = fs.readFileSync('./GoogleService-Info.plist', 'utf8');
    return plist.match(/<key>REVERSED_CLIENT_ID<\/key>\s*<string>([^<]+)<\/string>/)?.[1];
  } catch {
    return undefined;
  }
})();

const config: ExpoConfig = {
  name: 'Couple Sync',
  slug: 'couple-sync',
  version: '1.0.0',
  orientation: 'portrait',
  scheme: 'couplesync',
  // No `userInterfaceStyle`: it needs expo-system-ui to have any effect on Android, and Android
  // already follows the system setting, which is all useColors() in src/theme.ts reads.
  icon: './assets/icon.png',
  android: {
    package: 'dev.yashiel.couplesync',
    // Every store/TestFlight upload needs a fresh number. CI passes the run number
    // (ANDROID_VERSION_CODE / IOS_BUILD_NUMBER); locally it defaults to 1. android/ and ios/ are
    // prebuild output, so this config is the only place the number lives.
    versionCode: Number(process.env.ANDROID_VERSION_CODE ?? 1),
    // The *real* file: a developer drops it in from the Firebase console and it stays gitignored.
    // CI copies google-services.placeholder.json to this path immediately before prebuild. Pointing
    // this at the placeholder permanently would keep CI green while a device build consumed a fake
    // config and Google Sign-In failed at runtime with nothing explaining why.
    googleServicesFile: './google-services.json',
    adaptiveIcon: {
      foregroundImage: './assets/android-icon-foreground.png',
      backgroundImage: './assets/android-icon-background.png',
      monochromeImage: './assets/android-icon-monochrome.png',
    },
  },
  ios: {
    bundleIdentifier: 'dev.yashiel.couplesync',
    // BUMP on every App Store Connect / TestFlight upload — CI passes IOS_BUILD_NUMBER (see above).
    buildNumber: process.env.IOS_BUILD_NUMBER ?? '1',
    // Follow the system light/dark setting (expo-system-ui). Without this iOS pins Info.plist to Light
    // and the dark palette in src/theme.ts never activates; Android already follows the system.
    userInterfaceStyle: 'automatic',
    // Real Firebase iOS config, gitignored like its Android sibling. Pulled by scripts/pull-secrets.sh.
    googleServicesFile: './GoogleService-Info.plist',
  },
  plugins: [
    'expo-router',
    '@react-native-firebase/app',
    // iOS needs the reversed-client URL scheme registered; Android does not. Bare string when the
    // plist is absent (Android-only / CI) keeps prebuild working there.
    iosReversedClientId
      ? ['@react-native-google-signin/google-signin', { iosUrlScheme: iosReversedClientId }]
      : '@react-native-google-signin/google-signin',
    // Read-only device calendar access: busy intervals are read from the OS calendar (which already
    // aggregates every account on the device, work included). Only start/end times are read — never
    // an event title, matching the freebusy privacy stance in §5.
    [
      'expo-calendar',
      { calendarPermission: 'Couple Sync reads only your busy times to find free windows together.' },
    ],
    'expo-notifications',
    'expo-dev-client',
    // Signs the debug build with the couple-sync keystore (SHA-1 registered in Firebase) so Google
    // Sign-In works on-device. Keystore + passwords come from scripts/pull-secrets.sh; no-op in CI.
    './plugins/withAndroidDebugSigning',
    // react-native-firebase v23 pulls Firebase via SPM, which clashes with static useFrameworks
    // (below) and breaks `pod install`. Opt out of SPM so Firebase resolves via CocoaPods.
    './plugins/withRNFirebaseDisableSPM',
    // Strips the iOS push entitlement when CS_NO_PUSH=1 so a free Apple team can sign a test build.
    // No-op for the real paid-account build (push kept). Remove the flag once the paid team is active.
    './plugins/withStripPushEntitlement',
    // Xcode script sandboxing (default YES) blocks Expo/RNFirebase build-phase scripts writing into
    // the .app; disable it so the iOS build's dev-launcher script phases run.
    './plugins/withDisableScriptSandbox',
    // React Native Firebase requires static frameworks on iOS. Android does not care, but this is
    // the one setting whose absence breaks an iOS build later, and it costs nothing now.
    // E2E builds talk to the Auth emulator + backend over cleartext http://10.0.2.2; Android blocks
    // cleartext by default. Enabled ONLY in E2E — real builds stay https-only.
    [
      'expo-build-properties',
      {
        ios: { useFrameworks: 'static' },
        android: { usesCleartextTraffic: process.env.EXPO_PUBLIC_E2E === '1' },
      },
    ],
  ],
  extra: {
    apiBaseUrl: process.env.API_BASE_URL,
    googleWebClientId: process.env.GOOGLE_WEB_CLIENT_ID,
    // E2E builds only: swaps Google Sign-In for the Firebase Auth emulator (no real Google, which
    // cannot be automated in an emulator). Never set in a real build.
    e2e: process.env.EXPO_PUBLIC_E2E === '1',
  },
};

export default config;
