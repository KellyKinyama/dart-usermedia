import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

void main() {
  group('IntConstraint', () {
    test('IntIdeal: feasible, closer is smaller distance', () {
      expect(const IntIdeal(500).compare(500), (0.0, true));
      final (d400, ok400) = const IntIdeal(500).compare(400);
      final (d450, ok450) = const IntIdeal(500).compare(450);
      expect(ok400, isTrue);
      expect(ok450, isTrue);
      expect(d450, lessThan(d400));
    });

    test('IntExact: only exact is feasible', () {
      expect(const IntExact(640).compare(640), (0.0, true));
      expect(const IntExact(640).compare(641), (1.0, false));
    });

    test('IntOneOf: membership', () {
      const c = IntOneOf([480, 720, 1080]);
      expect(c.compare(720), (0.0, true));
      expect(c.compare(600), (1.0, false));
    });

    test('IntRanged: bounds and ideal', () {
      const c = IntRanged(min: 480, max: 1080, ideal: 720);
      expect(c.compare(480).$2, isTrue);
      expect(c.compare(1080).$2, isTrue);
      expect(c.compare(479), (1.0, false));
      expect(c.compare(1081), (1.0, false));
      expect(c.compare(720), (0.0, true));
      // Closer to ideal => smaller distance.
      expect(c.compare(600).$1, lessThan(c.compare(480).$1));
    });

    test('IntRanged: unspecified bounds are even', () {
      expect(const IntRanged(ideal: 720).compare(100), (0.0, true));
    });
  });

  group('StringConstraint', () {
    test('StringIdeal mismatch is still feasible', () {
      expect(const StringIdeal('cam0').compare('cam0'), (0.0, true));
      expect(const StringIdeal('cam0').compare('cam1'), (1.0, true));
    });

    test('StringExact mismatch is infeasible', () {
      expect(const StringExact('cam0').compare('cam1'), (1.0, false));
    });
  });

  group('BoolConstraint', () {
    test('BoolExact vs BoolIdeal feasibility on mismatch', () {
      expect(const BoolExact(true).compare(false), (1.0, false));
      expect(const BoolIdeal(true).compare(false), (1.0, true));
    });
  });

  group('FrameFormatConstraint', () {
    test('exact and ideal', () {
      expect(const FrameFormatExact(FrameFormat.i420).compare(FrameFormat.i420),
          (0.0, true));
      expect(const FrameFormatExact(FrameFormat.i420).compare(FrameFormat.nv12),
          (1.0, false));
      expect(const FrameFormatIdeal(FrameFormat.i420).compare(FrameFormat.nv12),
          (1.0, true));
    });
  });

  group('MediaConstraints.fitnessDistance', () {
    Media media({int w = 0, int h = 0, double fps = 0, String id = ''}) =>
        Media(deviceId: id, video: VideoProps(width: w, height: h, frameRate: fps));

    test('infeasible when an exact field fails', () {
      final c = MediaConstraints()..video.width = const IntExact(1280);
      expect(c.fitnessDistance(media(w: 640)), (0.0, false));
    });

    test('feasible accumulates distance; better device is smaller', () {
      final c = MediaConstraints()
        ..video.width = const IntIdeal(640)
        ..video.height = const IntIdeal(480);
      final (near, okNear) = c.fitnessDistance(media(w: 640, h: 480));
      final (far, okFar) = c.fitnessDistance(media(w: 320, h: 240));
      expect(okNear, isTrue);
      expect(okFar, isTrue);
      expect(near, 0.0);
      expect(near, lessThan(far));
    });

    test('framerate is skipped when device does not report it', () {
      final c = MediaConstraints()..video.frameRate = const FloatExact(30);
      // Device reports fps 0 -> framerate constraint ignored -> feasible.
      expect(c.fitnessDistance(media(w: 640, fps: 0)), (0.0, true));
      // Device reports a mismatching fps -> infeasible.
      expect(c.fitnessDistance(media(w: 640, fps: 25)), (0.0, false));
    });

    test('deviceId exact selects a device', () {
      final c = MediaConstraints()..deviceId = const StringExact('cam1');
      expect(c.fitnessDistance(media(id: 'cam1')).$2, isTrue);
      expect(c.fitnessDistance(media(id: 'cam0')), (0.0, false));
    });
  });
}
