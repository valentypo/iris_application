import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_page.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_page.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize cameras
    cameras = await availableCameras();
  } catch (e) {
    print('Error during initialization: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  final rememberMe = prefs.getBool('remember_me') ?? false;
  final userEmail = prefs.getString('user_email');
  final username = prefs.getString('username');

  Widget home = LoginPage();
  if (rememberMe && userEmail != null) {
    // Optionally, check if FirebaseAuth.instance.currentUser != null
    home = HomePage(email: userEmail, cameras: cameras);
  }

  runApp(
    MaterialApp(
      title: 'IRIS App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Color(0xFF234462),
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blue,
        ).copyWith(primary: Color(0xFF234462), secondary: Colors.blueAccent),
        fontFamily: 'Roboto',
      ),
      home:
          rememberMe && userEmail != null
              ? HomePage(
                email: userEmail,
                username: username ?? 'User',
                cameras: cameras,
              )
              : LoginPage(),
    ),
  );
}
