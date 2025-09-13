import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
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

// ======= THEME & BREAKPOINTS =======
const _bg = Color(0xFF0C0F1A);
const _sidebar = Color(0xFF121826);
const _panel = Color(0xFF0F1522);
const _panelAlt = Color(0xFF10182A);
const _ink = Color(0xFF233049);
const _primary = Color(0xFF00D3A7);
const _primaryDim = Color(0xFF00B895);
const _chipBg = Color(0xFF1A2133);
const _tblHeaderBg = Color(0xFF19233A);
const _tblRowA = Color(0xFF0F1522);
const _tblRowB = Color(0xFF0C1220);
const _tblBorder = Color(0xFF233049);
const double _kpiWidth = 300;
const double _kpiHeight = 160;
const double _kpiGap = 22;
const double _pageMaxWidth = 1560;

const Color sidebar = _sidebar;
const Color purple = _primary;
const Color text = Colors.white;
const Color subtext = Colors.white70;

// responsive breakpoints
const double _bpMd = 900; // switch to drawer + stacked content
const double _bpLg = 1200; // roomier layouts

class _PatientManagementPageState extends State<PatientManagementPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  DocumentSnapshot? selectedPatient;

  String? _uid;
  String username = 'User';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  // right-panel controllers (ONLY kept fields)
  final TextEditingController nameController = TextEditingController();
  final TextEditingController guardianContactController =
      TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController mohAreaController = TextEditingController();
  final TextEditingController phiAreaController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController schoolWorkController = TextEditingController();

  // we still read/display status in table/KPIs, but no longer edit it here
  String? status;

  // filters
  String? _statusFilter;
  bool _filterRecoveredThisMonth = false; // reused as "this year"
  String _searchQuery = '';
  bool _saving = false;
  bool _denseTable = false;

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
    guardianContactController.dispose();
    phoneController.dispose();
    mohAreaController.dispose();
    phiAreaController.dispose();
    addressController.dispose();
    schoolWorkController.dispose();
    super.dispose();
  }

  // ===== profile helpers =====
  String _pickName(Map<String, dynamic> m) {
    for (final k in [
      'display_name',
      'displayName',
      'name',
      'full_name',
      'username',
    ]) {
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

  // ===== year window for KPIs =====
  DateTime get _startOfThisYear {
    final now = DateTime.now();
    return DateTime(now.year, 1, 1);
  }

  DateTime get _startOfNextYear {
    final now = DateTime.now();
    return DateTime(now.year + 1, 1, 1);
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

  // ---------- READ populate ----------
  void populateForm(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    nameController.text = (data['fullname'] ?? '').toString();
    guardianContactController.text = (data['guardian_contact'] ?? '')
        .toString();
    phoneController.text = (data['phone_number'] ?? '').toString();

    mohAreaController.text =
        (data['patient_moh_area'] ?? data['moh_area'] ?? '').toString();
    phiAreaController.text =
        (data['patient_phi_area'] ?? data['phi_area'] ?? '').toString();

    addressController.text = (data['address'] ?? '').toString();
    schoolWorkController.text =
        (data['school_or_work'] ?? data['school/work'] ?? '').toString();

    status = _titleCase((data['status'] ?? '').toString());
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

  // ---------- WRITE ----------
  Future<void> _saveChanges() async {
    if (selectedPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a patient row first')),
      );
      return;
    }

    if (_saving) return;
    setState(() => _saving = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection('dengue_cases')
          .doc(selectedPatient!.id);

      final updates = <String, dynamic>{
        'fullname': nameController.text.trim(),
        'guardian_contact': guardianContactController.text.trim(),
        'phone_number': phoneController.text.trim(),
        'patient_moh_area': mohAreaController.text.trim(),
        'patient_phi_area': phiAreaController.text.trim(),
        'address': addressController.text.trim(),
        'school_or_work': schoolWorkController.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // NOTE: status editing removed per request; KPIs still read existing status.

      await docRef.set(updates, SetOptions(merge: true));
      selectedPatient = await docRef.get();
      if (mounted) setState(() {});
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

  // ===== UI =====
  Widget _searchBox() {
    return SizedBox(
      width: 360,
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          hintText: 'Search by name, patient MOH/PHI, or address',
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
      label: const Text('Recovered this year'),
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

  Widget _headerAndControls(BoxConstraints c) {
    final isNarrow = c.maxWidth < _bpMd;
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
  }

  // Filter for table; shows all by default; when "Recovered this year" chip is on + status=Recovered, applies year window
  List<QueryDocumentSnapshot> _applyFilters(List<QueryDocumentSnapshot> docs) {
    final start = _startOfThisYear;
    final next = _startOfNextYear;

    return docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;

      if (_statusFilter != null) {
        final s = (d['status'] ?? '').toString().toLowerCase();
        if (_statusFilter == 'Recovered' && _filterRecoveredThisMonth) {
          final ts = d['recovered_at'] as Timestamp?;
          if (ts == null) return false;
          final dt = ts.toDate();
          final inYear = !dt.isBefore(start) && dt.isBefore(next);
          if (!(s == 'recovered' && inYear)) return false;
        } else {
          if (s != _statusFilter!.toLowerCase()) return false;
        }
      }

      if (_searchQuery.isNotEmpty) {
        final name = (d['fullname'] ?? '').toString().toLowerCase();
        final moh = (d['patient_moh_area'] ?? d['moh_area'] ?? '')
            .toString()
            .toLowerCase();
        final phi = (d['patient_phi_area'] ?? d['phi_area'] ?? '')
            .toString()
            .toLowerCase();
        final addr = (d['address'] ?? '').toString().toLowerCase();
        final hay = '$name $moh $phi $addr';
        if (!hay.contains(_searchQuery)) return false;
      }

      return true;
    }).toList();
  }

  Future<void> _exportCsv(List<QueryDocumentSnapshot> allDocs) async {
    try {
      final filtered = _applyFilters(allDocs);
      final rows = <List<String>>[];
      rows.add([
        '#',
        'Full Name',
        'Age',
        'Admission Date',
        'Status',
        'Patient MOH Area',
        'Patient PHI Area',
        'Address',
        'Guardian Contact',
        'Phone',
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
          '$age',
          admissionDate,
          (data['status'] ?? '').toString(),
          (data['patient_moh_area'] ?? data['moh_area'] ?? '').toString(),
          (data['patient_phi_area'] ?? data['phi_area'] ?? '').toString(),
          (data['address'] ?? '').toString(),
          (data['guardian_contact'] ?? '').toString(),
          (data['phone_number'] ?? '').toString(),
          (data['school_or_work'] ?? data['school/work'] ?? '').toString(),
        ]);
      }

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
    return LayoutBuilder(
      builder: (_, constraints) {
        final isCompact = constraints.maxWidth < _bpMd;
        final bodyPad = isCompact ? 8.0 : 18.0;

        final appBar = isCompact
            ? AppBar(
                backgroundColor: sidebar,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                title: const Text('Patient Management'),
              )
            : null;

        final content = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: bodyPad, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(builder: (c, b) => _headerAndControls(b)),
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
                              style: const TextStyle(color: Colors.redAccent),
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

                        // --- Year window ---
                        final startOfYear = _startOfThisYear;
                        final startOfNextYear = _startOfNextYear;

                        // KPI counters (THIS YEAR)
                        int totalThisYear = 0;
                        int activeThisYear = 0;
                        int dischargedThisYear = 0;
                        int deathsThisYear = 0;

                        // Sparklines (THIS YEAR)
                        final List<Timestamp> admissionsThisYear =
                            <Timestamp>[];
                        final List<Timestamp> recoveredThisYear = <Timestamp>[];
                        final List<Timestamp> deathThisYear = <Timestamp>[];

                        for (final d in docs) {
                          final m = d.data() as Map<String, dynamic>;
                          final s = (m['status'] ?? '')
                              .toString()
                              .toLowerCase();

                          final doa = m['date_of_admission'];
                          if (doa is Timestamp) {
                            final ad = doa.toDate();
                            final inYear =
                                !ad.isBefore(startOfYear) &&
                                ad.isBefore(startOfNextYear);
                            if (inYear) {
                              totalThisYear++;
                              admissionsThisYear.add(doa);
                              if (s == 'active') activeThisYear++;
                            }
                          }

                          if (s == 'recovered') {
                            final ra = m['recovered_at'];
                            if (ra is Timestamp) {
                              final dt = ra.toDate();
                              final inYear =
                                  !dt.isBefore(startOfYear) &&
                                  dt.isBefore(startOfNextYear);
                              if (inYear) {
                                dischargedThisYear++;
                                recoveredThisYear.add(ra);
                              }
                            }
                          } else if (s == 'deceased') {
                            final da = m['deceased_at'];
                            if (da is Timestamp) {
                              final dt = da.toDate();
                              final inYear =
                                  !dt.isBefore(startOfYear) &&
                                  dt.isBefore(startOfNextYear);
                              if (inYear) {
                                deathsThisYear++;
                                deathThisYear.add(da);
                              }
                            }
                          }
                        }

                        // 14-day mini charts
                        final allAdmissionsSeries = _bucketPerDay(
                          admissionsThisYear,
                          days: 14,
                        );
                        final rSeries = _bucketPerDay(
                          recoveredThisYear,
                          days: 14,
                        );
                        final dSeries = _bucketPerDay(deathThisYear, days: 14);

                        return Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: _kpiGap,
                            runSpacing: _kpiGap,
                            children: [
                              statCardDynamic(
                                title: "Total Patients (This Year)",
                                value: totalThisYear.toString(),
                                series: allAdmissionsSeries,
                                color: _primaryDim,
                                selected:
                                    _statusFilter == null &&
                                    !_filterRecoveredThisMonth,
                                onTap: () => setState(() {
                                  _statusFilter = null;
                                  _filterRecoveredThisMonth = false;
                                }),
                                width: _kpiWidth,
                                height: _kpiHeight,
                              ),
                              statCardDynamic(
                                title: "Current Patients (This Year)",
                                value: activeThisYear.toString(),
                                series: allAdmissionsSeries,
                                color: const Color(0xFF6EA8FE),
                                selected:
                                    _statusFilter == 'Active' &&
                                    !_filterRecoveredThisMonth,
                                onTap: () => setState(() {
                                  if (_statusFilter == 'Active' &&
                                      !_filterRecoveredThisMonth) {
                                    _statusFilter = null;
                                  } else {
                                    _statusFilter = 'Active';
                                    _filterRecoveredThisMonth = false;
                                  }
                                }),
                                width: _kpiWidth,
                                height: _kpiHeight,
                              ),
                              statCardDynamic(
                                title: "Discharged (This Year)",
                                value: dischargedThisYear.toString(),
                                series: rSeries,
                                color: const Color(0xFF5FD7C5),
                                selected:
                                    _statusFilter == 'Recovered' &&
                                    _filterRecoveredThisMonth,
                                onTap: () => setState(() {
                                  if (_statusFilter == 'Recovered' &&
                                      _filterRecoveredThisMonth) {
                                    _statusFilter = null;
                                    _filterRecoveredThisMonth = false;
                                  } else {
                                    _statusFilter = 'Recovered';
                                    _filterRecoveredThisMonth = true;
                                  }
                                }),
                                width: _kpiWidth,
                                height: _kpiHeight,
                              ),
                              statCardDynamic(
                                title: "Deceased (This Year)",
                                value: deathsThisYear.toString(),
                                series: dSeries,
                                color: const Color(0xFFFF6B6B),
                                selected:
                                    _statusFilter == 'Deceased' &&
                                    !_filterRecoveredThisMonth,
                                onTap: () => setState(() {
                                  if (_statusFilter == 'Deceased' &&
                                      !_filterRecoveredThisMonth) {
                                    _statusFilter = null;
                                  } else {
                                    _statusFilter = 'Deceased';
                                    _filterRecoveredThisMonth = false;
                                  }
                                }),
                                width: _kpiWidth,
                                height: _kpiHeight,
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 14),

                  // ===== Table + side form (responsive) =====
                  Expanded(
                    child: _uid == null
                        ? const Center(
                            child: Text(
                              'Please sign in to view your hospital’s cases',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : StreamBuilder<QuerySnapshot>(
                            stream: _hospitalCasesQuery(_uid!)
                                .orderBy('date_of_admission', descending: true)
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
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final all = snapshot.data!.docs;
                              final filtered = _applyFilters(all);

                              // compact: stack table then detail panel
                              if (isCompact) {
                                return Column(
                                  children: [
                                    Expanded(
                                      child: _buildScrollableTable(filtered),
                                    ),
                                    const SizedBox(height: 12),
                                    // detail panel full width
                                    SizedBox(
                                      width: double.infinity,
                                      child: buildPatientForm(),
                                    ),
                                  ],
                                );
                              }

                              // wide: side-by-side
                              return Row(
                                children: [
                                  Expanded(
                                    child: _buildScrollableTable(filtered),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 380,
                                    child: buildPatientForm(),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );

        final page = Scaffold(
          key: _scaffoldKey,
          backgroundColor: _bg,
          appBar: appBar,
          drawer: isCompact ? Drawer(child: _buildSidebar()) : null,
          body: isCompact
              ? content
              : Row(
                  children: [
                    _buildSidebar(),
                    Expanded(child: content),
                  ],
                ),
        );

        return DefaultTextStyle(
          style: const TextStyle(fontFamily: 'Poppins'),
          child: page,
        );
      },
    );
  }

  // ===== Sidebar =====
  Widget _buildSidebar() {
    return Container(
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
                  child: const Icon(Icons.coronavirus, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Patient management',
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
            active: true,
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

  // ===== Table (now only kept columns) with horizontal scroll on small widths =====
  Widget _buildScrollableTable(List<QueryDocumentSnapshot> docs) {
    final table = _buildPatientTableBody(docs);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(
        builder: (_, c) {
          // if too narrow, allow horizontal scroll
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: c.maxWidth < 900 ? 900 : c.maxWidth,
              child: table,
            ),
          );
        },
      ),
    );
  }

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
          // Header
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
                Expanded(flex: 1, child: _Hdr('Age')),
                Expanded(flex: 3, child: _Hdr('Admission Date')),
                Expanded(flex: 2, child: _Hdr('Status')),
                Expanded(flex: 2, child: _Hdr('MOH Area')),
                Expanded(flex: 2, child: _Hdr('PHI Area')),
                Expanded(flex: 4, child: _Hdr('Address')),
              ],
            ),
          ),
          // Body
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
                          const SizedBox(width: 4),
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
                            flex: 2,
                            child: Text(
                              (data['patient_phi_area'] ??
                                      data['phi_area'] ??
                                      '')
                                  .toString(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              (data['address'] ?? '').toString(),
                              style: const TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
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
          // footer controls (density + export)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final allDocs = await _hospitalCasesQuery(_uid!).get();
                    await _exportCsv(allDocs.docs);
                  },
                  icon: const Icon(Icons.download, color: Colors.white),
                  label: const Text(
                    'Export CSV',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (_hasAnyFilterActive)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _statusFilter = null;
                      _filterRecoveredThisMonth = false;
                      _searchQuery = '';
                    }),
                    icon: const Icon(
                      Icons.filter_alt_off,
                      color: Colors.white70,
                    ),
                    label: const Text(
                      'Clear filters',
                      style: TextStyle(color: Colors.white70),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _ink.withOpacity(.4)),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                const Spacer(),
                Tooltip(
                  message: _denseTable ? 'Comfort density' : 'Compact density',
                  child: IconButton(
                    onPressed: () => setState(() => _denseTable = !_denseTable),
                    icon: Icon(
                      _denseTable ? Icons.view_comfy : Icons.table_rows,
                    ),
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== RIGHT PANEL (only kept fields) =====
  Widget buildPatientForm() {
    return Container(
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
          ? _emptyPanel()
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

                  const Text('Basic', style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  buildTextField(
                    nameController,
                    'Full Name',
                    icon: Icons.person,
                  ),

                  const SizedBox(height: 8),
                  const Text('Contacts & Location', style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  buildTextField(
                    guardianContactController,
                    'Guardian Contact',
                    icon: Icons.phone_android,
                  ),
                  buildTextField(
                    phoneController,
                    'Phone Number',
                    icon: Icons.phone,
                  ),
                  buildTextField(
                    addressController,
                    'Home Address',
                    icon: Icons.home,
                  ),
                  buildTextField(
                    schoolWorkController,
                    'School/Work Address',
                    icon: Icons.school,
                  ),

                  const SizedBox(height: 8),
                  const Text('Public Health Areas', style: sectionTitleStyle),
                  const SizedBox(height: 8),

                  MohPhiPickerInline(
                    initialMoh: mohAreaController.text,
                    initialPhi: phiAreaController.text,
                    onChanged: (moh, phi) {
                      mohAreaController.text = moh ?? '';
                      phiAreaController.text = phi ?? '';
                      setState(() {});
                    },
                    phiRequired: true,
                  ),

                  const SizedBox(height: 14),
                  if (status != null && status!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Chip(
                        label: Text(
                          status!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor: getStatusColor(status!),
                      ),
                    ),

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
  }

  Widget _emptyPanel() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 34,
            backgroundColor: _primary,
            child: Icon(Icons.person_search, color: Colors.white, size: 32),
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
                  pageBuilder: (context, a1, a2) => const PatientFormPage(),
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
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
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

// ===== helpers =====

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
    final double top = maxVal <= 0 ? 1 : maxVal * 1.25;
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
      return const Color(0xFFF4C430);
    case 'recovered':
      return const Color(0xFF3DDC97);
    case 'deceased':
      return const Color(0xFFFF5C5C);
    default:
      return Colors.grey;
  }
}

// ===== simple CSV converter =====
class ListToCsvConverter {
  const ListToCsvConverter();
  String convert(List<List<String>> rows) => rows.map(_toCsvRow).join('\n');
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

/// =================== MOH → PHI picker (asset) ===================
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
  String? _error;

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
    try {
      final jsonStr = await rootBundle.loadString('images/phi_area.json');
      final raw = jsonDecode(jsonStr) as Map<String, dynamic>;

      final normalized = <String, List<String>>{};
      for (final e in raw.entries) {
        final moh = _titleCase(e.key.toString());
        final items =
            (e.value as List)
                .map((v) => _titleCase(v.toString()))
                .toSet()
                .toList()
              ..sort();
        normalized[moh] = items;
      }
      final mohs = normalized.keys.toList()..sort();

      if (!mounted) return;
      setState(() {
        _map = normalized;
        _mohList = mohs;
        _loading = false;
        _error = null;
      });

      if (widget.initialMoh != null && widget.initialMoh!.trim().isNotEmpty) {
        _onMohChanged(
          _titleCase(widget.initialMoh!),
          initialPhi: widget.initialPhi == null
              ? null
              : _titleCase(widget.initialPhi!),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load images/phi_area.json: $e';
      });
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
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
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
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _ink.withOpacity(.35)),
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
                  : 'Filtered by MOH',
              helperStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.badge, color: Colors.white54),
              filled: true,
              fillColor: _panelAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _ink.withOpacity(.35)),
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
