// Screen-capture driver backed by the native usermedia_ffi shim (Phase E).
//
// On Windows the shim uses DXGI Desktop Duplication; on other platforms the
// native stub reports zero outputs, so [registerScreens] registers nothing.
//
// Screen drivers register as DeviceType.screen, so they are selected by
// getDisplayMedia (not getUserMedia).

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

/// Typed view over the shim's screen symbols.
class ScreenBindings {
  ScreenBindings(DynamicLibrary lib)
    : count = lib.lookupFunction<_CountC, _CountD>('um_screen_count'),
      name = lib.lookupFunction<_StrC, _StrD>('um_screen_name'),
      id = lib.lookupFunction<_StrC, _StrD>('um_screen_id'),
      open = lib.lookupFunction<_OpenC, _OpenD>('um_screen_open'),
      format = lib.lookupFunction<_FormatC, _FormatD>('um_screen_format'),
      read = lib.lookupFunction<_ReadC, _ReadD>('um_screen_read'),
      close = lib.lookupFunction<_CloseC, _CloseD>('um_screen_close');

  final int Function() count;
  final int Function(int, Pointer<Uint8>, int) name;
  final int Function(int, Pointer<Uint8>, int) id;
  final Pointer<Void> Function(int, int, int) open;
  final void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>)
  format;
  final int Function(Pointer<Void>, Pointer<Uint8>, int) read;
  final void Function(Pointer<Void>) close;

  static ScreenBindings open_() => ScreenBindings(userMediaLibrary());

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

  String displayName(int index) => _readString(index, name);
  String displayId(int index) => _readString(index, id);
}

/// A single display output exposed as an [Adapter] + [VideoRecorder].
class ScreenDriver implements Adapter, VideoRecorder {
  ScreenDriver(this._bindings, this._index, this.deviceId, this.deviceLabel);

  final ScreenBindings _bindings;
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
          video: VideoProps(frameFormat: FrameFormat.bgra),
        ),
      ];

  @override
  VideoReader videoRecord(Media property) {
    final handle = _bindings.open(
      _index,
      property.video.width,
      property.video.height,
    );
    if (handle == nullptr) {
      throw StateError('failed to open display "$deviceLabel"');
    }
    _handle = handle;
    return _ScreenReader(_bindings, handle);
  }
}

class _ScreenReader implements VideoReader {
  _ScreenReader(this._bindings, this._handle) {
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

  final ScreenBindings _bindings;
  final Pointer<Void> _handle;
  late final int _width;
  late final int _height;
  late final int _size;
  late final Pointer<Uint8> _buffer;

  @override
  (VideoFrame, ReleaseFunc) read() {
    final n = _bindings.read(_handle, _buffer, _size);
    if (n < 0) {
      throw StateError('screen read failed');
    }
    final data = Uint8List.fromList(_buffer.asTypedList(n));
    return (
      VideoFrame(
        width: _width,
        height: _height,
        format: FrameFormat.bgra,
        data: data,
      ),
      () {},
    );
  }
}

/// Number of display outputs reported by the native shim.
int screenCount() => ScreenBindings.open_().count();

/// Enumerates display outputs and registers a [ScreenDriver] for each.
/// Returns the registered driver ids (empty when none / no native lib).
List<String> registerScreens() {
  final bindings = ScreenBindings.open_();
  final n = bindings.count();
  final ids = <String>[];
  for (var i = 0; i < n; i++) {
    final label = bindings.displayName(i);
    final devId = bindings.displayId(i);
    final id = Manager.instance.register(
      ScreenDriver(bindings, i, devId, label),
      Info(
        label: label.isEmpty ? 'screen$i' : label,
        deviceType: DeviceType.screen,
      ),
    );
    ids.add(id);
  }
  return ids;
}
