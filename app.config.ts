import type { ExpoConfig } from 'expo/config';

// API_BASE_URL and GOOGLE_WEB_CLIENT_ID come from the environment (see .env.example). Neither gets a
// default: a missing value has to fail loudly where it is read, not silently point at localhost or
// start a Google sign-in that never resolves.
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
  // iOS is not built, tested, or shipped in v1 — Android only. The bundle id is reserved here so the
  // app identity does not change if iOS is ever picked up.
  ios: { bundleIdentifier: 'dev.yashiel.couplesync' },
  plugins: [
    'expo-router',
    '@react-native-firebase/app',
    '@react-native-google-signin/google-signin',
    'expo-notifications',
    'expo-dev-client',
    // React Native Firebase requires static frameworks on iOS. Android does not care, but this is
    // the one setting whose absence breaks an iOS build later, and it costs nothing now.
    ['expo-build-properties', { ios: { useFrameworks: 'static' } }],
  ],
  extra: {
    apiBaseUrl: process.env.API_BASE_URL,
    googleWebClientId: process.env.GOOGLE_WEB_CLIENT_ID,
  },
};

export default config;
