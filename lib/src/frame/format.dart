/// Ported from pion/mediadevices `pkg/frame` (frame.Format).
///
/// A raw frame pixel/buffer format. Modeled as a value type wrapping the
/// format string so unknown formats round-trip like they do in Go.
class FrameFormat {
  const FrameFormat(this.value);

  final String value;

  // Known formats (mirrors pion's frame format constants).
  static const FrameFormat unknown = FrameFormat('');
  static const FrameFormat i420 = FrameFormat('I420');
  static const FrameFormat nv21 = FrameFormat('NV21');
  static const FrameFormat nv12 = FrameFormat('NV12');
  static const FrameFormat yuy2 = FrameFormat('YUY2');
  static const FrameFormat uyvy = FrameFormat('UYVY');
  static const FrameFormat z16 = FrameFormat('Z16');
  static const FrameFormat rgba = FrameFormat('RGBA');
  static const FrameFormat mjpeg = FrameFormat('MJPEG');

  /// 32-bit RGB with a padding byte (B,G,R,X), as delivered by Media Foundation.
  static const FrameFormat rgb32 = FrameFormat('RGB32');

  /// 32-bit BGRA, as delivered by DXGI Desktop Duplication.
  static const FrameFormat bgra = FrameFormat('BGRA');

  @override
  bool operator ==(Object other) =>
      other is FrameFormat && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
