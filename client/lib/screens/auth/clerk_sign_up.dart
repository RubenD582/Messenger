import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:email_validator/email_validator.dart';
import '../../components/apple_text_field.dart';
import '../../components/apple_button.dart';
import '../../services/clerk_service.dart';

/// Apple-style sign up screen with Clerk authentication
class ClerkSignUpScreen extends StatefulWidget {
  const ClerkSignUpScreen({super.key});

  @override
  State<ClerkSignUpScreen> createState() => _ClerkSignUpScreenState();
}

class _ClerkSignUpScreenState extends State<ClerkSignUpScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _clerkService = ClerkService();

  bool _isLoading = false;
  String? _firstNameError;
  String? _lastNameError;
  String? _emailError;
  String? _passwordError;
  String? _generalError;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    // Clear previous errors
    setState(() {
      _firstNameError = null;
      _lastNameError = null;
      _emailError = null;
      _passwordError = null;
      _generalError = null;
    });

    // Validate first name
    if (_firstNameController.text.trim().isEmpty) {
      setState(() => _firstNameError = 'First name is required');
      return;
    }

    // Validate last name
    if (_lastNameController.text.trim().isEmpty) {
      setState(() => _lastNameError = 'Last name is required');
      return;
    }

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
      // Attempt sign up
      final result = await _clerkService.signUpWithEmailPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Sign up successful - show success message and navigate back to sign in
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Account created successfully!'),
              backgroundColor: Colors.green.shade600,
            ),
          );

          // Navigate back to sign in screen
          Navigator.of(context).pop();
        }
      } else {
        // Sign up failed
        setState(() {
          _generalError = result['error'] ?? 'Sign up failed';
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Large title (Apple style)
              const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -1.2,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Join Messenger today',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade400,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 40),

              // First name field
              AppleTextField(
                label: 'First Name',
                placeholder: 'John',
                controller: _firstNameController,
                keyboardType: TextInputType.name,
                errorText: _firstNameError,
                autofocus: true,
              ),

              const SizedBox(height: 20),

              // Last name field
              AppleTextField(
                label: 'Last Name',
                placeholder: 'Doe',
                controller: _lastNameController,
                keyboardType: TextInputType.name,
                errorText: _lastNameError,
              ),

              const SizedBox(height: 20),

              // Email field
              AppleTextField(
                label: 'Email',
                placeholder: 'your@email.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
              ),

              const SizedBox(height: 20),

              // Password field
              AppleTextField(
                label: 'Password',
                placeholder: 'At least 8 characters',
                controller: _passwordController,
                obscureText: true,
                errorText: _passwordError,
                onSubmitted: (_) => _handleSignUp(),
              ),

              const SizedBox(height: 32),

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

              // Create account button
              AppleButton(
                text: 'Create Account',
                onPressed: _isLoading ? null : _handleSignUp,
                isLoading: _isLoading,
              ),

              const SizedBox(height: 24),

              // Terms and privacy
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'By creating an account, you agree to our Terms of Service and Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
