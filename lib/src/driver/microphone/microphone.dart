// Microphone driver backed by the native usermedia_ffi shim (Phase D).
//
// On Windows the shim uses WASAPI shared-mode capture; on other platforms the
// native stub reports zero devices, so [registerMicrophones] registers nothing.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../ffi/loader.dart';
import '../../io/reader.dart';
import '../../prop/media.dart';
import '../driver.dart';
import '../manager.dart';

typedef _CountC = Int32 Function();
typedef _CountD = int Function();
typedef _StrC = Int32 Function(Int32, Pointer<Uint8>, Int32);
typedef _StrD = int Function(int, Pointer<Uint8>, int);
typedef _OpenC = Pointer<Void> Function(Int32, Int32, Int32);
typedef _OpenD = Pointer<Void> Function(int, int, int);
typedef _FormatC =
    Void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _FormatD =
    void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _ReadC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32);
typedef _ReadD = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _CloseC = Void Function(Pointer<Void>);
typedef _CloseD = void Function(Pointer<Void>);

/// Typed view over the shim's microphone symbols.
class MicBindings {
  MicBindings(DynamicLibrary lib)
    : count = lib.lookupFunction<_CountC, _CountD>('um_mic_count'),
      name = lib.lookupFunction<_StrC, _StrD>('um_mic_name'),
      id = lib.lookupFunction<_StrC, _StrD>('um_mic_id'),
      open = lib.lookupFunction<_OpenC, _OpenD>('um_mic_open'),
      format = lib.lookupFunction<_FormatC, _FormatD>('um_mic_format'),
      read = lib.lookupFunction<_ReadC, _ReadD>('um_mic_read'),
      close = lib.lookupFunction<_CloseC, _CloseD>('um_mic_close');

  final int Function() count;
  final int Function(int, Pointer<Uint8>, int) name;
  final int Function(int, Pointer<Uint8>, int) id;
  final Pointer<Void> Function(int, int, int) open;
  final void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>)
  format;
  final int Function(Pointer<Void>, Pointer<Uint8>, int) read;
  final void Function(Pointer<Void>) close;

  static MicBindings open_() => MicBindings(userMediaLibrary());

  String _readString(int index, int Function(int, Pointer<Uint8>, int) fn) {
    const cap = 512;
    final buf = calloc<Uint8>(cap);
    try {
      final n = fn(index, buf, cap);
      if (n <= 0) return '';
      return utf8.decode(buf.asTypedList(n), allowMalformed: true);
    } finally {
      calloc.free(buf);
    }
  }

  String deviceName(int index) => _readString(index, name);
  String deviceId(int index) => _readString(index, id);
}

/// A single native microphone exposed as an [Adapter] + [AudioRecorder].
class MicrophoneDriver implements Adapter, AudioRecorder {
  MicrophoneDriver(this._bindings, this._index, this.deviceId, this.deviceLabel);

  final MicBindings _bindings;
  final int _index;
  final String deviceId;
  final String deviceLabel;

  Pointer<Void> _handle = nullptr;

  @override
  void open() {}

  @override
  void close() {
    if (_handle != nullptr) {
      _bindings.close(_handle);
      _handle = nullptr;
    }
  }

  @override
  List<Media> properties() => [
        Media(
          deviceId: deviceId,
          audio: AudioProps(
            sampleRate: 48000,
            channelCount: 1,
            sampleSize: 16,
            isInterleaved: true,
          ),
        ),
      ];

  @override
  AudioReader audioRecord(Media property) {
    final sampleRate =
        property.audio.sampleRate == 0 ? 48000 : property.audio.sampleRate;
    final channels =
        property.audio.channelCount == 0 ? 1 : property.audio.channelCount;
    final handle = _bindings.open(_index, sampleRate, channels);
    if (handle == nullptr) {
      throw StateError('failed to open microphone "$deviceLabel"');
    }
    _handle = handle;
    return _MicReader(_bindings, handle);
  }
}

class _MicReader implements AudioReader {
  _MicReader(this._bindings, this._handle) {
    final sr = calloc<Int32>();
    final ch = calloc<Int32>();
    final bits = calloc<Int32>();
    try {
      _bindings.format(_handle, sr, ch, bits);
      _sampleRate = sr.value;
      _channels = ch.value;
    } finally {
      calloc
        ..free(sr)
        ..free(ch)
        ..free(bits);
    }
    _buffer = calloc<Uint8>(_bufferBytes);
  }

  // 200 ms of headroom at 48 kHz stereo PCM16.
  static const int _bufferBytes = 48000 * 2 * 2 ~/ 5;

  final MicBindings _bindings;
  final Pointer<Void> _handle;
  late final int _sampleRate;
  late final int _channels;
  late final Pointer<Uint8> _buffer;

  @override
  (AudioChunk, ReleaseFunc) read() {
    final n = _bindings.read(_handle, _buffer, _bufferBytes);
    if (n < 0) {
      throw StateError('microphone read failed');
    }
    final data = Uint8List.fromList(_buffer.asTypedList(n));
    return (
      AudioChunk(
        sampleRate: _sampleRate,
        channelCount: _channels,
        data: data,
      ),
      () {},
    );
  }
}

/// Number of audio capture devices reported by the native shim.
int microphoneCount() => MicBindings.open_().count();

/// Enumerates native microphones and registers a [MicrophoneDriver] for each.
/// Returns the registered driver ids (empty when none / no native lib).
List<String> registerMicrophones() {
  final bindings = MicBindings.open_();
  final n = bindings.count();
  final ids = <String>[];
  for (var i = 0; i < n; i++) {
    final label = bindings.deviceName(i);
    final devId = bindings.deviceId(i);
    final id = Manager.instance.register(
      MicrophoneDriver(bindings, i, devId, label),
      Info(
        label: label.isEmpty ? 'microphone$i' : label,
        deviceType: DeviceType.microphone,
      ),
    );
    ids.add(id);
  }
  return ids;
}
