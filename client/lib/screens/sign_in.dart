import 'package:client/screens/home.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../components/textfield.dart';
import '../services/auth.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _isLoading = false;
  final bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 300), () {
      FocusScope.of(context).requestFocus(_usernameFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          "Sign in",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 60),

                  CustomCupertinoTextField(
                    hintText: "Username or Email address",
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                  ),
          
                  const SizedBox(height: 10),
          
                  // Password field (minimal)
                  CustomCupertinoTextField(
                    hintText: "Password",
                    obscureText: _obscurePassword,
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                  ),

                  const SizedBox(height: 10),
          
                  // Forgot password - subtle alignment
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // Handle forgot password
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          "Forgot password?",
                          style: TextStyle(
                            color: Color(0xFF999999),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
          
                  const SizedBox(height: 60),
          
                  // Login Button - clean and minimal
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color.fromARGB(255, 0, 122, 255),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                        ? CupertinoActivityIndicator(color: Colors.white,)
                        : const Text(
                            "Continue",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                    ),
                  ),
          
                  // Login instructions
                  // Padding(
                  //   padding: const EdgeInsets.only(top: 10.0),
                  //   child: Text(
                  //     "Create an account",
                  //     textAlign: TextAlign.center,
                  //     style: TextStyle(
                  //       color: Color(0xFF999999),
                  //       fontSize: 13,
                  //       fontWeight: FontWeight.w400,
                  //     ),
                  //   ),
                  // ),
                ],
              ),
            ),
          ),
        ),
      ),

    );
  }

  // Handle login logic
  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showToast("Please enter both username and password.");
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final result = await AuthService.login(username, password);

      setState(() {
        _isLoading = false;
      });

      if (result['success']) {
        _showToast("Login successful!");

        // Navigate to Home screen and remove the current screen from the stack
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => Home()), // Replace with your home screen widget
        );
      } else {
        _showToast(result['message']);
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showToast("An error occurred. Please try again.");
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.TOP,
      backgroundColor: Color(0xFF212121),
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }
}