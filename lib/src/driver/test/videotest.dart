// Ported from pion/mediadevices `pkg/driver/videotest`.
//
// A synthetic camera driver producing animated I420 frames. Register it to use
// GetUserMedia without any real hardware (as pion's videotest adapter does).

import 'dart:typed_data';

import '../../frame/format.dart';
import '../../io/reader.dart';
import '../../prop/media.dart';
import '../driver.dart';
import '../manager.dart';

class VideotestDriver implements Adapter, VideoRecorder {
  @override
  void open() {}

  @override
  void close() {}

  @override
  List<Media> properties() => [
        Media(
          video: VideoProps(
            width: 640,
            height: 480,
            frameRate: 30,
            frameFormat: FrameFormat.i420,
          ),
        ),
        Media(
          video: VideoProps(
            width: 320,
            height: 240,
            frameRate: 30,
            frameFormat: FrameFormat.i420,
          ),
        ),
      ];

  @override
  VideoReader videoRecord(Media property) => _VideotestReader(property);
}

class _VideotestReader implements VideoReader {
  _VideotestReader(this._property);
  final Media _property;
  int _frame = 0;

  @override
  (VideoFrame, ReleaseFunc) read() {
    final w = _property.video.width == 0 ? 640 : _property.video.width;
    final h = _property.video.height == 0 ? 480 : _property.video.height;
    final chromaW = (w + 1) ~/ 2;
    final chromaH = (h + 1) ~/ 2;
    final size = w * h + 2 * chromaW * chromaH;
    final data = Uint8List(size);

    // Animated luma gradient; flat mid-gray chroma.
    final t = _frame++ & 0xff;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        data[row + x] = (x + y + t) & 0xff;
      }
    }
    for (var i = w * h; i < size; i++) {
      data[i] = 128;
    }

    return (
      VideoFrame(width: w, height: h, format: FrameFormat.i420, data: data),
      () {},
    );
  }
}

/// Registers a [VideotestDriver] and returns its driver id.
String registerVideotest() => Manager.instance.register(
      VideotestDriver(),
      const Info(label: 'videotest', deviceType: DeviceType.camera),
    );
