import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

/// A fake camera adapter used to validate the driver registry + discovery
/// without any native code.
class _FakeCamera implements Adapter, VideoRecorder {
  _FakeCamera(this._props);
  final List<Media> _props;
  bool opened = false;

  @override
  void open() => opened = true;
  @override
  void close() => opened = false;
  @override
  List<Media> properties() => _props;
  @override
  VideoReader videoRecord(Media property) => throw UnimplementedError();
}

class _FakeMic implements Adapter, AudioRecorder {
  @override
  void open() {}
  @override
  void close() {}
  @override
  List<Media> properties() => [
        Media(audio: AudioProps(sampleRate: 48000, channelCount: 2)),
      ];
  @override
  AudioReader audioRecord(Media property) => throw UnimplementedError();
}

void main() {
  setUp(Manager.instance.clear);

  test('register exposes a queryable driver', () {
    final id = Manager.instance.register(
      _FakeCamera([Media(video: VideoProps(width: 640, height: 480))]),
      const Info(label: 'FaceTime HD', deviceType: DeviceType.camera),
    );
    final found = Manager.instance.query(filterId(id));
    expect(found, hasLength(1));
    expect(found.single.info().label, 'FaceTime HD');
    expect(found.single.status(), DriverState.closed);
  });

  test('video/audio recorder filters match the right adapters', () {
    Manager.instance.register(
      _FakeCamera([Media(video: VideoProps(width: 640, height: 480))]),
      const Info(label: 'cam', deviceType: DeviceType.camera),
    );
    Manager.instance.register(
      _FakeMic(),
      const Info(label: 'mic', deviceType: DeviceType.microphone),
    );

    final cams = Manager.instance.query(filterVideoRecorder());
    final mics = Manager.instance.query(filterAudioRecorder());
    expect(cams, hasLength(1));
    expect(mics, hasLength(1));
    expect(cams.single.info().deviceType, DeviceType.camera);
    expect(mics.single.info().deviceType, DeviceType.microphone);
  });

  test('open/close toggles driver state', () {
    final id = Manager.instance.register(
      _FakeCamera([Media(video: VideoProps(width: 640, height: 480))]),
      const Info(label: 'cam', deviceType: DeviceType.camera),
    );
    final d = Manager.instance.query(filterId(id)).single;
    d.open();
    expect(d.status(), DriverState.running);
    d.close();
    expect(d.status(), DriverState.closed);
  });

  test('discovery picks the property with the smallest fitness distance', () {
    // One camera advertising two resolutions; constraints prefer 640x480.
    final cam = _FakeCamera([
      Media(video: VideoProps(width: 1920, height: 1080)),
      Media(video: VideoProps(width: 640, height: 480)),
    ]);
    Manager.instance.register(
      cam,
      const Info(label: 'multi', deviceType: DeviceType.camera),
    );

    final constraints = MediaConstraints()
      ..video.width = const IntIdeal(640)
      ..video.height = const IntIdeal(480);

    final driver = Manager.instance
        .query(filterAnd([
          filterVideoRecorder(),
          filterDeviceType(DeviceType.camera),
        ]))
        .single;

    Media? best;
    var bestDist = double.infinity;
    for (final p in driver.properties()) {
      final (dist, ok) = constraints.fitnessDistance(p);
      if (ok && dist < bestDist) {
        bestDist = dist;
        best = p;
      }
    }

    expect(best, isNotNull);
    expect(best!.video.width, 640);
    expect(best.video.height, 480);
    expect(bestDist, 0.0);
  });
}
