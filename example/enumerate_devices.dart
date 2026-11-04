// Loads the native shim and lists capture devices. On a headless Linux
// container this prints zero cameras/screens (and an ALSA "Default" mic)
// without throwing — a smoke test that the .so loads and enumerates safely.

import 'package:dart_usermedia/dart_usermedia.dart';

void main() {
  print('cameras:     ${cameraCount()}');
  print('microphones: ${microphoneCount()}');
  print('screens:     ${screenCount()}');

  registerCameras();
  registerMicrophones();
  registerScreens();

  for (final d in enumerateDevices()) {
    print('- ${d.label} [${d.kind.name}/${d.deviceType.name}] ${d.deviceId}');
  }
}
