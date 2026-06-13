# tfe-partybox

English and French quick-start for:
- flashing the correct ESP32 firmware
- building/getting the Android APK

## English

### Project Structure

- ESP32 firmware (main): `esp32_receiver/`
- Flutter app: `esp32_controller/`
- Share-ready APK folder: `esp32_controller/releases/`

### Flash The Correct ESP32 Code

Use the `esp32_receiver/` folder for the full PartyBox receiver/controller behavior.

1. Install Arduino IDE 2.x.
2. Install ESP32 board support:
	- Arduino IDE -> Preferences -> Additional Boards Manager URLs:
	  `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
	- Boards Manager: install `esp32` by Espressif.
3. Open the `esp32_receiver/` folder in Arduino IDE (File -> Open -> select the folder).
4. Select your board/port (typically `ESP32 Dev Module`).
5. Install required libraries (Library Manager):
	- `ESP32-A2DP`
	- `AudioTools`
	- `Adafruit NeoPixel`
	- `arduinoFFT`
	- BLE headers are provided by ESP32 core (`BLEDevice.h`, `BLEServer.h`, `BLEUtils.h`).
6. Verify/upload.

Firmware values expected by the app:
- BLE device name: `ESP32-FFT Ctrl`
- A2DP device name: `ESP32-FFT Audio`
- BLE service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- BLE characteristic UUID: `abcd1234-5678-90ab-cdef-1234567890ab`

Pin highlights in current firmware:
- LED strip data: GPIO 5
- I2S: BCK=18, WS=15, DATA=22
- Tone PWM: GAIN=25, BASS=26, TREBLE=27

### Get The APK

You have 2 options:

1. Use already prepared release APK:
	- `esp32_controller/releases/esp32-controller-vx.x.x.apk`
2. Build a new APK:
	- From `esp32_controller/` run:
	  - `flutter test`
	  - `flutter build apk --release`
	- Output:
	  - `esp32_controller/build/app/outputs/flutter-apk/app-release.apk`

Recommended release workflow:
1. Copy APK from build output to `esp32_controller/releases/`.
2. Rename with version, for example `esp32-controller-v1.0.1.apk`.
3. Upload to GitHub Releases/Drive/Dropbox and share the link.

### Install APK (Android)

1. Download APK on the phone.
2. Open it from Downloads/file manager.
3. If blocked, allow `Install unknown apps` for that app.
4. Install.
5. Optional: disable `Install unknown apps` after installation.

For a standalone install handout, see:
- `esp32_controller/releases/INSTALL.md`

---

## Francais

### Structure Du Projet

- Firmware ESP32 (principal): `esp32_receiver/`
- Application Flutter: `esp32_controller/`
- Dossier APK pret a partager: `esp32_controller/releases/`

### Flasher Le Bon Code ESP32

Utilisez le dossier `esp32_receiver/` pour le comportement complet du recepteur/controller PartyBox.

1. Installez Arduino IDE 2.x.
2. Installez le support de carte ESP32:
	- Arduino IDE -> Preferences -> Additional Boards Manager URLs:
	  `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
	- Boards Manager: installez `esp32` par Espressif.
3. Ouvrez le dossier `esp32_receiver/` dans Arduino IDE (Fichier -> Ouvrir -> selectionnez le dossier).
4. Selectionnez la carte et le port (souvent `ESP32 Dev Module`).
5. Installez les bibliotheques requises (Library Manager):
	- `ESP32-A2DP`
	- `AudioTools`
	- `Adafruit NeoPixel`
	- `arduinoFFT`
	- Les en-tetes BLE sont fournis par le core ESP32 (`BLEDevice.h`, `BLEServer.h`, `BLEUtils.h`).
6. Verifiez puis envoyez le firmware.

Valeurs firmware attendues par l'app:
- Nom BLE: `ESP32-FFT Ctrl`
- Nom A2DP: `ESP32-FFT Audio`
- UUID service BLE: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- UUID caracteristique BLE: `abcd1234-5678-90ab-cdef-1234567890ab`

Pins importants dans le firmware actuel:
- Data ruban LED: GPIO 5
- I2S: BCK=18, WS=15, DATA=22
- PWM tonalite: GAIN=25, BASS=26, TREBLE=27

### Recuperer L'APK

Vous avez 2 options:

1. Utiliser l'APK de release deja prepare:
	- `esp32_controller/releases/esp32-controller-vx.x.x.apk`
2. Construire un nouvel APK:
	- Depuis `esp32_controller/`, executez:
	  - `flutter test`
	  - `flutter build apk --release`
	- Fichier genere:
	  - `esp32_controller/build/app/outputs/flutter-apk/app-release.apk`

Workflow release recommande:
1. Copier l'APK genere vers `esp32_controller/releases/`.
2. Renommer avec une version, par exemple `esp32-controller-v1.0.1.apk`.
3. Envoyer sur GitHub Releases/Drive/Dropbox puis partager le lien.

### Installer L'APK (Android)

1. Telechargez l'APK sur le telephone.
2. Ouvrez-le depuis Downloads/gestionnaire de fichiers.
3. Si Android bloque, autorisez `Install unknown apps` pour cette application.
4. Installez.
5. Optionnel: desactivez `Install unknown apps` apres installation.

Pour un guide d'installation separe, voir:
- `esp32_controller/releases/INSTALL.md`