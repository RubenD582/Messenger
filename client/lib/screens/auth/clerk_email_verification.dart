import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../components/apple_button.dart';
import '../../services/clerk_service.dart';
import '../home.dart';

/// Email verification screen with PIN code input
class ClerkEmailVerificationScreen extends StatefulWidget {
  final String signUpId;
  final String email;

  const ClerkEmailVerificationScreen({
    super.key,
    required this.signUpId,
    required this.email,
  });

  @override
  State<ClerkEmailVerificationScreen> createState() => _ClerkEmailVerificationScreenState();
}

class _ClerkEmailVerificationScreenState extends State<ClerkEmailVerificationScreen> {
  final _pinController = TextEditingController();
  final _clerkService = ClerkService();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    if (_pinController.text.length != 6) {
      setState(() => _error = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _clerkService.verifyEmail(
        widget.signUpId,
        _pinController.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Email verification successful - navigate to home
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const Home()),
        );
      } else {
        // Verification failed
        setState(() {
          _error = result['error'] ?? 'Invalid verification code';
          _pinController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'An unexpected error occurred';
          _pinController.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _maskedEmail {
    final parts = widget.email.split('@');
    if (parts.length != 2) return widget.email;

    final username = parts[0];
    final domain = parts[1];

    if (username.length <= 2) {
      return '${username[0]}***@$domain';
    }

    return '${username.substring(0, 2)}***@$domain';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF5856D6).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.mail_solid,
                  size: 40,
                  color: Color(0xFF5856D6),
                ),
              ),

              const SizedBox(height: 32),

              // Title
              const Text(
                'Verify Your Email',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -1.2,
                ),
              ),

              const SizedBox(height: 16),

              // Description
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade400,
                    letterSpacing: -0.4,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to\n'),
                    TextSpan(
                      text: _maskedEmail,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // PIN code field
              PinCodeTextField(
                appContext: context,
                length: 6,
                controller: _pinController,
                autoFocus: true,
                enableActiveFill: true,
                keyboardType: TextInputType.number,
                textStyle: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(12),
                  fieldHeight: 56,
                  fieldWidth: 48,
                  activeFillColor: Colors.grey.shade900,
                  inactiveFillColor: Colors.grey.shade900,
                  selectedFillColor: Colors.grey.shade800,
                  activeColor: const Color(0xFF5856D6),
                  inactiveColor: Colors.grey.shade800,
                  selectedColor: const Color(0xFF5856D6),
                  borderWidth: 2,
                ),
                onCompleted: (_) => _handleVerify(),
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
              ),

              const SizedBox(height: 24),

              // Error message
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.shade700,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_triangle_fill,
                        color: Colors.red.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.red.shade300,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Verify button
              AppleButton(
                text: 'Verify Email',
                onPressed: _isLoading ? null : _handleVerify,
                isLoading: _isLoading,
              ),

              const SizedBox(height: 24),

              // Resend code button
              TextButton(
                onPressed: () {
                  // TODO: Implement resend code
                },
                child: Text(
                  'Resend Code',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade400,
                    letterSpacing: -0.4,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Different email
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Use Different Email',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: -0.3,
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
