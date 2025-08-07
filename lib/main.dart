import 'package:buzzoffwebnew/Hospital/PatientManagement.dart';
import 'package:buzzoffwebnew/Signin.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'Hospital/Patientform.dart';
import 'Hospital/PatientManagement.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDqkqUO7bdiCo4HaLeeCPrGTwJecL9qb6A",
      authDomain: "buzzoff2.firebaseapp.com",
      projectId: "buzzoff2",
      storageBucket: "buzzoff2.firebasestorage.app",
      messagingSenderId: "497532763551",
      appId: "1:497532763551:web:2974f471fdc4ef1ad851aa",
    ),
  );

  runApp(const MyWebApp());
}

class MyWebApp extends StatelessWidget {
  const MyWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BuzzOff Web',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Quicksand',
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SignInPage(),
    );
  }
}
