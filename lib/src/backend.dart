// Phase 0 backend: owns the native context, exposes the sync ping and the
// async event bridge. Later phases add enumerateDevices / getUserMedia here.

import 'dart:ffi';

import 'ffi/bindings.dart';
import 'ffi/event_bridge.dart';
import 'ffi/loader.dart';

/// Entry point to the native media-capture backend.
class UserMediaBackend {
  UserMediaBackend._(this._bindings, this._context, this._events) {
    _bindings.umSetEventPort(_context, _events.nativePort);
  }

  final UserMediaBindings _bindings;
  final Pointer<Void> _context;
  final EventBridge _events;
  bool _disposed = false;

  /// Loads the native library and initializes the context + event bridge.
  factory UserMediaBackend.open() {
    final lib = openUserMediaLibrary();
    final bindings = UserMediaBindings(lib);
    final events = EventBridge.initialize(bindings);
    final context = bindings.umInit();
    if (context == nullptr) {
      throw StateError('um_init returned null; backend failed to initialize.');
    }
    return UserMediaBackend._(bindings, context, events);
  }

  /// Synchronous FFI smoke test. Returns the native sentinel `0x7E57`.
  int ping() {
    _checkAlive();
    return _bindings.umPing();
  }

  /// Whether the native library was built and linked against libwebrtc.
  ///
  /// Returns `0` for a stub build, `1` when libwebrtc is linked and the
  /// video-capture `DeviceInfo` was constructed, `2` when linked but the
  /// factory returned null.
  int webrtcAvailable() {
    _checkAlive();
    return _bindings.umWebrtcAvailable();
  }

  /// Stream of async events posted by native code (Phase 0: raw int64).
  Stream<int> get events => _events.events;

  /// Asks native code to post [value] back over the event bridge.
  void emitTestEvent(int value) {
    _checkAlive();
    _bindings.umEmitTestEvent(_context, value);
  }

  void _checkAlive() {
    if (_disposed) throw StateError('UserMediaBackend has been disposed.');
  }

  /// Releases the native context and event bridge.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bindings.umDispose(_context);
    await _events.dispose();
  }
}
