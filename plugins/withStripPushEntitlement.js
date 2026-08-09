const { withEntitlementsPlist } = require('@expo/config-plugins');

// Free Apple personal teams cannot sign the Push Notifications capability (aps-environment), so a
// device build for on-phone testing fails until it is removed. This strips it ONLY when CS_NO_PUSH=1,
// so it is a no-op for the real (paid-account) build that keeps FCM/push. Reversible: unset the flag.
// FCM push simply won't work on iOS builds made with the flag set.
module.exports = (config) => {
  if (process.env.CS_NO_PUSH !== '1') return config;
  return withEntitlementsPlist(config, (config) => {
    delete config.modResults['aps-environment'];
    return config;
  });
};
