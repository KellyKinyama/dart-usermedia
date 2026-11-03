// Ported from pion/mediadevices `mediadevices.go` (GetUserMedia,
// GetDisplayMedia, selectBestDriver, queryDriverProperties, EnumerateDevices).

import 'constraints.dart';
import 'driver/driver.dart';
import 'driver/manager.dart';
import 'media_device_info.dart';
import 'media_stream.dart';
import 'prop/media.dart';
import 'track.dart';

/// Thrown when no driver/property satisfies the given constraints.
class DriverNotFoundError implements Exception {
  const DriverNotFoundError();
  @override
  String toString() =>
      'DriverNotFoundError: failed to find the best driver that fits the '
      'constraints';
}

/// Opens closed drivers matching [filter], collects their properties, then
/// closes any it opened. Mirrors pion `queryDriverProperties`.
Map<Driver, List<Media>> _queryDriverProperties(FilterFn filter) {
  final drivers = Manager.instance.query(filter);
  final opened = <Driver>[];
  final result = <Driver, List<Media>>{};

  for (final d in drivers) {
    if (d.status() == DriverState.closed) {
      try {
        d.open();
        opened.add(d);
      } catch (_) {
        // Skip drivers we cannot open; we can't read their properties.
        continue;
      }
    }
    result[d] = d.properties();
  }

  for (final d in opened) {
    d.close();
  }
  return result;
}

/// W3C SelectSettings: picks the driver + property with the minimum fitness
/// distance (adjusted by driver priority) that satisfies [constraints].
/// Mirrors pion `selectBestDriver`.
(Driver, MediaTrackConstraints) _selectBestDriver(
  FilterFn filter,
  MediaTrackConstraints constraints,
) {
  Driver? bestDriver;
  var bestProp = Media();
  var minFitnessDist = double.infinity;

  final driverProperties = _queryDriverProperties(filter);
  driverProperties.forEach((d, props) {
    final priority = d.info().priority.value;
    for (final p in props) {
      final (fitnessDist, ok) = constraints.constraints.fitnessDistance(p);
      if (!ok) continue;
      final adjusted = fitnessDist - priority;
      if (adjusted < minFitnessDist) {
        minFitnessDist = adjusted;
        bestDriver = d;
        bestProp = p;
      }
    }
  });

  final chosen = bestDriver;
  if (chosen == null) throw const DriverNotFoundError();

  constraints.selectedMedia = Media()
    ..mergeConstraints(constraints.constraints)
    ..merge(bestProp);
  return (chosen, constraints);
}

Track _selectVideo(MediaTrackConstraints constraints) {
  final filter = filterAnd([
    filterVideoRecorder(),
    filterNot(filterDeviceType(DeviceType.screen)),
  ]);
  final (d, c) = _selectBestDriver(filter, constraints);
  return newTrackFromDriver(d, c);
}

Track _selectAudio(MediaTrackConstraints constraints) {
  final (d, c) = _selectBestDriver(filterAudioRecorder(), constraints);
  return newTrackFromDriver(d, c);
}

Track _selectScreen(MediaTrackConstraints constraints) {
  final filter = filterAnd([
    filterVideoRecorder(),
    filterDeviceType(DeviceType.screen),
  ]);
  final (d, c) = _selectBestDriver(filter, constraints);
  return newTrackFromDriver(d, c);
}

/// Prompts for media input matching [constraints] and returns a
/// [MediaStream] (W3C `getUserMedia`). Throws [DriverNotFoundError] when no
/// device satisfies the constraints.
MediaStream getUserMedia(MediaStreamConstraints constraints) {
  final trackers = <Track>[];
  void cleanup() {
    for (final t in trackers) {
      t.close();
    }
  }

  final videoOption = constraints.video;
  if (videoOption != null) {
    final c = MediaTrackConstraints();
    videoOption(c);
    try {
      trackers.add(_selectVideo(c));
    } catch (_) {
      cleanup();
      rethrow;
    }
  }

  final audioOption = constraints.audio;
  if (audioOption != null) {
    final c = MediaTrackConstraints();
    audioOption(c);
    try {
      trackers.add(_selectAudio(c));
    } catch (_) {
      cleanup();
      rethrow;
    }
  }

  return MediaStream(trackers);
}

/// Captures a display/window as a [MediaStream] (W3C `getDisplayMedia`).
MediaStream getDisplayMedia(MediaStreamConstraints constraints) {
  final trackers = <Track>[];
  final videoOption = constraints.video;
  if (videoOption != null) {
    final c = MediaTrackConstraints();
    videoOption(c);
    try {
      trackers.add(_selectScreen(c));
    } catch (_) {
      for (final t in trackers) {
        t.close();
      }
      rethrow;
    }
  }
  return MediaStream(trackers);
}

/// Lists available media input devices (W3C `enumerateDevices`).
List<MediaDeviceInfo> enumerateDevices() {
  final drivers = Manager.instance.query((_) => true);
  final info = <MediaDeviceInfo>[];
  final isVideo = filterVideoRecorder();
  final isAudio = filterAudioRecorder();
  for (final d in drivers) {
    final MediaDeviceType kind;
    if (isVideo(d)) {
      kind = MediaDeviceType.videoInput;
    } else if (isAudio(d)) {
      kind = MediaDeviceType.audioInput;
    } else {
      continue;
    }
    final di = d.info();
    info.add(MediaDeviceInfo(
      deviceId: d.id(),
      kind: kind,
      label: di.label,
      deviceType: di.deviceType,
    ));
  }
  return info;
}
