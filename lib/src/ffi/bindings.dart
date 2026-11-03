// Minimal hand-written bindings for the Phase 0 usermedia_ffi surface.
//
// ffigen (see ffigen.yaml) will eventually emit lib/src/ffi/bindings.g.dart
// with the full surface; until the native header grows and libclang is set up,
// this keeps Phase 0 runnable with just the symbols we use.

import 'dart:ffi';

typedef _UmInitC = Pointer<Void> Function();
typedef _UmInitDart = Pointer<Void> Function();

typedef _UmDisposeC = Void Function(Pointer<Void>);
typedef _UmDisposeDart = void Function(Pointer<Void>);

typedef _UmPingC = Int32 Function();
typedef _UmPingDart = int Function();

typedef _UmInitDartApiC = IntPtr Function(Pointer<Void>);
typedef _UmInitDartApiDart = int Function(Pointer<Void>);

typedef _UmSetEventPortC = Void Function(Pointer<Void>, Int64);
typedef _UmSetEventPortDart = void Function(Pointer<Void>, int);

typedef _UmEmitTestEventC = Void Function(Pointer<Void>, Int64);
typedef _UmEmitTestEventDart = void Function(Pointer<Void>, int);

typedef _UmWebrtcAvailableC = Int32 Function();
typedef _UmWebrtcAvailableDart = int Function();

/// Thin typed view over the native library's exported symbols.
class UserMediaBindings {
  UserMediaBindings(DynamicLibrary lib)
    : umInit = lib.lookupFunction<_UmInitC, _UmInitDart>('um_init'),
      umDispose = lib
          .lookupFunction<_UmDisposeC, _UmDisposeDart>('um_dispose'),
      umPing = lib.lookupFunction<_UmPingC, _UmPingDart>('um_ping'),
      umInitDartApi = lib
          .lookupFunction<_UmInitDartApiC, _UmInitDartApiDart>(
            'um_init_dart_api',
          ),
      umSetEventPort = lib
          .lookupFunction<_UmSetEventPortC, _UmSetEventPortDart>(
            'um_set_event_port',
          ),
      umEmitTestEvent = lib
          .lookupFunction<_UmEmitTestEventC, _UmEmitTestEventDart>(
            'um_emit_test_event',
          ),
      umWebrtcAvailable = lib
          .lookupFunction<_UmWebrtcAvailableC, _UmWebrtcAvailableDart>(
            'um_webrtc_available',
          );

  final Pointer<Void> Function() umInit;
  final void Function(Pointer<Void>) umDispose;
  final int Function() umPing;
  final int Function(Pointer<Void>) umInitDartApi;
  final void Function(Pointer<Void>, int) umSetEventPort;
  final void Function(Pointer<Void>, int) umEmitTestEvent;
  final int Function() umWebrtcAvailable;
}
