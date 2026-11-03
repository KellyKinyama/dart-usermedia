import 'dart:typed_data';

import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

VideoFrame _frame(FrameFormat format, List<int> bytes, {int w = 1, int h = 1}) =>
    VideoFrame(
      width: w,
      height: h,
      format: format,
      data: Uint8List.fromList(bytes),
    );

void main() {
  group('toRgba', () {
    test('rgb32 (BGRX) maps to RGBA with opaque alpha', () {
      // B=10, G=20, R=30, X=40
      final rgba = _frame(FrameFormat.rgb32, [10, 20, 30, 40]).toRgba();
      expect(rgba, [30, 20, 10, 255]);
    });

    test('bgra maps to RGBA preserving alpha', () {
      // B=10, G=20, R=30, A=128
      final rgba = _frame(FrameFormat.bgra, [10, 20, 30, 128]).toRgba();
      expect(rgba, [30, 20, 10, 128]);
    });

    test('rgba passes through', () {
      final rgba = _frame(FrameFormat.rgba, [1, 2, 3, 4]).toRgba();
      expect(rgba, [1, 2, 3, 4]);
    });

    test('i420 solid white converts to white rgba', () {
      // 2x2 white: Y=255 x4, U=128, V=128.
      final data = [255, 255, 255, 255, 128, 128];
      final rgba = _frame(FrameFormat.i420, data, w: 2, h: 2).toRgba();
      expect(rgba.length, 2 * 2 * 4);
      for (var i = 0; i < 4; i++) {
        expect(rgba[i * 4], closeTo(255, 1)); // R
        expect(rgba[i * 4 + 1], closeTo(255, 1)); // G
        expect(rgba[i * 4 + 2], closeTo(255, 1)); // B
        expect(rgba[i * 4 + 3], 255); // A
      }
    });

    test('unsupported format throws', () {
      expect(() => _frame(FrameFormat.mjpeg, [0]).toRgba(),
          throwsUnsupportedError);
    });
  });

  group('encodeBmp', () {
    test('produces a valid 32-bit BMP header and size', () {
      final rgba = Uint8List.fromList([30, 20, 10, 255]);
      final bmp = encodeBmp(1, 1, rgba);

      expect(bmp[0], 0x42); // 'B'
      expect(bmp[1], 0x4D); // 'M'
      final bd = ByteData.view(bmp.buffer);
      expect(bd.getUint32(2, Endian.little), bmp.length); // file size
      expect(bd.getUint32(10, Endian.little), 54); // pixel offset
      expect(bd.getInt32(18, Endian.little), 1); // width
      expect(bd.getInt32(22, Endian.little), -1); // top-down height
      expect(bd.getUint16(28, Endian.little), 32); // bpp

      // Pixel stored as B,G,R,A.
      expect(bmp.sublist(54), [10, 20, 30, 255]);
    });

    test('frameToBmp round-trips a frame', () {
      final bmp = frameToBmp(_frame(FrameFormat.bgra, [10, 20, 30, 255]));
      expect(bmp.length, 54 + 4);
      expect(bmp.sublist(54), [10, 20, 30, 255]);
    });
  });
}
