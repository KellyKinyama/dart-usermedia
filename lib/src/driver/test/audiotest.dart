// Ported from pion/mediadevices `pkg/driver/audiotest`.
//
// A synthetic microphone driver producing a sine tone as interleaved PCM16.

import 'dart:math' as math;
import 'dart:typed_data';

import '../../io/reader.dart';
import '../../prop/media.dart';
import '../driver.dart';
import '../manager.dart';

const int _defaultSampleRate = 48000;
const int _samplesPerChunk = 480; // 10 ms at 48 kHz.
const double _toneHz = 440;

class AudiotestDriver implements Adapter, AudioRecorder {
  @override
  void open() {}

  @override
  void close() {}

  @override
  List<Media> properties() => [
        Media(
          audio: AudioProps(
            sampleRate: _defaultSampleRate,
            channelCount: 1,
            sampleSize: 16,
            isInterleaved: true,
          ),
        ),
      ];

  @override
  AudioReader audioRecord(Media property) => _AudiotestReader(property);
}

class _AudiotestReader implements AudioReader {
  _AudiotestReader(this._property);
  final Media _property;
  int _sampleIndex = 0;

  @override
  (AudioChunk, ReleaseFunc) read() {
    final sampleRate = _property.audio.sampleRate == 0
        ? _defaultSampleRate
        : _property.audio.sampleRate;
    final channels =
        _property.audio.channelCount == 0 ? 1 : _property.audio.channelCount;
    final bytes = ByteData(_samplesPerChunk * channels * 2);

    for (var i = 0; i < _samplesPerChunk; i++) {
      final t = (_sampleIndex + i) / sampleRate;
      final value = (math.sin(2 * math.pi * _toneHz * t) * 32767).round();
      for (var c = 0; c < channels; c++) {
        bytes.setInt16((i * channels + c) * 2, value, Endian.little);
      }
    }
    _sampleIndex += _samplesPerChunk;

    return (
      AudioChunk(
        sampleRate: sampleRate,
        channelCount: channels,
        data: bytes.buffer.asUint8List(),
      ),
      () {},
    );
  }
}

/// Registers an [AudiotestDriver] and returns its driver id.
String registerAudiotest() => Manager.instance.register(
      AudiotestDriver(),
      const Info(label: 'audiotest', deviceType: DeviceType.microphone),
    );
