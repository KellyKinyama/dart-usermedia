// Ported from pion/mediadevices `mediadeviceinfo.go`.

import 'driver/driver.dart';

/// Kind of media device (W3C `MediaDeviceKind`).
enum MediaDeviceType { videoInput, audioInput, audioOutput }

/// Describes a media device (W3C `MediaDeviceInfo`).
class MediaDeviceInfo {
  const MediaDeviceInfo({
    required this.deviceId,
    required this.kind,
    required this.label,
    required this.deviceType,
  });

  final String deviceId;
  final MediaDeviceType kind;
  final String label;
  final DeviceType deviceType;
}
