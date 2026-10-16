# EarPods AI Keys — agent instructions

Read PROJECT_SUMMARY.md for current state and README.md for the material map.

- This project turns a USB-C EarPods music remote into native macOS Dictation, Backspace and Enter keys. Keep the implementation small and understandable.
- Runtime uses tools/frameworks included with macOS. The author approved a native menu-bar app with event-driven EarPods input/connection handling on 2026-10-10. No periodic device polling, driver, Python runtime or third-party remapping app. See docs/menu-bar-app-spec.md for the approved scope and review status.
- Restrict HID operations to the known Apple EarPods Consumer Control device. Preserve nonempty foreign or unrecognized mappings.
- Installation and removal must respect files owned by other software. Clearing a mapping is allowed only when it exactly matches the shell profile or a native app's verified/pending ownership receipt; arbitrary nonempty rules are preserved.
- Developing the public package does not authorize changing the author's working EarPods installation. Test mutations with isolated tool doubles; actual hardware testing requires a separately agreed scenario.
- Do not claim compatibility beyond reported tests, guaranteed offline speech recognition, semantic undo, or unconditional message sending.
- Publication drafts live under docs/publications. Update instructions if the CLI changes. No Git commits, pushes or external publication without explicit user authorization.
- Keep private paths, logs, credentials, machine names and session transcripts out of public files.

On the author's workspace, shared collaboration rules are in ~/.knowledge/core/rules.md. Contributors elsewhere do not need that private Knowledge base.
