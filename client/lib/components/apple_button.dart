import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// Apple-style button component
///
/// Follows Apple Human Interface Guidelines with:
/// - Primary and secondary styles
/// - Loading states
/// - Smooth press animations
/// - Dark theme support
class AppleButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSecondary;
  final bool isDestructive;

  const AppleButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    this.isDestructive = false,
  });

  @override
  State<AppleButton> createState() => _AppleButtonState();
}

class _AppleButtonState extends State<AppleButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  Color get _buttonColor {
    if (widget.isDestructive) {
      return Colors.red.shade600;
    } else if (widget.isSecondary) {
      return Colors.grey.shade800;
    } else {
      return const Color(0xFF5856D6); // iOS purple
    }
  }

  Color get _textColor {
    if (widget.isSecondary) {
      return Colors.white;
    } else {
      return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.isLoading;

    return GestureDetector(
      onTapDown: isDisabled ? null : _handleTapDown,
      onTapUp: isDisabled ? null : _handleTapUp,
      onTapCancel: isDisabled ? null : _handleTapCancel,
      onTap: isDisabled ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: isDisabled ? 1.0 : _scaleAnimation.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              height: 45,
              decoration: BoxDecoration(
                color: isDisabled
                    ? _buttonColor.withOpacity(0.5)
                    : _buttonColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: isDisabled
                    ? []
                    : [
                        BoxShadow(
                          color: _buttonColor.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Center(
                child: widget.isLoading
                    ? const CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 12,
                      )
                    : Text(
                        widget.text,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDisabled
                              ? _textColor.withOpacity(0.5)
                              : _textColor,
                          letterSpacing: -0.4,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
