# EarPods AI Keys — current state

Updated: 2026-10-16.

## Goal

Publish Sergo Lebedovich's open-source macOS app and prepare platform-specific materials about turning a music remote into system input.

## State

- Native Swift/AppKit menu-bar app: center → macOS Dictation (Siri off in the tested setup), minus → Backspace, plus → Enter; configurable single keys/chords, optional login, event-driven reconnection and an in-app uninstall action.
- One resident native app observes device events; no periodic polling, driver, third-party runtime, AI account or backend. macOS performs speech recognition; offline processing is not guaranteed.
- USB-C EarPods are matched narrowly by VID 1452 / PID 4363 / Consumer Control page 12, usage 1. Unknown or foreign mappings and unrelated files are preserved.
- The original shell CLI remains an optional alternative, documented separately. Its one-shot login/manual-reconnect behavior must not be attributed to the native app.
- Physical reports cover two Macs on macOS 27.0.1: standard input and reconnection. The second also passed reboot with EarPods attached and reboot without them followed by late connection.
- On the first Mac, center start/stop, Disable with restored volume, minus → ⌘Z without a held modifier, full UI uninstall, clean reinstall and reactivation passed. Read-only state corroboration is detailed in [verification](docs/verification.md).
- Current tested app is version 0.1.0, build 3, ARM64, ad-hoc signed; original app copies and private recovery remain unchanged by publication preparation.
- The public preview removes private build paths from symbol records, then re-signs helper → app. All 36 main-app and 33 helper runtime sections match the physically tested build byte for byte. The public copy was not separately installed or given a new hardware run.
- Public asset: EarPods-AI-Keys-0.1.0-preview.3-arm64.dmg, 1,336,305 bytes, SHA-256 a341eff4e2e63c4e2d1b9475e5868ff622cd91db0c1c0651bf5e7c2b17095ed4. Checksum, read-only mount, bundle manifest/signature, Applications link and native background alias passed; see [public manifest](app/validation/public-release.json).
- Latest software run: 40 Swift tests, 36 shell/trial tests and 5 packaging regressions passed. The release build script now strips symbol records before signing.
- README in English/Russian now leads with the app, DMG, first-launch approval and a real settings screenshot. Two core UI screenshots plus an optional DMG-window image were supplied by the author and checked for visible private data.
- Habr, Pikabu, Threads and Reddit materials are prepared locally under [publications](docs/publications/README.md). Habr's rules prohibit AI-written/edited articles, so its file is reference material, not a ready-to-post article; the author must write that article himself. Pikabu's generated-content tag and Reddit community eligibility are documented.
- The author explicitly authorized a public GitHub repo and requested authorship under his own name, without AI coauthor credit. No social-platform posting was requested; those texts remain drafts.
- GitHub publication is being completed for metalebedenko/earpods-ai-keys; verified URL/commit/release facts will be recorded after completion.

## Active task

Finish pre-publication scan of the exact staged source and public asset; create the public repository and preview release, verify public access and remote commit. Keep the author's GitHub noreply address in repo-local Git identity. No assistant coauthor trailer.

## Limits

- Current downloadable architecture is ARM64. Other headsets, Intel downloads and macOS versions beyond the reported 27.0.1 configurations are unverified; the source deployment target is 13+.
- Exact readiness time is unmeasured. Chord reconnect, second-Mac chords/Disable/full uninstall, and legacy-cleanup outcome are not inferred from standard-input success.
- The first-Mac connected-at-login scenario is distinct from the second Mac's confirmed run; Spotlight icon refresh remains unreported.
- Siri off is a manual prerequisite of the tested Dictation route. Enter follows the active app and can execute terminal commands. No guaranteed offline recognition or semantic undo claim.
- Paid Developer Program enrollment/notarization is deferred (D-013). The release remains ad-hoc and documents per-app Open Anyway; no global security-policy bypass is introduced.
- Root has no access to the second Mac. Its results are the author's physical reports; no remote readback is claimed.
- Local build folders, old binaries, caches and the operational second-Mac cleanup handoff stay outside Git. Earlier private ZIP/DMG hashes are historical test evidence, not the public download.

## Next step

After public URL, commit, visibility and asset checks pass, report the live repository/release and the four local publication materials. The author chooses when and where to post; Habr needs his independently authored article. Video is deferred, Telegram excluded. Preserve private recovery and avoid general cache/BTM/TCC resets.
