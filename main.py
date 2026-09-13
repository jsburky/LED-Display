from evdev import InputDevice, categorize, ecodes
import subprocess
import threading
import time

# Find the event for your USB keypad (use ls /dev/input/ to list input devices)
# Replace '/dev/input/eventX' with the appropriate event number for your keypad
dev = InputDevice('/dev/input/event0')

# Define the commands corresponding to each key
command_mapping = {
    '0': '/home/ledpi/shutdown_services.sh',
    # '1': "sudo /home/ledpi/myenv/bin/python3 /home/ledpi/rpi-rgb-led-matrix/bindings/python/samples/album.py -m adafruit-hat",
    '2': "sudo /home/tradingpi/.venv/bin/python /home/tradingpi/LED-Display/time.py --led-rows=64 --led-cols=64 -m adafruit-hat --led-slowdown-gpio=2",
    '9': 'sudo reboot',
}

# Global variable to store the current subprocess
current_process = None
reset_timer = None

# Define a function to execute commands
def execute_command(key):
    global current_process, reset_timer
    command = command_mapping.get(key)
    
    if key == '2':
        # If key '2' is pressed, start the clock script and the restart timer
        if current_process is not None:
            current_process.terminate()
            print("Cancelled current command")
            current_process = None

        if command is not None:
            current_process = subprocess.Popen(command.split())

            if reset_timer is not None:
                reset_timer.cancel()

            reset_timer = threading.Timer(3600, restart_clock)
            reset_timer.start()

    else:
        # For other keys, just execute the corresponding command
        if current_process is not None:
            current_process.terminate()
            print("Cancelled current command")
            current_process = None

        if command is not None:
            current_process = subprocess.Popen(command.split())

# Define a function to restart the clock script
def restart_clock():
    global current_process, reset_timer
    if current_process is not None:
        current_process.terminate()
        print("Restarting clock script")
        current_process = subprocess.Popen(command_mapping['2'].split())
        reset_timer = threading.Timer(3600, restart_clock)
        reset_timer.start()

# Define a function to read input from the keypad
def read_keypad():
    for event in dev.read_loop():
        if event.type == ecodes.EV_KEY:
            key_event = categorize(event)
            if key_event.keystate == key_event.key_down:
                key = str(key_event.keycode[-1])
                execute_command(key)

# Automatically execute the command for key "2" on startup
execute_command('2')

# Start reading input from the keypad on a separate thread
keypad_thread = threading.Thread(target=read_keypad)
keypad_thread.daemon = True
keypad_thread.start()

# Keep the main thread alive
keypad_thread.join()