import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../Hospital/PatientForm.dart';
import '../signin.dart';
import '../firebase_options.dart';

const _bg = Color(0xFF0A0F16);
const _sidebar = Color(0xFF121A25);
const _panel = Color(0xFF0E1521);
const _panelAlt = Color(0xFF111C2B);
const _ink = Color(0xFF233049);
const _primary = Color(0xFF22D3EE);
const Color sidebar = _sidebar;
const Color purple = _primary;
const Color text = Colors.white;
const Color subtext = Colors.white70;

/// Colombo District – common MOH areas (curated)
const List<String> _colomboMohs = [
  'Colombo Municipal Council (CMC)',
  'Dehiwala–Mount Lavinia',
  'Sri Jayawardenepura Kotte',
  'Maharagama',
  'Kaduwela',
  'Kolonnawa',
  'Homagama',
  'Kesbewa (Piliyandala)',
  'Rathmalana',
  'Boralesgamuwa',
  'Moratuwa',
  'Seethawaka (Avissawella)',
  'Padukka',
  'Hanwella',
];

class AddUserPage extends StatefulWidget {
  const AddUserPage({super.key});

  @override
  State<AddUserPage> createState() => _AddUserPageState();
}

class _AddUserPageState extends State<AddUserPage> {
  final _formKey = GlobalKey<FormState>();

  // sidebar auth name
  String username = 'User';
  String? _uid;
  StreamSubscription<User?>? _authSub;

  // form controllers/fields to match your Firestore structure
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final districtCtrl = TextEditingController();
  final mohAreaCtrl = TextEditingController();

  String role = 'hospital'; // hospital | moh | ndcu | admin
  String? _selectedMoh; // <-- dropdown selection

  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    username = FirebaseAuth.instance.currentUser?.email ?? 'User';
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      setState(() {
        _uid = u?.uid;
        username = u?.email ?? 'User';
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    usernameCtrl.dispose();
    addressCtrl.dispose();
    cityCtrl.dispose();
    districtCtrl.dispose();
    mohAreaCtrl.dispose();
    super.dispose();
  }

  // ===== helpers =====
  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white70),
    filled: true,
    fillColor: _panelAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _ink.withOpacity(.35)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: _primary, width: 2),
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  );

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  bool _isValidPhone(String v) =>
      RegExp(r'^\+?\d{7,15}$').hasMatch(v.replaceAll(RegExp(r'[^\d+]'), ''));

  String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  void _genUsername() {
    if (usernameCtrl.text.trim().isNotEmpty) return;
    final base = nameCtrl.text.trim().isEmpty ? 'user' : _slug(nameCtrl.text);
    final suffix = Random().nextInt(999).toString().padLeft(3, '0');
    setState(() => usernameCtrl.text = '${base}_$suffix');
  }

  Future<FirebaseAuth> _secondaryAuth() async {
    const name = 'admin_add_user';
    FirebaseApp app;
    try {
      app = Firebase.app(name);
    } catch (_) {
      app = await Firebase.initializeApp(
        name: name,
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    return FirebaseAuth.instanceFor(app: app);
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    final name = nameCtrl.text.trim();
    final email = emailCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final uname = usernameCtrl.text.trim();
    final address = addressCtrl.text.trim();
    final city = cityCtrl.text.trim();
    final district = districtCtrl.text.trim();
    final mohArea = mohAreaCtrl.text.trim(); // set by dropdown

    final tempPassword = _tempPassword();

    final adminAuth = await _secondaryAuth();
    try {
      // 1) Create Auth user (secondary app so admin session is safe)
      final cred = await adminAuth.createUserWithEmailAndPassword(
        email: email,
        password: tempPassword,
      );
      final newUid = cred.user!.uid;

      // 2) Write Firestore profile (fields exactly as requested)
      await FirebaseFirestore.instance.collection('users').doc(newUid).set({
        'uid': newUid,
        'name': name,
        'username': uname,
        'email': email,
        'phone': phone,
        'address': address,
        'city': city,
        'district': district,
        'moh_area': mohArea,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3) Send reset email
      await adminAuth.sendPasswordResetEmail(email: email);

      // Optional cleanup of secondary session
      await adminAuth.signOut();

      setState(() {
        _success =
            'User created (uid: $newUid). A reset link was emailed to $email.';
      });

      // reset form
      _formKey.currentState!.reset();
      nameCtrl.clear();
      emailCtrl.clear();
      phoneCtrl.clear();
      usernameCtrl.clear();
      addressCtrl.clear();
      cityCtrl.clear();
      districtCtrl.clear();
      mohAreaCtrl.clear();
      _selectedMoh = null;
      role = 'hospital';
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'That email is already in use.';
          break;
        case 'invalid-email':
          msg = 'Invalid email address.';
          break;
        case 'operation-not-allowed':
          msg = 'Email/Password sign-in is disabled in this project.';
          break;
        case 'weak-password':
          msg = 'Generated password considered weak. Try again.';
          break;
        default:
          msg = e.message ?? 'Failed to create user.';
      }
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _tempPassword({int len = 12}) {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%*?';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final bool mohRequired = role == 'moh' || role == 'hospital';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 250,
              color: sidebar,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: purple.withOpacity(.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Admin',
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SideNavItem(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Add User',
                    active: true,
                  ),
                  _SideNavItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'complaints',
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundImage: AssetImage('images/pfp.png'),
                          radius: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            username,
                            style: const TextStyle(
                              color: subtext,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PopupMenuButton<String>(
                          color: _panelAlt,
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white54,
                            size: 18,
                          ),
                          onSelected: (value) async {
                            if (value == 'signout') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: _panelAlt,
                                  title: const Text(
                                    'Sign out',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: const Text(
                                    'Are you sure you want to sign out?',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primary,
                                      ),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Sign out'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await FirebaseAuth.instance.signOut();
                                if (!mounted) return;
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => const SignInPage(),
                                  ),
                                  (route) => false,
                                );
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'signout',
                              child: Row(
                                children: const [
                                  Icon(
                                    Icons.logout,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Sign out',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            // ===== RIGHT CONTENT =====
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _ink.withOpacity(.35)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.35),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Create user who can sign in',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Row 1: name + email
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: nameCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _dec('Full name *'),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Required'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: emailCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _dec('Email *'),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    return _isValidEmail(v.trim())
                                        ? null
                                        : 'Invalid email';
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Row 2: phone + role
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: phoneCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _dec('Phone (optional)'),
                                  keyboardType: TextInputType.phone,
                                  validator: (v) {
                                    final t = v?.trim() ?? '';
                                    if (t.isEmpty) return null;
                                    return _isValidPhone(t)
                                        ? null
                                        : 'Digits (+) 7–15';
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: role,
                                  dropdownColor: _panelAlt,
                                  decoration: _dec('Role *'),
                                  style: const TextStyle(color: Colors.white),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'hospital',
                                      child: Text(
                                        'Hospital',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'moh',
                                      child: Text(
                                        'MOH',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'ndcu',
                                      child: Text(
                                        'NDCU',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'admin',
                                      child: Text(
                                        'Admin',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    role = v ?? 'hospital';
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Row 3: username + MOH dropdown (Colombo)
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: usernameCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _dec('Username *').copyWith(
                                    suffixIcon: IconButton(
                                      icon: const Icon(
                                        Icons.auto_fix_high,
                                        color: Colors.white70,
                                      ),
                                      onPressed: _genUsername,
                                      tooltip: 'Generate',
                                    ),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Required'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedMoh,
                                  isExpanded: true,
                                  dropdownColor: _panelAlt,
                                  decoration: _dec(
                                    mohRequired ? 'MOH area *' : 'MOH area',
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  items: _colomboMohs
                                      .map(
                                        (m) => DropdownMenuItem(
                                          value: m,
                                          child: Text(
                                            m,
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _selectedMoh = v;
                                      // keep old storage logic working:
                                      mohAreaCtrl.text = v ?? '';
                                    });
                                  },
                                  validator: (v) {
                                    if (!mohRequired) return null;
                                    if (v == null || v.isEmpty) {
                                      return 'Pick an MOH area';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Row 4: city + district
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: cityCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _dec('City (optional)'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: districtCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _dec('District (optional)'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Row 5: address
                          TextFormField(
                            controller: addressCtrl,
                            maxLines: 2,
                            style: const TextStyle(color: Colors.white),
                            decoration: _dec('Address (optional, multi-line)'),
                          ),

                          const SizedBox(height: 18),

                          // Errors/success
                          if (_error != null) ...[
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
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_success != null) ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.greenAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _success!,
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],

                          // Submit
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _createUser,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
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
                                      'Create & send reset link',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'We create the account with a temporary password then email a reset link.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Sidebar item (same pattern as Patient Form) =====
class _SideNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _SideNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: InkWell(
        onTap: active ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: active ? purple.withOpacity(.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: active ? purple : text.withOpacity(.85),
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: active ? purple : subtext,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (active)
                const Icon(Icons.chevron_right, color: purple, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
