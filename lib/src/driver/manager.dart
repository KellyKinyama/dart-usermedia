// Ported from pion/mediadevices `pkg/driver/manager.go`.

import '../io/reader.dart';
import '../prop/media.dart';
import 'driver.dart';

/// Decides whether a driver is included in a query result.
typedef FilterFn = bool Function(Driver);

/// Drivers that can record video.
FilterFn filterVideoRecorder() => (d) => d is VideoRecorder;

/// Drivers that can record audio.
FilterFn filterAudioRecorder() => (d) => d is AudioRecorder;

/// Driver with the given id.
FilterFn filterId(String id) => (d) => d.id() == id;

/// Drivers matching device type [t].
FilterFn filterDeviceType(DeviceType t) => (d) => d.info().deviceType == t;

/// Logical AND of [filters].
FilterFn filterAnd(List<FilterFn> filters) =>
    (d) => filters.every((f) => f(d));

/// Logical NOT of [filter].
FilterFn filterNot(FilterFn filter) => (d) => !filter(d);

/// Singleton registry of drivers (pion `driver.Manager`).
class Manager {
  Manager._();
  static final Manager instance = Manager._();

  final Map<String, Driver> _drivers = {};
  int _seq = 0;

  /// Registers [adapter] with [info], returning the generated driver id.
  String register(Adapter adapter, Info info) {
    final d = _wrapAdapter(adapter, info, _seq++);
    _drivers[d.id()] = d;
    return d.id();
  }

  /// Returns drivers matching [filter].
  List<Driver> query(FilterFn filter) =>
      _drivers.values.where(filter).toList(growable: false);

  /// Removes a driver by id.
  void delete(String id) => _drivers.remove(id);

  /// Test/support hook: clears the registry.
  void clear() => _drivers.clear();
}

Driver _wrapAdapter(Adapter a, Info info, int seq) {
  final id = '${info.deviceType.name}-${info.label}-$seq';
  final isVideo = a is VideoRecorder;
  final isAudio = a is AudioRecorder;
  if (isVideo && isAudio) return _DriverVideoAudio(a, info, id);
  if (isVideo) return _DriverVideo(a, info, id);
  if (isAudio) return _DriverAudio(a, info, id);
  return _DriverBase(a, info, id);
}

class _DriverBase implements Driver {
  _DriverBase(this._adapter, this._info, this._id);

  final Adapter _adapter;
  final Info _info;
  final String _id;
  DriverState _state = DriverState.closed;

  @override
  String id() => _id;
  @override
  Info info() => _info;
  @override
  DriverState status() => _state;

  @override
  void open() {
    _adapter.open();
    _state = DriverState.running;
  }

  @override
  void close() {
    _adapter.close();
    _state = DriverState.closed;
  }

  @override
  List<Media> properties() => _adapter.properties();
}

class _DriverVideo extends _DriverBase implements VideoRecorder {
  _DriverVideo(super.adapter, super.info, super.id);
  @override
  VideoReader videoRecord(Media property) =>
      (_adapter as VideoRecorder).videoRecord(property);
}

class _DriverAudio extends _DriverBase implements AudioRecorder {
  _DriverAudio(super.adapter, super.info, super.id);
  @override
  AudioReader audioRecord(Media property) =>
      (_adapter as AudioRecorder).audioRecord(property);
}

class _DriverVideoAudio extends _DriverBase
    implements VideoRecorder, AudioRecorder {
  _DriverVideoAudio(super.adapter, super.info, super.id);
  @override
  VideoReader videoRecord(Media property) =>
      (_adapter as VideoRecorder).videoRecord(property);
  @override
  AudioReader audioRecord(Media property) =>
      (_adapter as AudioRecorder).audioRecord(property);
}
