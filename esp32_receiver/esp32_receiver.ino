#include <Arduino.h>
#include <BluetoothA2DPSink.h>
#include <AudioTools.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#include <Adafruit_NeoPixel.h>
#include <arduinoFFT.h>
#include "tests/esp32_firmware/include/esp32_receiver_logic.h"

#define LED_PIN 5
#define WIDTH 12
#define HEIGHT 6
#define NUMPIXELS (WIDTH * HEIGHT)

#define SAMPLES 256
#define SAMPLING_FREQ 16000

#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "abcd1234-5678-90ab-cdef-1234567890ab"

const char* A2DP_DEVICE_NAME = "ESP32-FFT Audio";
const char* BLE_DEVICE_NAME = "ESP32-FFT Ctrl";

constexpr uint8_t GAIN_PWM_PIN = 25;
constexpr uint8_t BASS_PWM_PIN = 26;
constexpr uint8_t TREBLE_PWM_PIN = 27;
constexpr uint8_t BT_RESET_BUTTON_PIN = 32;

constexpr uint8_t GAIN_PWM_CHANNEL = 0;
constexpr uint8_t BASS_PWM_CHANNEL = 1;
constexpr uint8_t TREBLE_PWM_CHANNEL = 2;

constexpr uint16_t PWM_FREQUENCY_HZ = 20000;
constexpr uint8_t PWM_RESOLUTION_BITS = 8;

// Temporary debug overlay to verify high-band column positions.
constexpr bool DEBUG_HIGH_COLUMN_MARKERS = false;

struct ToneControlState {
  uint8_t gain = 128;
  uint8_t bass = 128;
  uint8_t treble = 128;
};

// Subclass that prevents the library from deactivating I2S on pause/stop,
// which would cause a loud transient on the amplifier output.
class NeverStopA2DPSink : public BluetoothA2DPSink {
public:
  NeverStopA2DPSink(audio_tools::AudioStream &output) : BluetoothA2DPSink(output) {}
protected:
  void set_i2s_active(bool active) override {
    // Always keep I2S running; only allow explicit activation.
    BluetoothA2DPSink::set_i2s_active(true);
  }
};

I2SStream i2s;
NeverStopA2DPSink a2dp_sink(i2s);
Adafruit_NeoPixel pixels(NUMPIXELS, LED_PIN, NEO_GRB + NEO_KHZ800);

double vReal[SAMPLES];
double vImag[SAMPLES];
ArduinoFFT<double> FFT(vReal, vImag, SAMPLES, SAMPLING_FREQ);

volatile int sampleIndex = 0;

double ledLevels[WIDTH] = {0};
double peaks[WIDTH] = {0};

uint8_t r = 255, g = 0, b = 0;
uint8_t volume = 50;
uint8_t category = 0;
uint8_t subMode = 0;
uint8_t flags = 0;
ToneControlState toneControls;

unsigned long lastModeUpdate = 0;
const unsigned long MODE_UPDATE_INTERVAL = 50;
uint8_t animOffset = 0;
uint8_t columnOffset = 0;
uint8_t connectionPulse = 0;

bool deviceConnected = false;
bool oldDeviceConnected = false;
BLEServer* bleServer = nullptr;
unsigned long lastBlePacketMs = 0;
const unsigned long BLE_STALE_TIMEOUT_MS = 7000;
bool pendingRestartAdvertising = false;
unsigned long restartAdvertisingAtMs = 0;
volatile esp_a2d_connection_state_t btConnectionState = ESP_A2D_CONNECTION_STATE_DISCONNECTED;

volatile unsigned long lastAudioPacketMs = 0;
unsigned long lastSilenceWriteMs = 0;

volatile bool audioStreamActive = false;
volatile bool holdI2SOnPause = false;

const unsigned long SILENCE_WRITE_INTERVAL_MS = 4;
const unsigned long BUTTON_DEBOUNCE_MS = 35;
const unsigned long BUTTON_COOLDOWN_MS = 1200;

bool buttonLastReading = false;
bool buttonStableState = false;
unsigned long buttonLastChangeMs = 0;
unsigned long buttonLastActionMs = 0;

const double FFT_NOISE_FLOOR = 180.0;
const double FFT_MAX_LEVEL = 22000.0;
const double MIN_VOLUME_GAIN = 0.02;
const double MAX_VOLUME_GAIN = 0.95;

// Per-column weighting to compensate for narrow low-frequency bins and
// naturally lower bass-bin energy in this FFT resolution.
const double BAND_EQ[WIDTH] = {
  1.55, 1.38, 1.24, 1.12, 1.06, 1.02, 1.00, 1.03, 1.08, 1.14, 1.20, 1.26
};

// Lift the right-side high-frequency columns so highs show more lit LEDs.
const double HIGH_LED_BOOST[WIDTH] = {
  1.00, 1.00, 1.00, 1.00, 1.02, 1.05, 1.08, 1.20, 1.70, 1.70, 1.24, 1.18
};

int16_t silenceBuffer[256] = {0};

const int freqBins[WIDTH + 1] = {
  // WIDTH is 12, so we need 13 edges; keep them monotonic and <= SAMPLES/2.
  2, 4, 6, 9, 13, 18, 25, 34, 46, 62, 82, 106, 128
};

void renderSoundMode();
void renderBlank();
void renderConnectionAnimation();
void overlayHighColumnMarkers();
void restartBluetoothReceiver();
void handleBluetoothResetButton(unsigned long now);

void onConnectionStateChanged(esp_a2d_connection_state_t state, void* ptr) {
  (void)ptr;
  btConnectionState = state;

  if (state == ESP_A2D_CONNECTION_STATE_CONNECTED) {
    connectionPulse = 0;
  }
}

void onAudioStateChanged(esp_a2d_audio_state_t state, void* ptr) {
  (void)ptr;

  if (state == ESP_A2D_AUDIO_STATE_STARTED) {
    audioStreamActive = true;
    holdI2SOnPause = false;
    lastAudioPacketMs = millis();
  } else if (state == ESP_A2D_AUDIO_STATE_REMOTE_SUSPEND ||
             state == ESP_A2D_AUDIO_STATE_STOPPED) {
    audioStreamActive = false;
    holdI2SOnPause = true;
    for (int i = 0; i < WIDTH; i++) {
      ledLevels[i] = 0;
      peaks[i] = 0;
    }
  }
}

void configurePwmChannel(uint8_t pin, uint8_t channel) {
  (void)channel;
  ledcAttach(pin, PWM_FREQUENCY_HZ, PWM_RESOLUTION_BITS);
}

void applyToneControls() {
  ledcWrite(GAIN_PWM_PIN, toneControls.gain);
  ledcWrite(BASS_PWM_PIN, toneControls.bass);
  ledcWrite(TREBLE_PWM_PIN, toneControls.treble);
}

void restartBluetoothReceiver() {
  // Drop the current A2DP session and immediately return to discoverable mode.
  a2dp_sink.end(false);
  delay(150);

  a2dp_sink.set_default_bt_mode(ESP_BT_MODE_BTDM);
  a2dp_sink.set_auto_reconnect(false);
  a2dp_sink.set_on_connection_state_changed(onConnectionStateChanged);
  a2dp_sink.set_on_audio_state_changed(onAudioStateChanged);
  a2dp_sink.start(A2DP_DEVICE_NAME);
  a2dp_sink.set_stream_reader(audioCallback);

  btConnectionState = ESP_A2D_CONNECTION_STATE_DISCONNECTED;
  audioStreamActive = false;
  holdI2SOnPause = true;
  i2s.write((uint8_t*)silenceBuffer, sizeof(silenceBuffer));
  lastSilenceWriteMs = millis();
  connectionPulse = 0;
}

void handleBluetoothResetButton(unsigned long now) {
  // Use internal pull-up and wire button to GND (active-low press).
  bool pressed = digitalRead(BT_RESET_BUTTON_PIN) == LOW;

  if (pressed != buttonLastReading) {
    buttonLastReading = pressed;
    buttonLastChangeMs = now;
  }

  if ((now - buttonLastChangeMs) >= BUTTON_DEBOUNCE_MS &&
      pressed != buttonStableState) {
    buttonStableState = pressed;

    if (buttonStableState && (now - buttonLastActionMs) >= BUTTON_COOLDOWN_MS) {
      buttonLastActionMs = now;
      restartBluetoothReceiver();
    }
  }
}

int XY(int x, int y) {
  y = (HEIGHT - 1) - y;
  if (y % 2 == 0) return y * WIDTH + x;
  return y * WIDTH + (WIDTH - 1 - x);
}

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
    pendingRestartAdvertising = false;
    lastBlePacketMs = millis();
  }

  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    pendingRestartAdvertising = true;
    restartAdvertisingAtMs = millis() + 1500;
  }
};

class DataCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    String value = pCharacteristic->getValue();
    lastBlePacketMs = millis();

    const size_t maxPayloadSize = 10;
    uint8_t payload[maxPayloadSize] = {0};
    const size_t payloadLen = value.length() < static_cast<int>(maxPayloadSize)
        ? static_cast<size_t>(value.length())
        : maxPayloadSize;

    for (size_t i = 0; i < payloadLen; i++) {
      payload[i] = static_cast<uint8_t>(value[i]);
    }

    const ParsedBleWrite parsed = parseBleWrite(payload, payloadLen);

    if (parsed.hasColorPayload) {
      category = parsed.category;
      subMode = parsed.subMode;
      r = parsed.red;
      g = parsed.green;
      b = parsed.blue;
      volume = parsed.volume;
      flags = parsed.flags;
    }

    if (parsed.hasTonePayload) {
      toneControls.gain = parsed.gain;
      toneControls.bass = parsed.bass;
      toneControls.treble = parsed.treble;
      applyToneControls();
    }
  }
};

void audioCallback(const uint8_t* data, uint32_t len) {
  lastAudioPacketMs = millis();

  int16_t* samples = (int16_t*)data;
  int count = len / 2;

  for (int i = 0; i < count; i++) {
    if (sampleIndex < SAMPLES) {
      vReal[sampleIndex] = samples[i];
      vImag[sampleIndex] = 0;
      sampleIndex++;
    }
  }

  if (sampleIndex >= SAMPLES) {
    sampleIndex = 0;
    if (category == 0) {
      renderSoundMode();
    }
  }
}

uint32_t hsvToRgb(uint8_t h, uint8_t s, uint8_t v) {
  const uint32_t packed = hsvToRgbPacked(h, s, v);
  const uint8_t red = static_cast<uint8_t>((packed >> 16) & 0xFF);
  const uint8_t green = static_cast<uint8_t>((packed >> 8) & 0xFF);
  const uint8_t blue = static_cast<uint8_t>(packed & 0xFF);
  return pixels.Color(red, green, blue);
}

void processFFTData() {
  FFT.windowing(FFT_WIN_TYP_HAMMING, FFT_FORWARD);
  FFT.compute(FFT_FORWARD);
  FFT.complexToMagnitude();

  double volumeNorm = constrain(volume / 100.0, 0.0, 1.0);
  double volumeGain = MIN_VOLUME_GAIN + pow(volumeNorm, 2.2) * (MAX_VOLUME_GAIN - MIN_VOLUME_GAIN);
  double logFloor = log10(1.0 + FFT_NOISE_FLOOR);
  double logCeil = log10(1.0 + FFT_MAX_LEVEL);
  double logRange = max(0.001, logCeil - logFloor);

  for (int x = 0; x < WIDTH; x++) {
    int startBin = freqBins[x];
    int endBin = freqBins[x + 1];
    int bandWidth = endBin - startBin;
    double sum = 0;
    double peak = 0;
    for (int j = startBin; j < endBin; j++) {
      sum += vReal[j];
      if (vReal[j] > peak) {
        peak = vReal[j];
      }
    }

    double value = (sum / max(1, bandWidth)) * 0.72 + (peak / sqrt(static_cast<double>(max(1, bandWidth)))) * 0.28;
    value *= BAND_EQ[x];
    value *= volumeGain;

    if (x == WIDTH - 1 && value < 25) value = 0;

    // Map in log space so low-level bands remain visible without clipping highs.
    double mapped = (log10(1.0 + value) - logFloor) / logRange;
    mapped = constrain(mapped, 0.0, 1.0);
    double target = mapped * HEIGHT;
    target *= HIGH_LED_BOOST[x];
    target = min((double)HEIGHT, target);

    if (x >= 4 && x <= 10 && value > FFT_NOISE_FLOOR * 0.12 && target < 0.50) {
      target = 0.50;
    }

    // Keep 8th..11th columns (1-based) visible at moderate listening volume.
    if (x >= 7 && x <= 10 && value > FFT_NOISE_FLOOR * 0.16 && target < 0.60) {
      target = 0.60;
    }

    // Give the first few low-frequency columns a small visibility floor.
    if (x <= 3 && value > FFT_NOISE_FLOOR * 0.65 && target < 0.35) {
      target = 0.35;
    }

    if (target > ledLevels[x]) {
      ledLevels[x] = target;
    } else {
      ledLevels[x] -= 0.15;
      if (ledLevels[x] < 0) ledLevels[x] = 0;
    }

    if (ledLevels[x] > peaks[x]) {
      peaks[x] = ledLevels[x];
    } else {
      peaks[x] -= 0.05;
      if (peaks[x] < 0) peaks[x] = 0;
    }
  }
}

void renderRainbowFFT() {
  processFFTData();
  bool showPeak = (flags & 0x01) != 0;

  for (int x = 0; x < WIDTH; x++) {
    uint8_t h = (x * 256 / WIDTH + animOffset) % 256;
    uint32_t color = hsvToRgb(h, 255, 255);

    for (int y = 0; y < HEIGHT; y++) {
      int led = XY(x, y);
      int levelY = HEIGHT - 1 - y;

      if (levelY < ledLevels[x]) {
        pixels.setPixelColor(led, color);
      } else {
        pixels.setPixelColor(led, 0);
      }

      if (showPeak && (int)peaks[x] == levelY) {
        pixels.setPixelColor(led, pixels.Color(255, 255, 255));
      }
    }
  }

  if (DEBUG_HIGH_COLUMN_MARKERS) {
    overlayHighColumnMarkers();
  }
  pixels.show();
}

void renderGradientFFT() {
  processFFTData();
  bool showPeak = (flags & 0x01) != 0;

  for (int x = 0; x < WIDTH; x++) {
    uint8_t h = (x * 255 / WIDTH);
    uint32_t color = hsvToRgb(h, 200, 255);

    for (int y = 0; y < HEIGHT; y++) {
      int led = XY(x, y);
      int levelY = HEIGHT - 1 - y;

      if (levelY < ledLevels[x]) {
        pixels.setPixelColor(led, color);
      } else {
        pixels.setPixelColor(led, 0);
      }

      if (showPeak && (int)peaks[x] == levelY) {
        pixels.setPixelColor(led, pixels.Color(255, 255, 255));
      }
    }
  }

  if (DEBUG_HIGH_COLUMN_MARKERS) {
    overlayHighColumnMarkers();
  }
  pixels.show();
}

void renderSolidFFT() {
  processFFTData();
  bool showPeak = (flags & 0x01) != 0;
  uint32_t color = pixels.Color(r, g, b);

  for (int x = 0; x < WIDTH; x++) {
    for (int y = 0; y < HEIGHT; y++) {
      int led = XY(x, y);
      int levelY = HEIGHT - 1 - y;

      if (levelY < ledLevels[x]) {
        pixels.setPixelColor(led, color);
      } else {
        pixels.setPixelColor(led, 0);
      }

      if (showPeak && (int)peaks[x] == levelY) {
        pixels.setPixelColor(led, pixels.Color(255, 255, 255));
      }
    }
  }

  if (DEBUG_HIGH_COLUMN_MARKERS) {
    overlayHighColumnMarkers();
  }
  pixels.show();
}

void overlayHighColumnMarkers() {
  // Mark 8th..11th columns (1-based), i.e. indices 7..10.
  for (int x = 7; x <= 10; x++) {
    int topLed = XY(x, 0);
    pixels.setPixelColor(topLed, pixels.Color(255, 255, 255));
  }
}

void renderSoundMode() {
  switch (subMode) {
    case 0:
      renderRainbowFFT();
      break;
    case 1:
      renderGradientFFT();
      break;
    case 2:
      renderSolidFFT();
      break;
  }
}

void renderBlank() {
  for (int i = 0; i < NUMPIXELS; i++) {
    pixels.setPixelColor(i, 0);
  }
  pixels.show();
}

void renderConnectionAnimation() {
  const int travel = max(1, WIDTH - 1);
  const int period = travel * 2;
  const int phase = (connectionPulse / 2) % period;

  int displaySweepX = phase;
  bool movingRight = true;
  if (phase >= travel) {
    displaySweepX = period - phase;
    movingRight = false;
  }

  int tailX = movingRight ? (displaySweepX - 1) : (displaySweepX + 1);
  uint32_t mainBlue = pixels.Color(20, 20, 255);
  uint32_t tailBlue = pixels.Color(0, 0, 70);

  for (int x = 0; x < WIDTH; x++) {
    for (int y = 0; y < HEIGHT; y++) {
      uint32_t color = 0;
      if (x == displaySweepX) {
        color = mainBlue;
      } else if (x == tailX && tailX >= 0 && tailX < WIDTH) {
        color = tailBlue;
      }
      pixels.setPixelColor(XY(x, y), color);
    }
  }

  pixels.show();
  connectionPulse++;
}

void renderStaticSolidColor() {
  uint32_t color = pixels.Color(r, g, b);
  for (int i = 0; i < NUMPIXELS; i++) {
    pixels.setPixelColor(i, color);
  }
  pixels.show();
}

void renderStaticGradient() {
  for (int i = 0; i < WIDTH; i++) {
    uint8_t h = (i * 255 / WIDTH);
    uint32_t color = hsvToRgb(h, 200, 255);

    for (int j = 0; j < HEIGHT; j++) {
      int led = XY(i, j);
      pixels.setPixelColor(led, color);
    }
  }
  pixels.show();
}

void renderColumnRainbow() {
  for (int x = 0; x < WIDTH; x++) {
    uint8_t h = ((x + columnOffset) * 256 / WIDTH) % 256;
    uint32_t color = hsvToRgb(h, 255, (volume / 100.0) * 255);

    for (int y = 0; y < HEIGHT; y++) {
      int led = XY(x, y);
      pixels.setPixelColor(led, color);
    }
  }
  pixels.show();
  columnOffset++;
}

void renderStaticMode() {
  unsigned long now = millis();
  if (now - lastModeUpdate < MODE_UPDATE_INTERVAL) return;
  lastModeUpdate = now;

  switch (subMode) {
    case 0:
      renderStaticSolidColor();
      break;
    case 1:
      renderStaticGradient();
      break;
    case 2:
      renderColumnRainbow();
      break;
  }
}

void setup() {
  Serial.begin(115200);

  pixels.begin();
  pixels.setBrightness(80);
  pixels.show();

  pinMode(BT_RESET_BUTTON_PIN, INPUT_PULLUP);

  configurePwmChannel(GAIN_PWM_PIN, GAIN_PWM_CHANNEL);
  configurePwmChannel(BASS_PWM_PIN, BASS_PWM_CHANNEL);
  configurePwmChannel(TREBLE_PWM_PIN, TREBLE_PWM_CHANNEL);
  applyToneControls();

  auto cfg = i2s.defaultConfig();
  cfg.pin_bck = 18;
  cfg.pin_ws = 15;
  cfg.pin_data = 22;
  cfg.pin_mck = 1;
  i2s.begin(cfg);

  a2dp_sink.set_default_bt_mode(ESP_BT_MODE_BTDM);
  a2dp_sink.set_on_connection_state_changed(onConnectionStateChanged);
  a2dp_sink.set_on_audio_state_changed(onAudioStateChanged);
  a2dp_sink.start(A2DP_DEVICE_NAME);
  a2dp_sink.set_stream_reader(audioCallback);

  BLEDevice::init(BLE_DEVICE_NAME);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new MyServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);

  BLECharacteristic* characteristic = service->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );

  characteristic->setCallbacks(new DataCallback());
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  BLEDevice::startAdvertising();

  lastBlePacketMs = millis();
  lastAudioPacketMs = millis();
}

void loop() {
  unsigned long now = millis();

  handleBluetoothResetButton(now);

  if (!deviceConnected && oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  if (pendingRestartAdvertising && millis() >= restartAdvertisingAtMs) {
    BLEDevice::startAdvertising();
    pendingRestartAdvertising = false;
  }

  if (deviceConnected && (millis() - lastBlePacketMs > BLE_STALE_TIMEOUT_MS)) {
    deviceConnected = false;
    pendingRestartAdvertising = true;
    restartAdvertisingAtMs = millis() + 1500;
    lastBlePacketMs = millis();
  }

  // Keep writing digital silence while paused so data lines don't float.
  if (holdI2SOnPause && !audioStreamActive &&
      (now - lastSilenceWriteMs) >= SILENCE_WRITE_INTERVAL_MS) {
    i2s.write((uint8_t*)silenceBuffer, sizeof(silenceBuffer));
    lastSilenceWriteMs = now;
  }

  if (btConnectionState != ESP_A2D_CONNECTION_STATE_CONNECTED) {
    renderConnectionAnimation();
    delay(20);
    return;
  }

  if (!audioStreamActive) {
    renderBlank();
    delay(20);
    return;
  }

  if (category == 1) {
    renderStaticMode();
  }

  delay(10);
}