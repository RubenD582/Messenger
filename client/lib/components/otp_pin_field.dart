import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpPinField extends StatefulWidget {
  final int length;
  final ValueChanged<String> onCompleted;
  final double fieldWidth;
  final double fieldHeight;
  final double spacing;

  const OtpPinField({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.fieldWidth = 48.0,
    this.fieldHeight = 50.0,
    this.spacing = 12.0,
  });

  @override
  State<OtpPinField> createState() => _OtpPinFieldState();
}

class _OtpPinFieldState extends State<OtpPinField> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.length,
      (index) => TextEditingController(),
    );
    _focusNodes = List.generate(
      widget.length,
      (index) => FocusNode(),
    );
    for (var node in _focusNodes) {
      node.addListener(() {
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _checkCompletion();
      }
    }
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  void _checkCompletion() {
    String code = _controllers.map((c) => c.text).join();
    if (code.length == widget.length) {
      widget.onCompleted(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        widget.length,
        (index) => Container(
          margin: EdgeInsets.only(
            right: index < widget.length - 1 ? widget.spacing : 0,
          ),
          child: _buildPinField(index),
        ),
      ),
    );
  }

  Widget _buildPinField(int index) {
    return Container(
      width: widget.fieldWidth,
      height: widget.fieldHeight,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: AppColors.textTertiary.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: CupertinoTextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (value) => _onChanged(value, index),
        onTap: () {
          if (_controllers[index].text.isNotEmpty) {
            _controllers[index].clear();
          }
        },
        onSubmitted: (_) {
          if (index < widget.length - 1) {
            _focusNodes[index + 1].requestFocus();
          } else {
            _checkCompletion();
          }
        },
        onEditingComplete: () {
          _onBackspace(index);
        },
      ),
    );
  }
}
