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
  final bool _use2FA = false;

  @override
  void initState() {
    super.initState();
    // Auto-focus email field to show keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocusNode.requestFocus();
    });
    // Listen to text changes to update button state
    _emailController.addListener(_updateButtonState);
    _passwordController.addListener(_updateButtonState);
  }

  void _updateButtonState() {
    setState(() {});
  }

  @override
  void dispose() {
    _emailController.removeListener(_updateButtonState);
    _passwordController.removeListener(_updateButtonState);
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
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

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

              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SignUpScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Don\'t have an account? Tap here',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      TextSpan(text: 'By continuing, you agree to our\n'),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: _isLoading
                    ? const Center(
                        child: CupertinoActivityIndicator(radius: 16.0),
                      )
                    : GestureDetector(
                        onTap: (_emailController.text.isNotEmpty &&
                               _passwordController.text.isNotEmpty)
                            ? _signIn
                            : null,
                        child: Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            color: (_emailController.text.isNotEmpty &&
                                   _passwordController.text.isNotEmpty)
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Sign In',
                            style: TextStyle(
                              color: (_emailController.text.isNotEmpty &&
                                     _passwordController.text.isNotEmpty)
                                  ? Colors.black
                                  : Colors.black.withValues(alpha: 0.4),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
