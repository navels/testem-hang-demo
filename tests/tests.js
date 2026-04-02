(function () {
  const TEST_DELAY_MS = 300;
  const TEST_COUNT = 50;

  function runBrowserTest(assert) {
    return new Promise((resolve) => {
      setTimeout(() => {
        assert.true(true);
        resolve();
      }, TEST_DELAY_MS);
    });
  }

  QUnit.module('browser test', function () {
    for (let index = 0; index < TEST_COUNT; index += 1) {
      QUnit.test(`case ${index}`, async function (assert) {
        await runBrowserTest(assert);
      });
    }
  });
})();
