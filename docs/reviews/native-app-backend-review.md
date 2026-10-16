# Native app backend — independent review

Date: 2026-10-10. Reviewer: package_review. Review is bounded to the native HID command adapter, chord input and device watcher; it is not hardware acceptance.

## Reviewed sources

- `app/Sources/EarPodsMac/NativeHIDRuntime.swift`
- `app/Sources/EarPodsMac/NativeChordInput.swift`
- `app/Sources/EarPodsMac/EarPodsDeviceWatcher.swift`
- Related controller call paths were read to check ownership and permission requests.

No real HID write, input capture, permission request or login mutation was performed for this review.

## Finding 1 — command execution must be bounded

Status: resolved after the implementation update and independent source re-review.

The initial `runNativeTool` reads the combined output pipe with `readDataToEndOfFile()` and then calls `waitUntilExit()`, synchronously from the main actor. It has neither a deadline nor an output limit. A stalled `hidutil`/`launchctl` can therefore block the menu, controller and cancellation indefinitely; a large response is buffered without a limit. Combining stdout/stderr prevents a second-pipe deadlock but does not solve either condition.

Required fix: bound child execution and combined output, terminate/close handles on timeout or overflow, and return an error without parsing a partial or empty result as device absence. Add isolated native-process tests for timeout, overflow and ordinary completion; do not use real HID writes.

The updated runner uses a nonblocking combined pipe, a 3-second production deadline and a maximum of 64 KiB. Timeout/overflow throws instead of returning any partial data. Handles are closed and TERM/KILL cleanup has a separate bounded grace period. EOF alone is not treated as completion while the child is still alive. Read/write/legacy errors invalidate the cached snapshot, and messages correctly say termination was requested rather than asserting an unverified OS outcome.

The seven isolated runner tests exercise normal output from both streams, nonzero exit, timeout with no surviving child, EOF from a child ignoring TERM, output overflow, exact-size limits and invalid limits/encoding/launch. They run on the main actor and explicitly verify the main-thread context. The implementing agent reported all 35 Swift checks passing (17 Core, 11 management, seven runner); the independent reviewer read the updated runner and tests and did not rerun the same suite. No unresolved concrete backend blocker remains in the reviewed scope.

## Other reviewed boundaries

- Both notification matching and `hidutil` matching restrict VID/PID and the Consumer Control page/usage. Chord input additionally validates device properties and reads only configured source elements from one device. Multiple matching devices are rejected.
- The input is opened nonexclusively. The default profile does not require chord capture. Only the explicit permission action calls access-request APIs; preflight checks do not grant access.
- Physical down is deduplicated until release. A complete synthetic down/up pair is sent synchronously, with no separate modifier-down event. Loss of posting capability still attempts key-up and produces an error instead of claiming delivery.
- Input stop unschedules callbacks, unregisters the callback and closes the device. Notification iterators are initially drained, rearmed and released; stop removes the run-loop source and destroys the notification port.
- A write requires a prior snapshot and a matching fresh read. Controller receipt ownership remains required; a familiar mapping alone is not adopted. Unknown/malformed/multiple-service responses are refused.
- Arrival handling is event driven. The only readiness retries are the controller's bounded schedule; no periodic device poll or global keyboard event listener was found.

No additional concrete blocker was found in these reviewed paths. Raw usages remaining available after NoEvent mapping, suppression of stock media actions, native Dictation coexistence and actual focused-app delivery remain explicit physical gates. Successful compilation or software tests do not prove them.

## Disposable helper Trash check

Result: [helper-trash-fixture.json](../../app/validation/helper-trash-fixture.json).

The actual ad-hoc helper from `app/dist/20261010T121206Z-39939/EarPods AI Keys.app` was executed against a uniquely named disposable copy. Its private stage followed the real token/hash/manifest/recovery contract. The parent PID belonged to a child created for the test and already exited.

The helper exited 0 with empty stderr. The disposable source disappeared; its exact unique name was independently found in Trash. The helper removed its private stage. The original distribution bundle remained present and its main executable SHA-256 was unchanged. No new permission was granted, and no HID, login item or real support settings were changed. Trash was not emptied.

This proves the native helper's ordinary move/verification/temporary-cleanup path from a writable temporary directory on this Mac. It does not prove full UI uninstall, actual login unregistration, a still-running parent's graceful exit, or permissions when the app is installed in Applications; those remain separate acceptance checks.
