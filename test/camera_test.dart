@Tags(['native', 'camera'])
library;

import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

/// Real camera capture over the native shim. Requires the built library and a
/// connected camera; skips itself when none is present.
///   dart test -t camera    # run only these
///   dart test -x native    # skip
void main() {
  setUp(Manager.instance.clear);

  test('enumerates and captures real RGB32 frames via getUserMedia', () {
    if (cameraCount() == 0) {
      markTestSkipped('no camera present');
      return;
    }

    final ids = registerCameras();
    expect(ids, isNotEmpty);

    final devices = enumerateDevices();
    expect(devices.where((d) => d.kind == MediaDeviceType.videoInput),
        isNotEmpty);

    final stream = getUserMedia(MediaStreamConstraints(
      video: (c) {
        c.video.width = const IntIdeal(640);
        c.video.height = const IntIdeal(480);
      },
    ));
    final track = stream.videoTracks.single;
    addTearDown(track.close);

    final reader = track.newReader();

    // Warm up: early frames can be black while auto-exposure settles.
    VideoFrame? frame;
    for (var i = 0; i < 20; i++) {
      final (f, release) = reader.read();
      frame = f;
      release();
    }

    expect(frame, isNotNull);
    expect(frame!.format, FrameFormat.rgb32);
    expect(frame.data.length, frame.width * frame.height * 4);

    final nonZero = frame.data.where((b) => b != 0).length;
    expect(nonZero, greaterThan(frame.data.length ~/ 10),
        reason: 'expected a substantially exposed frame');
  });
}
