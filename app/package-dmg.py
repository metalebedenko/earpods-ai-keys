#!/usr/bin/env python3
"""Package an existing signed app; Python is a developer-only build tool.

Usage: python3 app/package-dmg.py '/path/EarPods AI Keys.app' '/path/output.dmg'
No app launch, installation, permission change, or login/HID operation occurs.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile


def run(args, timeout=90):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True,
                          timeout=timeout)


def manifest(directory):
    result = {}
    for parent, dirs, files in os.walk(directory, followlinks=False):
        for name in dirs + files:
            p = Path(parent) / name
            s = p.lstat()
            item = {"mode": stat.S_IMODE(s.st_mode)}
            if stat.S_ISLNK(s.st_mode):
                item.update(type="symlink", target=os.readlink(p))
            elif stat.S_ISDIR(s.st_mode):
                item.update(type="directory")
            elif stat.S_ISREG(s.st_mode):
                item.update(type="file", sha256=hashlib.sha256(p.read_bytes()).hexdigest())
            else:
                raise ValueError("Unsupported bundle entry: " + str(p))
            result[str(p.relative_to(directory))] = item
    return result


def validate_output(original, output):
    """Reject unsafe destinations before any filesystem or tool mutation."""
    canonical_source = original.resolve(strict=True)
    canonical_output = output.resolve()
    if canonical_source == canonical_output or canonical_source in canonical_output.parents:
        raise ValueError("Output must be outside the source app bundle.")
    if any(part.casefold().endswith(".app") for part in canonical_output.parts):
        raise ValueError("Output must be outside all app bundles.")
    if output.suffix != ".dmg" or output.exists() or output.is_symlink():
        raise ValueError("Output must be a new .dmg path; existing files are preserved.")
    if not output.parent.is_dir() or output.parent.is_symlink():
        raise ValueError("Output parent must be an existing directory.")


def image_devices(entities):
    whole = [x["dev-entry"] for x in entities
             if x.get("content-hint") in ("GUID_partition_scheme", "Apple_partition_scheme")]
    devices = whole or [x["dev-entry"] for x in entities if "mount-point" in x]
    if not devices or not all(re.fullmatch(r"/dev/disk[0-9]+(?:s[0-9]+)?", d) for d in devices):
        raise RuntimeError("Cannot identify exact image devices: " + repr(entities))
    return list(dict.fromkeys(devices))


def recover_failed_attach(image):
    """Query only this newly created image, never detach unrelated mounts."""
    data = plistlib.loads(run(["/usr/bin/hdiutil", "info", "-plist"], timeout=15).stdout)
    matching = [item for item in data.get("images", [])
                if item.get("image-path") and Path(item["image-path"]).resolve() == image.resolve()]
    for item in matching:
        for device in image_devices(item.get("system-entities", [])):
            run(["/usr/bin/hdiutil", "detach", device], timeout=45)


def attach(image, readonly=False):
    args = ["/usr/bin/hdiutil", "attach", "-nobrowse", "-noautoopen", "-verify", "-plist"]
    if readonly:
        args.append("-readonly")
    try:
        data = plistlib.loads(run(args + [image], timeout=45).stdout)
        entities = data["system-entities"]
        mounts = [x for x in entities if "mount-point" in x]
        devices = image_devices(entities)
        if len(mounts) != 1 or len(devices) != 1:
            raise RuntimeError("Expected one mounted image volume/device: " + repr(entities))
        return devices[0], Path(mounts[0]["mount-point"])
    except BaseException as error:
        try:
            recover_failed_attach(image)
        except Exception as cleanup_error:
            raise RuntimeError("Attach failed; automatic cleanup failed for exact image "
                               + str(image) + ": " + str(cleanup_error)) from error
        raise


def main():
    if len(sys.argv) != 3:
        raise ValueError(__doc__.strip())
    original = Path(sys.argv[1]).absolute()
    output = Path(sys.argv[2]).absolute()
    if original.is_symlink() or not original.is_dir() or original.name != "EarPods AI Keys.app":
        raise ValueError("Provide the real signed EarPods AI Keys.app directory.")
    validate_output(original, output)
    info = plistlib.loads((original / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "local.earpods-ai-keys.app":
        raise ValueError("Unexpected app identifier.")
    run(["/usr/bin/codesign", "--verify", "--strict", "--deep", original])
    before = manifest(original)
    app_root = Path(__file__).resolve().parent
    build = app_root / ".build"
    build.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="package-dmg-", dir=build))
    stage = work / "stage"
    stage.mkdir()
    run(["/usr/bin/ditto", original, stage / original.name])
    (stage / "Программы").symlink_to("/Applications", target_is_directory=True)
    (stage / ".background").mkdir()
    shutil.copy2(app_root / "Resources/DMG/background.png", stage / ".background/background.png")
    shutil.copy2(app_root / "Resources/DMG/layout-template.dsstore", stage / ".DS_Store")
    shutil.copy2(original / "Contents/Resources/AppIcon.icns", stage / ".VolumeIcon.icns")
    helper = work / "DMGBackgroundAlias"
    run(["/usr/bin/xcrun", "clang", "-Wno-deprecated-declarations", "-framework", "CoreServices",
         app_root / "Tools/DMGBackgroundAlias.c", "-o", helper])
    editable = work / "layout.dmg"
    run(["/usr/bin/hdiutil", "create", "-srcfolder", stage, "-fs", "HFS+",
         "-format", "UDRW", "-volname", "EarPods AI Keys", editable])
    device = None
    try:
        device, volume = attach(editable)
        alias = work / "background.alias"
        run([helper, "create", volume / ".DS_Store", volume / ".background/background.png", alias])
        layout = work / "layout.dsstore"
        run([sys.executable, app_root / "Tools/WriteDMGLayout.py",
             volume / ".DS_Store", alias, layout])
        # Update the existing metadata file in place: the native alias anchors to its file ID.
        with (volume / ".DS_Store").open("r+b") as stream:
            stream.write(layout.read_bytes())
            stream.truncate()
        run([helper, "check", volume / ".DS_Store", volume / ".background/background.png", alias])
        run(["/usr/bin/xcrun", "SetFile", "-a", "C", volume])
        run(["/usr/bin/hdiutil", "detach", device], timeout=45)
        device = None
        run(["/usr/bin/hdiutil", "convert", editable, "-format", "UDZO", "-o", output])
        run(["/usr/bin/hdiutil", "verify", output], timeout=45)
        image_info = plistlib.loads(run(["/usr/bin/hdiutil", "imageinfo", "-plist", output]).stdout)
        if image_info.get("Format") != "UDZO":
            raise RuntimeError("Final image is not UDZO.")
        device, volume = attach(output, readonly=True)
        expected = {original.name, "Программы", ".background", ".DS_Store", ".VolumeIcon.icns"}
        actual = {p.name for p in volume.iterdir()}
        # HFS+ may create its own bookkeeping directories. These are never user executables.
        system_metadata = {".fseventsd", ".Trashes", ".Spotlight-V100"}
        if actual - system_metadata != expected:
            raise RuntimeError("Unexpected image contents: " + repr(actual))
        link = volume / "Программы"
        if not link.is_symlink() or os.readlink(link) != "/Applications":
            raise RuntimeError("Applications link changed.")
        if manifest(volume / original.name) != before or manifest(original) != before:
            raise RuntimeError("Bundle contents/types/modes changed during packaging.")
        run(["/usr/bin/codesign", "--verify", "--strict", "--deep", volume / original.name])
        run([helper, "check", volume / ".DS_Store", volume / ".background/background.png", alias])
        # readonly attach is explicit; verify the actual mount flags too.
        mount_line = run(["/sbin/mount"]).stdout.decode().splitlines()
        matches = [line for line in mount_line if " on " + str(volume) + " (" in line]
        if len(matches) != 1 or "read-only" not in matches[0]:
            raise RuntimeError("Image mount was not confirmed read-only.")
        run(["/usr/bin/hdiutil", "detach", device], timeout=45)
        device = None
        report = {
            "artifact": output.name, "format": "UDZO", "read_only_mount_verified": True,
            "bytes": output.stat().st_size, "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "bundle_version": info.get("CFBundleShortVersionString"),
            "bundle_build": info.get("CFBundleVersion"),
            "same_source_bundle_manifest_verified": True,
            "strict_deep_signature_verified": True, "applications_link_verified": True,
            "background_alias_resolved_after_conversion": True,
            "source_bundle_unchanged": True, "verification_mount_detached": True,
            "finder_visual_inspection": "separate acceptance step",
            "notarization": "unchanged; no notarization performed",
        }
        (work / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"artifact": str(output), "validation": str(work / "validation.json"),
                          "work_directory": str(work)}, indent=2))
    finally:
        if device is not None:
            try:
                run(["/usr/bin/hdiutil", "detach", device], timeout=45)
            except Exception as error:
                print("Image detach failed; recover this exact device: " + device + ": " + str(error),
                      file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("DMG packaging failed: " + str(error), file=sys.stderr)
        sys.exit(1)
