// Pixel-format conversion helpers for captured frames (Phase F).
//
// Converts the formats the native drivers deliver (RGB32/BGRA from Media
// Foundation / DXGI, I420 from the test driver) into packed RGBA for display,
// encoding, or saving. Pure Dart.

import 'dart:typed_data';

import '../io/reader.dart';
import 'format.dart';

int _clamp8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

extension FrameConvert on VideoFrame {
  /// Returns the frame as tightly packed RGBA (width*height*4 bytes).
  ///
  /// Supports [FrameFormat.rgba], [FrameFormat.rgb32] (BGRX),
  /// [FrameFormat.bgra], and [FrameFormat.i420]. Throws [UnsupportedError]
  /// for other formats.
  Uint8List toRgba() {
    final pixels = width * height;
    switch (format) {
      case FrameFormat.rgba:
        return Uint8List.fromList(data);

      case FrameFormat.rgb32: // B,G,R,X
      case FrameFormat.bgra: // B,G,R,A
        final out = Uint8List(pixels * 4);
        final opaque = format == FrameFormat.rgb32;
        for (var i = 0; i < pixels; i++) {
          final s = i * 4;
          out[s] = data[s + 2]; // R
          out[s + 1] = data[s + 1]; // G
          out[s + 2] = data[s]; // B
          out[s + 3] = opaque ? 255 : data[s + 3]; // A
        }
        return out;

      case FrameFormat.i420:
        return _i420ToRgba();

      default:
        throw UnsupportedError('toRgba: unsupported format $format');
    }
  }

  Uint8List _i420ToRgba() {
    final out = Uint8List(width * height * 4);
    final chromaW = (width + 1) ~/ 2;
    final chromaH = (height + 1) ~/ 2;
    final ySize = width * height;
    final uOffset = ySize;
    final vOffset = ySize + chromaW * chromaH;

    for (var y = 0; y < height; y++) {
      final cy = y ~/ 2;
      for (var x = 0; x < width; x++) {
        final cx = x ~/ 2;
        final yv = data[y * width + x];
        final u = data[uOffset + cy * chromaW + cx] - 128;
        final v = data[vOffset + cy * chromaW + cx] - 128;
        final r = _clamp8((yv + 1.402 * v).round());
        final g = _clamp8((yv - 0.344 * u - 0.714 * v).round());
        final b = _clamp8((yv + 1.772 * u).round());
        final s = (y * width + x) * 4;
        out[s] = r;
        out[s + 1] = g;
        out[s + 2] = b;
        out[s + 3] = 255;
      }
    }
    return out;
  }
}
