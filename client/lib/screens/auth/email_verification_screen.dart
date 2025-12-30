import 'package:client/components/otp_pin_field.dart';
import 'package:client/screens/home.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _authService = AuthService();
  bool _isLoading = false;

  Future<void> _verifyEmail(String code) async {
    setState(() {
      _isLoading = true;
    });

    final result = await _authService.verifyEmail(
      email: widget.email,
      otp: code,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (!mounted) return;
      Fluttertoast.showToast(msg: 'Email verified successfully!');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const Home()),
        (Route<dynamic> route) => false,
      );
    } else {
      Fluttertoast.showToast(msg: result['error'] ?? 'Verification failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Verify Your Email',
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // const SizedBox(height: 60.0), // Removed as title is now in AppBar

              // Text(
              //   'Verify Your Email',
              //   style: Theme.of(context).textTheme.headlineSmall,
              // ),

              const SizedBox(height: 8),

              Text(
                'We sent a verification code to',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),

              const SizedBox(height: 4),

              Text(
                widget.email,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 48.0),

              OtpPinField(
                length: 6,
                onCompleted: (code) {
                  if (!_isLoading) {
                    _verifyEmail(code);
                  }
                },
              ),

              const SizedBox(height: 40.0),

              if (_isLoading)
                const CupertinoActivityIndicator(radius: 16.0)
              else
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    Fluttertoast.showToast(msg: 'Code resent!');
                  },
                  child: const Text(
                    "Didn't receive a code? Resend",
                    style: TextStyle(
                      fontSize: 13.0,
                      color: AppColors.primary,
                    ),
                  ),
                ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
