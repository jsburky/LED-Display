#!/usr/bin/env python3
"""Launch display programs from an evdev keypad.

All machine-specific values can be supplied through command-line options or
environment variables.  This lets the launcher work from any checkout path.
"""

import argparse
import os
import shlex
import subprocess
import sys
import threading
from pathlib import Path

from evdev import InputDevice, categorize, ecodes, list_devices


APP_DIR = Path(__file__).resolve().parent
DEFAULT_CLOCK_COMMAND = [
    sys.executable,
    str(APP_DIR / "time.py"),
    "--led-rows=64",
    "--led-cols=64",
    "-m",
    "adafruit-hat",
    "--led-slowdown-gpio=4",
]
DEFAULT_DEVICE = os.environ.get("LED_INPUT_DEVICE")
SUPPORTED_KEY_COMMANDS = {
    **{f"KEY_{digit}": str(digit) for digit in range(10)},
    **{f"KEY_KP{digit}": str(digit) for digit in range(10)},
}
CHILD_RESTART_BACKOFF_SECONDS = 2


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--device",
        default=DEFAULT_DEVICE,
        help="keypad event device (default: auto-detect, or LED_INPUT_DEVICE)",
    )
    parser.add_argument(
        "--restart-seconds",
        type=int,
        default=int(os.environ.get("LED_RESTART_SECONDS", "3600")),
        help="restart the clock after this many seconds (default: 3600)",
    )
    parser.add_argument(
        "--clock-command",
        default=os.environ.get("LED_CLOCK_COMMAND"),
        help="shell-like command for key 1 (default: local time.py)",
    )
    return parser.parse_args()


def find_keypad(device_path):
    if device_path:
        return InputDevice(device_path)

    candidates = []
    for path in list_devices():
        device = InputDevice(path)
        capabilities = device.capabilities().get(ecodes.EV_KEY, [])
        device_name = (device.name or "").lower()
        has_numeric_keys = any(
            key_code in capabilities
            for key_code in (ecodes.KEY_0, ecodes.KEY_KP0)
        )
        looks_like_keyboard = "keyboard" in device_name or "keypad" in device_name
        if has_numeric_keys and looks_like_keyboard:
            candidates.append(device)
        else:
            device.close()

    primary_candidates = [
        device for device in candidates if (device.phys or "").endswith("/input0")
    ]
    if len(primary_candidates) == 1:
        selected = primary_candidates[0]
        for device in candidates:
            if device is not selected:
                device.close()
        return selected

    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        raise RuntimeError(
            "No keypad found. Connect one or set LED_INPUT_DEVICE/--device "
            "to a /dev/input/eventX path."
        )

    names = ", ".join(f"{device.path} ({device.name})" for device in candidates)
    raise RuntimeError(
        "Multiple input devices found. Set LED_INPUT_DEVICE/--device to the "
        f"keypad device. Available devices: {names}"
    )


def build_commands(clock_command):
    if clock_command:
        clock = shlex.split(clock_command)
    else:
        clock = DEFAULT_CLOCK_COMMAND

    shutdown_script = APP_DIR / "shutdown_services.sh"
    shutdown = ["bash", str(shutdown_script)] if shutdown_script.exists() else ["bash", "shutdown_services.sh"]
    return {
        "0": shutdown,
        "1": clock,
        "9": ["sudo", "reboot"],
    }

# Global state for the currently running command.
current_process = None
reset_timer = None
process_lock = threading.Lock()
supervisor_stop_event = threading.Event()
clock_process_supervised = False
commands = {}
restart_seconds = 3600

# Stop a child completely before replacing it.
def stop_current_process():
    global current_process, reset_timer, clock_process_supervised
    if current_process is not None:
        process = current_process
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        current_process = None
        clock_process_supervised = False
        print("Cancelled current command")
    if reset_timer is not None:
        reset_timer.cancel()
        reset_timer = None


def execute_command(key):
    global current_process, reset_timer, clock_process_supervised
    command = commands.get(key)
    if command is None:
        return

    with process_lock:
        stop_current_process()
        current_process = subprocess.Popen(command)
        clock_process_supervised = key == "1"
        if key == "1" and restart_seconds > 0:
            reset_timer = threading.Timer(restart_seconds, restart_clock)
            reset_timer.daemon = True
            reset_timer.start()

def restart_clock():
    global current_process, reset_timer, clock_process_supervised
    with process_lock:
        if current_process is None or not clock_process_supervised:
            return
        stop_current_process()
        print("Restarting clock script")
        current_process = subprocess.Popen(commands["1"])
        clock_process_supervised = True
        reset_timer = threading.Timer(restart_seconds, restart_clock)
        reset_timer.daemon = True
        reset_timer.start()


def command_key_for_keycode(keycode):
    return SUPPORTED_KEY_COMMANDS.get(keycode)


def monitor_clock_process():
    global current_process, clock_process_supervised
    while not supervisor_stop_event.is_set():
        with process_lock:
            process = current_process
            supervised = clock_process_supervised

        if process is None or not supervised:
            supervisor_stop_event.wait(0.25)
            continue

        return_code = process.poll()
        if return_code is None:
            supervisor_stop_event.wait(0.25)
            continue

        with process_lock:
            if current_process is process:
                current_process = None
                clock_process_supervised = False

        if supervisor_stop_event.wait(CHILD_RESTART_BACKOFF_SECONDS):
            break

        with process_lock:
            if current_process is None and not supervisor_stop_event.is_set():
                current_process = subprocess.Popen(commands["1"])
                clock_process_supervised = True

def read_keypad(device):
    for event in device.read_loop():
        if event.type == ecodes.EV_KEY:
            key_event = categorize(event)
            if key_event.keystate == key_event.key_down:
                key = command_key_for_keycode(key_event.keycode)
                if key is not None:
                    execute_command(key)

def main():
    global commands, restart_seconds
    args = parse_args()
    commands = build_commands(args.clock_command)
    restart_seconds = args.restart_seconds
    device = find_keypad(args.device)

    supervisor_thread = threading.Thread(target=monitor_clock_process, daemon=True)
    supervisor_thread.start()
    execute_command("1")
    keypad_thread = threading.Thread(target=read_keypad, args=(device,), daemon=True)
    keypad_thread.start()

    try:
        keypad_thread.join()
    except KeyboardInterrupt:
        pass
    finally:
        supervisor_stop_event.set()
        with process_lock:
            stop_current_process()
        device.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
