// Minimal BMP encoder for captured frames (Phase F).
//
// Writes a 32-bit top-down BMP (BITMAPINFOHEADER). 32-bit rows are already
// 4-byte aligned, so no row padding is needed. Pure Dart, no dependencies.

import 'dart:typed_data';

import '../io/reader.dart';
import 'convert.dart';

/// Encodes packed [rgba] (width*height*4) as a 32-bit BMP byte stream.
Uint8List encodeBmp(int width, int height, Uint8List rgba) {
  const headerSize = 54; // 14-byte file header + 40-byte info header
  final imageSize = width * height * 4;
  final out = Uint8List(headerSize + imageSize);
  final bd = ByteData.view(out.buffer);

  // BITMAPFILEHEADER
  out[0] = 0x42; // 'B'
  out[1] = 0x4D; // 'M'
  bd.setUint32(2, out.length, Endian.little); // file size
  bd.setUint32(10, headerSize, Endian.little); // pixel data offset

  // BITMAPINFOHEADER
  bd.setUint32(14, 40, Endian.little); // header size
  bd.setInt32(18, width, Endian.little);
  bd.setInt32(22, -height, Endian.little); // negative => top-down
  bd.setUint16(26, 1, Endian.little); // planes
  bd.setUint16(28, 32, Endian.little); // bits per pixel
  bd.setUint32(30, 0, Endian.little); // BI_RGB
  bd.setUint32(34, imageSize, Endian.little);

  // BMP 32-bit stores pixels as B,G,R,A.
  for (var i = 0; i < width * height; i++) {
    final s = i * 4;
    final d = headerSize + s;
    out[d] = rgba[s + 2]; // B
    out[d + 1] = rgba[s + 1]; // G
    out[d + 2] = rgba[s]; // R
    out[d + 3] = rgba[s + 3]; // A
  }
  return out;
}

/// Encodes a [VideoFrame] as a 32-bit BMP, converting its format to RGBA first.
Uint8List frameToBmp(VideoFrame frame) =>
    encodeBmp(frame.width, frame.height, frame.toRgba());
