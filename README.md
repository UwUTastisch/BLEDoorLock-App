# ble_doorlock_opener

This app is for opening a door that uses an Arduino mini ESP32 and a relay. \
Through BLE characteristics the credentials are send and the door opens after the Arduino checked the vadility. \
In the near future the values of the characteristics will be encrypted with AES and the AES key is given out before every
whole action with RSA.

Actions: 
 - open the door
 - add another user

The Arduino mini ESP32 project can be found here https://github.com/Bastindo/BLEDoorLock/


## Install flutter 
git clone https://github.com/flutter/flutter.git -b stable \
sudo mv flutter /usr/lib/ \

## Compile for Android (from Arch host)
JVM runtime version of 17 is needed
Guide for jks key and key.properties tbd
1. Install flutter & https://aur.archlinux.org/packages/android-sdk \
2. Run sdkmanager --install "build-tools;34.0.0" \
3. Go to the root directory of this project. \
4. Run ```flutter build apk``` as production and ```flutter build apk --flavor dev``` for testing, so you don't override your stable builds if installed \
5. APK can be found in ./build/android/?/release/bundle \
## Compile for iOS 
tbd

## Encryption
 - RSA1024 PKCS#1v2.1 OAEP SHA-256
 - AES-GCM128
AES-GCM verwendet 3 Komponenten: Schlüssel, IV und Tag \\

Schlüssel (16 Bytes) bekommt man durch den Austausch mit RSA.\ 
IV (12 Bytes) legen wir vorher statisch fest und muss für alle gleich sein (wird dann eine zufällige Bytefolge sein) \
Tag (16 Bytes) werden beim verschlüsseln zusätzlich zur encrypted Message rausgegeben und die hängt man einfach hinten ran. \

Also jede BLE Characteristic wird 32 Byte Platz haben. Die ersten 16 Byte sollen das verschlüsselte Wort sein und nach dem 16. Byte beginnt der Tag mit weiteren 16 Bytes \\

entire characteristic: 32 Byte \
encrypted part: 16 Byte \
Tag: 16 Byte \


## Using Flutter on Arch Linux
Do yourself a favor and install paru. \
Then run "paru flutter" to get all the necessary dependencies and flutter itself. \
If that runs you into problems install the [manually](https://docs.flutter.dev/install/manual), since some of us run into problems using aur packages.  
Android Studio is also needed:\
"paru android-studio" \\
Build for linux (checking dependencies etc) \
"flutter build linux" \\
Build for Android \
Need to set ANDROID_HOME \
"flutter build apk" \
"flutter build apk --flavor dev" \ is recomended

# Using VSCode
Install the flutter extension

## Others
Take a look at https://docs.flutter.dev/get-started/install/

