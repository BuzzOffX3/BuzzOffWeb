import 'package:buzzoffwebnew/NDCU/ndcuanalytic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'Hospital/Patientform.dart';
import 'MOH/complaints.dart';
import 'Forgot.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true;
  String? _fieldError; // top-level error (non-field specific)

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    // Validate inputs first
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _fieldError = null;
    });

    try {
      final auth = FirebaseAuth.instance;
      final userCred = await auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final uid = userCred.user!.uid;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!doc.exists || !doc.data()!.containsKey('role')) {
        throw FirebaseAuthException(
          message: 'Role not found.',
          code: 'no-role',
        );
      }

      final role = doc['role'];

      if (role == 'hospital') {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PatientFormPage()),
        );
      } else if (role == 'moh') {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ComplaintsPage()),
        );
      } //else if (role == 'admin') {
      //if (!mounted) return;
      //Navigator.pushReplacement(
      //context,
      //MaterialPageRoute(builder: (context) => const AddUserPage()),
      //);
      else if (role == 'ndcu') {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AnalyticsPage()),
        );
      } else {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const NaughtyPage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      final msg = _mapAuthError(e);
      setState(() => _fieldError = msg);
    } catch (e) {
      setState(() => _fieldError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'The email address is badly formatted.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'no-role':
        return 'Your account is missing a role. Contact admin.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  bool _isValidEmail(String v) {
    // Minimal email check
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  }

  InputDecoration _fieldDecoration(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF22232A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('images/bg.png', fit: BoxFit.cover),
          ),
          // Soft dark overlay for readability
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 30,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF15161C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2A2C36)),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 30,
                      color: Colors.black54,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo + Title
                      Column(
                        children: [
                          Image.asset('images/logo.png', height: 56),
                          const SizedBox(height: 14),
                          const Text(
                            'Sign in to BuzzOff',
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Welcome back! Please enter your details.',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Email
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('Email'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!_isValidEmail(v.trim())) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Password
                      TextFormField(
                        controller: passwordController,
                        obscureText: _obscure,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(
                          'Password',
                          suffix: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Password is required';
                          }
                          if (v.length < 6) {
                            return 'Minimum 6 characters';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => !_isLoading ? signIn() : null,
                      ),

                      // Error (if any)
                      if (_fieldError != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _fieldError!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ForgotPasswordPage(),
                                    ),
                                  );
                                },
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(color: Color(0xFFB69CFF)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Sign In button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8C5EBF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Small footer
                      const Text(
                        'By continuing, you agree to our Terms & Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
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

class MohDashboardPage extends StatelessWidget {
  const MohDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'MOH Dashboard',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
      ),
    );
  }
}

class NaughtyPage extends StatelessWidget {
  const NaughtyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'Naughty naughty 😈\nYou are not allowed here!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.redAccent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
