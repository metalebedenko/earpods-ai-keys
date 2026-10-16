# Verification and compatibility evidence

## Physical workflow — 2026-10-07

The author tested the accepted three-button mapping on a Mac mini M4 running macOS 27.0.1, with Apple USB-C EarPods identified as VID `1452`, PID `4363` and Consumer Control page `12`, usage `1`.

| Check | Evidence |
|---|---|
| Center starts native macOS Dictation | Author's hands-on test |
| Minus deletes while dictating and speech input continues | Author's hands-on test |
| Plus presses Enter and sends in the tested AI input | Author's hands-on test |
| Personal login job has RunAtLoad only and exits successfully | Local plist/runtime inspection of the earlier installation |

This evidence concerns the author's accepted mapping and earlier personal installation. It is not an end-to-end test of the new public installer.

## Public package — 2026-10-09

The local publication candidate passed these checks:

| Check | Result |
|---|---|
| Shell syntax (`/bin/sh -n earpods-ai-keys.sh`) | Passed |
| Native plist validation (`plutil -lint launchagent.template.plist`) | Passed |
| Installer regression suite | 26 tests passed |
| Full discovery including temporary-trial helper | 36 tests passed |
| Independent review and rerun of the inspected isolated suite | 23 tests passed; no unresolved blocking findings |
| Native, read-only `status` on the author's Mac | Device present, exact mapping recognized, earlier personal installation reported |
| Actual HID state before/after package preparation | Identical readback |
| Local Markdown links and publication post lengths | Passed; Threads 361 / 322 / 450 / 490 characters |

Behavioral tests cover absent/empty/owned/foreign mapping states, unknown output, actual tool failures, precise device matching, repeated apply, invalid mapping assets, installation paths containing spaces and literal shell metacharacters, one-shot launch configuration, conflicts with earlier installs, altered/extra files, removal, failed readback and partial-install rollback.

Run the developer suite on macOS:

```sh
python3 -m unittest discover -s tests -v
```

Mutation tests use a temporary home directory and copies of the CLI whose absolute `hidutil` and `launchctl` paths are replaced with local test doubles. The inspected harness asserts that no real HID/launchctl path remains before it executes a copy. Production code does not accept tool-path overrides. Public-package install/apply/uninstall were not run against the author's real services.

Python is a developer test dependency only; the installed package uses native macOS tools and `/bin/sh`.

Normal `plutil -lint` rejected JSON on the tested system, so the CLI checks mapping assets through typed `plutil -extract` and the exact supported pairs. The installer generates its argument array with remove/insert and validates the result; a native array-replacement quirk was caught by the isolated suite and corrected.

## Second Mac — manual test in progress, 2026-10-09

The author transferred the package and ran it on Mac15,13 with macOS 27.0.1 (build 26A434). The root agent does not control that computer; these results come from the author's screenshots and report.

- Before installation: installation absent, legacy none, device present, mapping empty, agent not registered.
- Existing Dictation preferences: enabled; Russian (Russia); automatic microphone selection showing EarPods; Control twice. The author requested leaving these preferences unchanged.
- After installation: installation ours, legacy none, device present, mapping ours, agent registered.
- Initial physical center press with Siri enabled: Siri opens instead of Dictation.
- The author confirmed plus performs Enter and minus performs Backspace.
- Native Control-twice Dictation works. Center single press toggles Siri, double press also invokes it, and holding behaves erratically. This is not evidence that the user accidentally held the button during the single-press test.
- The author ran the D8 trial and selected result 2 (no effect). The screenshot confirms restoration/readback of the original CF / Backspace / Enter mapping. This does not establish a universal absence of D8 support; it records this device/setup's result.
- The standalone trial helper has ten isolated tests covering application/restoration, interruption, relaunch recovery, incompatible model, noninteractive input, absence/conflicts and tool failures. Main installer code was not changed for this experiment.
- The supplied uninstall/status screenshot confirms installation absent, legacy none, device present, mapping empty and agent not registered. The author then confirmed +/- adjust volume and the center opens Apple Music. Both the software removal and restored physical media behavior are confirmed.
- The later requested reboot/login check is recorded below; immediate remote readiness remains unresolved.
- Connected reinstallation then succeeded, and a subsequent install returned Already installed. Final status confirmed installation/mapping ours and agent registered.
- Unplugged install initially failed with Unrecognized hidutil response. First-Mac read-only reproduction found exit 0 with blank stdout/stderr from both matching property and list queries. The CLI now classifies that successful blank response as absent while preserving nonempty unknown/error refusals; 26 installer regression tests passed.
- The author updated through uninstall/install from the fixed bundle. The screenshot includes the new Siri prerequisite message, installation/mapping ours, device present and registered job. The author confirmed the requested remote functions work as intended on this build.
- With EarPods unplugged, the fixed status reports device absent and mapping absent without error. After reconnect it reports device present and mapping empty, while installation remains ours and the job registered. This physically confirms the corrected absence branch and loss of mapping on reconnect in this setup.
- Manual apply after that reconnect succeeded. The subsequent screenshot confirms installation ours, legacy none, device present, mapping ours and agent registered. This confirms mapping recovery/readback; physical buttons after this particular apply have not yet been separately reported.
- In response to the reboot/login instructions, the author ran only installed-path status. The screenshot shows installation ours, legacy none, device present, mapping ours and agent registered. The author reports the remote initially did not work, then worked after status, while roughly two minutes had also passed. Which buttons initially failed and their exact timing have not yet been specified.
- Targeted static review confirms status only fingerprints/reads files, calls launchctl print and reads UserKeyMapping. It does not set a mapping, bootstrap, kickstart or enable a job. That status screenshot confirms the exact rule at read time; the timing and reason for initial controls failing remain unknown.
- The next second-Mac screenshot of read-only launchctl print shows main state not running, runs 1, last exit code 0 and job state exited. One successful job execution and absence of a continuing job process are confirmed. The broad awk filter also printed nested state active lines; read-only inspection of the first Mac's equivalent personal job identifies these as resource/jetsam coalitions, not the job's process state. This structure check is not a second-Mac timing measurement.
- The author followed the disconnected reboot/login, wait, then connect scenario. The screenshot shows a new console login and installed-path status: installation ours, legacy none, device present, mapping empty, agent registered. Installed-path apply then printed success for the exact VoiceCommand/Backspace/Enter pairs. Static inspection of apply confirms that this success message follows exact mapping readback, so restoration is verified without a separate status command. Physical buttons after this latest apply have not yet been reported. No launchctl exit information for this disconnected-login run was provided.
- Fresh first-Mac file inspection confirms its installed three HID pairs are the same as the public bundle.
- The author found Siri off on the first Mac and on on the second. After switching Siri off on the second, center Dictation worked with the same CF rule and unchanged Control-twice shortcut. This establishes the Siri prerequisite for the observed setup; it is not a universal macOS compatibility claim.
- Siri was originally enabled, but the author explicitly chose to keep it off after removal. This is a deliberate final system preference. The uninstaller does not change Siri; restoring a reader's earlier Siri state is optional when they want an exact pre-test preference rollback.

## Native menu-bar app — development candidate, 2026-10-10

The author authorized the native app implementation and chose the first Mac for joint testing. This extends the CLI scope to an event-driven resident menu-bar process; it does not add periodic polling or change Siri/Dictation preferences.

| Check | Result / evidence |
|---|---|
| Concrete specification | Approved after two independent iterations; 97.5/100 final score, no spec blockers |
| Native build and ad-hoc code-signature verification | Passed for initial debug and final ARM64 release bundles; system frameworks/tools only |
| Isolated native software tests | 35 passed with Swift Testing: 17 Core, 11 management, 7 bounded child runner |
| Visual rendering | Native settings view and menu-shaped preview inspected; no clipping/overlap |
| Actual app launch/menu | Author screenshot: mode off, EarPods connected, expected menu actions visible |
| Actual settings window | Author screenshot and native accessibility tree: three rows, default Dictation/Backspace/Enter, reset/apply controls |
| Local chord recorder | Native UI tests: minus records ⌘Z; plus records ⌘Enter; unsaved state and permission action appear, without applying a HID map |
| Reset assignments | Actual window returns Dictation/Backspace/Enter, Apply disabled, saved state has enabled false and empty receipt |
| Native helper Trash path | Actual helper moved a uniquely named disposable copy into Trash and removed its own stage. Original bundle unchanged; no HID/login/support mutation or permission grant |
| Transfer archive | ARM64 release ZIP created; extracted bundle passes strict/deep signature verification, both executable hashes match source bundle |
| Prior installation preservation at this point | Read-only HID remains empty; personal login job remains registered. A private exact recovery copy was made; no job/mapping change yet |

Core tests cover exact reply normalization/refusal, validated keys/modifiers, NoEvent only for chord sources, receipt serialization, foreign/symlink support preservation, late arrival and retry cancellation, legacy refusal, permission-before-suppression, write/readback failure, startup cleanup of an owned residual rule, failed rollback ownership, restored chord dispatch, termination intent and failed-disable persistence. Management tests cover actual login status semantics through isolated adapters, approval/failure paths, ordering of cleanup, failed clear/unregister retention, support-file preservation, helper staging failure/recovery, and foreign bundle/symlink refusal.

Run the native developer suite with `cd app && /bin/sh ./test.sh`. The script loads the bundled Swift Testing macro explicitly when the Command Line Tools require it; production has no test dependency.

The native child-runner tests include ordinary combined stdout/stderr, nonzero exit, partial-output timeout with child termination, closed output streams while a child remains running, ignored TERM, output overflow, exact-limit success, launch failure and invalid UTF-8. Execution defaults to a 3-second deadline and 64-KiB combined output cap; timeout/overflow never reaches the HID parser. Production tool paths are fixed. NativeHIDRuntime invalidates its prior snapshot on failed command/write attempts.

The recorder test does not establish physical EarPods chord dispatch. Native hybrid input/media suppression, native Dictation alongside a chord, reconnect, real login registration and complete self-removal are separate acceptance gates. The helper test uses a writable temporary directory and an already exited own child; it does not establish Applications permissions or the full UI/login cleanup flow. See [backend review](reviews/native-app-backend-review.md) and its disposable-copy evidence. The candidate is ad-hoc signed and is not a notarized public release.

Independent re-review closed the native command-runner finding; no unresolved concrete code blockers remain in the inspected scopes. Transfer archive identity and SHA-256 are recorded in [release-candidate.json](../app/validation/release-candidate.json). No Git commit, push or public release was created. At the initial candidate handover the debug app remained disabled, its profile standard, the prior personal job registered and matching HID readback empty.

For the author's subsequent request to begin the first-Mac physical test, the verified release app was copied into an absent Applications target; both executable hashes and strict/deep signature checks passed. Fresh plist/mapping hashes, disabled saved profile/empty receipt and identical empty HID baseline were checked before booting out the exact prior job and moving its plist into private recovery storage. Runtime files and launchd disabled flags were preserved. Both other prior labels have no installed/registered job. Readback remained empty: no HID write was made. The release app is not yet launched; the author will close the disabled debug copy and enable the new copy through its menu.

Independent rollback review caught that the personal disable script also disables/boots out its login job. It will not be used for a mapping-only rollback; guarded restoration instructions are retained in the private backup. Physical results remain pending.

### First-Mac default profile and Disable — physical pass

The author then reported the actual app menu “Пульт работает”, minus deleting one symbol, plus inserting a newline, center starting Dictation and a repeated short center press stopping it. Plus/minus did not change volume while the app profile was enabled. After choosing Disable, plus/minus again controlled volume. The stock center action after Disable was not separately reported.

Subsequent read-only process inspection shows the Applications release copy as the sole EarPods app. HID readback is an empty array; saved state has enabled=false, the standard profile and an empty receipt. This corroborates the reported disabled state and owned-rule cleanup; it does not establish chord behavior or reconnect.

The reconnect acceptance protocol checks physical buttons before opening the menu or choosing Retry: opening the menu calls controller.refresh and can itself restore a mapping, so menu status alone could conceal a missing connection callback.

### First-Mac reconnect — physical pass

In response to that protocol, the author reports that the remote works as intended after reconnection: Dictation, Enter and Backspace all work. Subsequent read-only HID inspection shows the exact default three pairs on a changed registry service, with enabled=true, the standard profile and its verified ownership receipt. No diagnostic read writes a rule. This records first-Mac default-profile reconnect recovery in the reported test; actual disconnected-login startup and the chord profile remain separate checks.

### Chord permissions — unresolved preflight

The author granted permissions, but attempting minus=Command+Z still shows the missing-permissions message and restoration of the prior profile. Native UI inspection confirms EarPods AI Keys is toggled on in both Input Monitoring and the observed macOS 27 control-permission pane “Управление устройством и доступ к данным”. The similarly named main sidebar Accessibility page is a features page, not this permission list. The agent navigated/read these panes without changing a switch.

The agent retried the prepared Command+Z draft through Apply; it still failed with the same permission/rollback message. This is not evidence of physical chord failure: the chord suppression map was not activated. App restart is the next diagnostic. No restart success, false-preflight identity or underlying cause is established yet; no new binary, TCC reset or unrelated access was introduced.

The author subsequently restarted the same unchanged Applications app, repeated the draft/apply steps and reports success. Read-only inspection confirms a changed process, saved enabled profile with Command+Z on minus, native CF on center and Enter on plus, and the exact live CF/NoEvent/Enter mapping matching the verified receipt. This establishes successful chord-profile activation after restart; the original false preflight and the cause are not identified. Detailed physical Undo, modifier release, media suppression and Dictation coexistence remain awaiting the author's report. The installed code/signature has not changed.

### Original app/menu icon — build 2 candidate

The author requested a Finder/Applications icon matching the menu's idea. Original vector artwork depicts generic wired in-ear headphones and a three-button remote, with a blue app tile and a corresponding transparent monochrome menu glyph. Its geometry lives in app/Tools/GenerateIcons.swift. SF Symbols are not copied into the app icon; Apple restricts that use in its [SF Symbols HIG](https://developer.apple.com/design/human-interface-guidelines/sf-symbols).

Ten native iconset dimensions through 1024×1024 and the 22/44-pixel menu resources were verified. Native iconutil roundtrip and UI typecheck passed. Root inspection confirmed readable menu previews at 18/20/22 points on light/dark backgrounds and the app artwork at 1024. NSWorkspace.icon(forFile:) for the actual new bundle rendered the custom icon, confirming the Finder icon lookup path rather than merely a standalone PNG preview.

The build 2 release bundle has CFBundleIconFile=AppIcon.icns. Exactly three icon assets are copied before sealing; generator, iconset and previews are not packaged. Strict/deep ad-hoc signature and extracted ZIP signature/payload hashes passed. See [icon-candidate.json](../app/validation/icon-candidate.json). Core/HID logic was not changed and the earlier 35-test result is not presented as a new test run. Build 2 is not yet launched on hardware or installed.

Read-only hashing confirms installed build 1's executable, helper and Info.plist still match its verified original. The author chose to perform the detailed chord test later. Preserve this installed identity until that result; new ad-hoc packaging can require renewed permission confirmation. No TCC reset/grant or app/login/HID mutation was performed for the icon work.

The bounded independent packaging review found no concrete build 2 blocker. It checked the real icon name/slots, both template representations, shipped resource set and source bytes against the signature resource seal. It confirmed a new ad-hoc designated requirement tied to this candidate's CDHash, so transfer of the prior app's TCC grants is not assumed.

### First-Mac chord profile — physical pass, 2026-10-11

The author supplied the requested detailed TextEdit result: minus performs Undo, ordinary 123 typing after it works, center starts/stops Dictation, plus inserts a newline and minus does not change volume. This validates the hybrid route in this test: original input remains deliverable with the NoEvent map, the original volume action is suppressed and native Dictation coexists with a chord. No held Command was observed. Other apps, chord-profile reconnect and other computers remain separate checks.

Before icon replacement, source and installed signatures, the installed original build 1 payload and the build 2 ZIP checksum were freshly rechecked. Window automation currently fails with native pipe startup even after resetting its runtime. No alternate UI automation or TCC change was attempted. The author was asked to reset assignments and quit through the app; replacement waits for verified disabled standard state, empty mapping and no running app.

The author confirmed Reset and Disable/quit. Subsequent reads show standard disabled preferences, an empty receipt and live HID array, with no running EarPods process. The author also reported a generic failure from Launch at login; exact alert text was unavailable. Read-only BTM inventory contains no EarPods item, and scoped system logs repeatedly show record-not-found for the exact Applications app URL. No actual before-status value or register-call trace was captured.

The existing enable branch refused .notFound before register. Apple DTS explains that this status can occur when the system has never seen a service, while its [mainApp registration example](https://developer.apple.com/forums/thread/777520) invokes register directly. This supports a narrow change allowing an explicit user registration request from notRegistered or notFound, with the same required postcondition enabled/requiresApproval. See [DTS status discussion](https://developer.apple.com/forums/thread/719862). This is a code finding consistent with the observed failure; successful native registration is still unverified. Disable/uninstall strict verification remains unchanged; no BTM/TCC reset or fallback login job is introduced.

The narrow fix passed 40 Swift tests (17 Core, 16 management, 7 native runner), including five new first-registration/result/diagnostic regressions. Independent source review found no concrete blocker; Disable/uninstall paths remain strict. Build 3 combines the fix and original icons. It was installed only after standard disabled state, empty mapping and no running app were verified; the exact previous app was retained privately. Source/installed signatures, payload hashes and archive roundtrip passed.

The author then supplied a System Settings screenshot showing EarPods AI Keys.app in Open at Login, confirming native registration. This is not a reboot-launch test. Last saved mode is OFF, independent of registration; login behavior requires enabling that intent before reboot.

The author also supplied screenshots: Finder's Applications list now shows the correct custom blue icon, while the Spotlight Apps grid still shows a generic icon. NSWorkspace icon lookup for the actual installed app returns the custom icon. The exact bundle's directory timestamp/Launch Services metadata and Spotlight import were refreshed; signatures remained valid. Several own development copies appear in metadata searches, which is only a possible factor, not proof of Spotlight's choice. No global cache reset, reindex, BTM reset, backup relocation or binary alteration was performed for this display issue. Its next UI/reboot result remains pending.

### First-Mac build 3 disconnected login and late connection — physical pass, 2026-10-16

The author reported rebooting with EarPods disconnected. Its waiting-state menu screenshot shows the remote enabled, no EarPods attached and Launch at login checked. The author then confirmed that the menu icon appeared automatically at startup, without a manual app launch. In response to the protocol to connect EarPods, wait about five seconds and test in TextEdit before opening the menu or Retry, the author reported that all steps worked: center starts/stops Dictation, minus deletes a character and plus inserts a newline. This is the author's physical report; exact time to readiness was not measured.

Fresh read-only inspection corroborates a new process from the installed Applications copy, started after the current system boot, enabled standard preferences and the exact default three live HID pairs matching the verified receipt. Diagnostic reads did not apply a mapping or start the app. This confirms the reported disconnected-login/late-connection scenario on build 3; connected-at-login, chord-profile login/reconnect and other Macs remain separate cases. Full Applications UI uninstall remains pending. There was no code change or new software-test run for this acceptance result.

### First-Mac build 3 full UI uninstall and clean reinstallation — 2026-10-16

Starting with EarPods connected, the standard remote enabled and login registered, the author selected the full menu uninstall action. The author reports that the app was removed, stock button behavior returned and no errors appeared. Before any reinstallation, fresh read-only checks found no Applications bundle, no own support directory, no main/helper process or EarPods launch jobs, and an empty live HID mapping. The native BTM inventory retained a historical row marked disabled; no claim is made that macOS erased its record history. The implementation requires successful main-app login unregistration with notRegistered readback before settings removal and helper launch.

The temporary helper stage was absent. The held prior personal plist hash, original mapping hash and all 11 original personal runtime files still matched the recovery baseline, and the prior disabled flag was unchanged. Direct listing of Trash was denied by macOS privacy; its destination is therefore not independently verified in this run. No additional permission was requested. The reported successful UI outcome and the independently checked cleanup state are recorded separately in the acceptance JSON.

For the agreed return to the app, the same verified build 3 was copied into the absent Applications target. Strict/deep signature verification passed, and every installed bundle file matches the verified source. It was not launched through a command or otherwise during this step. The author then opened the Applications copy and confirmed the requested clean UI state: mode OFF, standard Dictation/Backspace/Enter assignments and Launch at login unchecked. Read-only inspection found that Applications process and an empty live mapping; settings.json is still absent before any first save, which is expected for the lazy store. Thus the UI defaults are confirmed by the author rather than represented as saved JSON values. The author then enabled the remote and Launch at login, checked the usual three actions and reported success. Fresh reads show settings.json now exists with enabled=true, the standard profile and a receipt matching the exact live rule. This closes post-reinstallation UI reactivation, not a second reboot test. No source change or new software-test run was needed.

### DMG delivery of the unchanged build 3 — 2026-10-16

The author requested a conventional drag-to-Applications window immediately. An original background and native Finder seed are packaged with the same signed build 3, without rebuilding or changing the installed app. The image contains only two visible entries: EarPods AI Keys.app and «Программы», a symbolic link to /Applications. Hidden resources hold the original background, saved single-leaf Finder layout and volume icon. Build-time Python uses only the standard library, while CoreServices creates and resolves a native background alias; these tools are not shipped as app runtime dependencies.

The final UDZO image passes hdiutil checksum verification, an explicit read-only mount with native mount-flag readback, exact relative path/type/permission/byte comparison of the app against the verified source, strict/deep signature verification, link validation and background-alias resolution after conversion. A fresh final build using the corrected packager completed these checks. The case-insensitive destination guard added afterward changes only refusal behavior; it does not change the image payload.

The actual final artifact in Downloads was opened with Finder. Its root window opened automatically; native AX shows the expected two items. A complete CUA screenshot was inspected: the 720×478 window has the blue app icon, arrow, Applications folder, title and Russian instruction, with no clipping. No app was launched from the image or dragged over the working installation. The image was ejected and a subsequent native image inventory confirms no packaging/verification image remains attached. Portable identity is in [dmg-candidate.json](../app/validation/dmg-candidate.json).

Five isolated packaging regressions cover refusing output inside the source bundle (including symlink and uppercase .APP paths), preserving existing output and exact-image cleanup after attach timeout, malformed plist or unexpected mount count. All passed without actual disk mutations. Independent source review closed the identified containment and failed-attach cleanup findings; see [packaging review](reviews/dmg-packaging-review.md). The previous 40 native app tests were not rerun or represented as new results. Second-Mac launch and basic native controls were subsequently reported as working, as recorded below. The exact drag gesture and Gatekeeper approval UX were not separately reported. The image does not add Developer ID signing or notarization.

### Second-Mac native app launch and standard input — physical report, 2026-10-16

After the earlier report of an installed app blocked at first launch, the author confirmed that the native app works on the second Mac: launched it, connected EarPods, enabled the remote, dictated text, deleted text and inserted a newline. This confirms the reported launch and basic Dictation/Backspace/Enter workflow on that computer. The root agent has no access to it; no local process, mapping, package hash or settings readback is implied. The precise approval steps used to open the app and the DMG drag gesture were not separately described.

The author's follow-up on the same date confirmed that the native app also works after disconnecting/reconnecting EarPods, after rebooting with EarPods connected, and after rebooting without EarPods followed by connecting them. These are physical author reports of the three requested connection/startup cases, not remote inspection. Exact readiness timing was not measured. They close the second-Mac standard-profile reconnect and both reboot/connection scenarios.

The reports do not separately establish a repeated center press to stop Dictation, Disable, chord assignments, full uninstall or completion of the legacy-cleanup prompt. Those remain separate cases. No source change, app rebuild or software-test rerun was needed to record these physical results; see [dmg-candidate.json](../app/validation/dmg-candidate.json).

## Still unverified

- Native app on the second Mac: repeated center press to stop Dictation, Disable, chords, full uninstall and legacy-cleanup outcome. Launch, basic standard input, reconnect and reboot both with attached EarPods and without them followed by late connection are author-confirmed. Exact readiness timing, the DMG drag gesture and Gatekeeper approval steps were not separately reported.
- Native app on the first Mac: chord-profile reconnect and a separate connected-at-login case.
- Detailed continuous-editing-during-Dictation evidence on the second Mac, and other macOS versions.
- Earlier second-Mac shell package: physical controls immediately after login and after the earlier manual apply, exact per-button results in that reboot/login test, and the cause of the reported delay. One successful login-job execution, later matching status and reported remote function are confirmed; prompt availability is not.
- Earlier second-Mac shell package: physical controls after the latest late-connection apply. The late-connection empty mapping and successful manual restoration are verified on physical hardware without polling.
- Multiple identical matching EarPods devices.
- Guaranteed offline Dictation processing. This project does not enforce it.

Report physical results separately from `status` output. In particular, a matching HID rule does not demonstrate speech recognition, the active input field, or the application's Enter behavior.


## Public preview preparation — 2026-10-16

The author authorized public GitHub publication. Pre-publication inspection found private build paths only in symbol records of the earlier main/helper binaries. On a separate copy, native strip -S removed those records; the helper and app were re-signed ad hoc in that order. Independent and root comparisons found all 36 main-app and 33 helper runtime sections byte-identical to the physically tested build 3. The original source bundle and installed app were not changed. The repackaged public copy has not been separately installed or physically tested; its signature differs from prior copies.

The public DMG passed native checksum verification, read-only mounting, exact source-bundle manifest and strict/deep signature checks, Applications-link and native background-alias validation, then detachment. Its identity is in [public-release.json](../app/validation/public-release.json). Earlier private DMG/ZIP values remain historical, not download instructions.

Fresh software runs passed 40 Swift tests, 36 shell/trial tests and 5 packaging guard regressions. The Swift toolchain emitted existing linker search-path and test deployment-target warnings but exited successfully. No runtime implementation changed; future release builds now strip debug symbol records before signing.

The author supplied three actual window screenshots for publication. The settings and menu show waiting for disconnected EarPods, not a simulated physical result; an optional third shows DMG installation. They were visually inspected and copied without adding UI or replacing text. See [media](media/README.md).


Public GitHub verification on 2026-10-16 confirmed private=false, visibility=public, main as default branch, MIT, and a published prerelease v0.1.0-preview.3 from source commit cba4e27fc7252462217bb0bf31ddf03fd577c49a. Remote main matched that source SHA at initial publication. Anonymous HTTP checks returned 200 for the repo, Russian README, publication index, screenshot and release page. The anonymously downloaded 1,336,305-byte DMG matches a341eff4e2e63c4e2d1b9475e5868ff622cd91db0c1c0651bf5e7c2b17095ed4, also reported by the release asset digest. The initial 94-file staged set and public asset passed independent privacy review. Author/committer map to metalebedenko and the contributor list contains only that account; no AI coauthor trailer is present. No posts were sent to the four social platforms.
