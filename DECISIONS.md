# EarPods AI Keys — decisions

## 2026-10-09 / D-001 — Project identity and purpose

- Decision: use EarPods AI Keys as the working name, with earpods-ai-keys as the repository slug.
- Reason: emphasize the change from a music remote to system keys useful for working with AI, while keeping the native system scope clear.
- Alternative: a Dictation-only project name.
- Basis: author's explicit naming preference and approval of the proposed packaging.
- Status: accepted working name; repository availability not yet checked.

## 2026-10-09 / D-002 — Preserve the simple workflow

- Decision: center sends the native microphone key; minus sends Backspace; plus sends Enter. Apply once at login, with a manual recovery command.
- Reason: the author accepted the physical workflow and prefers no recurring background checks or per-application shortcuts.
- Alternative: application-specific dictation/undo shortcuts, automation services and periodic restoration.
- Basis: author's tested configuration and instructions.
- Status: accepted; the center event's interpretation and Siri prerequisite are clarified by D-005.

## 2026-10-09 / D-003 — First publication scope

- Decision: prepare GitHub, Habr and Threads materials, including the author's personal account of working with an AI assistant. Telegram is excluded; video is deferred.
- Reason: match the author's available channels and prepare the package before recording a demonstration.
- Alternative: launch simultaneously with a video and Telegram post.
- Basis: author's explicit correction of the initial plan.
- Status: accepted for local preparation; external publication requires explicit authorization.

## 2026-10-09 / D-004 — Public package and licensing

- Decision: use a small native shell CLI with install/status/apply/uninstall, readable mapping data and an MIT license credited to Sergo Lebedovich.
- Reason: make the setup reproducible and removable by ordinary readers without adding runtime dependencies.
- Alternative: publish raw machine-specific files and manual XML-editing instructions.
- Basis: author's agreement with the proposed repository contents and MIT recommendation; public author name verified from GitHub account metadata.
- Status: accepted for the local publication candidate.

## 2026-10-09 / D-005 — Siri prerequisite for the tested center mapping

- Decision: retain the three fixed mappings and document Siri-off as a manual prerequisite of this tested profile. Preserve the existing Dictation shortcut. Include restoration of the original Siri state in complete rollback.
- Reason: the same CF mapping triggered Siri on the second Mac while Siri was on; the author turned Siri off and Dictation worked. The first Mac already had Siri off. Fn-versus-Control was not changed to resolve the issue.
- Alternative: a D8 Dictation usage trial, which produced no effect; a Control-based successor trial, which became unnecessary.
- Basis: author's comparison and physical second-Mac result; the D8 trial's verified restoration.
- Status: accepted for documentation. No automatic Siri setting changes or new code profile are authorized or implemented. Replaces the earlier interpretation of CF as a guaranteed native microphone key in D-002.

## 2026-10-09 / D-006 — Keep Siri off after package removal

- Decision: keep Siri disabled on the author's second Mac as the desired final preference, including after uninstall.
- Reason: the author explicitly said he does not want to enable Siri and does not like using it.
- Alternative: restore its earlier enabled state for an exact pre-test system-preference rollback.
- Basis: author's instruction after the screenshot confirming package removal, empty mapping and unregistered login job.
- Status: accepted. Refines the Siri-state restoration expectation in D-005; no automatic system preference change is introduced.

## 2026-10-09 / D-007 — Clear uninstall in the proposed menu-bar app

- Decision: include "Удалить EarPods AI Keys…" in the proposed menu, with a plain-language confirmation describing removal of the app, its login registration and settings, and restoration of owned button mappings. Move the app to Trash and report success only after cleanup succeeds.
- Reason: the author wants a clear removal path inside the app rather than another terminal procedure.
- Basis: author's explicit request to add an understandable uninstaller.
- Status: accepted UI requirement, subsequently authorized by D-009. Cleanup must preserve foreign mappings and files, and must not change the user's Siri or macOS Dictation preferences.

## 2026-10-09 / D-008 — Requested native app workflow and configurable keys

- Direction: a draggable Applications bundle with a menu-bar UI, on/off mode, per-button single key or combination assignment, optional login startup that waits for disconnected EarPods, and complete removal of app-owned configuration/login state. Provide the existing Dictation/Backspace/Enter profile as a default.
- Reset semantics: resetting assignments returns the app's default input profile; disabling or uninstalling returns the owned EarPods controls to their standard media behavior. Do not reset unrelated macOS preferences.
- Basis: author's explicit description of the desired workflow and invitation to identify questions or additions.
- Status: authorized by D-009. Retaining native center Dictation together with chord dispatch still requires hardware acceptance; API availability alone does not establish compatibility.

## 2026-10-10 / D-009 — Implement the native menu-bar app

- Decision: implement the D-008 workflow with native Swift/AppKit, one event-driven resident app, no recurring polling, and additional macOS input/control permissions only for chord assignments.
- Basis: the author's explicit “это прекрасно. го!” and later choice to connect EarPods to the first Mac for joint testing.
- Backend candidate: retain hidutil for native single keys and VoiceCommand; use nonexclusive per-device IOHID callbacks plus complete CGEvent key pairs for chords, with Keyboard NoEvent suppressing the chord source's original action. No exclusive seizure, global event tap or virtual HID driver.
- Ownership: refuse prior login installers and foreign HID rules. Persist verified/pending ownership before writes; clear only exact owned rules. Failed uninstall retains recovery information and does not self-Trash.
- Verification: the spec was approved after two independent review iterations (97.5/100). Isolated tests, native UI inspection and actual physical acceptance are separate evidence.
- Status: implementation authorized; development candidate built. Physical chord/media/Dictation coexistence, actual login startup and complete self-removal remain acceptance checks.

## 2026-10-10 / D-010 — Matching original app and menu icons

- Decision: add an original wired-headphone/three-button-remote icon for Finder/Applications and the corresponding monochrome template for the menu bar, following the author's request.
- Source: native Swift/AppKit vector geometry, PNG iconset, native iconutil-generated ICNS. No SF Symbols or device artwork is exported into the app icon. The Apple HIG restricts symbol use in app icons; the original motif also distinguishes this app from a generic music accessory.
- Packaging: CFBundleIconFile=AppIcon.icns, build 2, only ICNS and two menu PNG assets copied before code signing. Original generator and visual previews remain in the source project.
- Verification: size/ICNS roundtrip, UI compile, native Finder icon API preview, strict/deep signed bundle and archive roundtrip passed. Current installed build 1 remains unchanged while the author defers the detailed chord test. A later replacement may require renewed permission confirmation for the new ad-hoc identity.
- Status: requested icon implemented in a separate transferable candidate; current app has not been replaced.

## 2026-10-11 / D-011 — Permit explicit first-login registration

- Decision: allow an explicit Enable login request from mainApp status notRegistered or notFound. Continue requiring enabled/requiresApproval after register; preserve native NSError diagnostics and strict Disable/uninstall verification.
- Reason: the earlier guard refused a permitted first-registration attempt. Apple DTS documents notFound for never-seen services and demonstrates direct mainApp.register. Scoped absence/log evidence was consistent with that finding, although the original live before-status was not captured.
- Verification: five management regressions, 40-suite pass and independent source review. The author subsequently confirmed build 3 in the system's Open at Login list. Reboot launch is a separate pending acceptance check.
- Packaging: combine this fix with the original icon as build 3; retain the exact stopped build 1 privately. No hidden login fallback, recurring poll, BTM/TCC reset or paid signing action.


## 2026-10-16 / D-012 — Drag-to-Applications DMG

- Decision: provide a DMG with two visible items, the unchanged signed app and a real «Программы» link to /Applications, with an original background and saved Finder positions.
- Basis: the author explicitly asked to implement the proposed DMG immediately.
- Build scope: native disk-image tools, an original bounded offline layout writer and native background alias generator are developer tools only; no runtime dependency, app rebuild, settings migration, signing purchase or external publication.
- Verification: final UDZO/read-only attach, exact bundle payload/signature, background alias and Applications link passed. The final Downloads image opened its intended Finder window and was visually inspected, then ejected. Five failure regressions and independent packaging source review passed; see app/validation/dmg-candidate.json.
- Limit: the app remains the ad-hoc, non-notarized build 3. Actual drag installation and native app behavior on the second Mac remain the next acceptance stage.


## 2026-10-16 / D-013 — Defer paid Developer Program enrollment and notarization

- Decision: keep the current ad-hoc DMG and defer paid Developer Program enrollment/Developer ID notarization at this stage.
- Basis: the author explicitly declined the annual membership expense for this app for now. This is a present-stage choice, not a permanent ban on future notarization.
- Distribution: retain the documented per-app macOS first-launch approval procedure and describe the candidate's non-notarized status accurately. Do not replace this with automatic quarantine removal or global security changes.
- Scope: no purchase, enrollment, certificate creation, signing replacement or upload. Continue second-Mac cleanup and physical app acceptance with the existing verified DMG.


## 2026-10-16 / D-014 — Public repository and author-led publication

- Decision: publish the repository publicly under metalebedenko/earpods-ai-keys with Sergo Lebedovich as author; no AI coauthor trailer or assistant contributor identity. Use the author's GitHub noreply address for commit metadata.
- Basis: the author's explicit public-repo instruction and preference to keep AI assistance out of coauthor attribution. This does not authorize false claims of wholly manual development.
- Materials: prepare distinct Habr, Pikabu, Threads and Reddit texts with a minimal shared image set; no social-platform posting yet. Habr's current rules require a separate human-authored article, so its prepared material is reference only.
- Distribution: publish a privacy-cleaned ad-hoc preview DMG derived from tested build 3; stripping symbol records preserves all runtime sections, but the public asset has a new signature/hash. No paid signing or notarization.
- Status: published and verified public on 2026-10-16; preview v0.1.0-preview.3 from cba4e27fc7252462217bb0bf31ddf03fd577c49a. Anonymous download matches the public SHA-256. Social posts remain drafts.
