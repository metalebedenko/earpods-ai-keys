# EarPods AI Keys — Reddit drafts

Prepared 2026-10-16. Nothing has been posted. Suggested community: r/macapps. Start with its current monthly **App Pile** megathread unless the author qualifies for main-feed posting and completes the community's approval steps. Account eligibility has not been checked. See [platform notes and primary sources](platform-notes.md).

Use one version. The main-feed draft is conditional; a new open-source repository alone does not establish eligibility. Before publishing, verify that the repository and `v0.1.0-preview.3` release are publicly accessible.

## App Pile megathread comment

I'm the author of **EarPods AI Keys**, a free, MIT-licensed menu-bar app for the wired USB-C EarPods remote.

I bought the earphones and wanted to dictate prompts into a terminal or chat window from the buttons on the cable. The default mapping is:

- Center: native macOS Dictation. **Siri must be off for the setup I've tested.**
- Minus: Backspace.
- Plus: Enter, with the active app's usual behavior.

The Swift/AppKit app has configurable keys and chords, enable/disable, event-driven reconnect, optional launch at login and uninstall from its menu. It handles the remapping itself; no additional remapping app is needed. Speech recognition uses macOS Dictation, with its own processing settings.

Basic input works on my two Macs running macOS 27.0.1. On the second I also checked reconnect and rebooting both with EarPods attached and without them, then connecting later. Command-Z, Disable and full uninstall were checked on the first.

This is an **ARM64 preview, ad-hoc signed and not notarized**. The README explains the first-launch approval process. Chords need additional macOS permissions.

Source and release: https://github.com/metalebedenko/earpods-ai-keys

If you try it, I'd appreciate your Mac model, macOS version and what each button did.

## Main-feed post — only after eligibility and approval

### Title

[OS] I turned the USB-C EarPods remote into Dictation, Backspace and Enter keys for my Mac

### Body

I'm the author of **EarPods AI Keys**. It's free, MIT-licensed and still a preview.

**Problem:** I wanted to dictate prompts into a terminal or chat window, fix a bit of text and press Enter using the buttons on my wired USB-C EarPods.

The defaults are center → native macOS Dictation, minus → Backspace, plus → Enter. **The Dictation route I've tested requires Siri to be switched off manually.** Enter keeps the active app's normal behavior: it can insert a newline, send a message or execute a terminal command.

It's a native Swift/AppKit menu-bar app. You can change all three assignments, record a chord such as Command-Z, switch the mode off, optionally launch at login and uninstall from the menu. Reconnect is driven by device notifications, with no periodic polling.

Single-key actions use native HID remapping. Chords use input from the matching EarPods device and post a complete key pair. The app uses macOS Dictation for speech recognition; the text goes into the focused field. Speech processing follows Apple's Dictation settings and availability.

**Comparison:** Karabiner-Elements is a broader key remapper, and Hammerspoon provides general macOS automation through Lua. My goal here is a small, dedicated interface for this particular remote: three assignments, reconnect and removal in one place, with no extra remapping app or configuration script for the user. I haven't benchmarked it against either tool.

**Price:** $0. The full app is open source under MIT; there is no paid tier or subscription.

I checked basic Dictation/Backspace/Enter input on two Macs with macOS 27.0.1. On the second, reconnect and rebooting with or without EarPods attached passed my checks. On the first, I also tested Command-Z alongside Dictation, Disable with restored media controls and full uninstall. Those results don't establish compatibility with every Mac or macOS version.

The current download is **Apple Silicon / ARM64**, ad-hoc signed and **not notarized**. Gatekeeper may block the first launch; the README explains approval for this specific app. Custom chords need extra macOS permissions.

Source: https://github.com/metalebedenko/earpods-ai-keys

Preview DMG: https://github.com/metalebedenko/earpods-ai-keys/releases/tag/v0.1.0-preview.3

If you have USB-C EarPods and try it, I'd be interested in your Mac model, macOS version and the result for each button.

## Editorial notes — do not paste

- For the main feed, use the current community's free-app flair and `[OS]` title prefix. The text covers Problem / Comparison / Pricing. If qualifying through the transparency route, add the author's real, existing portfolio/identity/LinkedIn/contact and privacy/terms links required by the moderators. Those links have not been supplied; do not invent them or assume this draft qualifies.
- The megathread version needs no images. For an eligible main-feed post, one optional attachment is enough: [the shared settings screenshot](../media/button-settings.png). Caption: “Settings window waiting for EarPods. Default Dictation / Backspace / Enter assignments shown.” Do not paste this relative file link into Reddit; upload the real image. No second screenshot is needed.
- If asked about development: “Yes, I used AI assistance while building it. I ran the hardware checks on my own Macs; the source and test notes are in the repo.” No claim that every line was manually written, and no assistant credit or coauthor attribution.
- No claim of universal compatibility, guaranteed offline transcription, semantic undo, automatic sending to a particular AI service, or App Store/notarized distribution.
