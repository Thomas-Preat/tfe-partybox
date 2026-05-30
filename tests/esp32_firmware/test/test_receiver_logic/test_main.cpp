#include <unity.h>
#include <stdint.h>

#include "esp32_receiver_logic.h"

void setUp(void) {}
void tearDown(void) {}

void test_parse_ble_write_full_payload(void) {
  const uint8_t data[] = {1, 2, 10, 20, 30, 40, 1, 100, 110, 120};
  const ParsedBleWrite parsed = parseBleWrite(data, sizeof(data));

  TEST_ASSERT_TRUE(parsed.hasColorPayload);
  TEST_ASSERT_TRUE(parsed.hasTonePayload);

  TEST_ASSERT_EQUAL_UINT8(1, parsed.category);
  TEST_ASSERT_EQUAL_UINT8(2, parsed.subMode);
  TEST_ASSERT_EQUAL_UINT8(10, parsed.red);
  TEST_ASSERT_EQUAL_UINT8(20, parsed.green);
  TEST_ASSERT_EQUAL_UINT8(30, parsed.blue);
  TEST_ASSERT_EQUAL_UINT8(40, parsed.volume);
  TEST_ASSERT_EQUAL_UINT8(1, parsed.flags);
  TEST_ASSERT_EQUAL_UINT8(100, parsed.gain);
  TEST_ASSERT_EQUAL_UINT8(110, parsed.bass);
  TEST_ASSERT_EQUAL_UINT8(120, parsed.treble);
}

void test_parse_ble_write_color_only(void) {
  const uint8_t data[] = {0, 1, 255, 128, 64, 99, 0};
  const ParsedBleWrite parsed = parseBleWrite(data, sizeof(data));

  TEST_ASSERT_TRUE(parsed.hasColorPayload);
  TEST_ASSERT_FALSE(parsed.hasTonePayload);

  TEST_ASSERT_EQUAL_UINT8(0, parsed.category);
  TEST_ASSERT_EQUAL_UINT8(1, parsed.subMode);
  TEST_ASSERT_EQUAL_UINT8(255, parsed.red);
  TEST_ASSERT_EQUAL_UINT8(128, parsed.green);
  TEST_ASSERT_EQUAL_UINT8(64, parsed.blue);
  TEST_ASSERT_EQUAL_UINT8(99, parsed.volume);
  TEST_ASSERT_EQUAL_UINT8(0, parsed.flags);
}

void test_parse_ble_write_tone_only(void) {
  const uint8_t data[] = {11, 22, 33};
  const ParsedBleWrite parsed = parseBleWrite(data, sizeof(data));

  TEST_ASSERT_FALSE(parsed.hasColorPayload);
  TEST_ASSERT_TRUE(parsed.hasTonePayload);

  TEST_ASSERT_EQUAL_UINT8(11, parsed.gain);
  TEST_ASSERT_EQUAL_UINT8(22, parsed.bass);
  TEST_ASSERT_EQUAL_UINT8(33, parsed.treble);
}

void test_parse_ble_write_too_short(void) {
  const uint8_t data[] = {9, 8};
  const ParsedBleWrite parsed = parseBleWrite(data, sizeof(data));

  TEST_ASSERT_FALSE(parsed.hasColorPayload);
  TEST_ASSERT_FALSE(parsed.hasTonePayload);
}

void test_hsv_to_rgb_primary_colors(void) {
  TEST_ASSERT_EQUAL_HEX32(0x00FF0000, hsvToRgbPacked(0, 255, 255));
  TEST_ASSERT_EQUAL_HEX32(0x0000FF00, hsvToRgbPacked(85, 255, 255));
  TEST_ASSERT_EQUAL_HEX32(0x000000FF, hsvToRgbPacked(170, 255, 255));
}

int main(int argc, char **argv) {
  UNITY_BEGIN();
  RUN_TEST(test_parse_ble_write_full_payload);
  RUN_TEST(test_parse_ble_write_color_only);
  RUN_TEST(test_parse_ble_write_tone_only);
  RUN_TEST(test_parse_ble_write_too_short);
  RUN_TEST(test_hsv_to_rgb_primary_colors);
  return UNITY_END();
}
