const fs = require('fs');
const path = require('path');
const { withDangerousMod } = require('@expo/config-plugins');

// react-native-firebase v23 resolves firebase-ios-sdk through SPM, which ships only dynamic library
// products. Combined with this app's `useFrameworks: 'static'` (see app.config.ts), that produces
// duplicate-symbol link errors — `pod install` refuses with "SPM + static linkage is not supported".
// Opting out of SPM keeps the intended static linkage and resolves Firebase via CocoaPods (the
// pre-v23 behavior). `ios/` is prebuild output, so this belongs in a plugin, not a Podfile hand-edit.
module.exports = (config) =>
  withDangerousMod(config, [
    'ios',
    (config) => {
      const podfile = path.join(config.modRequest.platformProjectRoot, 'Podfile');
      let contents = fs.readFileSync(podfile, 'utf8');
      if (!contents.includes('$RNFirebaseDisableSPM')) {
        contents = `$RNFirebaseDisableSPM = true\n${contents}`;
        fs.writeFileSync(podfile, contents);
      }
      return config;
    },
  ]);
