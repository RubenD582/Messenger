import 'package:flutter/material.dart';
import 'dart:math' as math;

class SegmentedStatusRing extends StatelessWidget {
  final int segmentCount;
  final int viewedCount;
  final double size;
  final double strokeWidth;
  final Widget child;
  final List<Color> gradientColors;

  const SegmentedStatusRing({
    super.key,
    required this.segmentCount,
    this.viewedCount = 0,
    required this.size,
    this.strokeWidth = 3.0,
    required this.child,
    this.gradientColors = const [Color(0xFF4192EF), Color(0xFF4192EF)], // Changed to the specified blue
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Draw the segmented ring
          CustomPaint(
            size: Size(size, size),
            painter: _SegmentedRingPainter(
              segmentCount: segmentCount,
              viewedCount: viewedCount,
              strokeWidth: strokeWidth,
              gradientColors: gradientColors, 
            ),
          ),
          // Black background circle
          Container(
            width: size - (strokeWidth * 2),
            height: size - (strokeWidth * 2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black,
            ),
          ),
          // Child (profile picture)
          child,
        ],
      ),
    );
  }
}

class _SegmentedRingPainter extends CustomPainter {
  final int segmentCount;
  final int viewedCount;
  final double strokeWidth;
  final List<Color> gradientColors; // Still keep for potential custom gradients

  _SegmentedRingPainter({
    required this.segmentCount,
    required this.viewedCount,
    required this.strokeWidth,
    required this.gradientColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Gap between segments in degrees
    final gapDegrees = segmentCount > 1 ? 9.0 : 0.0;

    // Calculate degrees per segment
    final totalGapDegrees = gapDegrees * segmentCount;
    final totalSegmentDegrees = 360.0 - totalGapDegrees;
    final degreesPerSegment = totalSegmentDegrees / segmentCount;

    // Draw each segment
    for (int i = 0; i < segmentCount; i++) {
      // Determine color based on whether this segment has been viewed
      final isViewed = i < viewedCount;
      final segmentColor = isViewed
          ? const Color(0xFF48484A) // Lighter grey for viewed segments
          : const Color(0xFF4192EF); // Changed to the specified blue for unviewed
      
      final paint = Paint()
        ..color = segmentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round; // Rounded edges

      // Start angle for this segment (in radians)
      // Start from top (-90 degrees) and go clockwise
      final startAngleDegrees = -90 + (i * (degreesPerSegment + gapDegrees));
      final startAngle = startAngleDegrees * (math.pi / 180);

      // Sweep angle (in radians)
      final sweepAngle = degreesPerSegment * (math.pi / 180);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
