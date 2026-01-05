import 'package:flutter/material.dart';

class DismissibleStatusWrapper extends StatefulWidget {
  final Widget child;

  const DismissibleStatusWrapper({
    super.key,
    required this.child,
  });

  @override
  State<DismissibleStatusWrapper> createState() =>
      _DismissibleStatusWrapperState();
}

class _DismissibleStatusWrapperState extends State<DismissibleStatusWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dragController;

  static const double _dismissThresholdRatio = 0.25; // drag % to dismiss
  static const double _maxScale = 0.92; // scale at max drag

  double _dragVerticalDelta = 0.0;

  @override
  void initState() {
    super.initState();
    _dragController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      upperBound: 1.0,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragVerticalDelta += details.delta.dy;
    final screenHeight = MediaQuery.of(context).size.height;
    _dragVerticalDelta = _dragVerticalDelta.clamp(0.0, screenHeight);
    _dragController.value = _dragVerticalDelta / screenHeight;
  }

  void _handleDragEnd(DragEndDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    if (_dragVerticalDelta > screenHeight * _dismissThresholdRatio) {
      Navigator.of(context).pop();
    } else {
      _dragController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      ).then((_) => _dragVerticalDelta = 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      child: AnimatedBuilder(
        animation: _dragController,
        builder: (context, child) {
          final dragProgress = _dragController.value;

          final size = MediaQuery.of(context).size;

          // Move the page down with finger
          final translateY = dragProgress * size.height;

          // Scale slightly
          final scale = 1.0 - dragProgress * (1.0 - _maxScale);

          // Corners grow faster and can become a semi-circle
          final borderRadius =(dragProgress * 2).clamp(0.0, 1.0) * (size.width / 4);

          return Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(borderRadius),
                ),
                child: child,
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _dragController.dispose();
    super.dispose();
  }
}
