List<int> encodeBleControlPacket({
  required int category,
  required int subMode,
  required int red,
  required int green,
  required int blue,
  required int volume,
  required bool showPeak,
  required int gain,
  required int bass,
  required int treble,
}) {
  final ccat = category.clamp(0, 1);
  final csub = subMode.clamp(0, 2);
  final cr = red.clamp(0, 255);
  final cg = green.clamp(0, 255);
  final cb = blue.clamp(0, 255);
  final cv = volume.clamp(0, 100);
  final flags = showPeak ? 0x01 : 0x00;
  final cgain = gain.clamp(0, 255);
  final cbass = bass.clamp(0, 255);
  final ctreble = treble.clamp(0, 255);

  return [ccat, csub, cr, cg, cb, cv, flags, cgain, cbass, ctreble];
}