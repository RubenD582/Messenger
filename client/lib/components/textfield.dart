import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CustomCupertinoTextField extends StatefulWidget {
  final String hintText;
  final bool obscureText;
  final TextEditingController controller;
  final FocusNode focusNode;

  const CustomCupertinoTextField({
    super.key,
    required this.hintText,
    required this.controller,
    required this.focusNode,
    this.obscureText = false, 
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
      children: [
        // Row(
        //   children: [
        //     Padding(
        //       padding: const EdgeInsets.symmetric(horizontal: 5),
        //       child: Text(
        //         'Enter your ${widget.hintText}',
        //         textAlign: TextAlign.left,
        //           style: TextStyle(
        //             color: Color(0xFF999999),
        //             fontSize: 13,
        //             fontWeight: FontWeight.w400,
        //           ),
        //       ),
        //     ),
        //   ],
        // ),
        // const SizedBox(height: 3),
        Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: CupertinoTextField(
            controller: widget.controller,
            obscureText: _obscureText,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            placeholder: widget.hintText,
            placeholderStyle: const TextStyle(color: Color(0xFF89898D), fontSize: 15),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            cursorColor: Colors.blue, // Set cursor color to blue
            keyboardAppearance: Brightness.dark,
            decoration: BoxDecoration(
              color: Color(0xFF212121),
              borderRadius: BorderRadius.circular(10),
              // border: Border.all(color: const Color(0xFF363639), width: 1), // Default border
            ),
            onTap: () {
              // Optional: You can update the border color on focus manually if needed
            },
          ),
        ),

      ],
    );
  }
}
