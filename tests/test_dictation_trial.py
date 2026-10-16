"""One-off trial checks: no real HID mutation and no launchctl operations."""
import json
import os
from pathlib import Path
import pty
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
ORIGINAL = json.loads((REPO / "mapping.json").read_text())["UserKeyMapping"]
TRIAL = json.loads(json.dumps(ORIGINAL))
TRIAL[0]["HIDKeyboardModifierMappingDst"] = 51539607768


@unittest.skipUnless(sys.platform == "darwin", "macOS-only script")
class DictationTrialTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="earpods-dictation-trial-")
        self.root = Path(self.temp.name)
        self.state_path = self.root / "state.json"
        self.write_state(device=True, mapping=ORIGINAL, jobs={}, disabled={}, events=[])
        wrapper = self.root / "fake-hidutil"
        wrapper.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + " "
                           + shlex.quote(str(REPO / "tests/fake_tools.py"))
                           + ' hidutil "$@"\n')
        wrapper.chmod(0o700)
        self.model_tool = self.root / "fake-sysctl"
        self.model_tool.write_text("#!/bin/sh\nprintf '%s\\n' Mac15,13\n")
        self.model_tool.chmod(0o700)
        source = (REPO / "tools/EarPods-Dictation-Test.command").read_text()
        source = source.replace("/usr/bin/hidutil", shlex.quote(str(wrapper)))
        source = source.replace("/usr/sbin/sysctl", shlex.quote(str(self.model_tool)))
        self.assertNotIn("/usr/bin/hidutil", source)
        self.assertNotIn("launchctl", source)
        self.script = self.root / "EarPods-Dictation-Test.command"
        self.script.write_text(source)
        self.env = dict(os.environ, HOME=str(self.root),
                        EARPODS_TEST_STATE=str(self.state_path), EARPODS_TEST_ROOT=str(self.root))
        self.processes = []
        self.fds = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)
        for fd in self.fds:
            os.close(fd)
        self.temp.cleanup()

    def write_state(self, **changes):
        state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}
        state.update(changes)
        self.state_path.write_text(json.dumps(state))

    def state(self):
        return json.loads(self.state_path.read_text())

    def writes(self):
        return [json.loads(event[-1])["UserKeyMapping"] for event in self.state()["events"]
                if event[0] == "hidutil" and "--set" in event]

    def start(self, lines=None, args=(), tty=True):
        if tty:
            master, slave = pty.openpty()
            self.fds.extend([master, slave])
            stdin = slave
        else:
            master = None
            stdin = subprocess.DEVNULL
        process = subprocess.Popen(["/bin/sh", str(self.script), *args], env=self.env,
                                   stdin=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True)
        self.processes.append(process)
        if lines is not None:
            os.write(master, lines.encode())
        return process

    def finish(self, process, code=0):
        out, err = process.communicate(timeout=10)
        self.assertEqual(process.returncode, code, out + err)
        return out + err

    def wait_for_trial(self, process):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if self.state()["mapping"] == TRIAL:
                return
            if process.poll() is not None:
                self.fail("Script exited before trial: " + str(process.communicate()))
            time.sleep(0.03)
        self.fail("Trial mapping was not applied")

    def test_normal_trial_restores_before_success(self):
        output = self.finish(self.start("\n1\n\n"))
        self.assertEqual(self.writes(), [TRIAL, ORIGINAL])
        self.assertEqual(self.state()["mapping"], ORIGINAL)
        self.assertIn("Результат пользователя", output)
        self.assertIn("Возврат проверен", output)

    def test_silent_result_also_restores(self):
        self.finish(self.start("\n2\n\n"))
        self.assertEqual(self.writes(), [TRIAL, ORIGINAL])

    def test_foreign_absent_empty_and_unknown_output_are_preserved(self):
        cases = [dict(mapping=[{"HIDKeyboardModifierMappingSrc": 1,
                                 "HIDKeyboardModifierMappingDst": 2}]),
                 dict(device=False), dict(mapping=None), dict(bad_hid_response=True)]
        for changes in cases:
            with self.subTest(changes=changes):
                self.write_state(device=True, mapping=ORIGINAL, bad_hid_response=False, events=[])
                self.write_state(**changes)
                self.finish(self.start(), 1)
                self.assertEqual(self.writes(), [])

    def test_noninteractive_and_other_mac_are_refused(self):
        self.finish(self.start(tty=False), 1)
        self.model_tool.write_text("#!/bin/sh\nprintf '%s\\n' Mac16,10\n")
        self.finish(self.start(), 1)
        self.assertEqual(self.writes(), [])

    def test_relaunch_recovers_existing_trial_without_starting_new_one(self):
        self.write_state(mapping=TRIAL)
        self.finish(self.start())
        self.assertEqual(self.writes(), [ORIGINAL])

    def test_restore_mode_handles_original_trial_and_preserves_foreign(self):
        self.finish(self.start(args=("--restore",), tty=False))
        self.assertEqual(self.writes(), [])
        self.write_state(mapping=TRIAL)
        self.finish(self.start(args=("--restore",), tty=False))
        self.assertEqual(self.state()["mapping"], ORIGINAL)
        foreign = [{"HIDKeyboardModifierMappingSrc": 10, "HIDKeyboardModifierMappingDst": 20}]
        self.write_state(mapping=foreign, events=[])
        self.finish(self.start(args=("--restore",), tty=False), 1)
        self.assertEqual(self.state()["mapping"], foreign)
        self.assertEqual(self.writes(), [])

    def test_interrupts_restore_exact_trial(self):
        for sig in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(sig=sig):
                self.write_state(mapping=ORIGINAL, events=[])
                process = self.start("\n")
                self.wait_for_trial(process)
                process.send_signal(sig)
                self.finish(process, 128 + sig)
                self.assertEqual(self.state()["mapping"], ORIGINAL)
                self.assertEqual(self.writes(), [TRIAL, ORIGINAL])

    def test_disconnect_on_cleanup_reports_recovery_needed(self):
        process = self.start("\n")
        self.wait_for_trial(process)
        self.write_state(device=False)
        process.send_signal(signal.SIGTERM)
        output = self.finish(process, 1)
        self.assertIn("--restore", output)
        self.assertEqual(self.writes(), [TRIAL])

    def test_changed_mapping_during_trial_is_not_overwritten(self):
        process = self.start("\n")
        self.wait_for_trial(process)
        foreign = [{"HIDKeyboardModifierMappingSrc": 10, "HIDKeyboardModifierMappingDst": 20}]
        self.write_state(mapping=foreign)
        process.send_signal(signal.SIGTERM)
        self.finish(process, 1)
        self.assertEqual(self.state()["mapping"], foreign)
        self.assertEqual(self.writes(), [TRIAL])

    def test_failed_set_and_wrong_readback_do_not_replace_foreign_rules(self):
        self.write_state(fail_hid_set=True)
        self.finish(self.start("\n"), 1)
        self.assertEqual(self.state()["mapping"], ORIGINAL)
        self.write_state(fail_hid_set=False, wrong_set_readback=True, events=[])
        self.finish(self.start("\n"), 1)
        self.assertEqual(len(self.writes()), 1)
        self.assertNotEqual(self.state()["mapping"], ORIGINAL)


if __name__ == "__main__":
    unittest.main()
