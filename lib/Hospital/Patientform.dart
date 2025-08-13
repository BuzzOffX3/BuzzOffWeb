import 'dart:async'; // for StreamSubscription
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'PatientManagement.dart';
import '../signin.dart';

class PatientFormPage extends StatefulWidget {
  const PatientFormPage({super.key});

  @override
  State<PatientFormPage> createState() => _PatientFormPageState();
}

// ======= THEME (midnight blue + teal) =======
const _bg = Color(0xFF0C0F1A);
const _sidebar = Color(0xFF121826);
const _panel = Color(0xFF0F1522);
const _panelAlt = Color(0xFF10182A);
const _ink = Color(0xFF233049);
const _primary = Color(0xFF00D3A7); // teal
const _primaryDim = Color(0xFF00B895);
const _chipBg = Color(0xFF1A2133);

// --- aliases used by the sidebar snippet (for readability) ---
const Color sidebar = _sidebar;
const Color purple = _primary;
const Color text = Colors.white;
const Color subtext = Colors.white70;

class _PatientFormPageState extends State<PatientFormPage> {
  final _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  // 🔐 auth + sidebar profile
  String? _uid;
  String username = 'User';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  String? type;
  String? gender;
  bool isPregnant = false;

  DateTime? dateOfAdmit;
  DateTime? dateOfBirth;
  DateTime? dueDate;

  bool step1Complete = false;
  bool step2Complete = false;
  bool step3Complete = false;
  bool step4Complete = false;

  final fullNameController = TextEditingController();
  final remarksController = TextEditingController();
  final medicineController = TextEditingController();
  final emailController = TextEditingController();
  final guardianNameController = TextEditingController();
  final guardianContactController = TextEditingController();
  final phoneController = TextEditingController();
  final hospitalIdController = TextEditingController();
  final wardNoController = TextEditingController();
  final bedNoController = TextEditingController();
  final homeAddressController = TextEditingController();
  final workAddressController = TextEditingController();
  final weeksPregnantController = TextEditingController();

  final mohAreas = const [
    "Borella",
    "Colombo Central",
    "Colombo North",
    "Colombo South",
    "Dehiwala",
    "Homagama",
    "Kaduwela",
    "Kesbewa",
    "Kolonnawa",
    "Maharagama",
    "Moratuwa",
    "Nugegoda",
    "Ratmalana",
    "Thimbirigasyaya",
  ];
  String? selectedMohArea;

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
    remarksController.dispose();
    medicineController.dispose();
    emailController.dispose();
    guardianNameController.dispose();
    guardianContactController.dispose();
    phoneController.dispose();
    hospitalIdController.dispose();
    wardNoController.dispose();
    bedNoController.dispose();
    homeAddressController.dispose();
    workAddressController.dispose();
    weeksPregnantController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ===== Profile helpers =====
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

    // try users/{uid}, fallback to hospitals/{uid}
    DocumentReference<Map<String, dynamic>> ref = fs
        .collection('users')
        .doc(uid);
    final usersDoc = await ref.get();
    if (!usersDoc.exists) {
      ref = fs.collection('hospitals').doc(uid);
    }

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

      step2Complete =
          step1Complete &&
          type != null &&
          hospitalIdController.text.trim().isNotEmpty &&
          dateOfAdmit != null;

      step3Complete =
          step2Complete &&
          phoneController.text.trim().isNotEmpty &&
          emailController.text.trim().isNotEmpty &&
          guardianNameController.text.trim().isNotEmpty &&
          guardianContactController.text.trim().isNotEmpty;

      step4Complete =
          step3Complete && gender != null && selectedMohArea != null;
    });
  }

  // ---------- validators ----------
  String? _validateTenDigitPhone(String? val) {
    if (val == null || val.trim().isEmpty) return 'Required';
    final v = val.trim();
    final onlyDigits = RegExp(r'^\d+$');
    if (!onlyDigits.hasMatch(v)) return 'Digits only (no symbols)';
    if (v.length != 10) return 'Must be exactly 10 digits';
    return null;
  }

  String? _validateEmail(String? val) {
    if (val == null || val.trim().isEmpty) return 'Required';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return ok.hasMatch(val.trim()) ? null : 'Invalid email';
  }

  // ---------- date pickers with limits ----------
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
        // themed date picker
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
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primary, width: 2),
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

  // ---------- text field builder ----------
  Widget _buildTextField(
    String hint, {
    TextEditingController? controller,
    TextInputType? type,
    int maxLines = 1,
    bool isRequired = false,
    bool digitsOnly10 = false,
    String? Function(String?)? customValidator,
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
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        counterText: '',
      ),
      validator: (val) {
        if (digitsOnly10) return _validateTenDigitPhone(val);
        if (customValidator != null) return customValidator(val);
        if (isRequired) {
          return (val == null || val.trim().isEmpty) ? 'Required' : null;
        }
        return null;
      },
    );
  }

  Widget radioOption(String label, String value, String group) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(
          value: value,
          groupValue: group == "gender" ? gender : type,
          onChanged: (val) {
            setState(() {
              if (group == "gender") {
                gender = val!;
                if (gender != "Female") {
                  isPregnant = false;
                  weeksPregnantController.clear();
                  dueDate = null;
                }
              } else {
                type = val!;
              }
              _updateStepProgress();
            });
          },
          activeColor: _primary,
          fillColor: MaterialStateProperty.all(_primary),
        ),
        Text(label, style: const TextStyle(color: Colors.white)),
        const SizedBox(width: 10),
      ],
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
    remarksController.clear();
    medicineController.clear();
    emailController.clear();
    guardianNameController.clear();
    guardianContactController.clear();
    phoneController.clear();
    hospitalIdController.clear();
    wardNoController.clear();
    bedNoController.clear();
    homeAddressController.clear();
    workAddressController.clear();
    weeksPregnantController.clear();
    dateOfAdmit = null;
    dateOfBirth = null;
    dueDate = null;
    gender = null;
    type = null;
    selectedMohArea = null;
    isPregnant = false;
    _updateStepProgress();
    setState(() {});
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      _scrollToFirstInvalidField();
      return;
    }

    // confirm
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

    // auth check
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not signed in.')));
      return;
    }

    // fetch hospital profile (hospital-only)
    String hospitalIdProfile = '';
    String admitHospitalMoh = '';
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      final data = userDoc.data() ?? {};
      final role = (data['role'] ?? '').toString();
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
    } catch (e) {
      debugPrint('⚠️ Could not load hospital profile: $e');
    }

    final effectiveHospitalId = hospitalIdProfile.isNotEmpty
        ? hospitalIdProfile
        : hospitalIdController.text.trim();

    try {
      await FirebaseFirestore.instance.collection('dengue_cases').add({
        // ---- scope (who admits & where) ----
        'hospital_uid': authUser.uid,
        'hospital_id': effectiveHospitalId,
        'admit_hospital_moh': admitHospitalMoh,
        // ---- patient MOH (selector) ----
        'patient_moh_area': selectedMohArea,
        // ---- patient data ----
        'fullname': fullNameController.text.trim(),
        'address': homeAddressController.text.trim(),
        'ward_no': wardNoController.text.trim(),
        'bed_no': bedNoController.text.trim(),
        'phone_number': phoneController.text.trim(),
        'type': type, // New / Transferred
        'gender': gender,
        'status': 'Active',

        'date_of_admission': dateOfAdmit != null
            ? Timestamp.fromDate(dateOfAdmit!)
            : FieldValue.serverTimestamp(),
        'date_of_birth': dateOfBirth != null
            ? Timestamp.fromDate(dateOfBirth!)
            : null,

        'email': emailController.text.trim(),
        'guardian_name': guardianNameController.text.trim(),
        'guardian_contact': guardianContactController.text.trim(),
        'remarks': remarksController.text.trim(),
        'medicine': medicineController.text.trim(),
        'pregnant': isPregnant,
        'weeks_pregnant': isPregnant
            ? weeksPregnantController.text.trim()
            : null,
        'due_date': isPregnant && dueDate != null
            ? Timestamp.fromDate(dueDate!)
            : null,
        'school_or_work': workAddressController.text.trim(),

        // provenance
        'created_at': FieldValue.serverTimestamp(),
        'created_by': authUser.uid,
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Patient info added!')));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PatientManagementPage()),
      );
    } on FirebaseException catch (e) {
      debugPrint('🔥 Firestore error: ${e.code} — ${e.message}');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Firestore failed: ${e.code}')));
    } catch (e) {
      debugPrint('❌ Unknown error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to submit.')));
    }
  }

  // ---------- aligned timeline step ----------
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

  // (old navItemTile left here in case you still use it elsewhere)
  Widget navItemTile({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: selected
              ? BorderRadius.zero
              : const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? _primary : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(30),
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
            const SizedBox(height: 20),

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
            const SizedBox(height: 20),

            const Text(
              "🏥 Admission Info",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                radioOption("New", "New", "type"),
                radioOption("Transferred", "Transferred", "type"),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    "Hospital ID",
                    controller: hospitalIdController,
                    isRequired: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    "Ward No.",
                    controller: wardNoController,
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTextField(
                    "Bed No.",
                    controller: bedNoController,
                    isRequired: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildDateField(
              "Date of Admit",
              dateOfAdmit,
              (val) => setState(() => dateOfAdmit = val),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            ),
            const SizedBox(height: 20),

            const Text(
              "📞 Contact & Guardian",
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
              "Email",
              controller: emailController,
              isRequired: true,
              type: TextInputType.emailAddress,
              customValidator: _validateEmail,
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
            ),
            const SizedBox(height: 10),
            _buildTextField(
              "Guardian Name",
              controller: guardianNameController,
              isRequired: true,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              "Guardian Contact No.",
              controller: guardianContactController,
              isRequired: true,
              digitsOnly10: true,
            ),
            const SizedBox(height: 20),

            const Text(
              "🩺 Medical Info",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                radioOption("Male", "Male", "gender"),
                radioOption("Female", "Female", "gender"),
              ],
            ),
            if (gender == "Female") ...[
              Row(
                children: [
                  Checkbox(
                    value: isPregnant,
                    onChanged: (val) {
                      setState(() => isPregnant = val ?? false);
                      _updateStepProgress();
                    },
                    activeColor: _primary,
                    side: const BorderSide(color: Colors.white60),
                  ),
                  const Text("Pregnant", style: TextStyle(color: Colors.white)),
                ],
              ),
              if (isPregnant)
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        "Weeks Pregnant",
                        controller: weeksPregnantController,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _childDateDue()),
                  ],
                ),
            ],
            const SizedBox(height: 10),

            // Patient's MOH area (selector)
            DropdownSearch<String>(
              items: mohAreas,
              selectedItem: selectedMohArea,
              onChanged: (val) {
                setState(() => selectedMohArea = val);
                _updateStepProgress();
              },
              dropdownDecoratorProps: DropDownDecoratorProps(
                dropdownSearchDecoration: InputDecoration(
                  hintText: "Patient's MOH Area",
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
                ),
              ),
              popupProps: PopupProps.menu(
                showSearchBox: true,
                searchFieldProps: TextFieldProps(
                  decoration: InputDecoration(
                    hintText: "Search MOH Area...",
                    hintStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: _panelAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _ink.withOpacity(.35)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: _primary, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                menuProps: const MenuProps(backgroundColor: _panel),
              ),
              validator: (val) => val == null ? 'Required' : null,
              dropdownButtonProps: const DropdownButtonProps(
                icon: Icon(Icons.arrow_drop_down, color: Colors.white),
              ),
              dropdownBuilder: (context, selectedItem) => Text(
                selectedItem ?? '',
                style: const TextStyle(color: Colors.white),
              ),
            ),

            const SizedBox(height: 10),
            _buildTextField(
              "Remarks",
              controller: remarksController,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              "Prescribed Medicine",
              controller: medicineController,
              maxLines: 3,
            ),
            const SizedBox(height: 20),

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

  // due date with future-friendly range
  Widget _childDateDue() {
    return _buildDateField(
      "Due Date",
      dueDate,
      (val) => setState(() => dueDate = val),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(
          children: [
            // ===== SIDEBAR (fixed) =====
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
                            Icons.coronavirus,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'MOH ANALYTICS',
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
                  // Active page
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
                          pageBuilder: (_, __, ___) =>
                              const PatientManagementPage(),
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

            // ===== Main content (wider, themed) =====
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  height: MediaQuery.of(context).size.height * 0.92,
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
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _buildForm()),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.all(40),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0E1C2E), Color(0xFF09253A)],
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
                                "Contact & Guardian",
                                step3Complete,
                                isFirst: false,
                                isLast: false,
                              ),
                              const SizedBox(height: 6),
                              _timelineStep(
                                "STEP 4",
                                "Medical Info",
                                step4Complete,
                                isFirst: false,
                                isLast: true,
                              ),
                              const Spacer(),
                              Center(
                                child: Image.asset(
                                  'images/fmaily.png',
                                  height: 180,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

// ===== REUSABLE SIDENAV ITEM =====
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
