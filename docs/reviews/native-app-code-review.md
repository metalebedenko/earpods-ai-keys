# Native app controller and removal — code review

Date: 2026-10-10. Reviewer: native_button_mapping. Ordinary bounded review; no numerical score. The reviewer did not author the controller or management/helper code. The native HID adapters were authored by this reviewer and have a separate independent review in `native-app-backend-review.md`.

## Scope and method

Read `RuntimeController`, `DiskSettingsStore`, `MacManagement`, the uninstall helper and their isolated regression tests. Checked exact-rule ownership, cancellation, disabled recovery, profile rollback and incomplete removal. No real HID write, device capture, permission request, login registration or Trash operation was performed.

## Findings and accepted fixes

All four findings below are closed by static verification of the updated source. Each has a corresponding controller regression.

| Finding | Accepted fix | Regression |
| --- | --- | --- |
| A successful forward profile write followed by failed readback and failed rollback could lose ownership of the still-live forward rule when `pending` was replaced. | Promote a successfully read, receipt-owned current rule to `verified` before persisting the next `pending` target. Current and intended rules remain recoverable. | Forward readback failure, rollback write failure, then Disable still clears the forward rule. |
| Startup with disabled intent could report Off while an owned rule remained live after interrupted/failed Disable. | The disabled refresh path clears an exact receipt-owned live rule and requires readback; foreign rules remain preserved. | Disabled startup recovery and visible failed-clear state. |
| Successful restoration of an old chord profile still ended in `.problem`, while press dispatch required `.active`; NoEvent suppression remained but the restored chord did not emit. | Successful rollback restores `.active` for the previous profile and retains the rejected-edit message. | The previous chord still emits after a rejected profile edit. |
| Failed normal Quit stopped input but could leave the old `.active` status after termination was cancelled. | `stopForTermination` publishes `.problem` on cleanup failure and retains the recovery state; successful Quit preserves enabled intent for the next login. | Quit intent preservation and failed-Quit state. |

The related failed-Disable-persistence regression also checks that input stops and the failure is visible.

Validation: `/bin/sh app/test.sh` passed 35 isolated tests on the development host: 17 Core, 11 management/removal and 7 native child-process cases. The child-process cases exercise ordinary completion, nonzero exit, deadline/forced termination, closed streams with a live child, output limits, launch failure and invalid output encoding. These results are separate from physical acceptance.

## Removal boundaries checked

- The support directory requires its ownership marker; symlinked settings/marker paths and unrelated extra files are refused or preserved.
- Failed owned-map preparation or login unregistration does not launch the Trash helper. The disabled recovery snapshot is retained/recreated; if recovery cannot be written back, the separate staged recovery copy is reported and preserved.
- The helper is copied to a unique owned stage and validates token, helper digest, canonical app path and bundle identity. It waits for parent exit before attempting Trash.
- Temporary cleanup removes only byte-identical files created by the removal attempt; there is no recursive wildcard cleanup or emptying Trash. A failed Trash operation reports the remaining app path and Finder fallback.

No additional concrete blocker was found in these reviewed normal and partial-failure paths. This is a software review, not proof of real SMAppService registration or self-Trash behavior.

## Explicit transition before hardware testing

An earlier personal/public login job must be stopped before the app writes. Preserve exact old plist/runtime files, prior registered/disabled state and the HID baseline in a reviewed backup. Move the old plist outside LaunchAgents as well as unloading its job: the app checks both the plist and the live label. Clear only a confirmed old owned rule when required; begin app ownership from an empty mapping rather than seeding its receipt with another installation's rule. The rollback order is app Disable/Quit and exact owned cleanup, followed by restoration of the old files, login state and agreed HID baseline.

This transition is a separate owner-approved operation, not automatic adoption. The physical hybrid gate, actual permission/revocation behavior, login registration and self-Trash remain pending until observed on hardware.
