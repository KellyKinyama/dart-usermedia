// Ported (simplified) from pion/mediadevices `pkg/io/video` and
// `pkg/io/audio` Broadcaster.
//
// Fans a single upstream reader out to reader handles created via [newReader].
// Phase B keeps pass-through semantics (one active consumer); the buffered
// latest-frame fan-out for multiple simultaneous readers is future work.

import 'reader.dart';

class VideoBroadcaster {
  VideoBroadcaster(this._source);
  VideoReader _source;

  /// Replaces the upstream source (used by track transforms later).
  void replaceSource(VideoReader source) => _source = source;
  VideoReader source() => _source;

  VideoReader newReader() => _VideoBroadcastReader(this);
  (VideoFrame, ReleaseFunc) _read() => _source.read();
}

class _VideoBroadcastReader implements VideoReader {
  _VideoBroadcastReader(this._b);
  final VideoBroadcaster _b;
  @override
  (VideoFrame, ReleaseFunc) read() => _b._read();
}

class AudioBroadcaster {
  AudioBroadcaster(this._source);
  AudioReader _source;

  void replaceSource(AudioReader source) => _source = source;
  AudioReader source() => _source;

  AudioReader newReader() => _AudioBroadcastReader(this);
  (AudioChunk, ReleaseFunc) _read() => _source.read();
}

class _AudioBroadcastReader implements AudioReader {
  _AudioBroadcastReader(this._b);
  final AudioBroadcaster _b;
  @override
  (AudioChunk, ReleaseFunc) read() => _b._read();
}
