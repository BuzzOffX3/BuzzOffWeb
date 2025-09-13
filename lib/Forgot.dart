import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);

  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
      _sent = false;
    });

    try {
      final email = _emailCtrl.text.trim();

      // --- Option A: simple (uses default Firebase domain) ---
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      // --- Option B: custom domain (uncomment & edit) ---
      /*
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
        actionCodeSettings: ActionCodeSettings(
          url: 'https://app.buzzoff.lk/reset-password', // your hosted handler
          handleCodeInApp: false, // true if you have an in-app handler
          dynamicLinkDomain: 'app.buzzoff.lk', // or your Firebase dynamic link domain
        ),
      );
      */

      if (!mounted) return;
      setState(() => _sent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset link sent. Check your inbox.')),
      );
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'invalid-email':
          msg = 'That email address looks invalid.';
          break;
        case 'user-not-found':
          msg = 'No account found for this email.';
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Please try again later.';
          break;
        default:
          msg = e.message ?? 'Could not send reset email.';
      }
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white54),
    filled: true,
    fillColor: const Color(0xFF22232A),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: const Color(0xFF0F1115))),
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
                      Image.asset('images/logo.png', height: 56),
                      const SizedBox(height: 12),
                      const Text(
                        'Forgot password',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter your email and we\'ll send you a reset link.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 12.5),
                      ),
                      const SizedBox(height: 18),

                      // Email field
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decor('Email'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!_isValidEmail(v.trim())) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _busy ? null : _sendReset(),
                      ),

                      if (_error != null) ...[
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
                                _error!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ],

                      if (_sent) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: const [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Reset email sent. Check your inbox (and spam).',
                                style: TextStyle(color: Colors.greenAccent),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _sendReset,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8C5EBF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Send reset link',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text(
                          'Back to Sign In',
                          style: TextStyle(color: Color(0xFFB69CFF)),
                        ),
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
