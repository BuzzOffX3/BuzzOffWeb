import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'PatientManagement.dart';
import '../signin.dart';

// ===== THEME: charcoal + cyan =====
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
  final ScrollController _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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
    DocumentReference<Map<String, dynamic>> ref = fs
        .collection('users')
        .doc(uid);
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

      final contactOk =
          phoneController.text.trim().isNotEmpty &&
          guardianContactController.text.trim().isNotEmpty &&
          homeAddressController.text.trim().isNotEmpty &&
          workAddressController.text.trim().isNotEmpty;

      final mohPhiOk =
          selectedMohArea != null &&
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
            dialogBackgroundColor: _panel,
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
    if (selectedPhiArea == null || selectedPhiArea!.trim().isEmpty) {
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

    try {
      // Build common (lowercased) values
      final mohLc = (selectedMohArea ?? '').trim().toLowerCase();
      final phiLc = (selectedPhiArea ?? '').trim().toLowerCase();
      final admitMohLc = admitHospitalMoh.trim().toLowerCase();
      final patientAddress = homeAddressController.text.trim();

      // Full record for dengue_cases
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

      // Minimal record for moh_actions (ONLY the fields you listed)
      final mohActionPayload = <String, dynamic>{
        'action': 'new_case', // change if you prefer 'no_signs', etc.
        'actor_uid': authUser.uid,
        'case_status': 'active',
        'created_at': FieldValue.serverTimestamp(),
        'date_of_admission': Timestamp.fromDate(dateOfAdmit!),
        'location_address': patientAddress,
        'location_type': 'home',
        'patient_address': patientAddress,
        'patient_moh_area': mohLc,
        'patient_phi_area': phiLc,
        // 'case_id' will be set when we know the doc id
      };

      final fs = FirebaseFirestore.instance;
      final batch = fs.batch();

      // Create the dengue case with an auto id
      final caseRef = fs.collection('dengue_cases').doc();
      // tie action to that id
      final actionRef = fs.collection('moh_actions').doc();

      // fill in case_id on the action payload
      mohActionPayload['case_id'] = caseRef.id;

      batch.set(caseRef, casePayload);
      batch.set(actionRef, mohActionPayload);

      await batch.commit();

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
  }

  // ===== Sidebar content (used as Drawer on small, fixed panel on large) =====
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
                    color: purple.withOpacity(.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.coronavirus, color: Colors.white),
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
            icon: Icons.dashboard_outlined,
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

  // ===== Form content (single column but responsive spacing) =====
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
            _buildTextField(
              "Home Address",
              controller: homeAddressController,
              isRequired: true,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              "School/Work Address",
              controller: workAddressController,
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
          colors: [Color(0xFF0D1B2A), Color(0xFF0B2539)],
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
                const SizedBox.shrink(),
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
                  children: [
                    const SizedBox(width: 4),
                    const Icon(Icons.coronavirus, color: Colors.white),
                    const SizedBox(width: 10),
                    const Text('Patient Data'),
                    const Spacer(),
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white10,
                      backgroundImage: const AssetImage('images/pfp.png'),
                      child: Container(),
                    ),
                    const SizedBox(width: 12),
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
              height: isCompact
                  ? null
                  : MediaQuery.of(context).size.height * 0.92,
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

/// =================== MOH → PHI picker (inline, visible text) ===================
/// Loads from asset: images/phi_area.json
/// { "Kolonnawa": ["Orugodawatta","Salamulla"], "Kaduwela": ["Athurugiriya","Bomiriya"] }
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
  final _mohKey = GlobalKey<FormFieldState<String>>();
  final _phiKey = GlobalKey<FormFieldState<String>>();
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
      final items =
          (e.value as List).map((v) => _titleCase(v.toString())).toList()
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
        initialPhi: widget.initialPhi == null
            ? null
            : _titleCase(widget.initialPhi!),
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
    _mohKey.currentState?.validate();
    _phiKey.currentState?.validate();
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
          key: _mohKey,
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
            key: _phiKey,
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
              labelText: widget.phiRequired
                  ? 'PHI Area *'
                  : 'PHI Area (optional)',
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
