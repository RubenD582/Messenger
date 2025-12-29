import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// Apple-style text field component
///
/// Follows Apple Human Interface Guidelines with:
/// - Clean, minimal design
/// - Smooth animations
/// - Clear focus states
/// - Dark theme support
class AppleTextField extends StatefulWidget {
  final String label;
  final String? placeholder;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? errorText;
  final bool autofocus;
  final FocusNode? focusNode;
  final Function(String)? onChanged;
  final Function(String)? onSubmitted;

  const AppleTextField({
    super.key,
    required this.label,
    this.placeholder,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.errorText,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<AppleTextField> createState() => _AppleTextFieldState();
}

class _AppleTextFieldState extends State<AppleTextField> {
  late FocusNode _internalFocusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = widget.focusNode ?? FocusNode();
    _internalFocusNode.addListener(() {
      setState(() {
        _isFocused = _internalFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: hasError
                  ? Colors.red.shade400
                  : Colors.grey.shade300,
              letterSpacing: -0.2,
            ),
          ),
        ),

        // Text field container
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasError
                  ? Colors.red.shade400
                  : _isFocused
                      ? const Color(0xFF5856D6) // iOS purple
                      : Colors.grey.shade800,
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _internalFocusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              color: Colors.white,
              letterSpacing: -0.4,
            ),
            decoration: InputDecoration(
              hintText: widget.placeholder ?? widget.label,
              hintStyle: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 17,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.4,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),

        // Error text
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_circle_fill,
                  size: 14,
                  color: Colors.red.shade400,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.errorText!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
