import 'package:client/components/otp_pin_field.dart';
import 'package:client/screens/home.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class Auth2FAVerificationScreen extends StatefulWidget {
  final String email;

  const Auth2FAVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<Auth2FAVerificationScreen> createState() =>
      _Auth2FAVerificationScreenState();
}

class _Auth2FAVerificationScreenState
    extends State<Auth2FAVerificationScreen> {
  final _authService = AuthService();
  bool _isLoading = false;

  Future<void> _verify2FA(String code) async {
    setState(() {
      _isLoading = true;
    });

    final result = await _authService.verify2FA(
      email: widget.email,
      otp: code,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (!mounted) return;
      Fluttertoast.showToast(msg: 'Verification successful!');
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
              const SizedBox(height: 60.0),

              // Title
              Text(
                'Verify Your Identity',
                style: Theme.of(context).textTheme.headlineSmall,
              ),

              // Subtitle
              Text(
                'We sent a verification code to',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),

              Text(
                widget.email,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 48.0),

              // OTP Input
              OtpPinField(
                length: 6,
                onCompleted: (code) {
                  if (!_isLoading) {
                    _verify2FA(code);
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
                    // TODO: Implement resend code functionality
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
