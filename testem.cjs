'use strict';

const launchInCi = Array.from({ length: 10 }, () => 'Chrome');

const chromeCiExtraArgs = [
  process.env.CI ? '--no-sandbox' : null,
  '--headless',
  '--disable-dev-shm-usage',
  '--disable-software-rasterizer',
  '--mute-audio',
  '--remote-debugging-port=0',
  '--window-size=1440,900',
  '--no-default-browser-check',
  '--no-first-run',
  '--ignore-certificate-errors',
  '--test-type',
  '--disable-renderer-backgrounding',
  '--disable-background-timer-throttling',
].filter(Boolean);

if (typeof module !== 'undefined') {
  module.exports = {
    framework: 'qunit',
    test_page: 'tests/index.html?hidepassed',
    disable_watching: true,
    launch_in_ci: launchInCi,
    launch_in_dev: ['Chrome'],
    browser_start_timeout: 120,
    browser_disconnect_timeout: 120,
    browser_args: {
      Chrome: {
        ci: chromeCiExtraArgs,
      },
    },
    parallel: -1,
  };
}
