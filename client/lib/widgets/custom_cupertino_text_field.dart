import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CustomCupertinoTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  const CustomCupertinoTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  State<CustomCupertinoTextField> createState() =>
      _CustomCupertinoTextFieldState();
}

class _CustomCupertinoTextFieldState
    extends State<CustomCupertinoTextField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (!mounted) return;
    setState(() {
      _isFocused = widget.focusNode?.hasFocus ?? false;
    });
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isFocused
              ? AppColors.primary
              : AppColors.textTertiary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: CupertinoTextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: (_) => widget.onSubmitted?.call(),
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
        placeholder: widget.hintText,
        placeholderStyle: const TextStyle(
          fontSize: 15,
          color: AppColors.textTertiary,
        ),
        padding: EdgeInsets.zero,
        decoration: null, // IMPORTANT: removes Cupertino default border
      ),
    );
  }
}
