import 'package:client/screens/auth/forgot_password_screen.dart'; // Import ForgotPasswordScreen
import 'package:client/components/apple_button.dart';
import 'package:client/components/textfield.dart';
import 'package:client/screens/auth/auth_2fa_verification.dart';
import 'package:client/screens/auth/signup_screen.dart';
import 'package:client/screens/home.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _use2FA = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      Fluttertoast.showToast(msg: 'Please fill in all fields');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await _authService.loginWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      use2FA: _use2FA,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (result['requires2FA'] == true) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => Auth2FAVerificationScreen(
              email: _emailController.text.trim(),
            ),
          ),
        );
      } else {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const Home()),
          (Route<dynamic> route) => false,
        );
      }
    }
    else {
      Fluttertoast.showToast(msg: result['error'] ?? 'Login failed');
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
          'Sign In',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, // Changed from Icons.arrow_back_ios_new
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // const SizedBox(height: 40), // Removed this SizedBox

              const SizedBox(height: 48), // Changed back to 48

              CustomCupertinoTextField(
                label: 'Email',
                hintText: 'Enter your email',
                controller: _emailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 16),

              CustomCupertinoTextField(
                label: 'Password',
                hintText: 'Enter your password',
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                obscureText: true,
              ),

              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0.0),
                  onPressed: () {
                    // Navigate to Forgot Password Screen
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ForgotPasswordScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: AppColors.purpleAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Row(
              //   children: [
              //     CupertinoSwitch(
              //       value: _use2FA,
              //       onChanged: (value) {
              //         setState(() {
              //           _use2FA = value;
              //         });
              //       },
              //       activeTrackColor: AppColors.primary,
              //     ),
              //     const SizedBox(width: 12),
              //     const Text(
              //       'Use Two-Factor Authentication',
              //       style: TextStyle(
              //         color: AppColors.textSecondary,
              //         fontSize: 15,
              //       ),
              //     ),
              //   ],
              // ),

              const SizedBox(height: 24),

              _isLoading
                  ? const Center(
                      child: CupertinoActivityIndicator(radius: 16.0),
                    )
                  : AppleButton(
                      text: 'Sign In',
                      onPressed: _signIn,
                    ),

              const SizedBox(height: 24),

              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SignUpScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: AppColors.purpleAccent, // Changed to purpleAccent
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
