#include "AudioTools.h"
#include "BluetoothA2DPSink.h"

// Create an I2S stream
I2SStream i2s;

// Create the A2DP sink using the I2S output
BluetoothA2DPSink a2dp_sink(i2s);

void setup() {
    Serial.begin(115200);
    delay(1000);

    // Configure I2S pins for your DAC
    auto cfg = i2s.defaultConfig();
    cfg.pin_bck = 14;    // BCLK → DAC
    cfg.pin_ws  = 15;    // LRCK / WS → DAC
    cfg.pin_data = 22;   // DATA → DAC
    cfg.pin_mck = 0;    // Optional, connect if your DAC needs MCLK
    i2s.begin(cfg);

    // Start Bluetooth A2DP sink
    a2dp_sink.start("WindboundSpeaker");

    Serial.println("Bluetooth A2DP sink started. Connect your phone!");
}

void loop() {
    // Nothing needed here; audio is handled by I2S stream
}