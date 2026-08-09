const { withXcodeProject } = require('@expo/config-plugins');

// CI-only manual App Store signing, scoped to the APP target ONLY. Passing signing settings on the
// xcodebuild command line applies them to every target, and Pods library targets reject a
// provisioning profile ("<pod> does not support provisioning profiles"). Setting them here, only on
// the build configs whose PRODUCT_BUNDLE_IDENTIFIER is the app's, leaves the Pods project alone.
//
// Gated on IOS_APPSTORE_PROFILE_NAME (exported by the release workflow before prebuild); a no-op for
// local/dev builds, which sign with the debug/free-team path.
module.exports = (config) => {
  const profile = process.env.IOS_APPSTORE_PROFILE_NAME;
  const team = process.env.APPLE_TEAM_ID;
  if (!profile) return config;
  return withXcodeProject(config, (config) => {
    const project = config.modResults;
    const configurations = project.pbxXCBuildConfigurationSection();
    for (const key of Object.keys(configurations)) {
      const bs = configurations[key]?.buildSettings;
      if (!bs) continue;
      if ((bs.PRODUCT_BUNDLE_IDENTIFIER ?? '').replace(/"/g, '') !== 'dev.yashiel.couplesync') continue;
      bs.CODE_SIGN_STYLE = 'Manual';
      bs.CODE_SIGN_IDENTITY = '"Apple Distribution"';
      bs.PROVISIONING_PROFILE_SPECIFIER = `"${profile}"`;
      if (team) bs.DEVELOPMENT_TEAM = team;
    }
    return config;
  });
};
