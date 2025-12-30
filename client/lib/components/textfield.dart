import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CustomCupertinoTextField extends StatefulWidget {
  final String hintText;
  final String? label;
  final bool obscureText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputType? keyboardType;

  const CustomCupertinoTextField({
    super.key,
    required this.hintText,
    required this.controller,
    required this.focusNode,
    this.label,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  _CustomCupertinoTextFieldState createState() =>
      _CustomCupertinoTextFieldState();
}

class _CustomCupertinoTextFieldState extends State<CustomCupertinoTextField> {
  late bool _obscureText;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = widget.focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // if (widget.label != null) ...[
        //   Padding(
        //     padding: const EdgeInsets.only(left: 4, bottom: 8),
        //     child: Text(
        //       widget.label!,
        //       style: const TextStyle(
        //         color: AppColors.textPrimary,
        //         fontSize: 14,
        //         fontWeight: FontWeight.w600,
        //         letterSpacing: 0.2,
        //       ),
        //     ),
        //   ),
        // ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? AppColors.primary
                  : AppColors.textTertiary.withValues(alpha: 0.2),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  obscureText: _obscureText,
                  keyboardType: widget.keyboardType,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  placeholder: widget.hintText,
                  placeholderStyle: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  cursorColor: AppColors.primary,
                  keyboardAppearance: Brightness.dark,
                  decoration: null,
                ),
              ),
              if (widget.obscureText)
                CupertinoButton(
                  padding: const EdgeInsets.only(right: 12),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                  child: Icon(
                    _obscureText
                        ? CupertinoIcons.eye_slash_fill
                        : CupertinoIcons.eye_fill,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
