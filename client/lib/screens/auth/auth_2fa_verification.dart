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
        title: const Text(
          'Verify Identity',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

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
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Fluttertoast.showToast(msg: 'Code resent!');
                    },
                    child: const Text(
                      "Didn't receive a code? Tap here",
                      style: TextStyle(
                        fontSize: 14.0,
                        color: Colors.white,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
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
