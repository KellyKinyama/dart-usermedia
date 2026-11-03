// H.264 encoder backed by the native usermedia_ffi shim.
//
// On Windows the shim uses the Media Foundation H.264 encoder MFT; other
// platforms return a stub that throws on create.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ffi/loader.dart';
import '../io/reader.dart';

typedef _CreateC = Pointer<Void> Function(Int32, Int32, Int32, Int32);
typedef _CreateD = Pointer<Void> Function(int, int, int, int);
typedef _EncodeC =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Uint8>, Int32);
typedef _EncodeD =
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int);
typedef _FlushC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32);
typedef _FlushD = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _CloseC = Void Function(Pointer<Void>);
typedef _CloseD = void Function(Pointer<Void>);

class _H264Bindings {
  _H264Bindings(DynamicLibrary lib)
    : create = lib.lookupFunction<_CreateC, _CreateD>('um_h264_create'),
      encode = lib.lookupFunction<_EncodeC, _EncodeD>('um_h264_encode'),
      flush = lib.lookupFunction<_FlushC, _FlushD>('um_h264_flush'),
      close = lib.lookupFunction<_CloseC, _CloseD>('um_h264_close');

  final Pointer<Void> Function(int, int, int, int) create;
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  encode;
  final int Function(Pointer<Void>, Pointer<Uint8>, int) flush;
  final void Function(Pointer<Void>) close;
}

/// Encodes BGRA/BGRX video frames to H.264 (Annex B) via the native encoder.
///
/// Accepts [FrameFormat.bgra] and [FrameFormat.rgb32] frames (both B,G,R,_).
/// [encode] returns the encoded bytes produced for that frame, which may be
/// empty while the encoder is buffering; call [flush] at the end to drain.
class H264Encoder {
  H264Encoder._(this._bindings, this._handle, this.width, this.height)
    : _buffer = calloc<Uint8>(width * height * 4) {
    _bufferLen = width * height * 4;
  }

  final _H264Bindings _bindings;
  final Pointer<Void> _handle;
  final int width;
  final int height;
  final Pointer<Uint8> _buffer;
  late final int _bufferLen;
  bool _closed = false;

  /// Creates an encoder for [width] x [height] at [fps] targeting [bitrate]
  /// bits/second. [width]/[height] should be even.
  factory H264Encoder({
    required int width,
    required int height,
    int fps = 30,
    int bitrate = 2000000,
  }) {
    final bindings = _H264Bindings(userMediaLibrary());
    final handle = bindings.create(width, height, fps, bitrate);
    if (handle == nullptr) {
      throw StateError('failed to create H.264 encoder (unsupported platform?)');
    }
    return H264Encoder._(bindings, handle, width, height);
  }

  /// Encodes one frame; returns the H.264 bytes emitted (possibly empty).
  Uint8List encode(VideoFrame frame) {
    _checkAlive();
    if (frame.width != width || frame.height != height) {
      throw ArgumentError('frame size ${frame.width}x${frame.height} != '
          '${width}x$height');
    }
    final input = calloc<Uint8>(frame.data.length);
    try {
      input.asTypedList(frame.data.length).setAll(0, frame.data);
      final n = _bindings.encode(
        _handle,
        input,
        frame.data.length,
        _buffer,
        _bufferLen,
      );
      if (n < 0) throw StateError('H.264 encode failed');
      return Uint8List.fromList(_buffer.asTypedList(n));
    } finally {
      calloc.free(input);
    }
  }

  /// Drains any buffered output. Returns the remaining H.264 bytes.
  Uint8List flush() {
    _checkAlive();
    final n = _bindings.flush(_handle, _buffer, _bufferLen);
    if (n < 0) throw StateError('H.264 flush failed');
    return Uint8List.fromList(_buffer.asTypedList(n));
  }

  void _checkAlive() {
    if (_closed) throw StateError('H264Encoder is closed');
  }

  /// Releases native resources.
  void close() {
    if (_closed) return;
    _closed = true;
    _bindings.close(_handle);
    calloc.free(_buffer);
  }
}
