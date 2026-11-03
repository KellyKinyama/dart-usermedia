// Captures a single frame and saves it as a BMP file.
//
// Tries a real camera first; falls back to the synthetic videotest driver when
// no camera (or native library) is available, so it runs anywhere.
//
//   dart run example/capture_frame.dart [output.bmp]

import 'dart:io';

import 'package:dart_usermedia/dart_usermedia.dart';

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args.first : 'frame.bmp';

  var source = 'camera';
  try {
    if (registerCameras().isEmpty) throw StateError('no camera');
  } catch (_) {
    registerVideotest();
    source = 'videotest';
  }

  final stream = getUserMedia(MediaStreamConstraints(
    video: (c) {
      c.video.width = const IntIdeal(640);
      c.video.height = const IntIdeal(480);
    },
  ));
  final track = stream.videoTracks.single;
  final reader = track.newReader();

  // Warm up: early camera frames can be black while auto-exposure settles.
  VideoFrame frame = reader.read().$1;
  for (var i = 0; i < 15; i++) {
    final (f, release) = reader.read();
    frame = f;
    release();
  }

  File(outPath).writeAsBytesSync(frameToBmp(frame));
  track.close();

  print('saved ${frame.width}x${frame.height} ${frame.format} '
      'frame from $source to $outPath');
}
