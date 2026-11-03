import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

void main() {
  setUp(Manager.instance.clear);

  test('getUserMedia(video) returns a stream with one video track', () {
    registerVideotest();
    final stream = getUserMedia(MediaStreamConstraints(video: (c) {}));
    expect(stream.getVideoTracks(), hasLength(1));
    expect(stream.getAudioTracks(), isEmpty);
    expect(stream.getVideoTracks().single.kind(), TrackKind.video);
  });

  test('video track reader produces I420 frames of the chosen size', () {
    registerVideotest();
    final stream = getUserMedia(MediaStreamConstraints(
      video: (c) {
        c.video.width = const IntExact(320);
        c.video.height = const IntExact(240);
      },
    ));
    final track = stream.videoTracks.single;
    final reader = track.newReader();

    final (frame, release) = reader.read();
    expect(frame.width, 320);
    expect(frame.height, 240);
    expect(frame.format, FrameFormat.i420);
    // I420 buffer size = w*h + 2 * ceil(w/2)*ceil(h/2).
    expect(frame.data.length, 320 * 240 + 2 * 160 * 120);
    release();

    // Frames animate: a later frame differs from the first.
    final (frame2, release2) = reader.read();
    expect(frame2.data, isNot(equals(frame.data)));
    release2();

    track.close();
  });

  test('getUserMedia picks the resolution closest to the ideal', () {
    registerVideotest(); // advertises 640x480 and 320x240
    final stream = getUserMedia(MediaStreamConstraints(
      video: (c) {
        c.video.width = const IntIdeal(320);
        c.video.height = const IntIdeal(240);
      },
    ));
    final (frame, release) = stream.videoTracks.single.newReader().read();
    expect(frame.width, 320);
    expect(frame.height, 240);
    release();
  });

  test('getUserMedia(audio+video) returns both tracks', () {
    registerVideotest();
    registerAudiotest();
    final stream = getUserMedia(MediaStreamConstraints(
      video: (c) {},
      audio: (c) {},
    ));
    expect(stream.getVideoTracks(), hasLength(1));
    expect(stream.getAudioTracks(), hasLength(1));
    expect(stream.getTracks(), hasLength(2));
  });

  test('audio track reader produces PCM16 chunks', () {
    registerAudiotest();
    final stream = getUserMedia(MediaStreamConstraints(audio: (c) {}));
    final track = stream.audioTracks.single;
    final (chunk, release) = track.newReader().read();
    expect(chunk.sampleRate, 48000);
    expect(chunk.channelCount, 1);
    expect(chunk.data, isNotEmpty);
    release();
    track.close();
  });

  test('getUserMedia throws when no driver is registered', () {
    expect(
      () => getUserMedia(MediaStreamConstraints(video: (c) {})),
      throwsA(isA<DriverNotFoundError>()),
    );
  });

  test('overconstrained video throws DriverNotFoundError', () {
    registerVideotest();
    expect(
      () => getUserMedia(MediaStreamConstraints(
        video: (c) => c.video.width = const IntExact(9999),
      )),
      throwsA(isA<DriverNotFoundError>()),
    );
  });

  test('enumerateDevices lists registered inputs', () {
    registerVideotest();
    registerAudiotest();
    final devices = enumerateDevices();
    expect(devices, hasLength(2));
    expect(
      devices.map((d) => d.kind),
      containsAll([MediaDeviceType.videoInput, MediaDeviceType.audioInput]),
    );
    expect(devices.map((d) => d.label), containsAll(['videotest', 'audiotest']));
  });
}
