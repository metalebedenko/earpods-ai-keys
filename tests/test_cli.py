"""Meaningful mutation checks with isolated HOME and instrumented tool paths.

Run on macOS: python3 -m unittest discover -s tests -v
Production code has no environment-based tool override mechanism.
"""
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
CANONICAL = json.loads((REPO / "mapping.json").read_text())["UserKeyMapping"]
NATIVE_TOOLS = {
    "/usr/bin/hidutil": "hidutil", "/bin/launchctl": "launchctl",
    "/bin/mv": "mv", "/bin/cat": "cat", "/usr/bin/cksum": "cksum",
}


@unittest.skipUnless(sys.platform == "darwin", "uses native macOS plutil on isolated files")
class CliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="earpods-ai-keys-tests-")
        self.root = Path(self.temp.name)
        self.home = self.root / "Reader & $(literal) home"
        self.home.mkdir()
        self.package = self.root / "package"
        self.package.mkdir()
        self.tools = self.root / "fake-tools"
        self.tools.mkdir()
        self.state_path = self.root / "state.json"
        self.write_state(device=True, mapping=None, jobs={}, disabled={}, events=[])
        for native, name in NATIVE_TOOLS.items():
            wrapper = self.tools / name
            wrapper.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + " "
                               + shlex.quote(str(REPO / "tests/fake_tools.py")) + " "
                               + shlex.quote(name) + ' "$@"\n')
            wrapper.chmod(0o700)
        source = (REPO / "earpods-ai-keys.sh").read_text()
        for native, name in NATIVE_TOOLS.items():
            source = source.replace(native, shlex.quote(str(self.tools / name)))
        # Guard this harness itself: even the installed copy cannot contain a
        # route to a real HID mutation or launchctl command.
        self.assertNotIn("/usr/bin/hidutil", source)
        self.assertNotIn("/bin/launchctl", source)
        (self.package / "earpods-ai-keys.sh").write_text(source)
        for name in ("mapping.json", "launchagent.template.plist"):
            shutil.copyfile(REPO / name, self.package / name)
        self.env = dict(os.environ, HOME=str(self.home),
                        EARPODS_TEST_STATE=str(self.state_path),
                        EARPODS_TEST_ROOT=str(self.root))
        self.service = f"gui/{os.getuid()}/local.earpods-ai-keys"
        self.install_dir = self.home / "Library/Application Support/EarPods AI Keys"
        self.plist = self.home / "Library/LaunchAgents/local.earpods-ai-keys.plist"

    def tearDown(self):
        self.temp.cleanup()

    def write_state(self, **changes):
        state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}
        state.update(changes)
        self.state_path.write_text(json.dumps(state))

    def state(self):
        return json.loads(self.state_path.read_text())

    def run_cli(self, command, code=0):
        result = subprocess.run(["/bin/sh", str(self.package / "earpods-ai-keys.sh"), command],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def mutations(self):
        return [event for event in self.state()["events"]
                if (event[0] == "hidutil" and "--set" in event)
                or (event[0] == "launchctl" and event[1] != "print")]

    def install(self):
        self.run_cli("install")
        self.assertTrue(self.plist.exists())
        self.assertIn(self.service, self.state()["jobs"])

    def test_status_absent_empty_ours_foreign(self):
        for present, value, name in [(False, None, "absent"), (True, None, "empty"),
                                     (True, [], "empty"), (True, CANONICAL, "ours"),
                                     (True, [{"HIDKeyboardModifierMappingSrc": 1,
                                              "HIDKeyboardModifierMappingDst": 2}], "foreign"),
                                     (True, "unexpected-value", "foreign")]:
            with self.subTest(name=name, value=value):
                self.write_state(device=present, mapping=value)
                result = self.run_cli("status")
                self.assertIn("mapping: " + name, result.stdout)
        self.assertEqual(self.mutations(), [])

    def test_actual_tool_failure_is_not_absence(self):
        for flag in ("fail_hid_get", "fail_launch_print", "bad_hid_response"):
            with self.subTest(flag=flag):
                self.write_state(**{flag: True})
                self.run_cli("status", 1)
                self.write_state(**{flag: False})
        self.assertEqual(self.mutations(), [])

    def test_apply_absent(self):
        self.write_state(device=False)
        self.run_cli("apply", 3)
        self.assertEqual(self.mutations(), [])

    def test_header_only_absence_remains_supported(self):
        self.write_state(device=False, absent_header_only=True)
        self.assertIn("mapping: absent", self.run_cli("status").stdout)
        self.run_cli("apply", 3)
        self.assertEqual(self.mutations(), [])

    def test_absent_device_read_failure_is_not_successful_absence(self):
        self.write_state(device=False, fail_hid_get=True)
        self.run_cli("status", 1)
        self.run_cli("apply", 1)
        self.run_cli("install", 1)
        self.assertEqual(self.mutations(), [])
        self.assertFalse(self.install_dir.exists())

    def test_apply_empty_and_idempotence(self):
        self.run_cli("apply")
        self.assertEqual(self.state()["mapping"], CANONICAL)
        writes = len(self.mutations())
        self.run_cli("apply")
        self.assertEqual(len(self.mutations()), writes)

    def test_foreign_and_unknown_mapping_preserved(self):
        for value in ([{"HIDKeyboardModifierMappingSrc": 10,
                        "HIDKeyboardModifierMappingDst": 11}], "something-new"):
            self.write_state(mapping=value)
            self.run_cli("apply", 4)
            self.run_cli("install", 4)
            self.assertEqual(self.state()["mapping"], value)
        self.assertEqual(self.mutations(), [])

    def test_almost_ours_or_additional_property_is_foreign(self):
        value = json.loads(json.dumps(CANONICAL))
        value[0]["UnrelatedProperty"] = 123
        self.write_state(mapping=value)
        self.run_cli("apply", 4)
        self.assertEqual(self.mutations(), [])

    def test_set_error_and_wrong_readback_report_failure(self):
        self.write_state(fail_hid_set=True)
        self.run_cli("apply", 1)
        self.assertIsNone(self.state()["mapping"])
        self.write_state(fail_hid_set=False, wrong_set_readback=True)
        self.run_cli("apply", 1)

    def test_invalid_mapping_asset_is_not_applied(self):
        asset = self.package / "mapping.json"
        value = {"UserKeyMapping": json.loads(json.dumps(CANONICAL)), "OtherHIDProperty": True}
        asset.write_text(json.dumps(value))
        self.run_cli("apply", 1)
        value.pop("OtherHIDProperty")
        value["UserKeyMapping"][0]["HIDKeyboardModifierMappingSrc"] = "51539607757"
        asset.write_text(json.dumps(value))
        self.run_cli("apply", 1)
        self.assertEqual(self.mutations(), [])

    def test_install_safe_home_paths_and_login_only_plist(self):
        self.install()
        plist = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(plist["ProgramArguments"], ["/bin/sh", str(self.install_dir / "earpods-ai-keys.sh"), "apply"])
        self.assertTrue(plist["RunAtLoad"])
        self.assertNotIn("StartInterval", plist)
        self.assertNotIn("KeepAlive", plist)
        self.assertEqual(self.state()["mapping"], CANONICAL)
        self.assertEqual(self.plist.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.install_dir / "earpods-ai-keys.sh").stat().st_mode & 0o777, 0o700)
        count = len(self.mutations())
        self.run_cli("install")
        self.assertEqual(len(self.mutations()), count)

    def test_install_without_device_requires_later_manual_apply(self):
        self.write_state(device=False)
        self.install()
        self.assertIsNone(self.state()["mapping"])
        self.assertEqual(self.state()["jobs"][self.service]["exit"], 3)
        self.write_state(device=True)
        self.run_cli("apply")
        self.assertEqual(self.state()["mapping"], CANONICAL)

    def test_existing_files_and_symlinks_are_not_overwritten(self):
        self.install_dir.mkdir(parents=True)
        note = self.install_dir / "personal-note"
        note.write_text("keep me")
        self.run_cli("install", 4)
        self.assertEqual(note.read_text(), "keep me")
        shutil.rmtree(self.install_dir)
        self.install_dir.symlink_to(self.package, target_is_directory=True)
        self.run_cli("install", 4)
        self.assertEqual(self.mutations(), [])

    def test_existing_plist_and_registered_foreign_label_preserved(self):
        self.plist.parent.mkdir(parents=True)
        self.plist.write_text("another owner's plist")
        self.run_cli("install", 4)
        self.assertEqual(self.plist.read_text(), "another owner's plist")
        self.plist.unlink()
        self.write_state(jobs={self.service: {"exit": 0}})
        self.run_cli("install", 4)
        self.assertEqual(self.mutations(), [])

    def test_legacy_file_and_job_block_install_and_apply(self):
        old = self.plist.parent / "local.earpods-macos-dictation.plist"
        old.parent.mkdir(parents=True)
        old.write_text("legacy installation")
        for command in ("install", "apply"):
            self.run_cli(command, 4)
        self.assertIn("legacy: local.earpods-macos-dictation", self.run_cli("status").stdout)
        old.unlink()
        old_service = f"gui/{os.getuid()}/local.earpods-gpt-dictation"
        self.write_state(jobs={old_service: {"exit": 0}})
        self.run_cli("install", 4)
        self.run_cli("apply", 4)
        self.assertEqual(self.mutations(), [])

    def test_uninstall_clears_exact_ours_and_preserves_extra_files(self):
        self.install()
        extra = self.install_dir / "reader-note"
        extra.write_text("keep")
        self.run_cli("uninstall")
        self.assertEqual(self.state()["mapping"], [])
        self.assertNotIn(self.service, self.state()["jobs"])
        self.assertFalse(self.plist.exists())
        self.assertEqual(list(self.install_dir.iterdir()), [extra])
        self.assertEqual(extra.read_text(), "keep")

    def test_uninstall_foreign_mapping_is_preserved(self):
        self.install()
        foreign = [{"HIDKeyboardModifierMappingSrc": 10, "HIDKeyboardModifierMappingDst": 11}]
        self.write_state(mapping=foreign)
        self.run_cli("uninstall")
        self.assertEqual(self.state()["mapping"], foreign)
        self.assertFalse(self.install_dir.exists())

    def test_uninstall_with_disconnected_device_never_writes_hid(self):
        self.install()
        self.write_state(device=False)
        before = len([event for event in self.mutations() if event[0] == "hidutil"])
        self.run_cli("uninstall")
        after = len([event for event in self.mutations() if event[0] == "hidutil"])
        self.assertEqual(after, before)
        self.assertFalse(self.plist.exists())
        self.assertFalse(self.install_dir.exists())

    def test_uninstall_does_not_clear_mapping_used_by_new_legacy_job(self):
        self.install()
        jobs = self.state()["jobs"]
        jobs[f"gui/{os.getuid()}/local.earpods-macos-dictation"] = {"exit": 0}
        self.write_state(jobs=jobs)
        self.run_cli("uninstall")
        self.assertEqual(self.state()["mapping"], CANONICAL)

    def test_uninstall_changed_files_is_refused_before_mutations(self):
        self.install()
        self.plist.write_text("replacement owner")
        before = len(self.mutations())
        self.run_cli("uninstall", 4)
        self.assertEqual(len(self.mutations()), before)
        self.assertEqual(self.plist.read_text(), "replacement owner")

    def test_uninstall_absent_is_noop(self):
        self.write_state(mapping=CANONICAL)
        self.run_cli("uninstall")
        self.assertEqual(self.state()["mapping"], CANONICAL)
        self.assertEqual(self.mutations(), [])

    def test_clear_failure_leaves_owned_files_for_retry(self):
        self.install()
        self.write_state(fail_hid_set=True)
        self.run_cli("uninstall", 1)
        self.assertTrue(self.plist.exists())
        self.assertTrue((self.install_dir / ".earpods-ai-keys-owned").exists())
        self.write_state(fail_hid_set=False)
        self.run_cli("uninstall")
        self.assertFalse(self.plist.exists())

    def test_partial_file_move_and_plist_write_are_rolled_back(self):
        for flag in ({"fail_mv_name": "mapping.json"}, {"fail_cat_name": "agent.plist"}):
            with self.subTest(flag=flag):
                self.write_state(**flag)
                self.run_cli("install", 1)
                self.assertFalse(self.install_dir.exists())
                self.assertFalse(self.plist.exists())
                self.assertEqual(self.mutations(), [])
                self.write_state(fail_mv_name=None, fail_cat_name=None)

    def test_launchd_failure_leaves_removable_owned_installation(self):
        self.write_state(fail_launch_bootstrap=True)
        self.run_cli("install", 1)
        self.assertTrue(self.plist.exists())
        self.write_state(fail_launch_bootstrap=False)
        self.run_cli("uninstall")
        self.assertFalse(self.plist.exists())

    def test_checksum_io_failure_is_reported(self):
        self.install()
        self.write_state(fail_cksum=True)
        self.run_cli("status", 1)

    def test_template_cannot_introduce_polling_or_extra_launch_rules(self):
        template = self.package / "launchagent.template.plist"
        original = plistlib.loads(template.read_bytes())
        for key in ("StartInterval", "KeepAlive", "StartCalendarInterval"):
            modified = dict(original, **{key: 15})
            template.write_bytes(plistlib.dumps(modified))
            self.run_cli("install", 1)
            self.assertFalse(self.install_dir.exists())
        self.assertEqual(self.mutations(), [])


if __name__ == "__main__":
    unittest.main()
