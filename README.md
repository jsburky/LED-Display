# LED Display
## Parts Needed:
- [Adafruit 64x64 display](https://www.adafruit.com/product/5362)
- [Raspberry Pi Bonnet](https://www.adafruit.com/product/3211)
- 5V 4A Power Supply for 64x64 or 5V 15A for 128x128
- Raspberry Pi (zero - 4) Would recommend a 4 for better peformance 
- A computer with ssh capability. This can be done by connecting a monitor to the Pi but, it is easier with ssh because you can copy over code from this repository
## Setting Up Raspberry Pi
- For help with the next steps look [here](https://learn.adafruit.com/adafruit-rgb-matrix-plus-real-time-clock-hat-for-raspberry-pi/driving-matrices)
- First, on the Raspberry Pi Bonnet solder the E pad to the 8 pad it should look like this:

  
![Raspberry Pi Bonnet E Pad to 8 Pad Short](/assets/E8_Short.jpg)


- Next, solder a jumper wire between GPIO 4 and GPIO 18. This will reduce the flicker. It should look like this:

  
![Raspberry Pi Bonnet GPIO 4 to GPIO 18 Short](/assets/GPIO_Short.jpg)


- Next, you want to plug in the power cable and ribbon cable (make sure its the "in" connection" to the led screen like this:


![Matrix Panel Wiring](/assets/Panel_Wires.jpg)


- Then, cut off the other end of the power cable and attach to bonnet like this:

  
![Raspberry Pi Bonnet 5V Out](/assets/5V_Out.jpg)


- Connect ribbon cable to bonnet.
- Use the [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash Raspberry Pi OS Lite (64/32 bit depending on which Pi is being used) to an SD Card. I would recommend going through the settings to set up a hostname, wifi, username and password, and enable ssh
- Insert SD Card in Pi
- Plug in the bonnet using the power supply. You can power the raspberry pi seperate or through the bonnet depending on current supply.
- Once turned on, if set up properly, you can ssh from another computer using hostname@LOCAL_IP then entering the password. Or, you can attach a monitor and keyboard to setup
  - LOCAL_IP usally takes the form of 192.168.1.### and can be found on your routers desktop settings as a connected device



## Cloning the Repo
From the home directory of your Raspberry Pi

Run these commands:

sudo apt update && sudo apt install -y git

git clone https://github.com/jsburky/LED-Display.git

cd LED-Display

Create a .env file copying the format from SAMPLE_ENV.txt

Copy in API Keys from massive.com and openweather.com

Run sudo ./install.sh

After reboot, the display should be working.
