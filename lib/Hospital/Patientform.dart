// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as dom show document; // web-only: read meta key

import 'PatientManagement.dart';
import '../signin.dart';

// ===== THEME: calm hospital (navy + teal, readable) =====
const _bg = Color(0xFF0C1424); // deep navy
const _sidebar = Color(0xFF0F1B2E); // navy-800
const _panel = Color(0xFF12233B); // navy-700
const _panelAlt = Color(0xFF0F2A45); // navy-650
const _ink = Color(0xFF2D4362); // desaturated stroke
const _primary = Color(0xFF00C2BA); // hospital teal

const Color sidebar = _sidebar;
const Color purple = _primary; // keep variable name used by UI
const Color text = Colors.white;
const Color subtext = Colors.white70;

// ===== Breakpoints =====
const double _bpMd = 900; // compact -> drawer
const double _bpLg = 1200; // show full timeline

class PatientFormPage extends StatefulWidget {
  const PatientFormPage({super.key});

  @override
  State<PatientFormPage> createState() => _PatientFormPageState();
}

class _PatientFormPageState extends State<PatientFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  String? _uid;
  String username = 'User';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  DateTime? dateOfAdmit;
  DateTime? dateOfBirth;

  // step progress
  bool step1Complete = false; // name + dob
  bool step2Complete = false; // date of admit
  bool step3Complete = false; // contact + addresses + guardian + moh/phi

  // controllers
  final fullNameController = TextEditingController();
  final phoneController = TextEditingController();
  final homeAddressController = TextEditingController();
  final workAddressController = TextEditingController();
  final guardianContactController = TextEditingController();

  // MOH/PHI state
  String? selectedMohArea;
  String? selectedPhiArea;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) _listenToUserProfile(_uid!);
    FirebaseAuth.instance.authStateChanges().listen((user) {
      setState(() => _uid = user?.uid);
      if (user?.uid != null) {
        _listenToUserProfile(user!.uid);
      } else {
        _profileSub?.cancel();
        _profileSub = null;
        setState(() => username = 'User');
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    fullNameController.dispose();
    phoneController.dispose();
    homeAddressController.dispose();
    workAddressController.dispose();
    guardianContactController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _pickName(Map<String, dynamic> m) {
    final keys = [
      'display_name',
      'displayName',
      'name',
      'full_name',
      'username',
    ];
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return 'User';
  }

  Future<void> _listenToUserProfile(String uid) async {
    _profileSub?.cancel();
    final fs = FirebaseFirestore.instance;
    DocumentReference<Map<String, dynamic>> ref =
        fs.collection('users').doc(uid);
    final usersDoc = await ref.get();
    if (!usersDoc.exists) ref = fs.collection('hospitals').doc(uid);
    _profileSub = ref.snapshots().listen(
      (snap) {
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final name = _pickName(data);
        if (mounted) setState(() => username = name);
      },
      onError: (_) {
        if (mounted) setState(() => username = 'User');
      },
    );
  }

  void _updateStepProgress() {
    setState(() {
      step1Complete =
          fullNameController.text.trim().isNotEmpty && dateOfBirth != null;
      step2Complete = dateOfAdmit != null;

      final contactOk = phoneController.text.trim().isNotEmpty &&
          guardianContactController.text.trim().isNotEmpty &&
          homeAddressController.text.trim().isNotEmpty &&
          workAddressController.text.trim().isNotEmpty;

      final mohPhiOk = selectedMohArea != null &&
          selectedMohArea!.trim().isNotEmpty &&
          selectedPhiArea != null &&
          selectedPhiArea!.trim().isNotEmpty;

      step3Complete = contactOk && mohPhiOk;
    });
  }

  String? _validateTenDigitPhone(String? val) {
    if (val == null || val.trim().isEmpty) return 'Required';
    final v = val.trim();
    if (!RegExp(r'^\d+$').hasMatch(v)) return 'Digits only';
    if (v.length != 10) return 'Must be exactly 10 digits';
    return null;
  }

  Future<void> _pickDate(
    BuildContext context,
    ValueChanged<DateTime?> onPicked, {
    required DateTime firstDate,
    required DateTime lastDate,
    DateTime? initialDate,
  }) async {
    final now = DateTime.now();
    final safeInitial =
        initialDate ?? (lastDate.isBefore(now) ? lastDate : now);

    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _primary,
              surface: _panelAlt,
              onSurface: Colors.white,
            ),
            dialogTheme: DialogThemeData(backgroundColor: _panel),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onPicked(picked);
      _updateStepProgress();
    }
  }

  Widget _buildDateField(
    String label,
    DateTime? value,
    void Function(DateTime?) onPicked, {
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    return InkWell(
      onTap: () => _pickDate(
        context,
        onPicked,
        firstDate: firstDate,
        lastDate: lastDate,
        initialDate: value ?? DateTime.now(),
      ),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: _panelAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _ink.withOpacity(.35)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _primary, width: 2),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        child: Text(
          value != null
              ? DateFormat('dd/MM/yyyy').format(value)
              : 'Select date',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String hint, {
    TextEditingController? controller,
    TextInputType? type,
    int maxLines = 1,
    bool isRequired = false,
    bool digitsOnly10 = false,
  }) {
    final inputFormatters = <TextInputFormatter>[];
    if (digitsOnly10) {
      inputFormatters.addAll([
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ]);
      type ??= TextInputType.number;
    }

    return TextFormField(
      controller: controller,
      onChanged: (_) => _updateStepProgress(),
      keyboardType: type,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      autofillHints: const [
        AutofillHints.name,
        AutofillHints.givenName,
        AutofillHints.familyName,
      ],
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white60),
        filled: true,
        fillColor: _panelAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _ink.withOpacity(.35)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _primary, width: 2),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        counterText: '',
      ),
      validator: (val) {
        if (digitsOnly10) return _validateTenDigitPhone(val);
        if (isRequired) {
          return (val == null || val.trim().isEmpty) ? 'Required' : null;
        }
        return null;
      },
    );
  }

  void _scrollToFirstInvalidField() {
    Future.delayed(const Duration(milliseconds: 300)).then((_) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    fullNameController.clear();
    phoneController.clear();
    homeAddressController.clear();
    workAddressController.clear();
    guardianContactController.clear();

    dateOfAdmit = null;
    dateOfBirth = null;

    selectedMohArea = null;
    selectedPhiArea = null;

    _updateStepProgress();
    setState(() {});
  }

  bool _validateNonFormRequired() {
    if (dateOfBirth == null) {
      _showErr('Date of Birth is required');
      return false;
    }
    if (dateOfAdmit == null) {
      _showErr('Date of Admit is required');
      return false;
    }
    if (selectedMohArea == null || selectedMohArea!.trim().isEmpty) {
      _showErr('Patient MOH Area is required');
      return false;
    }
    if (selectedPhiArea == null ||
        selectedPhiArea!.trim().isNotEmpty == false) {
      _showErr('PHI Area is required');
      return false;
    }
    return true;
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      _scrollToFirstInvalidField();
      return;
    }
    if (!_validateNonFormRequired()) {
      _scrollToFirstInvalidField();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panelAlt,
        title: const Text(
          "Confirm Submission",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Are you sure you want to submit this form?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Submit"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not signed in.')));
      return;
    }

    String hospitalIdProfile = '';
    String admitHospitalMoh = '';
    String role = '';
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      final data = userDoc.data() ?? {};
      role = (data['role'] ?? '').toString();
      if (role != 'hospital') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Your role is "$role". Only hospital can submit.'),
          ),
        );
        return;
      }
      hospitalIdProfile = (data['hospital_id'] ?? '').toString();
      admitHospitalMoh = (data['moh_area'] ?? '').toString();
    } catch (_) {}

    // ------------- Two-step writes -------------
    try {
      // Common values
      final mohLc = (selectedMohArea ?? '').trim().toLowerCase();
      final phiLc = (selectedPhiArea ?? '').trim().toLowerCase();
      final admitMohLc = admitHospitalMoh.trim().toLowerCase();
      final patientAddress = homeAddressController.text.trim();

      // (1) Create dengue case first
      final casePayload = <String, dynamic>{
        'hospital_uid': authUser.uid,
        if (hospitalIdProfile.isNotEmpty) 'hospital_id': hospitalIdProfile,
        'patient_moh_area': mohLc,
        'patient_phi_area': phiLc,
        'admit_hospital_moh': admitMohLc,
        'fullname': fullNameController.text.trim(),
        'address': patientAddress,
        'phone_number': phoneController.text.trim(),
        'school_or_work': workAddressController.text.trim(),
        'guardian_contact': guardianContactController.text.trim(),
        'date_of_admission': Timestamp.fromDate(dateOfAdmit!),
        'date_of_birth': Timestamp.fromDate(dateOfBirth!),
        'status': 'active',
        'case_status': 'active',
        'created_at': FieldValue.serverTimestamp(),
        'created_by': authUser.uid,
        'updated_at': FieldValue.serverTimestamp(),
      };

      final fs = FirebaseFirestore.instance;
      final caseRef = await fs.collection('dengue_cases').add(casePayload);

      // (2) Create scrubbed mirror in moh_actions AFTER case exists
      final mohActionPayload = <String, dynamic>{
        'case_id': caseRef.id, // points to existing case
        'action': 'new_case', // hospitals: only 'new_case'
        'actor_uid': authUser.uid,
        'case_status': 'active',
        'created_at': FieldValue.serverTimestamp(),
        'date_of_admission': Timestamp.fromDate(dateOfAdmit!),

        // address-level fields (scrubbed)
        'location_type': 'home',
        'location_address': patientAddress,
        'patient_address': patientAddress,
        'patient_moh_area': mohLc,
        'patient_phi_area': phiLc,
      };

      try {
        await fs.collection('moh_actions').add(mohActionPayload);
      } catch (e) {
        // Optional rollback if action write fails
        try {
          await caseRef.delete();
        } catch (_) {}
        rethrow;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Patient info added!')));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PatientManagementPage()),
      );
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Firestore failed: ${e.code}')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to submit.')));
    }
    // ------------------------------------------
  }

  // ===== Sidebar content =====
  Widget _buildSidebar(BuildContext context) {
    return Container(
      color: sidebar,
      width: 250,
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
                    color: purple.withOpacity(.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.local_hospital_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Patient Data',
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
            icon: Icons.assignment_outlined,
            label: 'Patient Form',
            active: true,
          ),
          _SideNavItem(
            icon: Icons.receipt_long_outlined,
            label: 'Patient Management',
            onTap: () {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const PatientManagementPage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            },
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
                    style: const TextStyle(color: subtext, fontSize: 12),
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
                              onPressed: () => Navigator.pop(ctx, false),
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
                          MaterialPageRoute(builder: (_) => const SignInPage()),
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
                          Icon(Icons.logout, color: Colors.white70, size: 18),
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
    );
  }

  // ===== Form content =====
  Widget _buildFormBody(double spacing) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.all(spacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Patient Admission Form",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: spacing),
            const Text(
              "👤 Patient Details",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            _buildTextField(
              "Full Name",
              controller: fullNameController,
              isRequired: true,
            ),
            const SizedBox(height: 10),
            _buildDateField(
              "Date of Birth",
              dateOfBirth,
              (val) => setState(() => dateOfBirth = val),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            ),
            SizedBox(height: spacing),
            const Text(
              "🏥 Admission Info",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            _buildDateField(
              "Date of Admit",
              dateOfAdmit,
              (val) => setState(() => dateOfAdmit = val),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            ),
            SizedBox(height: spacing),
            const Text(
              "📞 Contact & Location",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            _buildTextField(
              "Phone Number",
              controller: phoneController,
              isRequired: true,
              digitsOnly10: true,
            ),
            const SizedBox(height: 10),
            AddressAutocompleteField(
              controller: homeAddressController,
              labelText: 'Home Address',
              onChanged: (_) => _updateStepProgress(),
              country: 'lk', // Sri Lanka
              isRequired: true,
            ),
            const SizedBox(height: 10),
            AddressAutocompleteField(
              controller: workAddressController,
              labelText: 'School/Work Address',
              onChanged: (_) => _updateStepProgress(),
              country: 'lk',
              isRequired: true,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              "Guardian Contact No.",
              controller: guardianContactController,
              isRequired: true,
              digitsOnly10: true,
            ),
            const SizedBox(height: 10),
            MohPhiPickerInline(
              initialMoh: selectedMohArea,
              initialPhi: selectedPhiArea,
              onChanged: (moh, phi) {
                setState(() {
                  selectedMohArea = moh;
                  selectedPhiArea = phi;
                });
                _updateStepProgress();
              },
              phiRequired: true,
            ),
            SizedBox(height: spacing),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitForm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  "SUBMIT",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _resetForm,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: _ink.withOpacity(.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "RESET",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Right-side timeline panel =====
  Widget _buildTimelinePanel({required bool compact}) {
    return Container(
      padding: EdgeInsets.all(compact ? 24 : 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF10243E), Color(0xFF0C2C4D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timelineStep(
            "STEP 1",
            "Patient Details",
            step1Complete,
            isFirst: true,
            isLast: false,
          ),
          const SizedBox(height: 6),
          _timelineStep(
            "STEP 2",
            "Admission Info",
            step2Complete,
            isFirst: false,
            isLast: false,
          ),
          const SizedBox(height: 6),
          _timelineStep(
            "STEP 3",
            "Contact & Location",
            step3Complete,
            isFirst: false,
            isLast: true,
          ),
          const Spacer(),
          Center(
            child: Image.asset(
              'images/fmaily.png',
              height: compact ? 140 : 180,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineStep(
    String step,
    String label,
    bool isComplete, {
    required bool isFirst,
    required bool isLast,
  }) {
    final active = _primary;
    const idle = Colors.white38;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  Expanded(
                    child: isFirst
                        ? const SizedBox.shrink()
                        : Container(
                            width: 2,
                            color: isComplete ? active : idle,
                          ),
                  ),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isComplete ? active : Colors.transparent,
                      border: Border.all(
                        color: isComplete ? active : idle,
                        width: 2,
                      ),
                    ),
                  ),
                  Expanded(
                    child: isLast
                        ? const SizedBox.shrink()
                        : Container(
                            width: 2,
                            color: isComplete ? active : idle,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final isCompact = constraints.maxWidth < _bpMd;
        final showTimeline = constraints.maxWidth >= _bpMd;
        final showFullTimeline = constraints.maxWidth >= _bpLg;

        final outerPad = isCompact ? 0.0 : 12.0;
        final cardMaxWidth = showFullTimeline ? 1300.0 : 1100.0;
        final formSpacing = isCompact ? 20.0 : 30.0;

        final appBar = isCompact
            ? AppBar(
                backgroundColor: sidebar,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                title: Row(
                  children: const [
                    SizedBox(width: 4),
                    Icon(Icons.local_hospital_outlined, color: Colors.white),
                    SizedBox(width: 10),
                    Text('Patient Data'),
                    Spacer(),
                  ],
                ),
              )
            : null;

        final body = Container(
          color: _bg,
          padding: EdgeInsets.all(outerPad),
          child: Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: cardMaxWidth),
              height:
                  isCompact ? null : MediaQuery.of(context).size.height * 0.92,
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
              child: isCompact
                  ? _buildFormBody(formSpacing)
                  : Row(
                      children: [
                        Expanded(flex: 3, child: _buildFormBody(formSpacing)),
                        if (showTimeline)
                          Expanded(
                            flex: 2,
                            child: _buildTimelinePanel(
                              compact: !showFullTimeline,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _bg,
          appBar: appBar,
          drawer: isCompact ? Drawer(child: _buildSidebar(context)) : null,
          body: isCompact
              ? body
              : Row(
                  children: [
                    _buildSidebar(context),
                    Expanded(child: body),
                  ],
                ),
        );
      },
    );
  }
}

class _SideNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _SideNavItem({
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

/// =================== MOH → PHI picker (no GlobalKeys) ===================
class MohPhiPickerInline extends StatefulWidget {
  final String? initialMoh;
  final String? initialPhi;
  final void Function(String? moh, String? phi) onChanged;
  final bool phiRequired;

  const MohPhiPickerInline({
    super.key,
    this.initialMoh,
    this.initialPhi,
    required this.onChanged,
    this.phiRequired = false,
  });

  @override
  State<MohPhiPickerInline> createState() => _MohPhiPickerInlineState();
}

class _MohPhiPickerInlineState extends State<MohPhiPickerInline> {
  bool _loading = true;

  Map<String, List<String>> _map = {};
  List<String> _mohList = [];
  List<String> _phiList = [];
  String? _moh;
  String? _phi;

  String _titleCase(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return t;
    return t
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1)))
        .join(' ');
  }

  Future<void> _load() async {
    final jsonStr = await rootBundle.loadString('images/phi_area.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final normalized = <String, List<String>>{};
    for (final e in data.entries) {
      final moh = _titleCase(e.key.toString());
      final items = (e.value as List)
          .map((v) => _titleCase(v.toString()))
          .toList()
        ..sort();
      normalized[moh] = items;
    }
    final mohs = normalized.keys.toList()..sort();

    setState(() {
      _map = normalized;
      _mohList = mohs;
      _loading = false;
    });

    if (widget.initialMoh != null && widget.initialMoh!.trim().isNotEmpty) {
      _onMohChanged(
        _titleCase(widget.initialMoh!),
        initialPhi:
            widget.initialPhi == null ? null : _titleCase(widget.initialPhi!),
      );
    }
  }

  void _emit() => widget.onChanged(_moh, _phi);

  void _onMohChanged(String? moh, {String? initialPhi}) {
    setState(() {
      _moh = moh;
      _phiList = moh == null ? [] : (_map[moh] ?? const <String>[]);
      _phi = (initialPhi != null && _phiList.contains(initialPhi))
          ? initialPhi
          : null;
    });
    _emit();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: LinearProgressIndicator(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _moh,
          dropdownColor: _panelAlt,
          items: _mohList
              .map(
                (m) => DropdownMenuItem(
                  value: m,
                  child: Text(m, style: const TextStyle(color: Colors.white)),
                ),
              )
              .toList(),
          onChanged: (v) => _onMohChanged(v),
          decoration: InputDecoration(
            labelText: 'Patient MOH Area *',
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: const Icon(Icons.location_on, color: Colors.white54),
            filled: true,
            fillColor: _panelAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _ink.withOpacity(.35)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _primary, width: 2),
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          validator: (v) => (v == null || v.isEmpty) ? 'Select MOH area' : null,
        ),
        const SizedBox(height: 10),
        AbsorbPointer(
          absorbing: _phiList.isEmpty,
          child: DropdownButtonFormField<String>(
            value: _phiList.contains(_phi) ? _phi : null,
            dropdownColor: _panelAlt,
            items: _phiList
                .map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text(p, style: const TextStyle(color: Colors.white)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() => _phi = v);
              _emit();
            },
            decoration: InputDecoration(
              labelText:
                  widget.phiRequired ? 'PHI Area *' : 'PHI Area (optional)',
              labelStyle: const TextStyle(color: Colors.white70),
              helperText: _phiList.isEmpty
                  ? 'Select MOH first'
                  : 'Filtered by selected MOH',
              helperStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.badge, color: Colors.white54),
              filled: true,
              fillColor: _panelAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _ink.withOpacity(.35)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: _primary, width: 2),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            validator: (v) {
              if (widget.phiRequired) {
                if (_moh == null || _moh!.isEmpty) return 'Pick MOH first';
                if (v == null || v.isEmpty) return 'Select PHI area';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }
}

/// ======== Helpers ========

// Web-safe session token (avoid 1 << 32 which becomes 0 in JS)
String _makeSessionToken() {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = Random().nextInt(0x3fffffff).toRadixString(36); // 30-bit safe
  return 'sess_${stamp}_$r';
}

/// =============== Address Autocomplete (inline list, no overlays/keys) ===============
class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.labelText,
    required this.onChanged,
    this.country = 'lk',
    this.isRequired = false,
  });

  final TextEditingController controller;
  final String labelText;
  final void Function(String value) onChanged;
  final String country;
  final bool isRequired;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final FocusNode _focus = FocusNode();
  Timer? _deb;
  bool _loading = false;
  bool _showList = false;
  List<String> _suggestions = [];

  String get _apiKey =>
      dom.document
          .querySelector('meta[name="gmaps-key"]')
          ?.getAttribute('content') ??
      '';

  late final String _sessionToken;

  @override
  void initState() {
    super.initState();
    _sessionToken = _makeSessionToken();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showList = false);
        });
      } else {
        if (widget.controller.text.trim().length >= 3 && _apiKey.isNotEmpty) {
          setState(() => _showList = true);
          _fetch(widget.controller.text);
        }
      }
    });
  }

  @override
  void dispose() {
    _deb?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _fetch(String q) async {
    if (_apiKey.isEmpty || q.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);

    try {
      // Prefer Places API (New) v1
      final v1 = await http.post(
        Uri.https('places.googleapis.com', '/v1/places:autocomplete'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'autocompletePredictions.placeId,autocompletePredictions.text',
        },
        body: jsonEncode({
          'input': q,
          'regionCode': widget.country.toUpperCase(),
          'languageCode': 'en',
          'sessionToken': _sessionToken,
          'includedPrimaryTypes': ['street_address', 'premise', 'route'],
        }),
      );

      List<String> results = [];
      if (v1.statusCode == 200) {
        final j = jsonDecode(v1.body) as Map<String, dynamic>;
        final list = (j['autocompletePredictions'] as List?) ?? const [];
        results = list
            .map((e) => (e['text']?['text'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .cast<String>()
            .toList();
      }

      // Legacy fallback
      if (results.isEmpty) {
        final legacy = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/autocomplete/json',
          {
            'input': q,
            'key': _apiKey,
            'types': 'address',
            'components': 'country:${widget.country.toLowerCase()}',
            'language': 'en',
            'sessiontoken': _sessionToken,
          },
        );
        final res = await http.get(legacy);
        if (res.statusCode == 200) {
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          if ((j['status'] ?? '') == 'OK') {
            final list = (j['predictions'] as List?) ?? const [];
            results = list
                .map((e) => (e['description'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .cast<String>()
                .toList();
          }
        }
      }

      setState(() {
        _suggestions = results;
        _loading = false;
        _showList = _focus.hasFocus && results.isNotEmpty;
      });
    } catch (_) {
      setState(() {
        _suggestions = [];
        _loading = false;
      });
    }
  }

  void _onChanged(String v) {
    widget.onChanged(v);
    if (_apiKey.isEmpty) return;
    if (!_focus.hasFocus) return;
    if (v.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _showList = false;
      });
      return;
    }
    setState(() => _showList = true);
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 250), () => _fetch(v));
  }

  void _select(String value) {
    widget.controller.text = value;
    widget.onChanged(value);
    setState(() {
      _showList = false;
      _suggestions = [];
    });
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          onChanged: _onChanged,
          style: const TextStyle(color: Colors.white),
          autofillHints: const [
            AutofillHints.streetAddressLine1,
            AutofillHints.fullStreetAddress,
          ],
          decoration: InputDecoration(
            labelText: widget.labelText,
            labelStyle: const TextStyle(color: Colors.white70),
            hintText: 'Start typing…',
            hintStyle: const TextStyle(color: Colors.white60),
            filled: true,
            fillColor: _panelAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _ink.withOpacity(.35)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _primary, width: 2),
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            suffixIcon: _apiKey.isEmpty
                ? const Icon(
                    Icons.edit_location_alt_outlined,
                    color: Colors.white54,
                  )
                : (_loading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.place_outlined,
                        color: Colors.white70,
                      )),
          ),
          validator: (val) {
            if (!widget.isRequired) return null;
            return (val == null || val.trim().isEmpty) ? 'Required' : null;
          },
        ),
        if (_showList)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: _panelAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _ink.withOpacity(.45)),
            ),
            constraints: const BoxConstraints(maxHeight: 240),
            child: _suggestions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text(
                      'No suggestions',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (_, i) => InkWell(
                      onTap: () => _select(_suggestions[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.place,
                              size: 16,
                              color: Colors.white60,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _suggestions[i],
                                style: const TextStyle(color: Colors.white),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}
