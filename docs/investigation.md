# Investigation

## Summary

This repo was built to isolate an intermittent Testem shutdown hang seen in a larger application.

The strongest conclusion from the investigation is:

- the slow shutdown is not caused by test execution still running
- it happens after the last expected test result has already been printed
- in failing runs, at least one Chrome child process emits `exit` promptly, but Testem keeps waiting on child `close`
- on macOS with installed Google Chrome, the delayed `close` correlates with late `stderr` output from Chrome updater processes

That makes the issue best described as:

- a Chrome-triggered delayed child teardown
- exposed to users as a Testem shutdown hang because Testem waits on `close`

## Reproduction Shape

The browser test page is intentionally small. The stress is in the browser count and repeated async tests:

- 50 async QUnit tests
- 10 parallel Chrome instances in the default repro mode
- one short async boundary per test

The main repro command is:

```sh
npm run repro
```

The looped repro command is:

```sh
./scripts/run-repro-loop.sh
```

The failure shape is:

1. all tests complete
2. the last expected test result line is printed
3. the parent process stays alive for much longer than expected

## Main Investigation Steps

### 1. Confirmed the repo was a real reproducer

This repo reproduced the same shutdown stall class as the original larger app:

- tests finished
- Testem reached the normal end marker
- the parent process still did not exit promptly

### 2. Instrumented Testem process and socket behavior

The investigation added local instrumentation to the installed Testem package to trace:

- runner lifecycle
- browser child `exit`
- browser child `close`
- stdout/stderr activity
- server-side socket activity

This ruled out several weaker hypotheses and showed that the shutdown stall was in Testem's child-process lifecycle handling, not in test completion itself.

### 3. Verified the stall was `exit` vs `close`

The important pattern in failing runs was:

- Chrome child `exit` happened quickly after shutdown
- Testem still waited for child `close`
- `close` could lag by tens of seconds or, in earlier runs, many minutes

That was the key Testem-side bug shape.

### 4. Captured the late stdio content

The next step was to capture the raw child `stderr` that was keeping the process open.

That showed real late writes, not just an idle-open pipe. The delayed output referenced Chrome updater code paths such as:

- `chrome/updater/...`
- `app_wakeall.cc`
- `UpdaterMain (--wake-all) returned 0`

This made the best explanation:

- installed Google Chrome was spawning updater-related activity during shutdown
- that activity kept the child stdio open
- Testem then waited on `close`

### 5. Compared installed Google Chrome with Chrome for Testing

The investigation compared:

- installed Google Chrome
- Chrome for Testing launched with a Playwright-like automation flag set

The strongest result was:

- real installed Google Chrome reproduced the delayed-shutdown behavior
- Chrome for Testing did not reproduce the same long-tail shutdown pattern in the successful 10-pass comparison run

This did not prove a single Chrome bug, but it strengthened the hypothesis that installed-Chrome updater/background behavior was involved.

### 6. Tested multiple Testem-side fixes

Several fixes were prototyped:

- process-group killing, closer to Playwright's force-kill behavior
- Chrome-aware graceful close over the DevTools protocol
- a bounded fallback in `Process.kill()` once the child had already emitted `exit`

Findings:

- process-group killing helped but did not reliably bound shutdown
- DevTools `Browser.close` made the browser PID exit quickly, but did not stop the delayed `close` problem
- the bounded post-`exit` fallback did reliably stop the multi-minute hang class in local 10-pass runs

### 7. Compared Testem's shutdown model with Playwright's

The investigation also compared this behavior with Playwright, because the same machine did not show the same long-tail shutdown problem when Chrome was launched through Playwright.

The important differences were:

- Playwright attempts a protocol-level browser close first
- if that does not finish in time, Playwright force-kills the whole process group
- Playwright also uses a more opinionated Chromium automation flag set by default

That comparison was useful for two reasons:

- it showed that "Chrome is involved" did not automatically mean "nothing can be done in the harness"
- it suggested that Testem's shutdown behavior was less robust than other browser automation tooling, even if Chrome updater behavior was part of the trigger

The Playwright comparison did not eliminate the need for the Testem fix. In local testing:

- process-group killing alone improved some cases but did not reliably prevent long tails
- DevTools `Browser.close` made the browser PID exit quickly but still did not prevent delayed child `close`

So the Playwright comparison helped identify better shutdown patterns, but the smallest Testem fix that actually held up was still the bounded post-`exit` fallback.

## Current Conclusion

The most defensible conclusion is:

- installed Google Chrome on macOS can delay child-process `close` well after the browser has effectively exited
- Testem's current shutdown behavior is too strict because it treats `close` as the only completion signal
- once the child has already emitted `exit` and Testem's kill timeout has already elapsed, continuing to wait on `close` can turn browser-side linger into a visible harness hang

## Proposed Testem Fix

The smallest fix that held up in local testing was:

- keep Testem's existing shutdown behavior
- if the child has already emitted `exit`
- and the normal kill timeout has already expired
- resolve shutdown after a short additional bound even if `close` never arrives

That keeps the change narrow:

- no Chrome-specific logic
- no instrumentation required
- no behavioral change in the normal case

It only changes the pathological case where the process is already dead but stdio teardown is still lagging.

## What This Repo Is For

This repo is intended to support:

- a public Testem issue with a credible reproduction
- a small Testem PR for the bounded post-`exit` shutdown fix

It is not intended to prove a precise upstream Chromium root cause. The Chrome-side behavior is part of the story, but the actionable bug for Testem is that shutdown is not bounded once the child has already exited.
