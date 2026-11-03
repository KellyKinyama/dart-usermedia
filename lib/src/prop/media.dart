// Ported from pion/mediadevices `pkg/prop` (prop.go: Media, MediaConstraints,
// Video/Audio, FitnessDistance).

import '../frame/format.dart';
import 'constraint.dart';

/// Resolved concrete video properties of a device/track.
class VideoProps {
  VideoProps({
    this.width = 0,
    this.height = 0,
    this.frameRate = 0,
    this.frameFormat = FrameFormat.unknown,
    this.discardFramesOlderThan = Duration.zero,
  });

  int width;
  int height;
  double frameRate;
  FrameFormat frameFormat;
  Duration discardFramesOlderThan;
}

/// Resolved concrete audio properties of a device/track.
class AudioProps {
  AudioProps({
    this.channelCount = 0,
    this.latency = Duration.zero,
    this.sampleRate = 0,
    this.sampleSize = 0,
    this.isBigEndian = false,
    this.isFloat = false,
    this.isInterleaved = false,
  });

  int channelCount;
  Duration latency;
  int sampleRate;
  int sampleSize;
  bool isBigEndian;
  bool isFloat;
  bool isInterleaved;
}

/// A single resolved set of media properties (pion `prop.Media`).
class Media {
  Media({this.deviceId = '', VideoProps? video, AudioProps? audio})
    : video = video ?? VideoProps(),
      audio = audio ?? AudioProps();

  String deviceId;
  VideoProps video;
  AudioProps audio;

  /// Fills resolved fields from the concrete values pinned by [c]
  /// (ideal/exact constraints). Mirrors pion `Media.MergeConstraints`.
  void mergeConstraints(MediaConstraints c) {
    final did = c.deviceId;
    if (did != null) {
      final (v, ok) = did.value();
      if (ok) deviceId = v;
    }
    final w = c.video.width;
    if (w != null) {
      final (v, ok) = w.value();
      if (ok) video.width = v;
    }
    final h = c.video.height;
    if (h != null) {
      final (v, ok) = h.value();
      if (ok) video.height = v;
    }
    final fr = c.video.frameRate;
    if (fr != null) {
      final (v, ok) = fr.value();
      if (ok) video.frameRate = v;
    }
    final ff = c.video.frameFormat;
    if (ff != null) {
      final (v, ok) = ff.value();
      if (ok) video.frameFormat = v;
    }
    video.discardFramesOlderThan = c.video.discardFramesOlderThan;
    final cc = c.audio.channelCount;
    if (cc != null) {
      final (v, ok) = cc.value();
      if (ok) audio.channelCount = v;
    }
    final sr = c.audio.sampleRate;
    if (sr != null) {
      final (v, ok) = sr.value();
      if (ok) audio.sampleRate = v;
    }
    final ss = c.audio.sampleSize;
    if (ss != null) {
      final (v, ok) = ss.value();
      if (ok) audio.sampleSize = v;
    }
    final lat = c.audio.latency;
    if (lat != null) {
      final (v, ok) = lat.value();
      if (ok) audio.latency = v;
    }
    final be = c.audio.isBigEndian;
    if (be != null) audio.isBigEndian = be.value();
    final fl = c.audio.isFloat;
    if (fl != null) audio.isFloat = fl.value();
    final il = c.audio.isInterleaved;
    if (il != null) audio.isInterleaved = il.value();
  }

  /// Overrides resolved fields with the non-zero values from [o]. Bool fields
  /// are always copied. Mirrors pion `Media.Merge`.
  void merge(Media o) {
    if (o.deviceId.isNotEmpty) deviceId = o.deviceId;
    if (o.video.width != 0) video.width = o.video.width;
    if (o.video.height != 0) video.height = o.video.height;
    if (o.video.frameRate != 0) video.frameRate = o.video.frameRate;
    if (o.video.frameFormat != FrameFormat.unknown) {
      video.frameFormat = o.video.frameFormat;
    }
    if (o.video.discardFramesOlderThan != Duration.zero) {
      video.discardFramesOlderThan = o.video.discardFramesOlderThan;
    }
    if (o.audio.channelCount != 0) audio.channelCount = o.audio.channelCount;
    if (o.audio.sampleRate != 0) audio.sampleRate = o.audio.sampleRate;
    if (o.audio.sampleSize != 0) audio.sampleSize = o.audio.sampleSize;
    if (o.audio.latency != Duration.zero) audio.latency = o.audio.latency;
    audio.isBigEndian = o.audio.isBigEndian;
    audio.isFloat = o.audio.isFloat;
    audio.isInterleaved = o.audio.isInterleaved;
  }
}

/// Video constraint fields (null field == unconstrained / "any").
class VideoConstraints {
  IntConstraint? width;
  IntConstraint? height;
  FloatConstraint? frameRate;
  FrameFormatConstraint? frameFormat;
  Duration discardFramesOlderThan = Duration.zero;
}

/// Audio constraint fields (null field == unconstrained / "any").
class AudioConstraints {
  IntConstraint? channelCount;
  DurationConstraint? latency;
  IntConstraint? sampleRate;
  IntConstraint? sampleSize;
  BoolConstraint? isBigEndian;
  BoolConstraint? isFloat;
  BoolConstraint? isInterleaved;
}

/// A set of media property constraints (pion `prop.MediaConstraints`).
class MediaConstraints {
  StringConstraint? deviceId;
  final VideoConstraints video = VideoConstraints();
  final AudioConstraints audio = AudioConstraints();

  /// W3C fitness distance of these constraints against resolved [o].
  ///
  /// Returns `(totalDistance, feasible)`. If any constrained field is
  /// infeasible for [o], returns `(0, false)`. Lower distance is a better fit.
  (double, bool) fitnessDistance(Media o) {
    var dist = 0.0;
    var ok = true;

    void addInt(IntConstraint? c, int actual) {
      if (c == null) return;
      final (d, k) = c.compare(actual);
      dist += d;
      ok = ok && k;
    }

    void addFloat(FloatConstraint? c, double actual) {
      if (c == null) return;
      final (d, k) = c.compare(actual);
      dist += d;
      ok = ok && k;
    }

    void addString(StringConstraint? c, String actual) {
      if (c == null) return;
      final (d, k) = c.compare(actual);
      dist += d;
      ok = ok && k;
    }

    void addBool(BoolConstraint? c, bool actual) {
      if (c == null) return;
      final (d, k) = c.compare(actual);
      dist += d;
      ok = ok && k;
    }

    void addDuration(DurationConstraint? c, Duration actual) {
      if (c == null) return;
      final (d, k) = c.compare(actual);
      dist += d;
      ok = ok && k;
    }

    void addFrameFormat(FrameFormatConstraint? c, FrameFormat actual) {
      if (c == null) return;
      final (d, k) = c.compare(actual);
      dist += d;
      ok = ok && k;
    }

    addString(deviceId, o.deviceId);
    addInt(video.width, o.video.width);
    addInt(video.height, o.video.height);
    addFrameFormat(video.frameFormat, o.video.frameFormat);
    // Framerate is skipped when the device does not report it (<= 0).
    if (o.video.frameRate > 0.0) {
      addFloat(video.frameRate, o.video.frameRate);
    }
    addInt(audio.sampleRate, o.audio.sampleRate);
    addDuration(audio.latency, o.audio.latency);
    addInt(audio.channelCount, o.audio.channelCount);
    addInt(audio.sampleSize, o.audio.sampleSize);
    addBool(audio.isBigEndian, o.audio.isBigEndian);
    addBool(audio.isFloat, o.audio.isFloat);
    addBool(audio.isInterleaved, o.audio.isInterleaved);

    if (!ok) return (0.0, false);
    return (dist, true);
  }
}
