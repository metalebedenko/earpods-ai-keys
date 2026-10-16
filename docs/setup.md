# Setup and removal

## Before installation

Use USB-C Apple EarPods matching VID `0x05ac`, PID `0x110b`, Consumer Control usage page `12`, usage `1`. The physical behavior has been tested on a Mac mini M4 with macOS 27.0.1; support for other configurations needs confirmation.

1. Connect EarPods.
2. Open **System Settings → Keyboard → Dictation**. Enable Dictation, choose your language and the EarPods microphone.
3. Keep your existing Dictation keyboard shortcut. The tested center sends VoiceCommand rather than synthesizing that shortcut. **Turn Siri off manually in System Settings → Siri** for this tested profile, and record whether it was originally on for rollback.
4. Download the project folder or clone its repository. Open a terminal in that folder. Cloning after publication:

```sh
git clone https://github.com/metalebedenko/earpods-ai-keys.git
cd earpods-ai-keys
```

No administrator password or installation of another remapping application is required. The project does not change Dictation, Siri, microphone permissions or speech-processing preferences for you. If you need to keep Siri enabled, this tested center-button profile does not meet that requirement; no alternate trigger is verified yet.

## Commands

```sh
/bin/sh ./earpods-ai-keys.sh status
/bin/sh ./earpods-ai-keys.sh install
/bin/sh ./earpods-ai-keys.sh status
```

`status` reports the connected device's mapping and this package's installation. Treat an absent device, a foreign mapping or an error as a separate state; a stored LaunchAgent does not prove the buttons work.

`install` puts the runtime in `~/Library/Application Support/EarPods AI Keys/` and adds `~/Library/LaunchAgents/local.earpods-ai-keys.plist`. The job uses `RunAtLoad` only. It has no repeating interval or `KeepAlive`. With connected EarPods and an empty or already-owned mapping, the setup can apply its three pairs immediately.

The installer preserves unrelated nonempty mappings and refuses conflicting installation files. An earlier personal setup named `local.earpods-macos-dictation` is a separate installation; the public package does not silently migrate or replace it. Installation while EarPods are disconnected is allowed, but you must connect them and run `apply` before using the keys.

For recovery after removing the downloaded source folder, the installed CLI is also available at:

```sh
/bin/sh "$HOME/Library/Application Support/EarPods AI Keys/earpods-ai-keys.sh" status
```

Replace `status` with `apply` or `uninstall` as needed. `install` uses the source bundle, including its template.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Command completed; `status` can still report absent or foreign state |
| 1 | Tool or filesystem failure |
| 2 | Invalid arguments |
| 3 | EarPods absent during manual `apply` |
| 4 | Mapping, file or legacy installation conflict |

## Check the actual buttons

Start in an empty text document, with the cursor in its editable field.

1. Press and release the center button and dictate a short phrase.
2. Press − and confirm that it deletes the character before the cursor, or your selection. This is ordinary Backspace.
3. Press + and confirm that the document receives Enter.
4. Repeat in your desired AI input field. Enter follows that application's behavior. In a terminal it may execute a command.

On the author's Apple silicon setup, deletion during Dictation allowed speech input to continue. Apple also documents typing during Dictation on Apple silicon. This does not establish the same experience on every Mac.

## After login or reconnecting

`hidutil` mappings are temporary. Apple documents reset after system restart or removal of the relevant HID service. EarPods must be connected when the one-shot login job runs.

If you connect later or lose the mapping, run:

```sh
/bin/sh ./earpods-ai-keys.sh apply
/bin/sh ./earpods-ai-keys.sh status
```

The package has no listener waiting for connection. Test a real next login and reconnect on your own configuration; these scenarios are not covered by the author's initial physical test.

## Uninstall

```sh
/bin/sh ./earpods-ai-keys.sh uninstall
```

The command stops its login setup and removes its owned installation files. Ownership is checked with a marker and file fingerprints. If installation files have been modified, replaced or lost, removal stops so those files can be reviewed. Extra files are kept.

It clears the connected device's mapping only if the current rule exactly matches this project's three pairs. Foreign or unrecognized rules are preserved. A detected legacy installation also prevents clearing a rule it may use. If EarPods are disconnected, the command cannot verify or clear their current mapping; reconnect and check the actual buttons before assuming stock behavior.

The Dictation and Siri preferences you changed manually remain your system preferences. If you want the exact pre-test preferences, restore those original choices yourself after uninstall. You may also intentionally keep Siri off; that is the author's chosen final preference on the second Mac. The usual media functions are replaced while the project's mapping is active.

## References

- [Apple TN2450](https://developer.apple.com/library/archive/technotes/tn2450/_index.html)
- [Apple Dictation guide](https://support.apple.com/en-gb/guide/mac-help/mh40584/mac)
- [Apple: Siri, Dictation & Privacy](https://www.apple.com/legal/privacy/data/en/ask-siri-dictation/)
