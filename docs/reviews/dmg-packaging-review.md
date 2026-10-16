# DMG packaging review — 2026-10-16

Scope: build-only package-dmg.py, native background-alias helper and the bounded layout-writer contract. The existing app/runtime and its working installation are outside this change.

An independent reviewer found two concrete blocking issues in the first packaging-script draft:

1. Output inside the source .app was not rejected before conversion. The fixed guard checks canonical containment and refuses any app ancestor, with casefold for .APP paths on case-insensitive macOS. The regression verifies direct, symlink and uppercase paths are rejected before any tool runs. Existing output is also preserved.
2. A failed or timed-out attach could mount an image before returning a device to the caller. Failure recovery now queries native inventory and detaches only devices backed by the exact canonical newly created image path. Malformed/unknown device data refuses broad cleanup; cleanup failure reports the exact image for recovery. Tests cover timeout, malformed response and unexpected mounts while preserving another mounted image.

The reviewer re-read the fixes and closed the findings, reporting no new concrete blockers in the inspected scope. The C helper and layout contract also had no blocking findings. No reviewer performed OS mutations or ran the app.

Root validation: five mocked failure-path tests passed, a real final image build passed checksum/read-only/payload/signature/link/alias checks, and the actual final Finder window was opened and visually inspected, then ejected. These runtime checks are distinct from the static review. This is an ordinary bounded code review, not a specification score or a broad compatibility audit.
