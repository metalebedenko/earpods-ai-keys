# From a music remote to system keys

USB-C EarPods expose a Consumer Control HID service. The microphone remains a normal audio input. EarPods AI Keys changes three button events through macOS's built-in `hidutil`; macOS Dictation performs the speech recognition.

## Device scope

Operations match VendorID `1452` (`0x05ac`), ProductID `4363` (`0x110b`), PrimaryUsagePage `12` and PrimaryUsage `1`. The mapping is restricted to that device identity; it is not a remap of the Mac keyboard. The login job belongs to the user, but Apple describes the HID mapping itself as applying to all users while its service remains active. Multiple identical devices matching that identity have not been tested.

## The three mappings

| Source | Destination | Result |
|---|---|---|
| Consumer Play/Pause `0xC000000CD` | Consumer Voice Command `0xC000000CF` | Dictation with Siri off in the tested setups |
| Consumer Volume Down `0xC000000EA` | Keyboard Backspace `0x70000002A` | Delete before cursor or selection |
| Consumer Volume Up `0xC000000E9` | Keyboard Return `0x700000028` | Enter in the active application |

`mapping.json` stores these values as decimal integers. It is a fixed mapping for the tested setup, not a general remapping editor.

The center button does not synthesize the configured Dictation shortcut, invoke an application's voice feature, or send text to an AI service. AI applications receive ordinary keyboard and text-input events.

CF is the general VoiceCommand usage, not a guaranteed alias for Apple's physical Microphone key. On the second Mac, it invoked Siri while Siri was enabled; turning Siri off made Dictation work with the same mapping and unchanged Control-twice shortcut. The first Mac also had Siri disabled. Siri-off is therefore an explicit prerequisite of the tested profile; the installer never changes it automatically.

A separate Consumer D8 (Start/Stop Voice Dictation Session) trial produced no effect on the second setup and was restored. It is not used by the installer.

## Persistence

Apple documents that `hidutil` mappings are temporary: restarting the system or removing the HID service can clear them. A `RunAtLoad` LaunchAgent reapplies the mapping once at login and exits. It has no `StartInterval` or `KeepAlive`.

If the device is absent during that run, it is not watched for later connection. The user can rerun `apply` when it is connected. Reconnect behavior must be tested on each configuration.

## Speech processing and focus

Dictation settings control the language and microphone. Apple's guide says Keyboard settings indicate whether ordinary text Dictation uses on-device processing or needs an internet connection. EarPods AI Keys does not choose a recognition engine or modify data-sharing preferences.

Button behavior follows focus: Backspace edits the current selection or character, and Enter may send a message, insert a newline, submit a form or execute a terminal command. Test center start/stop with short press-and-release gestures; do not infer Apple's Microphone-key semantics from the CF usage name or promise hold-to-talk across systems.

## Primary references

- [Apple TN2450: Remapping Keys](https://developer.apple.com/library/archive/technotes/tn2450/_index.html) — the built-in tool, key encoding and mapping lifetime.
- [USB-IF HID Usage Tables 1.3](https://www.usb.org/sites/default/files/hut1_3_0.pdf) — the source and destination usage names and values.
- [Apple: Dictate messages and documents on Mac](https://support.apple.com/en-gb/guide/mac-help/mh40584/mac) — native microphone-key behavior, Dictation setup, typing during Dictation on Apple silicon and processing indicators.
- [Apple: Siri, Dictation & Privacy](https://www.apple.com/legal/privacy/data/en/ask-siri-dictation/) — processing and data sharing.
