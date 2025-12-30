import 'package:client/components/apple_button.dart';
import 'package:client/components/textfield.dart';
import 'package:client/screens/auth/email_verification_screen.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  final AuthService _authService = AuthService();
  bool _isLoading = false;

  String _currentPageTitle = "What's your name?"; // Initialize with the first step's title

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_updatePageTitle);
  }

  void _updatePageTitle() {
    if (_pageController.page == null) return;
    setState(() {
      if (_pageController.page! < 0.5) {
        _currentPageTitle = "What's your name?";
      } else if (_pageController.page! < 1.5) {
        _currentPageTitle = "What's your email?";
      } else {
        _currentPageTitle = "Create a password";
      }
    });
  }

  @override
  void dispose() {
    _pageController.removeListener(_updatePageTitle);
    _pageController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      Fluttertoast.showToast(msg: 'Passwords do not match');
      return;
    }

    if (_passwordController.text.length < 8) {
      Fluttertoast.showToast(msg: 'Password must be at least 8 characters');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await _authService.registerWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => EmailVerificationScreen(
            email: _emailController.text.trim(),
          ),
        ),
      );
    } else {
      Fluttertoast.showToast(msg: result['error'] ?? 'Registration failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _currentPageTitle,
          style: const TextStyle(
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
            if (_pageController.page == 0) {
              Navigator.of(context).pop();
            } else {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          },
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildStep(
            // title: "What's your name?", // Removed
            description: "To help your friends recognize you.",
            fields: [
              CustomCupertinoTextField(
                label: 'First Name',
                hintText: 'Enter first name',
                controller: _firstNameController,
                focusNode: _firstNameFocusNode,
              ),
              const SizedBox(height: 16),
              CustomCupertinoTextField(
                label: 'Last Name',
                hintText: 'Enter last name',
                controller: _lastNameController,
                focusNode: _lastNameFocusNode,
              ),
            ],
            onNext: () {
              if (_firstNameController.text.trim().isEmpty ||
                  _lastNameController.text.trim().isEmpty) {
                Fluttertoast.showToast(msg: 'Please enter your name');
                return;
              }
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
          _buildStep(
            // title: "What's your email?", // Removed
            description: "You'll use this to sign in.",
            fields: [
              CustomCupertinoTextField(
                label: 'Email',
                hintText: 'Enter your email',
                controller: _emailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
              ),
            ],
            onNext: () {
              final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
              if (!emailRegex.hasMatch(_emailController.text.trim())) {
                Fluttertoast.showToast(msg: 'Please enter a valid email');
                return;
              }
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
          _buildStep(
            // title: 'Create a password', // Removed
            description: "Make sure it's at least 8 characters long.",
            fields: [
              CustomCupertinoTextField(
                label: 'Password',
                hintText: 'Enter password',
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              CustomCupertinoTextField(
                label: 'Confirm Password',
                hintText: 'Re-enter password',
                controller: _confirmPasswordController,
                focusNode: _confirmPasswordFocusNode,
                obscureText: true,
              ),
            ],
            onNext: _signUp,
            buttonText: 'Sign Up',
          ),
        ],
      ),
    );
  }

  Widget _buildStep({
    // removed title: required String title,
    String? description,
    required List<Widget> fields,
    required VoidCallback onNext,
    String buttonText = 'Continue',
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Centered the whole column
        children: [
          // const SizedBox(height: 20), // Removed this SizedBox

          if (description != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 48), // Changed back to 48

          ...fields,

          const SizedBox(height: 48),

          _isLoading
              ? const Center(
                  child: CupertinoActivityIndicator(radius: 16.0),
                )
              : AppleButton(
                  text: buttonText,
                  onPressed: onNext,
                ),
        ],
      ),
    );
  }
}
