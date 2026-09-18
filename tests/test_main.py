import importlib.util
import sys
import types
from pathlib import Path


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


def test_command_key_mapping_rejects_function_key_collisions():
    assert main.command_key_for_keycode("KEY_9") == "9"
    assert main.command_key_for_keycode("KEY_KP9") == "9"
    assert main.command_key_for_keycode("KEY_F9") is None


def test_clock_monitor_restarts_a_crashed_child(monkeypatch):
    class FakeProcess:
        def __init__(self, return_code=None):
            self.return_code = return_code
            self.terminated = False

        def poll(self):
            return self.return_code

        def terminate(self):
            self.terminated = True

        def wait(self, timeout=None):
            return self.return_code

    processes = [FakeProcess(return_code=7), FakeProcess()]

    def fake_popen(command):
        return processes.pop(0)

    monkeypatch.setattr(main.subprocess, "Popen", fake_popen)
    monkeypatch.setattr(main, "CHILD_RESTART_BACKOFF_SECONDS", 0.01)
    main.commands = {"1": ["clock"]}
    main.current_process = FakeProcess(return_code=7)
    main.clock_process_supervised = True
    main.supervisor_stop_event.clear()

    thread = __import__("threading").Thread(target=main.monitor_clock_process)
    thread.start()
    thread.join(timeout=1)
    main.supervisor_stop_event.set()
    thread.join(timeout=1)

    assert main.current_process is not None
    assert main.clock_process_supervised is True
    main.current_process = None
    main.clock_process_supervised = False


def test_weather_request_uses_https_and_bounded_timeout(monkeypatch):
    fake_rgbmatrix = types.ModuleType("rgbmatrix")
    fake_rgbmatrix.RGBMatrix = object
    fake_rgbmatrix.RGBMatrixOptions = object
    fake_rgbmatrix.graphics = types.SimpleNamespace()
    monkeypatch.setitem(sys.modules, "rgbmatrix", fake_rgbmatrix)

    module_path = Path(__file__).parents[1] / "time.py"
    spec = importlib.util.spec_from_file_location("led_time_for_test", module_path)
    led_time = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(led_time)

    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {
                "main": {"temp": 72},
                "weather": [{"main": "Clear"}],
                "sys": {"sunrise": 1, "sunset": 9999999999},
            }

    calls = []

    def fake_get(url, **kwargs):
        calls.append((url, kwargs))
        return Response()

    monkeypatch.setattr(led_time.requests, "get", fake_get)
    instance = led_time.GraphicsTest.__new__(led_time.GraphicsTest)
    instance.weather_api_key = "test-key"
    instance.logger = types.SimpleNamespace(exception=lambda message: None)

    assert instance.get_weather_data(1, 2)["temperature"] == 72
    assert calls[0][0] == "https://api.openweathermap.org/data/2.5/weather"
    assert calls[0][1]["timeout"] == (5, 10)