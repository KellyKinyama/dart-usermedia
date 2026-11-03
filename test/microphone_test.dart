@Tags(['native', 'microphone'])
library;

import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

/// Real microphone capture over the native shim. Requires the built library and
/// a capture device; skips itself when none is present.
///   dart test -t microphone   # run only these
///   dart test -x native       # skip
void main() {
  setUp(Manager.instance.clear);

  test('enumerates and captures interleaved PCM16 via getUserMedia', () {
    if (microphoneCount() == 0) {
      markTestSkipped('no microphone present');
      return;
    }

    final ids = registerMicrophones();
    expect(ids, isNotEmpty);

    final devices = enumerateDevices();
    expect(devices.where((d) => d.kind == MediaDeviceType.audioInput),
        isNotEmpty);

    final stream = getUserMedia(MediaStreamConstraints(audio: (c) {}));
    final track = stream.audioTracks.single;
    addTearDown(track.close);

    final reader = track.newReader();
    final (chunk, release) = reader.read();

    expect(chunk.sampleRate, greaterThan(0));
    expect(chunk.channelCount, greaterThan(0));
    expect(chunk.data, isNotEmpty);
    // Whole interleaved frames of 16-bit samples.
    expect(chunk.data.length % (chunk.channelCount * 2), 0);
    release();
  });
}
