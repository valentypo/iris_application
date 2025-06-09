import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iris_application/screens/login_page.dart';

class AuthServices {
  Future<void> signup({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      await credential.user?.updateDisplayName(username);
      await credential.user?.reload();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user?.uid)
          .set({'email': email, 'username': username});
    } on FirebaseAuthException catch (e) {
      // Handle specific Firebase Auth exceptions
      if (e.code == 'weak-password') {
        print('The password provided is too weak.');
      } else if (e.code == 'email-already-in-use') {
        print('The account already exists for that email.');
      } else {
        print('Error: ${e.message}');
      }

      // Fluttertoast.showToast(
      //   msg: e.message ?? 'An error occurred during signup.',
      //   toastLength: Toast.LENGTH_LONG,
      //   gravity: ToastGravity.SNACKBAR,
      //   backgroundColor: Colors.red,
      //   textColor: Colors.white,
      //   fontSize: 14.0,
      // );

      throw e;
    } catch (e) {
      print("Signup error: $e");
      throw e;
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user?.displayName ?? '';
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'Login failed';
    }
  }
}

Future<void> logout({required BuildContext context}) async {
  try {
    await FirebaseAuth.instance.signOut();
    await Future.delayed(Duration(seconds: 1));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (BuildContext context) => LoginPage()),
    );
  } catch (e) {
    print("Logout error: $e");
    throw e;
  }
}
