import 'package:dart_usermedia/dart_usermedia.dart';

/// Phase B demo: capture a synthetic camera frame end-to-end through the
/// ported getUserMedia pipeline — pure Dart, no native build required.
void main(List<String> arguments) {
  registerVideotest();
  registerAudiotest();

  for (final d in enumerateDevices()) {
    print('device: ${d.label} (${d.kind.name})');
  }

  final stream = getUserMedia(MediaStreamConstraints(
    video: (c) {
      c.video.width = const IntIdeal(640);
      c.video.height = const IntIdeal(480);
    },
    audio: (c) {},
  ));

  final video = stream.videoTracks.single;
  final (frame, releaseVideo) = video.newReader().read();
  print('video frame: ${frame.width}x${frame.height} '
      '${frame.format} (${frame.data.length} bytes)');
  releaseVideo();

  final audio = stream.audioTracks.single;
  final (chunk, releaseAudio) = audio.newReader().read();
  print('audio chunk: ${chunk.sampleRate} Hz x${chunk.channelCount}ch '
      '(${chunk.data.length} bytes)');
  releaseAudio();

  for (final t in stream.getTracks()) {
    t.close();
  }
}
