@Tags(['native', 'screen'])
library;

import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

/// Real desktop capture over the native shim. Requires the built library and a
/// display; skips itself when none is present.
///   dart test -t screen    # run only these
///   dart test -x native    # skip
void main() {
  setUp(Manager.instance.clear);

  test('captures real BGRA desktop frames via getDisplayMedia', () {
    if (screenCount() == 0) {
      markTestSkipped('no display present');
      return;
    }

    final ids = registerScreens();
    expect(ids, isNotEmpty);

    final devices = enumerateDevices();
    expect(devices.where((d) => d.deviceType == DeviceType.screen), isNotEmpty);

    final stream = getDisplayMedia(MediaStreamConstraints(video: (c) {}));
    final track = stream.videoTracks.single;
    addTearDown(track.close);

    final reader = track.newReader();

    // The first duplication frame can be empty; read a few until content shows.
    VideoFrame? frame;
    var nonZero = 0;
    for (var i = 0; i < 30 && nonZero == 0; i++) {
      final (f, release) = reader.read();
      frame = f;
      nonZero = f.data.where((b) => b != 0).length;
      release();
    }

    expect(frame, isNotNull);
    expect(frame!.format, FrameFormat.bgra);
    expect(frame.data.length, frame.width * frame.height * 4);
    expect(nonZero, greaterThan(0), reason: 'expected a non-black desktop frame');
  });
}
