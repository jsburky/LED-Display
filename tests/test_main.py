import sys
import types


fake_evdev = types.ModuleType("evdev")
fake_evdev.InputDevice = object
fake_evdev.categorize = lambda event: event
fake_evdev.ecodes = types.SimpleNamespace()
fake_evdev.list_devices = lambda: []
sys.modules.setdefault("evdev", fake_evdev)

import main


def test_build_commands_uses_project_shutdown_script():
    commands = main.build_commands(None)

    assert commands["0"] == ["bash", str(main.APP_DIR / "shutdown_services.sh")]
    assert commands["9"] == ["sudo", "reboot"]
    assert commands["1"][1] == str(main.APP_DIR / "time.py")


def test_build_commands_splits_custom_clock_command():
    commands = main.build_commands("python time.py --led-brightness 50")

    assert commands["1"] == ["python", "time.py", "--led-brightness", "50"]