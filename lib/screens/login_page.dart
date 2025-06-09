import 'package:flutter/material.dart';
import 'register_page.dart';
import 'home_page.dart';
import 'package:iris_application/services/auth_services.dart';
import 'package:iris_application/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool rememberMe = false;
  bool _obscurePassword = true;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 40),
              Center(
                child: Column(
                  children: [
                    Image.asset('assets/images/logo.png', height: 150),
                  ],
                ),
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Color(0xFF234462),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text('Login'),
                    ),
                  ),
                  SizedBox(width: 10),
                  SizedBox(
                    width: 160,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    RegisterPage(),
                            transitionsBuilder: (
                              context,
                              animation,
                              secondaryAnimation,
                              child,
                            ) {
                              return child;
                            },
                            transitionDuration: Duration(milliseconds: 500),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Color(0xFF234462),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text('Register'),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 20),
                  Center(
                    child: SizedBox(
                      width: 700,
                      child: TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          hintText: 'Email Address',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 15),
                  Center(
                    child: SizedBox(
                      width: 700,
                      child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 15),
                  Center(
                    child: SizedBox(
                      width: 700,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            final username = await AuthServices().login(
                              email: _emailController.text,
                              password: _passwordController.text,
                            );
                            // Show success dialog
                            showDialog(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: Text('Login Successful'),
                                    content: Text('Welcome back!'),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(
                                            context,
                                          ).pop(); // Close dialog
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (context) => HomePage(
                                                    cameras: cameras,
                                                    email:
                                                        _emailController.text,
                                                    username: username,
                                                  ),
                                            ),
                                          );
                                        },
                                        child: Text('OK'),
                                      ),
                                    ],
                                  ),
                            );
                            if (rememberMe) {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool('remember_me', true);
                              await prefs.setString(
                                'user_email',
                                _emailController.text,
                              );
                              await prefs.setString(
                                'username',
                                username ?? '',
                              ); // Save the username
                            } else {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.remove('remember_me');
                              await prefs.remove('user_email');
                            }
                          } catch (e) {
                            String errorMsg =
                                e.toString().contains('wrong-password') ||
                                        e.toString().contains('user-not-found')
                                    ? 'Incorrect email or password. Please try again.'
                                    : 'Login failed: ${e.toString()}';
                            showDialog(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: Text('Login Failed'),
                                    content: Text(errorMsg),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.of(context).pop(),
                                        child: Text('OK'),
                                      ),
                                    ],
                                  ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Color(0xFF234462),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text('Login'),
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Center(
                    child: SizedBox(
                      width: 700,
                      child: Row(
                        children: [
                          Checkbox(
                            value: rememberMe,
                            activeColor: Color(0xFF234462),
                            onChanged: (val) {
                              setState(() {
                                rememberMe = val ?? false;
                              });
                            },
                          ),
                          Text(
                            'Remember Me',
                            style: TextStyle(color: Color(0xFF234462)),
                          ),
                          Spacer(),
                          TextButton(
                            onPressed: () {},
                            child: Text(
                              'Forgot password',
                              style: TextStyle(
                                color: Color.fromARGB(255, 116, 134, 150),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 5),
                  Center(
                    child: SizedBox(
                      width: 700,
                      child: Text(
                        'or connect with',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Center(
                    child: SizedBox(
                      width: 700,
                      child: Column(
                        children: [
                          SizedBox(
                            width: 500,
                            child: socialButton(
                              Icons.g_mobiledata,
                              'Login with Google',
                            ),
                          ),
                          SizedBox(height: 10),
                          SizedBox(
                            width: 500,
                            child: socialButton(
                              Icons.apple,
                              'Login with Apple ID',
                            ),
                          ),
                          SizedBox(height: 10),
                          SizedBox(
                            width: 500,
                            child: socialButton(
                              Icons.facebook,
                              'Login with Facebook',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget socialButton(IconData icon, String label) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 5),
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: Icon(icon, color: Color(0xFF234462)),
        label: Text(label, style: TextStyle(color: Color(0xFF234462))),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Color(0xFF234462)),
          padding: EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
