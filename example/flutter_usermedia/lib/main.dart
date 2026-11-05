import 'dart:io';
import 'dart:ui' as ui;

import 'package:dart_usermedia/dart_usermedia.dart' hide VideoSource;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'capture.dart';

void main() => runApp(const UserMediaApp());

class UserMediaApp extends StatelessWidget {
  const UserMediaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dart_usermedia example',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _video = VideoCapture();
  final _mic = MicLevel();

  String? _libError;
  List<MediaDeviceInfo> _devices = const [];
  VideoSource? _active;
  bool _micOn = false;

  ui.Image? _frame;
  int _frameCount = 0;
  double _fps = 0;
  DateTime _fpsMark = DateTime.now();

  bool get _desktop => Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _enumerate();
  }

  @override
  void dispose() {
    _video.dispose();
    _mic.dispose();
    super.dispose();
  }

  void _enumerate() {
    try {
      Manager.instance.clear();
      registerCameras();
      registerMicrophones();
      if (_desktop) registerScreens();
      setState(() {
        _devices = enumerateDevices();
        _libError = null;
      });
    } catch (e) {
      setState(() => _libError = '$e');
    }
  }

  Future<bool> _ensurePermission(Permission p) async {
    if (!Platform.isAndroid) return true;
    final status = await p.request();
    return status.isGranted;
  }

  Future<void> _startVideo(VideoSource source) async {
    await _video.stop();
    if (source == VideoSource.camera &&
        !await _ensurePermission(Permission.camera)) {
      _toast('Camera permission denied');
      return;
    }
    setState(() {
      _active = source;
      _frame = null;
      _frameCount = 0;
      _fps = 0;
      _fpsMark = DateTime.now();
    });
    _video.frames.listen(
      (img) {
        _frameCount++;
        final now = DateTime.now();
        final dt = now.difference(_fpsMark).inMilliseconds;
        if (dt >= 500) {
          _fps = _frameCount * 1000 / dt;
          _frameCount = 0;
          _fpsMark = now;
        }
        if (mounted) setState(() => _frame = img);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _active = null);
          _toast('Capture failed: $e');
        }
      },
    );
    await _video.start(source);
  }

  Future<void> _stopVideo() async {
    await _video.stop();
    setState(() {
      _active = null;
      _frame = null;
    });
  }

  Future<void> _toggleMic() async {
    if (_micOn) {
      await _mic.stop();
      setState(() => _micOn = false);
      return;
    }
    if (!await _ensurePermission(Permission.microphone)) {
      _toast('Microphone permission denied');
      return;
    }
    await _mic.start();
    setState(() => _micOn = true);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('dart_usermedia — getUserMedia'),
        actions: [
          IconButton(
            tooltip: 'Re-enumerate',
            onPressed: _enumerate,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _libError != null
          ? _LibErrorView(error: _libError!)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 300, child: _sidebar()),
                const VerticalDivider(width: 1),
                Expanded(child: _preview()),
              ],
            ),
    );
  }

  Widget _sidebar() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Platform: ${Platform.operatingSystem}',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        const Text('Capture source',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _sourceChip('Camera', VideoSource.camera, Icons.videocam),
            _sourceChip('Videotest', VideoSource.videotest, Icons.animation),
            if (_desktop)
              _sourceChip('Screen', VideoSource.screen, Icons.desktop_windows),
          ],
        ),
        const SizedBox(height: 8),
        if (_active != null)
          FilledButton.tonalIcon(
            onPressed: _stopVideo,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        const Divider(height: 32),
        Row(
          children: [
            const Text('Microphone',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Switch(value: _micOn, onChanged: (_) => _toggleMic()),
          ],
        ),
        if (_micOn)
          StreamBuilder<double>(
            stream: _mic.levels,
            builder: (_, snap) => LinearProgressIndicator(
              value: snap.data ?? 0,
              minHeight: 8,
            ),
          ),
        const Divider(height: 32),
        Text('Devices (${_devices.length})',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._devices.map((d) => ListTile(
              dense: true,
              leading: Icon(switch (d.kind) {
                MediaDeviceType.videoInput => Icons.videocam,
                MediaDeviceType.audioInput => Icons.mic,
                MediaDeviceType.audioOutput => Icons.speaker,
              }),
              title:
                  Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(d.kind.name),
            )),
      ],
    );
  }

  Widget _sourceChip(String label, VideoSource src, IconData icon) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: _active == src,
      onSelected: (_) => _startVideo(src),
    );
  }

  Widget _preview() {
    if (_active == null) {
      return const Center(child: Text('Pick a capture source'));
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: _frame == null
                ? const CircularProgressIndicator()
                : RawImage(image: _frame, fit: BoxFit.contain),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _frame == null
                ? 'waiting for frames…'
                : '${_frame!.width}×${_frame!.height}  •  '
                    '${_fps.toStringAsFixed(1)} fps  •  ${_active!.name}',
          ),
        ),
      ],
    );
  }
}

class _LibErrorView extends StatelessWidget {
  const _LibErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text('Native library not found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'Build usermedia_ffi for this platform and make the shared '
              'library discoverable (see the example README). On desktop set '
              'USERMEDIA_FFI_PATH; on Android the .so ships in jniLibs.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
