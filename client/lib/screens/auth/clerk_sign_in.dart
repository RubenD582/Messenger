import 'package:client/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:email_validator/email_validator.dart';
import '../../components/apple_text_field.dart';
import '../../components/apple_button.dart';
import '../../services/clerk_service.dart';
import 'clerk_2fa_verification.dart';
import 'clerk_sign_up.dart';
import '../home.dart';

/// Apple-style sign in screen with Clerk authentication
class ClerkSignInScreen extends StatefulWidget {
  const ClerkSignInScreen({super.key});

  @override
  State<ClerkSignInScreen> createState() => _ClerkSignInScreenState();
}

class _ClerkSignInScreenState extends State<ClerkSignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _clerkService = ClerkService();

  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;
  String? _generalError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    // Clear previous errors
    setState(() {
      _emailError = null;
      _passwordError = null;
      _generalError = null;
    });

    // Validate email
    if (_emailController.text.trim().isEmpty) {
      setState(() => _emailError = 'Email is required');
      return;
    }

    if (!EmailValidator.validate(_emailController.text.trim())) {
      setState(() => _emailError = 'Please enter a valid email');
      return;
    }

    // Validate password
    if (_passwordController.text.isEmpty) {
      setState(() => _passwordError = 'Password is required');
      return;
    }

    if (_passwordController.text.length < 8) {
      setState(() => _passwordError = 'Password must be at least 8 characters');
      return;
    }

    // Show loading
    setState(() => _isLoading = true);

    try {
      // Attempt sign in
      final result = await _clerkService.signInWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Sign in successful - navigate to home
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const Home()),
        );
      } else if (result['requires2FA'] == true) {
        // 2FA required - navigate to 2FA screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => Clerk2FAVerificationScreen(
              signInId: result['signInId'],
            ),
          ),
        );
      } else {
        // Sign in failed
        setState(() {
          _generalError = result['error'] ?? 'Sign in failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generalError = 'An unexpected error occurred';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),

              // Large title (Apple style)
              const Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -1.2,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Welcome back to Messenger',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade400,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 48),

              // Email field
              AppleTextField(
                label: 'Email',
                placeholder: 'your@email.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                autofocus: true,
                onSubmitted: (_) => _handleSignIn(),
              ),

              const SizedBox(height: 20),

              // Password field
              AppleTextField(
                label: 'Password',
                placeholder: 'Enter your password',
                controller: _passwordController,
                obscureText: true,
                errorText: _passwordError,
                onSubmitted: (_) => _handleSignIn(),
              ),

              const SizedBox(height: 12),

              // Forgot password (future feature)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // TODO: Implement forgot password
                  },
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade400,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // General error message
              if (_generalError != null)
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
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_triangle_fill,
                        color: Colors.red.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _generalError!,
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

              // Sign in button
              AppleButton(
                text: 'Sign In',
                onPressed: _isLoading ? null : _handleSignIn,
                isLoading: _isLoading,
              ),

              const SizedBox(height: 32),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Create account button
              AppleButton(
                text: 'Create Account',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ClerkSignUpScreen(),
                    ),
                  );
                },
                isSecondary: true,
              ),

              const SizedBox(height: 48),

              // Footer text
              Center(
                child: Text(
                  'Secured by Clerk',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
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
