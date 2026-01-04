import 'dart:math';
import 'package:flutter/material.dart';

/// A page route that animates with a circular reveal effect expanding from an origin point
class CircularRevealPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final Offset originOffset; // Circle center (tap position)
  final double originRadius; // Starting circle radius

  CircularRevealPageRoute({
    required this.builder,
    required this.originOffset,
    this.originRadius = 32.0, // Default: Status circle radius
    RouteSettings? settings,
  }) : super(settings: settings);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic, // Smooth reverse animation
    );

    // Faster fade animation
    final fadeAnimation = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      reverseCurve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: AnimatedBuilder(
        animation: curvedAnimation,
        builder: (context, child) {
          final screenSize = MediaQuery.of(context).size;
          final maxRadius = _calculateMaxRadius(screenSize, originOffset);
          final currentRadius =
              originRadius + (maxRadius - originRadius) * curvedAnimation.value;

          return ClipPath(
            clipper: CircularRevealClipper(
              center: originOffset,
              radius: currentRadius,
            ),
            child: child!,
          );
        },
        child: child,
      ),
    );
  }

  /// Calculate the maximum radius needed to cover the entire screen
  /// This is the distance from the origin to the farthest corner
  double _calculateMaxRadius(Size screenSize, Offset center) {
    final dx = max(center.dx, screenSize.width - center.dx);
    final dy = max(center.dy, screenSize.height - center.dy);
    return sqrt(dx * dx + dy * dy);
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;
}

/// Custom clipper that creates a circular clip path
class CircularRevealClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;

  CircularRevealClipper({
    required this.center,
    required this.radius,
  });

  @override
  Path getClip(Size size) {
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(CircularRevealClipper oldClipper) {
    return oldClipper.radius != radius || oldClipper.center != center;
  }
}
