"""Isolated macOS tool doubles. Never import this from the production CLI."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys


state_path = Path(os.environ["EARPODS_TEST_STATE"])
state = json.loads(state_path.read_text())
tool, *args = sys.argv[1:]
state["events"].append([tool, *args])


def save():
    state_path.write_text(json.dumps(state))


def finish(code=0, message=None):
    save()
    if message:
        print(message, file=sys.stderr)
    sys.exit(code)


if tool == "hidutil":
    # A bad device scope must fail the test instead of touching a wider model.
    assert args[:2] == ["property", "--matching"], args
    assert json.loads(args[2]) == {
        "VendorID": 1452, "ProductID": 4363,
        "PrimaryUsagePage": 12, "PrimaryUsage": 1,
    }, args
    if args[3:] == ["--get", "UserKeyMapping"]:
        if state.get("fail_hid_get"):
            finish(1, "injected HID read failure")
        if state.get("bad_hid_response"):
            print("not a hidutil property table")
            finish()
        if not state["device"]:
            # Actual macOS 27.0.1: exit 0, no stdout/stderr when unmatched.
            # Keep the header-only form as a compatibility fixture as well.
            if state.get("absent_header_only"):
                print("RegistryID  Key                   Value")
            finish()
        print("RegistryID  Key                   Value")
        mapping = state["mapping"]
        if mapping is None:
            print("100001  UserKeyMapping  (null)")
        elif isinstance(mapping, str):
            print("100001  UserKeyMapping  " + mapping)
        else:
            print("100001  UserKeyMapping  (")
            for index, item in enumerate(mapping):
                print("    {")
                for key, value in item.items():
                    print(f"    {key} = {value};")
                print("    }" + ("," if index < len(mapping) - 1 else ""))
            print(")")
        finish()
    assert args[3] == "--set" and len(args) == 5, args
    if state.get("fail_hid_set"):
        finish(1, "injected HID write failure")
    if state["device"]:
        value = json.loads(args[4])
        assert list(value) == ["UserKeyMapping"], value
        state["mapping"] = value["UserKeyMapping"]
        if state.get("wrong_set_readback"):
            state["mapping"] = [{"HIDKeyboardModifierMappingSrc": 42,
                                 "HIDKeyboardModifierMappingDst": 43}]
    finish()

elif tool == "launchctl":
    if args[0] == "print":
        if state.get("fail_launch_print"):
            finish(1, "injected launchctl inspection failure")
        if args[1] not in state["jobs"]:
            finish(113, 'Could not find service "' + args[1] + '" in domain')
        print("state = not running\nlast exit code = " + str(state["jobs"][args[1]].get("exit", 0)))
        finish()
    if args[0] in ("enable", "disable"):
        if state.get("fail_launch_" + args[0]):
            finish(1, "injected launchctl " + args[0] + " failure")
        state["disabled"][args[1]] = args[0] == "disable"
        finish()
    if args[0] == "bootstrap":
        if state.get("fail_launch_bootstrap"):
            finish(1, "injected launchctl bootstrap failure")
        plist = plistlib.loads(Path(args[2]).read_bytes())
        assert plist["Label"] == "local.earpods-ai-keys", plist
        assert plist["RunAtLoad"] is True, plist
        assert "StartInterval" not in plist and "KeepAlive" not in plist, plist
        service = args[1] + "/" + plist["Label"]
        state["jobs"][service] = {"exit": 0}
        save()
        # Simulate RunAtLoad only with the instrumented test copy, never with
        # a production script that could invoke the real macOS services.
        script = Path(plist["ProgramArguments"][1])
        text = script.read_text()
        assert "/usr/bin/hidutil" not in text and "/bin/launchctl" not in text
        result = subprocess.run(plist["ProgramArguments"], capture_output=True, text=True)
        state = json.loads(state_path.read_text())
        state["jobs"][service]["exit"] = result.returncode
        finish()
    if args[0] == "bootout":
        if state.get("fail_launch_bootout"):
            finish(1, "injected bootout failure")
        state["jobs"].pop(args[1], None)
        finish()
    raise AssertionError(args)

elif tool in ("mv", "cat", "cksum"):
    # Only these optional doubles delegate to a native tool, and only paths
    # under the isolated HOME/test folder are passed by this test suite.
    test_root = Path(os.environ["EARPODS_TEST_ROOT"])
    for arg in args:
        if arg.startswith("/"):
            assert Path(arg).resolve().is_relative_to(test_root.resolve()), args
    if tool == "mv" and state.get("fail_mv_name") == Path(args[0]).name:
        finish(1, "injected file move failure")
    if tool == "cat" and state.get("fail_cat_name") == Path(args[0]).name:
        finish(1, "injected file write failure")
    if tool == "cksum" and state.get("fail_cksum"):
        finish(1, "injected checksum failure")
    save()
    native = {"mv": "/bin/mv", "cat": "/bin/cat", "cksum": "/usr/bin/cksum"}[tool]
    os.execv(native, [native, *args])
else:
    raise AssertionError(tool)
