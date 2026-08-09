const { withXcodeProject } = require('@expo/config-plugins');

// Xcode defaults ENABLE_USER_SCRIPT_SANDBOXING to YES, which denies the Expo dev-launcher / RNFirebase
// build-phase scripts writing into the .app (e.g. ip.txt) — the build fails with a "Sandbox: deny
// file-write-data" error. Disable it across the app project's build configurations. `ios/` is prebuild
// output, so this belongs in a plugin, not a hand-edited pbxproj.
module.exports = (config) =>
  withXcodeProject(config, (config) => {
    const project = config.modResults;
    const configurations = project.pbxXCBuildConfigurationSection();
    for (const key of Object.keys(configurations)) {
      const buildSettings = configurations[key]?.buildSettings;
      if (buildSettings) buildSettings.ENABLE_USER_SCRIPT_SANDBOXING = 'NO';
    }
    return config;
  });
