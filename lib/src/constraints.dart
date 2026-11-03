// Ported from pion/mediadevices `mediastreamconstraints.go`.

import 'prop/constraint.dart';
import 'prop/media.dart';

/// Builder callback applied to a track's constraints.
typedef MediaOption = void Function(MediaTrackConstraints);

/// Constraints for a single track (W3C `MediaTrackConstraints`).
///
/// Wraps [MediaConstraints]; [selectedMedia] holds the resolved property set
/// chosen by driver discovery. The [deviceId]/[video]/[audio] accessors forward
/// to the underlying [constraints] for ergonomic builder callbacks.
class MediaTrackConstraints {
  final MediaConstraints constraints = MediaConstraints();
  Media selectedMedia = Media();

  StringConstraint? get deviceId => constraints.deviceId;
  set deviceId(StringConstraint? c) => constraints.deviceId = c;

  VideoConstraints get video => constraints.video;
  AudioConstraints get audio => constraints.audio;
}

/// Constraints passed to `getUserMedia` (W3C `MediaStreamConstraints`).
class MediaStreamConstraints {
  MediaStreamConstraints({this.audio, this.video});

  /// Audio track option, or null to omit audio.
  MediaOption? audio;

  /// Video track option, or null to omit video.
  MediaOption? video;
  // Codec selection is added in a later phase.
}
