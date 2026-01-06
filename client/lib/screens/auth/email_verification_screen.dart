import 'package:client/components/otp_pin_field.dart';
import 'package:client/screens/home.dart';
import 'package:client/services/auth_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
        title: SvgPicture.asset(
          'assets/way.svg',
          height: 24,
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

              const Text(
                'An OTP has been sent to',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),

              Text(
                widget.email,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
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
