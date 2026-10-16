# Updating a fingerprinted installation

The installer keeps fingerprints of its installed CLI, mapping and LaunchAgent. Replace source files in the project folder, not files inside `~/Library/Application Support/EarPods AI Keys/`.

For this pre-release update, with connected EarPods, run the new source CLI's `uninstall`, then `install`, then `status`. The new uninstaller recognizes the existing ownership format and exact mapping; the installer writes a fresh complete bundle and matching fingerprints.

Do not merely rerun `install` expecting an upgrade: an intact existing installation is deliberately left unchanged with an Already installed message. Dictation and Siri preferences are not modified by this update.

The 2026-10-09 update fixes successful blank `hidutil` output when no matching EarPods are connected. Installation without a device is allowed, but the login job makes only one attempt; connection afterwards still requires manual `apply`.
