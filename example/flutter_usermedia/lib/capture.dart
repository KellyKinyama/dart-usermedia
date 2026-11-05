// Isolate-based capture controllers. getUserMedia's reads are synchronous and
// blocking, so capture runs in a background isolate and posts frames/levels
// back to the UI isolate.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_usermedia/dart_usermedia.dart';

/// What the video isolate should capture.
enum VideoSource { camera, videotest, screen }

// --- Video ------------------------------------------------------------------

void _videoIsolate((SendPort, String, int) args) {
  final (toMain, kind, cameraIndex) = args;
  final control = ReceivePort();
  toMain.send(control.sendPort);
  var running = true;
  control.listen((m) {
    if (m == 'stop') running = false;
  });

  try {
    String? camDeviceId;
    switch (kind) {
      case 'camera':
        final ids = registerCameras();
        if (cameraIndex >= 0 && cameraIndex < ids.length) {
          final driver = Manager.instance.query(filterId(ids[cameraIndex]));
          if (driver.isNotEmpty) {
            final props = driver.single.properties();
            if (props.isNotEmpty) camDeviceId = props.first.deviceId;
          }
        }
      case 'screen':
        registerScreens();
      default:
        registerVideotest();
    }

    final stream = kind == 'screen'
        ? getDisplayMedia(MediaStreamConstraints(video: (c) {}))
        : getUserMedia(MediaStreamConstraints(
            video: (c) {
              if (camDeviceId != null) {
                c.deviceId = StringExact(camDeviceId);
              }
              c.video.width = const IntIdeal(640);
              c.video.height = const IntIdeal(480);
            },
          ));
    final track = stream.videoTracks.single;
    final reader = track.newReader();

    void loop() {
      if (!running) {
        track.close();
        toMain.send('stopped');
        control.close();
        return;
      }
      try {
        final (frame, release) = reader.read();
        final rgba = frame.toRgba();
        toMain.send((frame.width, frame.height, rgba));
        release();
      } catch (e) {
        toMain.send('error: $e');
        running = false;
      }
      // Reschedule so the event loop can process a 'stop' between frames.
      Future(loop);
    }

    loop();
  } catch (e) {
    toMain.send('error: $e');
    control.close();
  }
}

/// Drives the video isolate and exposes decoded frames.
class VideoCapture {
  final _frames = StreamController<ui.Image>.broadcast();
  Isolate? _iso;
  SendPort? _control;
  ReceivePort? _recv;
  String? error;

  Stream<ui.Image> get frames => _frames.stream;

  Future<void> start(VideoSource source, {int cameraIndex = 0}) async {
    error = null;
    _recv = ReceivePort();
    _recv!.listen((m) async {
      if (m is SendPort) {
        _control = m;
      } else if (m is (int, int, Uint8List)) {
        final (w, h, rgba) = m;
        final img = await _decode(w, h, rgba);
        if (!_frames.isClosed) _frames.add(img);
      } else if (m == 'stopped') {
        _kill();
      } else if (m is String && m.startsWith('error')) {
        error = m.substring('error: '.length);
        if (!_frames.isClosed) _frames.addError(error!);
        _kill();
      }
    });
    _iso = await Isolate.spawn(
        _videoIsolate, (_recv!.sendPort, source.name, cameraIndex));
  }

  Future<void> stop() async {
    _control?.send('stop');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _kill();
  }

  void _kill() {
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _recv?.close();
    _recv = null;
  }

  Future<void> dispose() async {
    await stop();
    await _frames.close();
  }

  Future<ui.Image> _decode(int w, int h, Uint8List rgba) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}

// --- Audio (microphone level meter) -----------------------------------------

void _micIsolate(SendPort toMain) {
  final control = ReceivePort();
  toMain.send(control.sendPort);
  var running = true;
  control.listen((m) {
    if (m == 'stop') running = false;
  });

  try {
    registerMicrophones();
    final stream = getUserMedia(MediaStreamConstraints(audio: (c) {}));
    final track = stream.audioTracks.single;
    final reader = track.newReader();

    void loop() {
      if (!running) {
        track.close();
        control.close();
        return;
      }
      try {
        final (chunk, release) = reader.read();
        final pcm = chunk.data.buffer
            .asInt16List(chunk.data.offsetInBytes, chunk.data.length ~/ 2);
        var sum = 0.0;
        for (final s in pcm) {
          sum += s * s;
        }
        final rms = pcm.isEmpty ? 0.0 : (sum / pcm.length);
        toMain.send((rms / (32768 * 32768)).clamp(0.0, 1.0)); // 0..1
        release();
      } catch (e) {
        toMain.send('error: $e');
        running = false;
      }
      Future(loop);
    }

    loop();
  } catch (e) {
    toMain.send('error: $e');
    control.close();
  }
}

/// Drives the mic isolate and exposes a normalized 0..1 level.
class MicLevel {
  final _levels = StreamController<double>.broadcast();
  Isolate? _iso;
  SendPort? _control;
  ReceivePort? _recv;

  Stream<double> get levels => _levels.stream;

  Future<void> start() async {
    _recv = ReceivePort();
    _recv!.listen((m) {
      if (m is SendPort) {
        _control = m;
      } else if (m is double) {
        if (!_levels.isClosed) _levels.add(m);
      }
    });
    _iso = await Isolate.spawn(_micIsolate, _recv!.sendPort);
  }

  Future<void> stop() async {
    _control?.send('stop');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _recv?.close();
    _recv = null;
  }

  Future<void> dispose() async {
    await stop();
    await _levels.close();
  }
}
