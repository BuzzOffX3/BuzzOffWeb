import 'dart:html' as html;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 🔐 auth for scoping
import 'PatientForm.dart';
import '../signin.dart';

class PatientManagementPage extends StatefulWidget {
  const PatientManagementPage({super.key});

  @override
  State<PatientManagementPage> createState() => _PatientManagementPageState();
}

const sectionTitleStyle = TextStyle(
  color: Colors.white70,
  fontSize: 14,
  fontWeight: FontWeight.bold,
);

// ======= THEME (midnight blue + teal) =======
const _bg = Color(0xFF0C0F1A);
const _sidebar = Color(0xFF121826);
const _panel = Color(0xFF0F1522);
const _panelAlt = Color(0xFF10182A);
const _ink = Color(0xFF233049);
const _primary = Color(0xFF00D3A7); // teal
const _primaryDim = Color(0xFF00B895);
const _chipBg = Color(0xFF1A2133);

// --- Table palette ---
const _tblHeaderBg = Color(0xFF19233A);
const _tblRowA = Color(0xFF0F1522);
const _tblRowB = Color(0xFF0C1220);
const _tblBorder = Color(0xFF233049);

// --- KPI sizing/spacing ---
const double _kpiWidth = 300; // wider
const double _kpiHeight = 160;
const double _kpiGap = 22;

// --- Wider page max width ---
const double _pageMaxWidth = 1560;

// --- aliases used by the sidebar snippet ---
const Color sidebar = _sidebar;
const Color purple = _primary;
const Color text = Colors.white;
const Color subtext = Colors.white70;

class _PatientManagementPageState extends State<PatientManagementPage> {
  DocumentSnapshot? selectedPatient;

  // 🔐 signed-in uid (null until available)
  String? _uid;

  // Sidebar name (live from Firestore)
  String username = 'User';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  // form controllers (right panel)
  final TextEditingController nameController = TextEditingController();
  final TextEditingController genderController = TextEditingController();
  final TextEditingController guardianNameController = TextEditingController();
  final TextEditingController guardianContactController =
      TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController mohAreaController =
      TextEditingController(); // patient MOH
  final TextEditingController addressController = TextEditingController();
  final TextEditingController wardNoController = TextEditingController();
  final TextEditingController bedNoController = TextEditingController();
  final TextEditingController medicineController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  final TextEditingController schoolWorkController = TextEditingController();

  String? status;
  String? type;

  // --- KPI/table filter state ---
  String? _statusFilter; // 'Active', 'Recovered', 'Deceased' or null
  bool _filterRecoveredThisMonth = false;

  // --- toolbar search ---
  String _searchQuery = '';

  // --- saving guard ---
  bool _saving = false;

  // --- table density ---
  bool _denseTable = false;

  @override
  void initState() {
    super.initState();

    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) {
      _listenToUserProfile(_uid!);
    }

    FirebaseAuth.instance.authStateChanges().listen((user) {
      setState(() => _uid = user?.uid);
      if (user?.uid != null) {
        _listenToUserProfile(user!.uid);
      } else {
        setState(() => username = 'User');
        _profileSub?.cancel();
        _profileSub = null;
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    nameController.dispose();
    genderController.dispose();
    guardianNameController.dispose();
    guardianContactController.dispose();
    phoneController.dispose();
    emailController.dispose();
    mohAreaController.dispose();
    addressController.dispose();
    wardNoController.dispose();
    bedNoController.dispose();
    medicineController.dispose();
    remarkController.dispose();
    schoolWorkController.dispose();
    super.dispose();
  }

  // ===== Firestore profile helpers =====
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

  DateTime get _startOfThisMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  DateTime get _startOfNextMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1);
  }

  bool get _hasAnyFilterActive =>
      _statusFilter != null ||
      _filterRecoveredThisMonth ||
      _searchQuery.isNotEmpty;

  Query _hospitalCasesQuery(String uid) {
    return FirebaseFirestore.instance
        .collection('dengue_cases')
        .where('hospital_uid', isEqualTo: uid);
  }

  // ---------- READ: prefer safe keys, fall back to legacy keys ----------
  void populateForm(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    nameController.text = (data['fullname'] ?? '').toString();
    genderController.text = (data['gender'] ?? '').toString();

    guardianNameController.text =
        (data['guardian_name'] ?? data['guardian_name '] ?? '').toString();
    guardianContactController.text = (data['guardian_contact'] ?? '')
        .toString();

    phoneController.text = (data['phone_number'] ?? '').toString();
    emailController.text = (data['email'] ?? '').toString();

    // 👇 patient’s MOH (not hospital scope)
    mohAreaController.text =
        (data['patient_moh_area'] ?? data['moh_area'] ?? '').toString();

    addressController.text = (data['address'] ?? '').toString();
    wardNoController.text = (data['ward_no'] ?? '').toString();
    bedNoController.text = (data['bed_no'] ?? '').toString();

    // safe first, legacy fallbacks
    medicineController.text =
        (data['medicine'] ??
                data['prescribed_medicine'] ??
                data['presecribed_medicine'] ??
                data['medicine '] ??
                '')
            .toString();
    remarkController.text = (data['remarks'] ?? data['remark'] ?? '')
        .toString();
    schoolWorkController.text =
        (data['school_or_work'] ?? data['school/work'] ?? '').toString();

    status = _titleCase((data['status'] ?? '').toString());
    type = _titleCase((data['type'] ?? '').toString());
    setState(() {});
  }

  String? _titleCase(String? s) {
    if (s == null || s.isEmpty) return null;
    final low = s.toLowerCase();
    return low[0].toUpperCase() + low.substring(1);
  }

  int calculateAge(Timestamp? dob) {
    if (dob == null) return 0;
    final birthDate = dob.toDate();
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  // last-N days bucket for sparkline series
  List<double> _bucketPerDay(Iterable<Timestamp> times, {int days = 14}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1));
    final buckets = List<double>.filled(days, 0);
    for (final ts in times) {
      final d = ts.toDate();
      final day = DateTime(d.year, d.month, d.day);
      if (!day.isBefore(start) && !day.isAfter(today)) {
        final idx = day.difference(start).inDays;
        if (idx >= 0 && idx < days) buckets[idx] += 1;
      }
    }
    return buckets;
  }

  // ---------- WRITE: normalized status/type + timestamp sync ----------
  Future<void> _saveChanges() async {
    if (selectedPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a patient row first')),
      );
      return;
    }

    // normalize
    final newStatus = (status ?? '').trim().toLowerCase();
    final newType = (type ?? '').trim().toLowerCase();

    // guard accidental "deceased"
    if (newStatus == 'deceased') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _panelAlt,
          title: const Text(
            'Mark as Deceased?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This will mark the patient as deceased and update charts.\nAre you sure?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    if (_saving) return;
    setState(() => _saving = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection('dengue_cases')
          .doc(selectedPatient!.id);

      final old = (await docRef.get()).data() ?? <String, dynamic>{};
      final oldStatus = (old['status'] ?? '').toString().toLowerCase();

      final updates = <String, dynamic>{
        'fullname': nameController.text.trim(),
        'gender': genderController.text.trim(),
        'guardian_name': guardianNameController.text.trim(),
        'guardian_contact': guardianContactController.text.trim(),
        'phone_number': phoneController.text.trim(),
        'email': emailController.text.trim(),

        // 👇 we edit the patient’s MOH, not scope fields
        'patient_moh_area': mohAreaController.text.trim(),

        'address': addressController.text.trim(),
        'ward_no': wardNoController.text.trim(),
        'bed_no': bedNoController.text.trim(),
        'medicine': medicineController.text.trim(),
        'remarks': remarkController.text.trim(),
        'school_or_work': schoolWorkController.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (newStatus.isNotEmpty) updates['status'] = newStatus;
      if (newType.isNotEmpty) updates['type'] = newType;

      // ---- keep timestamps in sync with CURRENT status ----
      if (newStatus != oldStatus) {
        if (newStatus == 'recovered') {
          updates['recovered_at'] = FieldValue.serverTimestamp();
          updates['deceased_at'] = null;
        } else if (newStatus == 'deceased') {
          updates['deceased_at'] = FieldValue.serverTimestamp();
          updates['recovered_at'] = null;
        } else {
          // active / other: clear both milestone stamps
          updates['recovered_at'] = null;
          updates['deceased_at'] = null;
        }
      } else {
        // keep consistent even if status text didn't change
        if (newStatus != 'recovered' && (old['recovered_at'] != null)) {
          updates['recovered_at'] = null;
        }
        if (newStatus != 'deceased' && (old['deceased_at'] != null)) {
          updates['deceased_at'] = null;
        }
      }

      await docRef.set(updates, SetOptions(merge: true));

      selectedPatient = await docRef.get();
      setState(() {});

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved ✅')));
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: ${e.code} — ${e.message}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- header + controls on the same row (wraps on small widths) ----
  Widget _searchBox() {
    return SizedBox(
      width: 360,
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          hintText: 'Search by name, patient MOH, or address',
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: _panelAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _ink.withOpacity(.4)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 14,
          ),
        ),
      ),
    );
  }

  Widget _recoveredToggle() {
    return FilterChip(
      label: const Text('Recovered this month'),
      selected: _filterRecoveredThisMonth,
      onSelected: (val) => setState(() => _filterRecoveredThisMonth = val),
      selectedColor: _primary.withOpacity(.25),
      showCheckmark: false,
      labelStyle: const TextStyle(color: Colors.white),
      backgroundColor: _chipBg,
      side: BorderSide(color: _ink.withOpacity(.35)),
    );
  }

  Widget _addPatientBtn() {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, a1, a2) => const PatientFormPage(),
            transitionDuration: Duration.zero,
          ),
        );
      },
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text('Add Patient', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _headerAndControls() {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 900;
        final controls = Wrap(
          alignment: isNarrow ? WrapAlignment.start : WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [_searchBox(), _recoveredToggle(), _addPatientBtn()],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Patient Overview",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              controls,
            ],
          );
        } else {
          return Row(
            children: [
              const Text(
                "Patient Overview",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              controls,
            ],
          );
        }
      },
    );
  }

  // ===== apply the SAME filters/search as the table (for reuse) =====
  List<QueryDocumentSnapshot> _applyFilters(
    List<QueryDocumentSnapshot> docs, {
    DateTime? startOfMonth,
    DateTime? startOfNext,
  }) {
    final start = startOfMonth ?? _startOfThisMonth;
    final next = startOfNext ?? _startOfNextMonth;

    return docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;

      // KPI status filter
      if (_statusFilter != null) {
        final s = (d['status'] ?? '').toString().toLowerCase();
        if (_statusFilter == 'Recovered' && _filterRecoveredThisMonth) {
          final ts = d['recovered_at'] as Timestamp?;
          if (ts == null) return false;
          final dt = ts.toDate();
          final inMonth = !dt.isBefore(start) && dt.isBefore(next);
          if (!(s == 'recovered' && inMonth)) return false;
        } else {
          if (s != _statusFilter!.toLowerCase()) return false;
        }
      }

      // search filter
      if (_searchQuery.isNotEmpty) {
        final name = (d['fullname'] ?? '').toString().toLowerCase();
        final moh = (d['patient_moh_area'] ?? d['moh_area'] ?? '')
            .toString()
            .toLowerCase();
        final addr = (d['address'] ?? '').toString().toLowerCase();
        final hay = '$name $moh $addr';
        if (!hay.contains(_searchQuery)) return false;
      }

      return true;
    }).toList();
  }

  // ===== Export current filtered subset to CSV (web) =====
  Future<void> _exportCsv(List<QueryDocumentSnapshot> allDocs) async {
    try {
      final filtered = _applyFilters(allDocs);

      final rows = <List<String>>[];
      rows.add([
        '#',
        'Full Name',
        'Gender',
        'Age',
        'Admission Date',
        'Status',
        'Patient MOH Area',
        'Address',
        'Guardian Name',
        'Guardian Contact',
        'Phone',
        'Email',
        'Ward No',
        'Bed No',
        'Medicine',
        'Remarks',
        'School/Work',
      ]);

      final df = DateFormat('yyyy-MM-dd');

      for (int i = 0; i < filtered.length; i++) {
        final data = filtered[i].data() as Map<String, dynamic>;
        final dob = data['date_of_birth'] as Timestamp?;
        final doa = data['date_of_admission'] as Timestamp?;
        final age = calculateAge(dob);
        final admissionDate = doa != null ? df.format(doa.toDate()) : '';

        rows.add([
          '${i + 1}',
          (data['fullname'] ?? '').toString(),
          (data['gender'] ?? '').toString(),
          '$age',
          admissionDate,
          (data['status'] ?? '').toString(),
          (data['patient_moh_area'] ?? data['moh_area'] ?? '').toString(),
          (data['address'] ?? '').toString(),
          (data['guardian_name'] ?? data['guardian_name '] ?? '').toString(),
          (data['guardian_contact'] ?? '').toString(),
          (data['phone_number'] ?? '').toString(),
          (data['email'] ?? '').toString(),
          (data['ward_no'] ?? '').toString(),
          (data['bed_no'] ?? '').toString(),
          (data['medicine'] ??
                  data['prescribed_medicine'] ??
                  data['presecribed_medicine'] ??
                  data['medicine '] ??
                  '')
              .toString(),
          (data['remarks'] ?? data['remark'] ?? '').toString(),
          (data['school_or_work'] ?? data['school/work'] ?? '').toString(),
        ]);
      }

      // Build CSV
      final csv = const ListToCsvConverter().convert(rows);
      final bytes = utf8.encode(csv);
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..download = 'patients_${DateTime.now().millisecondsSinceEpoch}.csv';
      anchor.click();
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${filtered.length} rows to CSV ✅')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Poppins'),
      child: Scaffold(
        backgroundColor: _bg,
        body: Row(
          children: [
            // ===== SIDEBAR (unified with Patient Form page) =====
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

                  _SideNavItem(
                    icon: Icons.dashboard_outlined,
                    label: 'Patient Form',
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const PatientFormPage(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    },
                  ),
                  const _SideNavItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Patient Management',
                    active: true, // current page
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

            // ===== Right content — wider constraint to eat empty space
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _headerAndControls(),
                        const SizedBox(height: 14),

                        // ===== KPI ROW =====
                        if (_uid == null)
                          const Center(
                            child: Text(
                              'Please sign in to view your hospital’s cases',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        else
                          StreamBuilder<QuerySnapshot>(
                            stream: _hospitalCasesQuery(_uid!).snapshots(),
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'Error: ${snap.error}',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                );
                              }
                              if (!snap.hasData) {
                                return Center(
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: _kpiGap,
                                    runSpacing: _kpiGap,
                                    children: const [
                                      _StatSkeleton(),
                                      _StatSkeleton(),
                                      _StatSkeleton(),
                                      _StatSkeleton(),
                                    ],
                                  ),
                                );
                              }

                              final docs = snap.data!.docs;

                              // KPI numbers + series
                              int active = 0,
                                  deaths = 0,
                                  dischargedThisMonth = 0,
                                  totalThisMonth = 0;
                              final admissionsAllTimes = <Timestamp>[];
                              final recoveredTimes = <Timestamp>[];
                              final deathTimes = <Timestamp>[];

                              final startOfMonth = _startOfThisMonth;
                              final startOfNext = _startOfNextMonth;

                              for (final d in docs) {
                                final m = d.data() as Map<String, dynamic>;
                                final s = (m['status'] ?? '')
                                    .toString()
                                    .toLowerCase();

                                final doa = m['date_of_admission'];
                                if (doa is Timestamp) {
                                  admissionsAllTimes.add(doa);
                                  final ad = doa.toDate();
                                  if (!ad.isBefore(startOfMonth) &&
                                      ad.isBefore(startOfNext)) {
                                    totalThisMonth++;
                                  }
                                }

                                if (s == 'active') {
                                  active++;
                                } else if (s == 'deceased') {
                                  final da = m['deceased_at'];
                                  if (da is Timestamp) deathTimes.add(da);
                                  deaths++;
                                } else if (s == 'recovered') {
                                  final ra = m['recovered_at'] as Timestamp?;
                                  if (ra != null) {
                                    recoveredTimes.add(ra);
                                    final dt = ra.toDate();
                                    if (!dt.isBefore(startOfMonth) &&
                                        dt.isBefore(startOfNext)) {
                                      dischargedThisMonth++;
                                    }
                                  }
                                }
                              }

                              final allAdmissionsSeries = _bucketPerDay(
                                admissionsAllTimes,
                                days: 14,
                              );
                              final rSeries = _bucketPerDay(
                                recoveredTimes,
                                days: 14,
                              );
                              final dSeries = _bucketPerDay(
                                deathTimes,
                                days: 14,
                              );

                              return Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: _kpiGap,
                                  runSpacing: _kpiGap,
                                  children: [
                                    statCardDynamic(
                                      title: "Total Patients (This Month)",
                                      value: totalThisMonth.toString(),
                                      series: allAdmissionsSeries,
                                      color: _primaryDim,
                                      selected:
                                          _statusFilter == null &&
                                          !_filterRecoveredThisMonth,
                                      onTap: () {
                                        setState(() {
                                          _statusFilter = null;
                                          _filterRecoveredThisMonth = false;
                                        });
                                      },
                                      width: _kpiWidth,
                                      height: _kpiHeight,
                                    ),
                                    statCardDynamic(
                                      title: "Current Patients",
                                      value: active.toString(),
                                      series: allAdmissionsSeries,
                                      color: const Color(0xFF6EA8FE),
                                      selected:
                                          _statusFilter == 'Active' &&
                                          !_filterRecoveredThisMonth,
                                      onTap: () {
                                        setState(() {
                                          if (_statusFilter == 'Active' &&
                                              !_filterRecoveredThisMonth) {
                                            _statusFilter = null;
                                          } else {
                                            _statusFilter = 'Active';
                                            _filterRecoveredThisMonth = false;
                                          }
                                        });
                                      },
                                      width: _kpiWidth,
                                      height: _kpiHeight,
                                    ),
                                    statCardDynamic(
                                      title: "Discharged (This Month)",
                                      value: dischargedThisMonth.toString(),
                                      series: rSeries,
                                      color: const Color(0xFF5FD7C5),
                                      selected:
                                          _statusFilter == 'Recovered' &&
                                          _filterRecoveredThisMonth,
                                      onTap: () {
                                        setState(() {
                                          if (_statusFilter == 'Recovered' &&
                                              _filterRecoveredThisMonth) {
                                            _statusFilter = null;
                                            _filterRecoveredThisMonth = false;
                                          } else {
                                            _statusFilter = 'Recovered';
                                            _filterRecoveredThisMonth = true;
                                          }
                                        });
                                      },
                                      width: _kpiWidth,
                                      height: _kpiHeight,
                                    ),
                                    statCardDynamic(
                                      title: "Deceased",
                                      value: deaths.toString(),
                                      series: dSeries,
                                      color: const Color(0xFFFF6B6B),
                                      selected:
                                          _statusFilter == 'Deceased' &&
                                          !_filterRecoveredThisMonth,
                                      onTap: () {
                                        setState(() {
                                          if (_statusFilter == 'Deceased' &&
                                              !_filterRecoveredThisMonth) {
                                            _statusFilter = null;
                                          } else {
                                            _statusFilter = 'Deceased';
                                            _filterRecoveredThisMonth = false;
                                          }
                                        });
                                      },
                                      width: _kpiWidth,
                                      height: _kpiHeight,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 14),

                        // ===== Table + side form =====
                        Expanded(
                          child: Row(
                            children: [
                              // table takes remaining width
                              Expanded(
                                child: _uid == null
                                    ? const Center(
                                        child: Text(
                                          'Please sign in to view your hospital’s cases',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      )
                                    : StreamBuilder<QuerySnapshot>(
                                        stream: _hospitalCasesQuery(_uid!)
                                            .orderBy(
                                              'date_of_admission',
                                              descending: true,
                                            )
                                            .snapshots(),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasError) {
                                            return Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Text(
                                                'Error: ${snapshot.error}',
                                                style: const TextStyle(
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            );
                                          }
                                          if (!snapshot.hasData) {
                                            return const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            );
                                          }

                                          final all = snapshot.data!.docs;
                                          final filtered = _applyFilters(all);

                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // ---- Report Toolbar
                                              Row(
                                                children: [
                                                  ElevatedButton.icon(
                                                    onPressed: () =>
                                                        _exportCsv(all),
                                                    icon: const Icon(
                                                      Icons.download,
                                                      color: Colors.white,
                                                    ),
                                                    label: const Text(
                                                      'Export CSV',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: _primary,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 10,
                                                            horizontal: 14,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  if (_hasAnyFilterActive)
                                                    OutlinedButton.icon(
                                                      onPressed: () => setState(
                                                        () {
                                                          _statusFilter = null;
                                                          _filterRecoveredThisMonth =
                                                              false;
                                                          _searchQuery = '';
                                                        },
                                                      ),
                                                      icon: const Icon(
                                                        Icons.filter_alt_off,
                                                        color: Colors.white70,
                                                      ),
                                                      label: const Text(
                                                        'Clear filters',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                      style: OutlinedButton.styleFrom(
                                                        side: BorderSide(
                                                          color: _ink
                                                              .withOpacity(.4),
                                                        ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 10,
                                                              horizontal: 14,
                                                            ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  const Spacer(),
                                                  Tooltip(
                                                    message: _denseTable
                                                        ? 'Comfort density'
                                                        : 'Compact density',
                                                    child: IconButton(
                                                      onPressed: () => setState(
                                                        () => _denseTable =
                                                            !_denseTable,
                                                      ),
                                                      icon: Icon(
                                                        _denseTable
                                                            ? Icons.view_comfy
                                                            : Icons.table_rows,
                                                      ),
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),

                                              // ---- Table ----
                                              Expanded(
                                                child: _buildPatientTableBody(
                                                  filtered,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(width: 16),
                              // fixed-width right panel (wider)
                              SizedBox(width: 380, child: buildPatientForm()),
                            ],
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
      ),
    );
  }

  // Only the body of the table (header moved here via first row)
  Widget _buildPatientTableBody(List<QueryDocumentSnapshot> docs) {
    final double vPad = _denseTable ? 8 : 14;

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Header
          Container(
            padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 12),
            decoration: const BoxDecoration(
              color: _tblHeaderBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 1, child: _Hdr(' # ')),
                Expanded(flex: 3, child: _Hdr('Name')),
                Expanded(flex: 2, child: _Hdr('Gender')),
                Expanded(flex: 1, child: _Hdr('Age')),
                Expanded(flex: 3, child: _Hdr('Admission Date')),
                Expanded(flex: 2, child: _Hdr('Status')),
                Expanded(flex: 2, child: _Hdr('Patient MOH Area')),
                Expanded(flex: 3, child: _Hdr('Address')),
              ],
            ),
          ),

          // Table Content
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: _tblRowA,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final dob = data['date_of_birth'] as Timestamp?;
                  final doa = data['date_of_admission'] as Timestamp?;
                  final age = calculateAge(dob);
                  final admissionDate = doa != null
                      ? DateFormat('yyyy-MM-dd').format(doa.toDate())
                      : '-';

                  final rowColor = index.isEven ? _tblRowA : _tblRowB;

                  return InkWell(
                    onTap: () {
                      selectedPatient = doc;
                      populateForm(doc);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: vPad,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: rowColor,
                        border: const Border(
                          top: BorderSide(color: _tblBorder, width: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              (data['fullname'] ?? '').toString(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              (data['gender'] ?? '').toString(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              '$age',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              admissionDate,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              (data['status'] ?? '').toString(),
                              style: TextStyle(
                                color: getStatusColor(
                                  (data['status'] ?? '').toString(),
                                ),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              (data['patient_moh_area'] ??
                                      data['moh_area'] ??
                                      '')
                                  .toString(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              (data['address'] ?? '').toString(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== EMPTY-STATE-AWARE RIGHT PANEL =====
  Widget buildPatientForm() {
    final panel = Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(2, 4),
          ),
        ],
        border: Border.all(color: _ink.withOpacity(.35)),
      ),
      padding: const EdgeInsets.all(18),
      child: selectedPatient == null
          // ---- EMPTY STATE ----
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 34,
                    backgroundColor: _primary,
                    child: Icon(
                      Icons.person_search,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'No patient selected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select a row from the table to view/edit details\nor add a new patient.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, a1, a2) =>
                              const PatientFormPage(),
                          transitionDuration: Duration.zero,
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text(
                      'Add Patient',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            )
          // ---- EXISTING FORM ----
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'Patient Details',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: _primary,
                      child: Icon(Icons.person, color: Colors.white, size: 28),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Personal Information', style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  buildTextField(
                    nameController,
                    'Full Name',
                    icon: Icons.person,
                  ),
                  buildTextField(
                    genderController,
                    'Gender',
                    icon: Icons.transgender,
                  ),

                  const SizedBox(height: 8),
                  const Text('Guardian Information', style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  buildTextField(
                    guardianNameController,
                    'Guardian Name',
                    icon: Icons.person_outline,
                  ),
                  buildTextField(
                    guardianContactController,
                    'Guardian Contact',
                    icon: Icons.phone_android,
                  ),

                  const SizedBox(height: 8),
                  const Text('Contact Information', style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  buildTextField(
                    phoneController,
                    'Phone Number',
                    icon: Icons.phone,
                  ),
                  buildTextField(emailController, 'Email', icon: Icons.email),

                  const SizedBox(height: 8),
                  const Text('Hospital Information', style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  buildTextField(
                    mohAreaController,
                    'Patient MOH Area',
                    icon: Icons.location_on,
                  ),
                  buildTextField(
                    addressController,
                    'Address',
                    icon: Icons.home,
                  ),
                  buildTextField(
                    wardNoController,
                    'Ward No',
                    icon: Icons.meeting_room,
                  ),
                  buildTextField(
                    bedNoController,
                    'Bed No',
                    icon: Icons.bed_outlined,
                  ),

                  const SizedBox(height: 8),
                  const Text('Medical Information', style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  buildTextField(
                    medicineController,
                    'Medicine',
                    icon: Icons.medical_services,
                  ),
                  buildTextField(
                    schoolWorkController,
                    'School/Work',
                    icon: Icons.school,
                  ),
                  buildTextField(
                    remarkController,
                    'Remarks',
                    icon: Icons.notes,
                  ),

                  const SizedBox(height: 8),
                  const Text('Status & Type', style: sectionTitleStyle),
                  const SizedBox(height: 8),

                  if (status != null && status!.isNotEmpty)
                    Chip(
                      label: Text(
                        status!,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: getStatusColor(status!),
                    ),
                  const SizedBox(height: 8),
                  buildDropdown('Status', status, [
                    'Active',
                    'Recovered',
                    'Deceased',
                  ], (val) => setState(() => status = val)),
                  buildDropdown('Type', type, [
                    'New',
                    'Transferred',
                  ], (val) => setState(() => type = val)),

                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, color: Colors.white),
                    label: Text(
                      _saving ? 'Saving...' : 'Save Changes',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _saving ? null : _saveChanges,
                  ),

                  const SizedBox(height: 12),
                  Text(
                    'Last Updated: ${DateFormat.yMd().format(DateTime.now())}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
    );

    return panel;
  }

  Widget buildTextField(
    TextEditingController controller,
    String label, {
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: icon != null ? Icon(icon, color: Colors.white54) : null,
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: _panelAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _ink.withOpacity(.35)),
          ),
        ),
      ),
    );
  }

  Widget buildDropdown(
    String label,
    String? value,
    List<String> items,
    void Function(String?) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: value.isEmptyOrNull ? null : value,
        dropdownColor: _panelAlt,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: _panelAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _ink.withOpacity(.35)),
          ),
        ),
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(e, style: const TextStyle(color: Colors.white)),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ===== KPI card with real mini area chart (no overflow) =====
  Widget statCardDynamic({
    required String title,
    required String value,
    required List<double> series,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
    double? width,
    double height = _kpiHeight,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [(selected ? color : color.withOpacity(0.35)), _panel],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
            ],
            border: Border.all(
              color: selected ? color.withOpacity(0.7) : Colors.transparent,
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: double.tryParse(value) ?? 0),
                duration: const Duration(milliseconds: 450),
                builder: (_, val, __) => Text(
                  val.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: MiniAreaChart(data: series, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== helper widgets/classes =====

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

class _Hdr extends StatelessWidget {
  final String label;
  const _Hdr(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    );
  }
}

class _StatSkeleton extends StatelessWidget {
  const _StatSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kpiWidth,
      height: _kpiHeight,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class MiniAreaChart extends StatelessWidget {
  final List<double> data;
  final Color color;
  const MiniAreaChart({super.key, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final double maxVal = data.isEmpty
        ? 1
        : data.reduce((a, b) => a > b ? a : b);
    final double top = maxVal <= 0 ? 1 : maxVal * 1.25; // headroom

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (data.isEmpty ? 1 : data.length - 1).toDouble(),
          minY: 0,
          maxY: top,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          clipData: const FlClipData.all(),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (int i = 0; i < data.length; i++)
                  FlSpot(i.toDouble(), data[i]),
              ],
              isCurved: true,
              barWidth: 2,
              color: color,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.35), color.withOpacity(0.05)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
      ),
    );
  }
}

extension NullableString on String? {
  bool get isEmptyOrNull => this == null || this!.isEmpty;
}

Color getStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'active':
      return const Color(0xFFF4C430); // warm yellow
    case 'recovered':
      return const Color(0xFF3DDC97); // green
    case 'deceased':
      return const Color(0xFFFF5C5C); // red
    default:
      return Colors.grey;
  }
}

// ===== simple CSV converter =====
class ListToCsvConverter {
  const ListToCsvConverter();
  String convert(List<List<String>> rows) {
    return rows.map(_toCsvRow).join('\n');
  }

  String _toCsvRow(List<String> row) {
    return row
        .map((cell) {
          final needsQuotes =
              cell.contains(',') || cell.contains('"') || cell.contains('\n');
          var out = cell.replaceAll('"', '""');
          return needsQuotes ? '"$out"' : out;
        })
        .join(',');
  }
}
