// Ported (non-codec subset) from pion/mediadevices `track.go`.
//
// The encode/RTP/WebRTC layers of pion's Track are out of scope here; Phase B
// exposes raw frame readers. Encoding arrives in a later phase.

import 'constraints.dart';
import 'driver/driver.dart';
import 'io/broadcaster.dart';
import 'io/reader.dart';
import 'source.dart';

/// Kind of a track (W3C `MediaStreamTrack.kind`).
enum TrackKind { video, audio }

/// A media stream track (W3C `MediaStreamTrack`).
abstract class Track implements Source {
  TrackKind kind();

  /// Registers a handler invoked when the track ends with an error. If an
  /// error already occurred, the handler is called immediately.
  void onEnded(void Function(Object error)? handler);
}

abstract class _BaseTrack implements Track {
  _BaseTrack(this._source, this._kind);
  final Source _source;
  final TrackKind _kind;
  void Function(Object error)? _onEnded;
  Object? _error;
  bool _ended = false;

  @override
  String id() => _source.id();
  @override
  TrackKind kind() => _kind;
  @override
  void close() => _source.close();

  @override
  void onEnded(void Function(Object error)? handler) {
    _onEnded = handler;
    final err = _error;
    if (err != null && handler != null && !_ended) {
      _ended = true;
      handler(err);
    }
  }

  void onError(Object error) {
    _error = error;
    final handler = _onEnded;
    if (handler != null && !_ended) {
      _ended = true;
      handler(error);
    }
  }
}

/// A video track that allows multiple readers over a shared source.
class VideoTrack extends _BaseTrack {
  VideoTrack(Source source, VideoReader reader)
    : _broadcaster = VideoBroadcaster(reader),
      super(source, TrackKind.video);

  final VideoBroadcaster _broadcaster;

  /// Creates a new reader over the track's source.
  VideoReader newReader() => _broadcaster.newReader();
}

/// An audio track that allows multiple readers over a shared source.
class AudioTrack extends _BaseTrack {
  AudioTrack(Source source, AudioReader reader)
    : _broadcaster = AudioBroadcaster(reader),
      super(source, TrackKind.audio);

  final AudioBroadcaster _broadcaster;

  AudioReader newReader() => _broadcaster.newReader();
}

/// Adapts a [Driver] to the [Source] interface.
class _DriverSource implements Source {
  _DriverSource(this._driver);
  final Driver _driver;
  @override
  String id() => _driver.id();
  @override
  void close() => _driver.close();
}

/// Opens [d] and builds the matching track from the resolved
/// [MediaTrackConstraints.selectedMedia].
Track newTrackFromDriver(Driver d, MediaTrackConstraints constraints) {
  d.open();
  if (d is VideoRecorder) {
    final reader = (d as VideoRecorder).videoRecord(constraints.selectedMedia);
    return VideoTrack(_DriverSource(d), reader);
  }
  if (d is AudioRecorder) {
    final reader = (d as AudioRecorder).audioRecord(constraints.selectedMedia);
    return AudioTrack(_DriverSource(d), reader);
  }
  throw StateError('invalid driver type: not a video or audio recorder');
}
