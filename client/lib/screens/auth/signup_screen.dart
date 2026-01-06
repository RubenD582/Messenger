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
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Add listeners to update button state
    _firstNameController.addListener(_updateButtonState);
    _lastNameController.addListener(_updateButtonState);
    _usernameController.addListener(_updateButtonState);
    _emailController.addListener(_updateButtonState);
    _passwordController.addListener(_updateButtonState);
    _confirmPasswordController.addListener(_updateButtonState);
    // Auto-focus first field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstNameFocusNode.requestFocus();
    });
  }

  void _updateButtonState() {
    setState(() {});
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_updateButtonState);
    _lastNameController.removeListener(_updateButtonState);
    _usernameController.removeListener(_updateButtonState);
    _emailController.removeListener(_updateButtonState);
    _passwordController.removeListener(_updateButtonState);
    _confirmPasswordController.removeListener(_updateButtonState);
    _pageController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _usernameFocusNode.dispose();
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
      username: _usernameController.text.trim(),
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
        title: const Text(
          'Sign Up',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
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
            title: "What's your name?",
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
            isButtonEnabled: () => _firstNameController.text.trim().isNotEmpty &&
                                    _lastNameController.text.trim().isNotEmpty,
          ),
          _buildStep(
            title: "Choose a username",
            fields: [
              CustomCupertinoTextField(
                label: 'Username',
                hintText: 'Enter username',
                controller: _usernameController,
                focusNode: _usernameFocusNode,
              ),
            ],
            onNext: () {
              final username = _usernameController.text.trim();
              final usernameRegex = RegExp(r'^[a-zA-Z0-9_.]{3,20}$');
              if (username.isEmpty) {
                Fluttertoast.showToast(msg: 'Please enter a username');
                return;
              }
              if (!usernameRegex.hasMatch(username)) {
                Fluttertoast.showToast(msg: 'Username must be 3-20 characters (letters, numbers, _, .)');
                return;
              }
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            isButtonEnabled: () => _usernameController.text.trim().isNotEmpty,
          ),
          _buildStep(
            title: "What's your email?",
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
            isButtonEnabled: () => _emailController.text.trim().isNotEmpty,
          ),
          _buildStep(
            title: "Create a password",
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
            isLastStep: true,
            isButtonEnabled: () => _passwordController.text.isNotEmpty &&
                                    _confirmPasswordController.text.isNotEmpty,
          ),
        ],
      ),
    );
  }

  Widget _buildStep({
    String? title,
    String? description,
    required List<Widget> fields,
    required VoidCallback onNext,
    String buttonText = 'Continue',
    bool isLastStep = false,
    bool Function()? isButtonEnabled,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),

          if (title != null)
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),

          if (title != null) const SizedBox(height: 24),

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
          if (description != null) const SizedBox(height: 24),

          ...fields,

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
                    onTap: (isButtonEnabled != null && isButtonEnabled())
                        ? onNext
                        : null,
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        color: (isButtonEnabled != null && isButtonEnabled())
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        buttonText,
                        style: TextStyle(
                          color: (isButtonEnabled != null && isButtonEnabled())
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
    );
  }
}
