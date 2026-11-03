// Camera driver backed by the native usermedia_ffi shim (Phase C).
//
// On Windows the shim uses Media Foundation; on other platforms the native
// stub reports zero devices, so [registerCameras] simply registers nothing.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../ffi/loader.dart';
import '../../frame/format.dart';
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

/// Typed view over the shim's camera symbols.
class CameraBindings {
  CameraBindings(DynamicLibrary lib)
    : count = lib.lookupFunction<_CountC, _CountD>('um_camera_count'),
      name = lib.lookupFunction<_StrC, _StrD>('um_camera_name'),
      id = lib.lookupFunction<_StrC, _StrD>('um_camera_id'),
      open = lib.lookupFunction<_OpenC, _OpenD>('um_camera_open'),
      format = lib.lookupFunction<_FormatC, _FormatD>('um_camera_format'),
      read = lib.lookupFunction<_ReadC, _ReadD>('um_camera_read'),
      close = lib.lookupFunction<_CloseC, _CloseD>('um_camera_close');

  final int Function() count;
  final int Function(int, Pointer<Uint8>, int) name;
  final int Function(int, Pointer<Uint8>, int) id;
  final Pointer<Void> Function(int, int, int) open;
  final void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>)
  format;
  final int Function(Pointer<Void>, Pointer<Uint8>, int) read;
  final void Function(Pointer<Void>) close;

  static CameraBindings open_() => CameraBindings(userMediaLibrary());

  /// Reads a UTF-8 string field (name/id) for [index] using [fn].
  String _readString(int index, int Function(int, Pointer<Uint8>, int) fn) {
    const cap = 512;
    final buf = calloc<Uint8>(cap);
    try {
      final n = fn(index, buf, cap);
      if (n <= 0) return '';
      return utf8FromBytes(buf, n);
    } finally {
      calloc.free(buf);
    }
  }

  String deviceName(int index) => _readString(index, name);
  String deviceId(int index) => _readString(index, id);
}

/// Decodes [n] bytes at [ptr] as UTF-8.
String utf8FromBytes(Pointer<Uint8> ptr, int n) =>
    utf8.decode(ptr.asTypedList(n), allowMalformed: true);

/// A single native camera device exposed as an [Adapter] + [VideoRecorder].
class CameraDriver implements Adapter, VideoRecorder {
  CameraDriver(this._bindings, this._index, this.deviceId, this.deviceLabel);

  final CameraBindings _bindings;
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
        _prop(1280, 720),
        _prop(640, 480),
      ];

  Media _prop(int w, int h) => Media(
        deviceId: deviceId,
        video: VideoProps(
          width: w,
          height: h,
          frameFormat: FrameFormat.rgb32,
        ),
      );

  @override
  VideoReader videoRecord(Media property) {
    final handle = _bindings.open(
      _index,
      property.video.width,
      property.video.height,
    );
    if (handle == nullptr) {
      throw StateError('failed to open camera "$deviceLabel"');
    }
    _handle = handle;
    return _CameraReader(_bindings, handle);
  }
}

class _CameraReader implements VideoReader {
  _CameraReader(this._bindings, this._handle) {
    final wp = calloc<Int32>();
    final hp = calloc<Int32>();
    final sp = calloc<Int32>();
    try {
      _bindings.format(_handle, wp, hp, sp);
      _width = wp.value;
      _height = hp.value;
      _size = sp.value;
    } finally {
      calloc
        ..free(wp)
        ..free(hp)
        ..free(sp);
    }
    _buffer = calloc<Uint8>(_size);
  }

  final CameraBindings _bindings;
  final Pointer<Void> _handle;
  late final int _width;
  late final int _height;
  late final int _size;
  late final Pointer<Uint8> _buffer;

  @override
  (VideoFrame, ReleaseFunc) read() {
    final n = _bindings.read(_handle, _buffer, _size);
    if (n < 0) {
      throw StateError('camera read failed');
    }
    final data = Uint8List.fromList(_buffer.asTypedList(n));
    return (
      VideoFrame(
        width: _width,
        height: _height,
        format: FrameFormat.rgb32,
        data: data,
      ),
      () {},
    );
  }
}

/// Number of video capture devices reported by the native shim.
int cameraCount() => CameraBindings.open_().count();

/// Enumerates native cameras and registers a [CameraDriver] for each.
/// Returns the registered driver ids (empty when no cameras / no native lib).
List<String> registerCameras() {
  final bindings = CameraBindings.open_();
  final n = bindings.count();
  final ids = <String>[];
  for (var i = 0; i < n; i++) {
    final label = bindings.deviceName(i);
    final devId = bindings.deviceId(i);
    final id = Manager.instance.register(
      CameraDriver(bindings, i, devId, label),
      Info(label: label.isEmpty ? 'camera$i' : label, deviceType: DeviceType.camera),
    );
    ids.add(id);
  }
  return ids;
}
