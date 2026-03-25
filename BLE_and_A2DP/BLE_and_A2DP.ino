#include "AudioTools.h"
#include "BluetoothA2DPSink.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <Arduino.h>  // <-- pour analogWrite

// ================= CONFIG =================
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_COLOR_UUID  "abcd1234-5678-90ab-cdef-1234567890ab"

// I2S pins
#define I2S_BCK 14
#define I2S_LRCK 15
#define I2S_DATA 22
#define I2S_MCK 0

// LED RGB pins (doivent supporter PWM)
#define LED_R 25
#define LED_G 26
#define LED_B 27

// ================= AUDIO =================
I2SStream i2s;
BluetoothA2DPSink a2dp_sink(i2s);

// ================= BLE =================
BLECharacteristic *colorCharacteristic;

// ================= CALLBACK =================
class ColorCallback : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) override {
        String value = pCharacteristic->getValue();
        if (value.length() >= 3) { // R,G,B
            uint8_t r = value.charAt(0);
            uint8_t g = value.charAt(1);
            uint8_t b = value.charAt(2);

            analogWrite(LED_R, r);
            analogWrite(LED_G, g);
            analogWrite(LED_B, b);

            Serial.printf("LED RGB set to R:%d G:%d B:%d\n", r,g,b);
        }
    }
};

// ================= SETUP =================
void setup() {
    Serial.begin(115200);
    delay(1000);

    // ===== I2S config =====
    auto cfg = i2s.defaultConfig();
    cfg.pin_bck = I2S_BCK;
    cfg.pin_ws  = I2S_LRCK;
    cfg.pin_data = I2S_DATA;
    cfg.pin_mck = I2S_MCK;
    i2s.begin(cfg);

    // ===== A2DP =====
    a2dp_sink.set_default_bt_mode(ESP_BT_MODE_BTDM);
    a2dp_sink.start("WindboundSpeaker");
    Serial.println("A2DP Started!");

    // ===== LED PWM =====
    pinMode(LED_R, OUTPUT);
    pinMode(LED_G, OUTPUT);
    pinMode(LED_B, OUTPUT);
    analogWrite(LED_R, 0);
    analogWrite(LED_G, 0);
    analogWrite(LED_B, 0);

    // ===== BLE =====
    BLEDevice::init("WindboundSpeaker");
    BLEServer *pServer = BLEDevice::createServer();
    BLEService *pService = pServer->createService(SERVICE_UUID);

    // Color characteristic
    colorCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_COLOR_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    colorCharacteristic->setCallbacks(new ColorCallback());

    pService->start();

    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    BLEDevice::startAdvertising();
    Serial.println("BLE advertising started!");
}

// ================= LOOP =================
void loop() {
    delay(1000);
}