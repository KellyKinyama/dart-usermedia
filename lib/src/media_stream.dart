// Ported from pion/mediadevices `mediastream.go`.

import 'track.dart';

/// A collection of tracks (W3C `MediaStream`).
class MediaStream {
  MediaStream([Iterable<Track> tracks = const []]) {
    _tracks.addAll(tracks);
  }

  final Set<Track> _tracks = {};

  List<Track> getVideoTracks() =>
      _tracks.where((t) => t.kind() == TrackKind.video).toList();

  List<Track> getAudioTracks() =>
      _tracks.where((t) => t.kind() == TrackKind.audio).toList();

  List<Track> getTracks() => _tracks.toList();

  void addTrack(Track t) => _tracks.add(t);

  void removeTrack(Track t) => _tracks.remove(t);

  /// Video tracks, typed as [VideoTrack] for convenience.
  List<VideoTrack> get videoTracks =>
      getVideoTracks().cast<VideoTrack>();

  /// Audio tracks, typed as [AudioTrack] for convenience.
  List<AudioTrack> get audioTracks =>
      getAudioTracks().cast<AudioTrack>();
}
