const fs = require('fs');
const path = require('path');
const { withAppBuildGradle, withDangerousMod } = require('@expo/config-plugins');

// Local device builds (`expo run:android`, debug variant) must be signed with the `couple-sync`
// keystore — its SHA-1 is the one registered in Firebase, so Google Sign-In works. Expo's generated
// debug.keystore has a different SHA-1 and gets DEVELOPER_ERROR. `android/` is prebuild output and is
// regenerated every prebuild, so this signing config cannot live as a hand-edit; it belongs here.
//
// Passwords come from gradle properties CS_STORE_PASSWORD / CS_KEY_PASSWORD (written to
// ~/.gradle/gradle.properties by scripts/pull-secrets.sh). The keystore is pulled from 1Password to
// credentials/couple-sync.jks and copied into android/app/ below. If neither exists (CI, or a dev
// who has not run pull-secrets), the copy is skipped and the release build's own injected signing
// (see .github/workflows/android-release.yml) governs the APK — this plugin only touches `debug`.
const SIGNING_BLOCK = `debug {
            storeFile file('couple-sync.jks')
            storePassword findProperty('CS_STORE_PASSWORD')
            keyAlias 'couple-sync'
            keyPassword findProperty('CS_KEY_PASSWORD')
        }`;

const withKeystoreCopy = (config) =>
  withDangerousMod(config, [
    'android',
    async (config) => {
      const src = path.join(config.modRequest.projectRoot, 'credentials', 'couple-sync.jks');
      const dest = path.join(config.modRequest.platformProjectRoot, 'app', 'couple-sync.jks');
      if (fs.existsSync(src)) {
        fs.copyFileSync(src, dest);
      } else {
        console.warn(
          '[withAndroidDebugSigning] credentials/couple-sync.jks not found — run scripts/pull-secrets.sh. ' +
            'Debug build will fail to sign; Google Sign-In will not work.',
        );
      }
      return config;
    },
  ]);

const withDebugSigningConfig = (config) =>
  withAppBuildGradle(config, (config) => {
    // Replace Expo's default debug signingConfig block. Scoped by [^}]* so it cannot escape the block.
    config.modResults.contents = config.modResults.contents.replace(
      /debug \{[^}]*storeFile file\('debug\.keystore'\)[^}]*\}/,
      SIGNING_BLOCK,
    );
    return config;
  });

module.exports = (config) => withKeystoreCopy(withDebugSigningConfig(config));
