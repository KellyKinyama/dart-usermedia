@Tags(['native', 'h264'])
library;

import 'dart:typed_data';

import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

/// Native H.264 encoder (Media Foundation). Requires the built library.
///   dart test -t h264     # run only this
///   dart test -x native   # skip
void main() {
  test('encodes BGRA frames to Annex-B H.264 with an SPS NAL', () {
    const w = 320, h = 240;
    final H264Encoder enc;
    try {
      enc = H264Encoder(width: w, height: h, fps: 30, bitrate: 1000000);
    } on StateError {
      markTestSkipped('H.264 encoder unavailable');
      return;
    }

    final out = BytesBuilder();
    for (var f = 0; f < 60; f++) {
      final data = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        final s = i * 4;
        data[s] = (i + f * 3) & 0xff;
        data[s + 1] = (i ~/ w + f) & 0xff;
        data[s + 2] = (f * 5) & 0xff;
        data[s + 3] = 255;
      }
      out.add(enc.encode(
        VideoFrame(width: w, height: h, format: FrameFormat.bgra, data: data),
      ));
    }
    out.add(enc.flush());
    enc.close();

    final bytes = out.toBytes();
    expect(bytes.length, greaterThan(0));

    var hasStart = false, hasSps = false;
    for (var i = 0; i + 4 < bytes.length; i++) {
      if (bytes[i] == 0 &&
          bytes[i + 1] == 0 &&
          bytes[i + 2] == 0 &&
          bytes[i + 3] == 1) {
        hasStart = true;
        if ((bytes[i + 4] & 0x1f) == 7) hasSps = true;
      }
    }
    expect(hasStart, isTrue, reason: 'expected Annex-B start codes');
    expect(hasSps, isTrue, reason: 'expected an SPS NAL (type 7)');
  });
}
