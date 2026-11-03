// Ported from pion/mediadevices `pkg/driver` (driver.go, state.go, devicetype).

import '../io/reader.dart';
import '../prop/media.dart';

/// Kind of a capture device.
enum DeviceType { camera, microphone, screen }

/// Lifecycle state of a driver.
enum DriverState { closed, running }

/// Device selection priority. Higher wins ties during discovery.
extension type const Priority(double value) {
  /// System-default devices.
  static const Priority high = Priority(0.1);

  /// Normal devices.
  static const Priority normal = Priority(0.0);

  /// Unrecommended devices.
  static const Priority low = Priority(-0.1);
}

/// Static metadata describing a driver.
class Info {
  const Info({
    required this.label,
    required this.deviceType,
    this.priority = Priority.normal,
    this.name = '',
  });

  final String label;
  final DeviceType deviceType;
  final Priority priority;
  final String name;
}

/// A low-level capture adapter. `open`/`close` throw on failure (Go returns
/// an error); `properties` lists the capability sets the device supports.
abstract interface class Adapter {
  void open();
  void close();
  List<Media> properties();
}

/// A registered, discoverable driver (adapter + identity + metadata + state).
abstract interface class Driver implements Adapter {
  String id();
  Info info();
  DriverState status();
}

/// Adapter capable of recording video for a chosen property set.
abstract interface class VideoRecorder {
  VideoReader videoRecord(Media property);
}

/// Adapter capable of recording audio for a chosen property set.
abstract interface class AudioRecorder {
  AudioReader audioRecord(Media property);
}
