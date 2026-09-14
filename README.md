# LED-Display

From the home directory of your Raspberry Pi

Run these commands:
sudo apt update && sudo apt install -y git
git clone https://github.com/jsburky/LED-Display.git
cd LED-Display
Create a .env file copying the format from SAMPLE_ENV.txt
Copy in API Keys from massive.com and openweather.com
Run sudo ./install.sh




1. sudo apt update
2. sudo apt install python3-venv
3. sudo apt install -y git build-essential cmake python3-dev python3-pip cython3
4. sudo apt-get install python-dev-is-python3 python3-pil
5. sudo apt install python3-evdev
6. python3 -m venv .venv
7. source .venv/bin/activate
8. git clone https://github.com/jsburky/LED-Display.git
9. cd LED-Display
10. pip install -r requirements.txt
11. sudo ./install.sh

From here, the main display should be visible once the reboot finishes.
