// Bridges async events posted by native code to a Dart Stream.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'bindings.dart';

/// Owns the native event port and exposes incoming events as a [Stream].
///
/// Native code posts int64 values via `um_emit_*`; those arrive on the
/// [ReceivePort] and are forwarded to [events].
class EventBridge {
  EventBridge._(this._receivePort, this.nativePort) {
    _sub = _receivePort.listen(_onMessage);
  }

  final ReceivePort _receivePort;

  /// The native send-port integer to hand to `um_set_event_port`.
  final int nativePort;

  final _controller = StreamController<int>.broadcast();
  late final StreamSubscription<dynamic> _sub;

  /// Events posted from native code (Phase 0: raw int64 values).
  Stream<int> get events => _controller.stream;

  /// Initializes the Dart DL API on the native side and creates the bridge.
  ///
  /// Must be called once before any `um_emit_*` call. Throws on failure.
  static EventBridge initialize(UserMediaBindings bindings) {
    final status = bindings.umInitDartApi(NativeApi.initializeApiDLData);
    if (status != 0) {
      throw StateError(
        'Dart_InitializeApiDL failed (status $status); native event bridge '
        'unavailable.',
      );
    }
    final port = ReceivePort();
    return EventBridge._(port, port.sendPort.nativePort);
  }

  void _onMessage(dynamic message) {
    if (message is int) _controller.add(message);
  }

  /// Tears down the port and stream.
  Future<void> dispose() async {
    await _sub.cancel();
    _receivePort.close();
    await _controller.close();
  }
}
