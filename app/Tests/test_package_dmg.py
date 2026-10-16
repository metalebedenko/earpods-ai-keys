"""Failure-path regression checks; all disk-image tools are mocked."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("package_dmg", Path(__file__).parents[1] / "package-dmg.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackagingGuards(unittest.TestCase):
    def test_output_inside_source_or_through_parent_symlink_is_rejected_before_tools(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            app = root / "EarPods AI Keys.app"
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            (root / "shortcut").symlink_to(app, target_is_directory=True)
            for output in [resources / "bad.dmg", root / "shortcut/Contents/Resources/bad.dmg",
                           root / "EARPODS AI KEYS.APP/Contents/Resources/bad.dmg"]:
                with self.subTest(output=output), patch.object(package, "run") as run:
                    with patch.object(package.sys, "argv", ["package-dmg.py", str(app), str(output)]):
                        with self.assertRaisesRegex(ValueError, "outside .*app"):
                            package.main()
                    run.assert_not_called()
                    self.assertFalse(output.exists())

    def test_existing_output_preserved(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            app = root / "EarPods AI Keys.app"
            app.mkdir()
            output = root / "existing.dmg"
            output.write_bytes(b"keep")
            with self.assertRaises(ValueError):
                package.validate_output(app, output)
            self.assertEqual(output.read_bytes(), b"keep")

    def check_failed_attach_cleanup(self, failure):
        image = Path("/temporary/our-new-image.dmg")
        calls = []
        def entity(device):
            return {"dev-entry": device, "content-hint": "GUID_partition_scheme"}
        inventory = {"images": [
            {"image-path": str(image), "system-entities": [entity("/dev/disk8")]},
            {"image-path": "/temporary/someone-else.dmg", "system-entities": [entity("/dev/disk9")]},
        ]}
        def run(args, timeout=90):
            calls.append([str(a) for a in args])
            if args[1] == "attach":
                if isinstance(failure, BaseException):
                    raise failure
                return subprocess.CompletedProcess(args, 0, failure)
            if args[1] == "info":
                return subprocess.CompletedProcess(args, 0, plistlib.dumps(inventory))
            return subprocess.CompletedProcess(args, 0, b"")
        with patch.object(package, "run", side_effect=run):
            with self.assertRaises(Exception):
                package.attach(image)
        detached = [args[-1] for args in calls if args[1] == "detach"]
        self.assertEqual(detached, ["/dev/disk8"])

    def test_timeout_recovers_only_exact_new_image(self):
        self.check_failed_attach_cleanup(subprocess.TimeoutExpired("attach", 45))

    def test_invalid_plist_recovers_only_exact_new_image(self):
        self.check_failed_attach_cleanup(b"not a plist")

    def test_unexpected_mount_count_recovers_only_exact_new_image(self):
        self.check_failed_attach_cleanup(plistlib.dumps({"system-entities": [
            {"dev-entry": "/dev/disk8", "content-hint": "GUID_partition_scheme"},
            {"dev-entry": "/dev/disk8s1", "mount-point": "/Volumes/one"},
            {"dev-entry": "/dev/disk8s2", "mount-point": "/Volumes/two"},
        ]}))


if __name__ == "__main__":
    unittest.main()
