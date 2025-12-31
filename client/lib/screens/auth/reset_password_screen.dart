import 'package:client/components/apple_button.dart';
import 'package:client/components/textfield.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/theme/colors.dart';
import 'package:client/widgets/background_pattern.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? token;

  const ResetPasswordScreen({super.key, this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _newPasswordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (widget.token == null || widget.token!.isEmpty) {
      Fluttertoast.showToast(msg: 'Invalid or missing reset token.');
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      Fluttertoast.showToast(msg: 'Passwords do not match.');
      return;
    }

    if (_newPasswordController.text.length < 8) {
      Fluttertoast.showToast(msg: 'Password must be at least 8 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await _authService.resetPassword(
      token: widget.token!,
      newPassword: _newPasswordController.text,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (!mounted) return;
      Fluttertoast.showToast(msg: result['message'] ?? 'Password reset successfully!');
      // Navigate to sign-in screen or home
      Navigator.of(context).popUntil((route) => route.isFirst); // Go back to the first route (usually sign-in or splash)
    } else {
      Fluttertoast.showToast(msg: result['error'] ?? 'Failed to reset password.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Reset Password',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          const BackgroundPattern(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 48),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      'Please enter your new password.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 48),
                  CustomCupertinoTextField(
                    label: 'New Password',
                    hintText: 'Enter new password',
                    controller: _newPasswordController,
                    focusNode: _newPasswordFocusNode,
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  CustomCupertinoTextField(
                    label: 'Confirm New Password',
                    hintText: 'Re-enter new password',
                    controller: _confirmPasswordController,
                    focusNode: _confirmPasswordFocusNode,
                    obscureText: true,
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(
                          child: CupertinoActivityIndicator(radius: 16.0),
                        )
                      : AppleButton(
                          text: 'Reset Password',
                          onPressed: _resetPassword,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
