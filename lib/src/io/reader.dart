// Ported from pion/mediadevices `pkg/io/video` and `pkg/io/audio` (Reader).
//
// A reader yields a frame/chunk plus a [ReleaseFunc] the caller invokes to
// return the underlying buffer to the source for reuse.

import 'dart:typed_data';

import '../frame/format.dart';

/// Called by the consumer to release a frame/chunk back to the pool.
typedef ReleaseFunc = void Function();

/// A decoded video frame.
class VideoFrame {
  VideoFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.data,
  });

  final int width;
  final int height;
  final FrameFormat format;
  final Uint8List data;
}

/// A chunk of audio samples (interleaved or planar per the owning props).
class AudioChunk {
  AudioChunk({
    required this.sampleRate,
    required this.channelCount,
    required this.data,
  });

  final int sampleRate;
  final int channelCount;
  final Uint8List data;
}

/// Reads decoded video frames (pion `video.Reader`).
abstract interface class VideoReader {
  (VideoFrame, ReleaseFunc) read();
}

/// Reads audio sample chunks (pion `audio.Reader`).
abstract interface class AudioReader {
  (AudioChunk, ReleaseFunc) read();
}
