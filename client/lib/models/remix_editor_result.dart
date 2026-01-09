import 'dart:typed_data';

class RemixEditorResult {
  final Uint8List overlayImageBytes;
  final double normalizedCenterX;
  final double normalizedCenterY;
  final double scale;
  final double rotation;

  RemixEditorResult({
    required this.overlayImageBytes,
    required this.normalizedCenterX,
    required this.normalizedCenterY,
    required this.scale,
    required this.rotation,
  });
}
