# LED-Display
1. sudo apt update
2. sudo apt install python3-venv
3. python3 -m venv .venv
4. sudo apt install -y git build-essential cmake python3-dev python3-pip python3-venv cython3
5. sudo apt-get install python-dev-is-python3 python3-pil cython3
6. source .venv/bin/activate
7. git clone https://github.com/hzeller/rpi-rgb-led-matrix.git
8. Run pip install . from the rpi-rgb-led-matrix folder
9. Navigate to bindings/python/samples
10. Copy time.py
11. sudo ~/.venv/bin/python time.py --led-rows=64 --led-cols=64 -m adafruit-hat --led-slowdown-gpio=2
