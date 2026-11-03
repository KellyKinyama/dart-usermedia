import 'package:dart_usermedia/dart_usermedia.dart';
import 'package:test/test.dart';

/// Phase 0 native handshake tests.
///
/// These require the native usermedia_ffi library to be built (see
/// native/usermedia_ffi/CMakeLists.txt). They are tagged `native` so they can
/// be skipped where the library is unavailable:
///   dart test -x native   # skip
///   dart test -t native   # run only these
void main() {
  group('UserMediaBackend (native)', () {
    late UserMediaBackend backend;

    setUp(() => backend = UserMediaBackend.open());
    tearDown(() => backend.dispose());

    test('um_ping returns the native sentinel', () {
      expect(backend.ping(), 0x7E57);
    });

    test('native posts an async event back to Dart', () async {
      final received = backend.events.first;
      backend.emitTestEvent(1234);
      expect(await received, 1234);
    });

    test('reports libwebrtc link status', () {
      // 0 = stub build, 1 = libwebrtc linked (+DeviceInfo), 2 = linked/null.
      expect(backend.webrtcAvailable(), anyOf(0, 1, 2));
    });
  }, tags: 'native');
}
