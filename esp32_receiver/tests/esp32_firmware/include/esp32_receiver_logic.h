#ifndef ESP32_RECEIVER_LOGIC_H
#define ESP32_RECEIVER_LOGIC_H

#include <stddef.h>
#include <stdint.h>

struct ParsedBleWrite {
  bool hasColorPayload;
  bool hasTonePayload;
  uint8_t category;
  uint8_t subMode;
  uint8_t red;
  uint8_t green;
  uint8_t blue;
  uint8_t volume;
  uint8_t flags;
  uint8_t gain;
  uint8_t bass;
  uint8_t treble;
};

inline ParsedBleWrite parseBleWrite(const uint8_t* data, size_t len) {
  ParsedBleWrite result = {false, false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

  if (data == nullptr || len == 0) {
    return result;
  }

  if (len >= 10) {
    result.hasColorPayload = true;
    result.hasTonePayload = true;

    result.category = data[0];
    result.subMode = data[1];
    result.red = data[2];
    result.green = data[3];
    result.blue = data[4];
    result.volume = data[5];
    result.flags = data[6];
    result.gain = data[7];
    result.bass = data[8];
    result.treble = data[9];
    return result;
  }

  if (len >= 7) {
    result.hasColorPayload = true;

    result.category = data[0];
    result.subMode = data[1];
    result.red = data[2];
    result.green = data[3];
    result.blue = data[4];
    result.volume = data[5];
    result.flags = data[6];
    return result;
  }

  if (len >= 3) {
    result.hasTonePayload = true;

    result.gain = data[0];
    result.bass = data[1];
    result.treble = data[2];
  }

  return result;
}

inline uint32_t packRgb(uint8_t r, uint8_t g, uint8_t b) {
  return (static_cast<uint32_t>(r) << 16) |
         (static_cast<uint32_t>(g) << 8) |
         static_cast<uint32_t>(b);
}

inline uint32_t hsvToRgbPacked(uint8_t h, uint8_t s, uint8_t v) {
  float hf = static_cast<float>(h) / 255.0f * 6.0f;
  float sf = static_cast<float>(s) / 255.0f;
  float vf = static_cast<float>(v) / 255.0f;

  int i = static_cast<int>(hf);
  float f = hf - static_cast<float>(i);

  float p = vf * (1.0f - sf);
  float q = vf * (1.0f - sf * f);
  float t = vf * (1.0f - sf * (1.0f - f));

  float rf = 0.0f;
  float gf = 0.0f;
  float bf = 0.0f;

  switch (i % 6) {
    case 0: rf = vf; gf = t; bf = p; break;
    case 1: rf = q; gf = vf; bf = p; break;
    case 2: rf = p; gf = vf; bf = t; break;
    case 3: rf = p; gf = q; bf = vf; break;
    case 4: rf = t; gf = p; bf = vf; break;
    case 5: rf = vf; gf = p; bf = q; break;
    default: rf = 0.0f; gf = 0.0f; bf = 0.0f; break;
  }

  const uint8_t r = static_cast<uint8_t>(rf * 255.0f);
  const uint8_t g = static_cast<uint8_t>(gf * 255.0f);
  const uint8_t b = static_cast<uint8_t>(bf * 255.0f);
  return packRgb(r, g, b);
}

#endif
