#include <Arduino.h>
#include <BluetoothA2DPSink.h>
#include <AudioTools.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#include <Adafruit_NeoPixel.h>
#include <arduinoFFT.h>

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

constexpr uint8_t GAIN_PWM_CHANNEL = 0;
constexpr uint8_t BASS_PWM_CHANNEL = 1;
constexpr uint8_t TREBLE_PWM_CHANNEL = 2;

constexpr uint16_t PWM_FREQUENCY_HZ = 20000;
constexpr uint8_t PWM_RESOLUTION_BITS = 8;

// Temporary debug overlay to verify high-band column positions.
constexpr bool DEBUG_HIGH_COLUMN_MARKERS = true;

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

bool deviceConnected = false;
bool oldDeviceConnected = false;
BLEServer* bleServer = nullptr;
unsigned long lastBlePacketMs = 0;
const unsigned long BLE_STALE_TIMEOUT_MS = 7000;
bool pendingRestartAdvertising = false;
unsigned long restartAdvertisingAtMs = 0;

volatile unsigned long lastAudioPacketMs = 0;
unsigned long lastSilenceWriteMs = 0;

volatile bool audioStreamActive = false;
volatile bool holdI2SOnPause = false;

const unsigned long SILENCE_WRITE_INTERVAL_MS = 4;

const double FFT_NOISE_FLOOR = 180.0;
const double FFT_MAX_LEVEL = 22000.0;
const double MIN_VOLUME_GAIN = 0.02;
const double MAX_VOLUME_GAIN = 0.95;

// Per-column weighting to compensate for narrow low-frequency bins and
// naturally lower bass-bin energy in this FFT resolution.
const double BAND_EQ[WIDTH] = {
  2.8, 2.4, 2.1, 1.8, 1.55, 1.35, 1.18, 1.05, 0.98, 0.92, 0.88, 0.84
};

// Lift the right-side high-frequency columns so highs show more lit LEDs.
const double HIGH_LED_BOOST[WIDTH] = {
  1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.12, 1.55, 1.85, 2.10, 2.35, 1.85
};

int16_t silenceBuffer[256] = {0};

const int freqBins[WIDTH + 1] = {
  // WIDTH is 12, so we need 13 edges; keep them monotonic and <= SAMPLES/2.
  2, 3, 4, 6, 8, 12, 18, 26, 38, 54, 74, 100, 128
};

void renderSoundMode();
void overlayHighColumnMarkers();

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

int XY(int x, int y) {
  x = (WIDTH - 1) - x;
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

    if (value.length() >= 10) {
      category = static_cast<uint8_t>(value[0]);
      subMode = static_cast<uint8_t>(value[1]);
      r = static_cast<uint8_t>(value[2]);
      g = static_cast<uint8_t>(value[3]);
      b = static_cast<uint8_t>(value[4]);
      volume = static_cast<uint8_t>(value[5]);
      flags = static_cast<uint8_t>(value[6]);
      toneControls.gain = static_cast<uint8_t>(value[7]);
      toneControls.bass = static_cast<uint8_t>(value[8]);
      toneControls.treble = static_cast<uint8_t>(value[9]);
      applyToneControls();
    } else if (value.length() >= 7) {
      category = static_cast<uint8_t>(value[0]);
      subMode = static_cast<uint8_t>(value[1]);
      r = static_cast<uint8_t>(value[2]);
      g = static_cast<uint8_t>(value[3]);
      b = static_cast<uint8_t>(value[4]);
      volume = static_cast<uint8_t>(value[5]);
      flags = static_cast<uint8_t>(value[6]);
    } else if (value.length() >= 3) {
      toneControls.gain = static_cast<uint8_t>(value[0]);
      toneControls.bass = static_cast<uint8_t>(value[1]);
      toneControls.treble = static_cast<uint8_t>(value[2]);
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
  float hf = h / 255.0 * 6.0;
  float sf = s / 255.0;
  float vf = v / 255.0;

  int i = (int)hf;
  float f = hf - i;

  float p = vf * (1.0 - sf);
  float q = vf * (1.0 - sf * f);
  float t = vf * (1.0 - sf * (1.0 - f));

  float rf;
  float gf;
  float bf;
  switch (i % 6) {
    case 0: rf = vf; gf = t; bf = p; break;
    case 1: rf = q; gf = vf; bf = p; break;
    case 2: rf = p; gf = vf; bf = t; break;
    case 3: rf = p; gf = q; bf = vf; break;
    case 4: rf = t; gf = p; bf = vf; break;
    case 5: rf = vf; gf = p; bf = q; break;
    default: rf = gf = bf = 0; break;
  }

  return pixels.Color((uint8_t)(rf * 255), (uint8_t)(gf * 255), (uint8_t)(bf * 255));
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
    double value = 0;
    for (int j = startBin; j < endBin; j++) {
      value += vReal[j];
    }
    value /= max(1, bandWidth);
    value *= BAND_EQ[x];
    value *= volumeGain;

    if (x == WIDTH - 1 && value < 25) value = 0;

    // Map in log space so low-level bands remain visible without clipping highs.
    double mapped = (log10(1.0 + value) - logFloor) / logRange;
    mapped = constrain(mapped, 0.0, 1.0);
    double target = mapped * HEIGHT;
    target *= HIGH_LED_BOOST[x];
    target = min((double)HEIGHT, target);

    // Keep 8th..11th columns (1-based) visible at moderate listening volume.
    if (x >= 7 && x <= 10 && value > FFT_NOISE_FLOOR * 0.25 && target < 0.60) {
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
      int led = XY(x, HEIGHT - 1 - y);

      if (y < ledLevels[x]) {
        pixels.setPixelColor(led, color);
      } else {
        pixels.setPixelColor(led, 0);
      }

      if (showPeak && (int)peaks[x] == y) {
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
      int led = XY(x, HEIGHT - 1 - y);

      if (y < ledLevels[x]) {
        pixels.setPixelColor(led, color);
      } else {
        pixels.setPixelColor(led, 0);
      }

      if (showPeak && (int)peaks[x] == y) {
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
      int led = XY(x, HEIGHT - 1 - y);

      if (y < ledLevels[x]) {
        pixels.setPixelColor(led, color);
      } else {
        pixels.setPixelColor(led, 0);
      }

      if (showPeak && (int)peaks[x] == y) {
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

  if (category == 1) {
    renderStaticMode();
  }

  delay(10);
}
