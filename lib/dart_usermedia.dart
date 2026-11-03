/// dart_usermedia — a Dart port of pion/mediadevices (W3C MediaDevices API).
///
/// Phase A exposes the pure-Dart core: the constraint/property fitness system,
/// the driver registry, and the device/stream value types. Native capture
/// drivers (camera/microphone/screen) arrive in later phases over the FFI
/// foundation in `src/ffi/`.
library;

export 'src/backend.dart' show UserMediaBackend;
export 'src/codec/h264.dart' show H264Encoder;
export 'src/constraints.dart';
export 'src/driver/camera/camera.dart'
    show CameraDriver, cameraCount, registerCameras;
export 'src/driver/driver.dart';
export 'src/driver/manager.dart';
export 'src/driver/microphone/microphone.dart'
    show MicrophoneDriver, microphoneCount, registerMicrophones;
export 'src/driver/screen/screen.dart'
    show ScreenDriver, screenCount, registerScreens;
export 'src/driver/test/audiotest.dart';
export 'src/driver/test/videotest.dart';
export 'src/ffi/loader.dart' show NativeLibraryNotFoundError;
export 'src/frame/bmp.dart' show encodeBmp, frameToBmp;
export 'src/frame/convert.dart' show FrameConvert;
export 'src/frame/format.dart';
export 'src/io/reader.dart';
export 'src/media_device_info.dart';
export 'src/media_devices.dart';
export 'src/media_stream.dart';
export 'src/prop/constraint.dart';
export 'src/prop/media.dart';
export 'src/source.dart';
export 'src/track.dart';
