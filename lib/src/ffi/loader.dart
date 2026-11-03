// Locates and opens the native usermedia_ffi shared library.

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown when the native usermedia_ffi library cannot be located or opened.
class NativeLibraryNotFoundError extends Error {
  NativeLibraryNotFoundError(this.message);
  final String message;
  @override
  String toString() => 'NativeLibraryNotFoundError: $message';
}

/// Platform-specific base file name for the shared library.
String get _libFileName {
  if (Platform.isWindows) return 'usermedia_ffi.dll';
  if (Platform.isMacOS) return 'libusermedia_ffi.dylib';
  return 'libusermedia_ffi.so';
}

/// Candidate directories to search, in priority order.
Iterable<String> _searchDirs() sync* {
  // 1. Explicit override for development / CI.
  final override = Platform.environment['USERMEDIA_FFI_PATH'];
  if (override != null && override.isNotEmpty) yield override;

  // 2. Common CMake build output locations relative to the package root.
  final root = _packageRoot();
  if (root != null) {
    final base = p.join(root, 'native', 'usermedia_ffi', 'build');
    yield base;
    yield p.join(base, 'Release');
    yield p.join(base, 'Debug');
  }

  // 3. Next to the running executable.
  yield p.dirname(Platform.resolvedExecutable);
}

/// Best-effort package root (walks up looking for pubspec.yaml).
String? _packageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// Opens the native library, trying each candidate location.
DynamicLibrary openUserMediaLibrary() {
  final tried = <String>[];
  for (final dir in _searchDirs()) {
    final candidate = p.join(dir, _libFileName);
    tried.add(candidate);
    if (File(candidate).existsSync()) {
      return DynamicLibrary.open(candidate);
    }
  }
  // Last resort: let the OS resolve it from the default search path.
  try {
    return DynamicLibrary.open(_libFileName);
  } on ArgumentError {
    throw NativeLibraryNotFoundError(
      'Could not find $_libFileName. Tried:\n  ${tried.join('\n  ')}\n'
      'Build it with CMake (see native/usermedia_ffi/CMakeLists.txt) or set '
      'USERMEDIA_FFI_PATH to the directory containing the library.',
    );
  }
}

DynamicLibrary? _cached;

/// Opens the native library once and caches the handle for reuse by the
/// backend and the native drivers.
DynamicLibrary userMediaLibrary() => _cached ??= openUserMediaLibrary();
