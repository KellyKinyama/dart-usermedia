// Ported from pion/mediadevices `track.go` (Source/VideoSource/AudioSource).

import 'io/reader.dart';

/// A generic media source.
abstract interface class Source {
  String id();
  void close();
}

/// A source that emits a series of video frames.
abstract interface class VideoSource implements VideoReader, Source {}

/// A source that emits a series of audio chunks.
abstract interface class AudioSource implements AudioReader, Source {}
