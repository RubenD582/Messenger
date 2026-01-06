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

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
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
        Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.textTertiary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
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
              vertical: 18,
              horizontal: 16,
            ),
            cursorColor: AppColors.primary,
            keyboardAppearance: Brightness.dark,
            decoration: null,
          ),
        ),
      ],
    );
  }
}
