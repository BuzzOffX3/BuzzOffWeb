import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:buzzoffwebnew/MOH/complaints.dart';
import 'package:buzzoffwebnew/MOH/MapPage.dart';
import 'package:buzzoffwebnew/signin.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  static const Color bg = Color(0xFF0F1115);
  static const Color sidebar = Color(0xFF14161B);
  static const Color panel = Color(0xFF13161C);
  static const Color panelAlt = Color(0xFF171A21);
  static const Color border = Color(0xFF242833);
  static const Color purple = Color(0xFF7C4DFF);
  static const Color purpleDim = Color(0xFF5C3FD4);
  static const Color text = Color(0xFFE8E9F1);
  static const Color subtext = Color(0xFFA9AAB5);

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

/* ---------------- helpers for MOH key variants (match any case) ---------------- */
String _titleCase(String s) {
  final t = s.trim().toLowerCase();
  if (t.isEmpty) return t;
  return t
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1)))
      .join(' ');
}

List<String> areaKeys(String raw) {
  final t = raw.trim();
  return {t, t.toLowerCase(), _titleCase(t), t.toUpperCase()}.toList();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<double> _bucketPerDay(Iterable<Timestamp> times, {int days = 30}) {
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

  /* ---------------- MOH-scoped streams (no orderBy needed for KPIs) ---------------- */
  Stream<QuerySnapshot<Map<String, dynamic>>> _casesStreamForMoh(String moh) {
    return FirebaseFirestore.instance
        .collection('dengue_cases')
        .where('patient_moh_area', whereIn: areaKeys(moh))
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _complaintsStreamForMoh(
    String moh,
  ) {
    return FirebaseFirestore.instance
        .collection('complaints')
        .where('moh_area', whereIn: areaKeys(moh))
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AnalyticsPage.bg,
      body: Row(
        children: [
          _Sidebar(),
          Expanded(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: AnalyticsPage.text),
                      child: _BuildWithMoh(
                        childBuilder: (context, mohArea) {
                          final casesStream = _casesStreamForMoh(mohArea);
                          final complaintsStream = _complaintsStreamForMoh(
                            mohArea,
                          );

                          return Column(
                            children: [
                              const _Header(),
                              const SizedBox(height: 20),

                              // ======= KPIs (UNCHANGED) =======
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: casesStream,
                                builder: (context, casesSnap) {
                                  int totalCases = 0;
                                  int activeCases = 0;
                                  final admissions = <Timestamp>[];

                                  final now = DateTime.now();
                                  final startThisMonth = DateTime(
                                    now.year,
                                    now.month,
                                    1,
                                  );
                                  final startNextMonth = DateTime(
                                    now.year,
                                    now.month + 1,
                                    1,
                                  );
                                  final startPrevMonth = DateTime(
                                    now.year,
                                    now.month - 1,
                                    1,
                                  );

                                  int thisMonthCount = 0;
                                  int prevMonthCount = 0;

                                  if (casesSnap.hasData) {
                                    for (final d in casesSnap.data!.docs) {
                                      final m = d.data();
                                      totalCases++;

                                      final status = (m['status'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .trim();
                                      if (status == 'active') activeCases++;

                                      final ts = m['date_of_admission'];
                                      if (ts is Timestamp) {
                                        admissions.add(ts);
                                        final dt = ts.toDate();
                                        if (!dt.isBefore(startThisMonth) &&
                                            dt.isBefore(startNextMonth)) {
                                          thisMonthCount++;
                                        } else if (!dt.isBefore(
                                              startPrevMonth,
                                            ) &&
                                            dt.isBefore(startThisMonth)) {
                                          prevMonthCount++;
                                        }
                                      }
                                    }
                                  }

                                  final seriesCases = _bucketPerDay(admissions);
                                  final growthPct = prevMonthCount == 0
                                      ? (thisMonthCount > 0 ? 100.0 : 0.0)
                                      : ((thisMonthCount - prevMonthCount) /
                                                prevMonthCount) *
                                            100.0;

                                  return StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>
                                  >(
                                    stream: complaintsStream,
                                    builder: (context, compSnap) {
                                      int totalComplaints = 0;
                                      final compTimes = <Timestamp>[];
                                      if (compSnap.hasData) {
                                        totalComplaints =
                                            compSnap.data!.docs.length;
                                        for (final d in compSnap.data!.docs) {
                                          final ts = d.data()['timestamp'];
                                          if (ts is Timestamp) {
                                            compTimes.add(ts);
                                          }
                                        }
                                      }
                                      final seriesComplaints = _bucketPerDay(
                                        compTimes,
                                      );

                                      return Row(
                                        children: [
                                          Expanded(
                                            child: KpiCardBig(
                                              title: 'Total Cases (MOH)',
                                              value: '$totalCases',
                                              hint: mohArea,
                                              series: seriesCases,
                                              color: AnalyticsPage.purple,
                                              height: 160,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: KpiCardBig(
                                              title: 'Case Growth (MoM)',
                                              value:
                                                  '${growthPct.isNaN ? 0 : growthPct.toStringAsFixed(1)}%',
                                              hint:
                                                  'This month vs last • $mohArea',
                                              series: seriesCases,
                                              color: const Color(0xFF6EA8FE),
                                              height: 160,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: KpiCardBig(
                                              title: 'Total Complaints',
                                              value: '$totalComplaints',
                                              hint: 'Last 30d series',
                                              series: seriesComplaints,
                                              color: const Color(0xFF5FD7C5),
                                              height: 160,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: KpiCardBig(
                                              title: 'Active Dengue Cases',
                                              value: '$activeCases',
                                              hint: 'status = Active',
                                              series: seriesCases,
                                              color: const Color(0xFFFF6B6B),
                                              height: 160,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),

                              const SizedBox(height: 20),

                              // ======= BODY =======
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      const SizedBox(height: 16),

                                      // Row 1: Yearly chart (UNCHANGED) + Report (kept)
                                      _RowWithReport(
                                        left: _YearlyCasesBarCard(
                                          mohArea: mohArea,
                                        ),
                                        right: const _ReportCard(),
                                      ),

                                      const SizedBox(height: 16),

                                      // Row 2: New vs Transferred (stacked) — full width
                                      _NewVsTransferredStackedCard(
                                        mohArea: mohArea,
                                      ),

                                      const SizedBox(height: 16),

                                      // Row 3: Age pyramid — full width
                                      _AgePyramidCard(mohArea: mohArea),

                                      const SizedBox(height: 16),

                                      // Row 4: Complaints → Cases conversion (bubble grid) + Report
                                      _RowWithReport(
                                        left:
                                            _ComplaintsConversionBubbleGridCard(
                                              mohArea: mohArea,
                                            ),
                                        right: const _ReportCard(),
                                      ),

                                      const SizedBox(height: 16),

                                      // ===== New Bottom Sections =====
                                      // Public Health Risk Indicators
                                      _SectionHeader(
                                        "Public Health Risk Indicators",
                                      ),
                                      const SizedBox(height: 12),

                                      // High-Risk Zones (full width)
                                      _HighRiskZonesCard(),
                                      const SizedBox(height: 16),

                                      // Seasonal Trend Tracker (full width, placed under High-Risk Zones)
                                      _SeasonalTrendTrackerCard(
                                        mohArea: mohArea,
                                      ),

                                      const SizedBox(height: 16),

                                      // Data Quality & Ops Tracking
                                      _SectionHeader(
                                        "Data Quality & Ops Tracking",
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _AvgReportingLagCard(
                                              mohArea: mohArea,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: _DuplicateComplaintRatioCard(
                                              mohArea: mohArea,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),

                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
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

class _BuildWithMoh extends StatelessWidget {
  final Widget Function(BuildContext context, String mohArea) childBuilder;
  const _BuildWithMoh({required this.childBuilder});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(
        child: Text(
          'Please sign in',
          style: TextStyle(color: AnalyticsPage.text),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data!.data() ?? {};
        final mohArea = (data['moh_area'] ?? '').toString().trim();
        if (mohArea.isEmpty) {
          return const Center(
            child: Text(
              'Your account has no MOH area set (users/{uid}.moh_area).',
              style: TextStyle(color: AnalyticsPage.subtext),
              textAlign: TextAlign.center,
            ),
          );
        }
        return childBuilder(context, mohArea);
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      width: 250,
      color: AnalyticsPage.sidebar,
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
                    color: AnalyticsPage.purple.withOpacity(.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.coronavirus, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'MOH ANALYTICS',
                    style: TextStyle(
                      color: AnalyticsPage.text,
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
            label: 'Analytics',
            active: true,
            onTap: () {},
          ),
          _SideNavItem(
            icon: Icons.receipt_long_outlined,
            label: 'Complaints',
            onTap: () {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const ComplaintsPage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            },
          ),
          _SideNavItem(
            icon: Icons.map_outlined,
            label: 'Maps',
            onTap: () {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const MapsPage(),
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
                  child: uid == null
                      ? const Text(
                          'User',
                          style: TextStyle(
                            color: AnalyticsPage.subtext,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .snapshots(),
                          builder: (context, snap) {
                            String name = 'User';
                            if (snap.hasData && snap.data!.data() != null) {
                              final m = snap.data!.data()!;
                              name =
                                  (m['username'] ??
                                          m['name'] ??
                                          m['display_name'] ??
                                          'User')
                                      .toString();
                            }
                            return Text(
                              name,
                              style: const TextStyle(
                                color: AnalyticsPage.subtext,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white54,
                    size: 18,
                  ),
                  color: AnalyticsPage.panel,
                  onSelected: (val) async {
                    if (val == 'signout') {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AnalyticsPage.panelAlt,
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
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AnalyticsPage.purple,
                              ),
                              child: const Text('Sign out'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const SignInPage(),
                            ),
                            (route) => false,
                          );
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'signout',
                      child: Text(
                        'Sign out',
                        style: TextStyle(color: Colors.white),
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
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

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
            color: active
                ? AnalyticsPage.purple.withOpacity(.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: active
                    ? AnalyticsPage.purple
                    : AnalyticsPage.text.withOpacity(.85),
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: active ? AnalyticsPage.purple : AnalyticsPage.subtext,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (active)
                const Icon(
                  Icons.chevron_right,
                  color: AnalyticsPage.purple,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AnalyticsPage.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AnalyticsPage.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: const [
                Icon(Icons.search, color: AnalyticsPage.subtext, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Search anything",
                    style: TextStyle(color: AnalyticsPage.subtext),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _IconChip(icon: Icons.notifications_none_rounded),
        const SizedBox(width: 10),
        _IconChip(icon: Icons.settings_outlined),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  const _IconChip({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AnalyticsPage.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AnalyticsPage.border),
      ),
      child: Icon(icon, color: AnalyticsPage.subtext),
    );
  }
}

class _RowWithReport extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _RowWithReport({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: AnalyticsPage.text,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: .2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: AnalyticsPage.border)),
      ],
    );
  }
}

// ================== UNCHANGED: Yearly Cases Card ==================
class _YearlyCasesBarCard extends StatelessWidget {
  final String mohArea;
  const _YearlyCasesBarCard({required this.mohArea});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: "Yearly Patients (MOH: $mohArea)",
      tabHint: "Last 6 years",
      child: SizedBox(
        height: 280,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('dengue_cases')
              .where('patient_moh_area', whereIn: areaKeys(mohArea))
              .snapshots(),
          builder: (context, snap) {
            final now = DateTime.now();
            final years = List<int>.generate(6, (i) => now.year - 5 + i);
            final counts = {for (final y in years) y: 0};

            if (snap.hasData) {
              for (final doc in snap.data!.docs) {
                final m = doc.data();
                final doa = m['date_of_admission'];
                if (doa is Timestamp) {
                  final y = doa.toDate().year;
                  if (counts.containsKey(y)) counts[y] = (counts[y] ?? 0) + 1;
                }
              }
            }

            final maxVal = (counts.values.isEmpty
                ? 1
                : counts.values.reduce((a, b) => a > b ? a : b));
            final barGroups = <BarChartGroupData>[];
            for (int i = 0; i < years.length; i++) {
              final y = years[i];
              barGroups.add(
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: (counts[y] ?? 0).toDouble(),
                      width: 18,
                      borderRadius: BorderRadius.circular(4),
                      color: AnalyticsPage.purple,
                      rodStackItems: const [],
                    ),
                  ],
                ),
              );
            }

            return BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawHorizontalLine: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: AnalyticsPage.border, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, meta) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                            color: AnalyticsPage.subtext,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) {
                        final idx = v.toInt();
                        final yearsList = years;
                        if (idx < 0 || idx >= yearsList.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            yearsList[idx].toString(),
                            style: const TextStyle(
                              color: AnalyticsPage.subtext,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: barGroups,
                maxY: (maxVal == 0 ? 1 : (maxVal * 1.2)).toDouble(),
                minY: 0,
              ),
              swapAnimationDuration: const Duration(milliseconds: 400),
            );
          },
        ),
      ),
    );
  }
}

// ================== New vs Transferred (stacked monthly) ==================
class _NewVsTransferredStackedCard extends StatelessWidget {
  final String mohArea;
  const _NewVsTransferredStackedCard({required this.mohArea});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: "New vs Transferred (last 12 months)",
      tabHint: "Stacked columns",
      child: SizedBox(
        height: 280,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('dengue_cases')
              .where('patient_moh_area', whereIn: areaKeys(mohArea))
              .snapshots(),
          builder: (context, snap) {
            final now = DateTime.now();
            final start = DateTime(now.year, now.month - 11, 1); // rolling 12m
            final newCounts = List<int>.filled(12, 0);
            final transferCounts = List<int>.filled(12, 0);

            if (snap.hasData) {
              for (final doc in snap.data!.docs) {
                final m = doc.data();
                final ts = m['date_of_admission'];
                if (ts is! Timestamp) continue;
                final dt = ts.toDate();
                if (dt.isBefore(start) ||
                    dt.isAfter(DateTime(now.year, now.month + 1, 0))) {
                  continue;
                }
                final monthIdx =
                    (dt.year - start.year) * 12 + (dt.month - start.month);
                if (monthIdx < 0 || monthIdx > 11) continue;

                final type = (m['type'] ?? '').toString().toLowerCase().trim();
                if (type == 'transferred' || type == 'transfer') {
                  transferCounts[monthIdx] += 1;
                } else {
                  // default bucket = New
                  newCounts[monthIdx] += 1;
                }
              }
            }

            final totalPerMonth = List<int>.generate(
              12,
              (i) => newCounts[i] + transferCounts[i],
            );
            final maxVal = totalPerMonth.isEmpty
                ? 1
                : totalPerMonth.reduce((a, b) => a > b ? a : b);
            final groups = <BarChartGroupData>[];
            for (var i = 0; i < 12; i++) {
              final n = newCounts[i].toDouble();
              final t = transferCounts[i].toDouble();
              groups.add(
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: n + t,
                      width: 16,
                      borderRadius: BorderRadius.circular(4),
                      rodStackItems: [
                        BarChartRodStackItem(0, n, const Color(0xFF6EA8FE)),
                        BarChartRodStackItem(n, n + t, const Color(0xFFFF6B6B)),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: BarChart(
                    BarChartData(
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) =>
                            FlLine(color: AnalyticsPage.border, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (v, m) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                v.toInt().toString(),
                                style: const TextStyle(
                                  color: AnalyticsPage.subtext,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, m) {
                              final idx = v.toInt();
                              if (idx < 0 || idx > 11) {
                                return const SizedBox.shrink();
                              }
                              final dt = DateTime(
                                now.year,
                                now.month - 11 + idx,
                                1,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _months[dt.month - 1],
                                  style: const TextStyle(
                                    color: AnalyticsPage.subtext,
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: groups,
                      maxY: (maxVal == 0 ? 1 : (maxVal * 1.2)).toDouble(),
                      minY: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    _LegendDot(color: Color(0xFF6EA8FE), label: 'New'),
                    SizedBox(width: 14),
                    _LegendDot(color: Color(0xFFFF6B6B), label: 'Transferred'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ================== Complaints → Cases conversion (bubble grid, monthly) ==================
class _ComplaintsConversionBubbleGridCard extends StatelessWidget {
  final String mohArea;
  const _ComplaintsConversionBubbleGridCard({required this.mohArea});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: "Complaints → Cases conversion (last 12 months)",
      tabHint: "Bubble grid (ratio = cases / complaints)",
      child: SizedBox(
        height: 280,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('dengue_cases')
              .where('patient_moh_area', whereIn: areaKeys(mohArea))
              .snapshots(),
          builder: (context, casesSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('complaints')
                  .where('moh_area', whereIn: areaKeys(mohArea))
                  .snapshots(),
              builder: (context, compSnap) {
                final now = DateTime.now();
                final start = DateTime(now.year, now.month - 11, 1);
                final casesPerMonth = List<int>.filled(12, 0);
                final compsPerMonth = List<int>.filled(12, 0);

                if (casesSnap.hasData) {
                  for (final d in casesSnap.data!.docs) {
                    final ts = d.data()['date_of_admission'];
                    if (ts is! Timestamp) continue;
                    final dt = ts.toDate();
                    final idx =
                        (dt.year - start.year) * 12 + (dt.month - start.month);
                    if (idx >= 0 && idx < 12) casesPerMonth[idx] += 1;
                  }
                }
                if (compSnap.hasData) {
                  for (final d in compSnap.data!.docs) {
                    final ts = d.data()['timestamp'];
                    if (ts is! Timestamp) continue;
                    final dt = ts.toDate();
                    final idx =
                        (dt.year - start.year) * 12 + (dt.month - start.month);
                    if (idx >= 0 && idx < 12) compsPerMonth[idx] += 1;
                  }
                }

                final ratios = List<double>.generate(12, (i) {
                  final c = casesPerMonth[i];
                  final q = compsPerMonth[i];
                  if (q == 0) return 0.0;
                  return c / q;
                });

                double bubbleSize(double r) {
                  final clamped = r.clamp(0.0, 3.0);
                  return 14 + clamped * 9.0;
                }

                return LayoutBuilder(
                  builder: (ctx, cons) {
                    final tileW = (cons.maxWidth - 16 * 3) / 4; // 4 per row
                    return Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        for (int i = 0; i < 12; i++)
                          Container(
                            width: tileW,
                            height: 58,
                            decoration: BoxDecoration(
                              color: AnalyticsPage.panelAlt,
                              border: Border.all(color: AnalyticsPage.border),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: bubbleSize(ratios[i]),
                                  height: bubbleSize(ratios[i]),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AnalyticsPage.purple.withOpacity(
                                      0.35 + 0.2 * ratios[i].clamp(0.0, 1.0),
                                    ),
                                    border: Border.all(
                                      color: AnalyticsPage.purple,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _months[DateTime(
                                              now.year,
                                              now.month - 11 + i,
                                              1,
                                            ).month -
                                            1],
                                        style: const TextStyle(
                                          color: AnalyticsPage.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Ratio: ${ratios[i].isNaN ? '0.0' : ratios[i].toStringAsFixed(2)}  •  C:${casesPerMonth[i]}  Q:${compsPerMonth[i]}",
                                        style: const TextStyle(
                                          color: AnalyticsPage.subtext,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ================== Age Pyramid (mirrored) ==================
class _AgePyramidCard extends StatelessWidget {
  final String mohArea;
  const _AgePyramidCard({required this.mohArea});

  static const _bands = <String>[
    '0-9',
    '10-19',
    '20-29',
    '30-39',
    '40-49',
    '50-59',
    '60-69',
    '70+',
  ];

  int _ageFromDob(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hadBirthday =
        (now.month > dob.month) ||
        (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age--;
    return age;
  }

  int _bandIndex(int age) {
    if (age <= 9) return 0;
    if (age <= 19) return 1;
    if (age <= 29) return 2;
    if (age <= 39) return 3;
    if (age <= 49) return 4;
    if (age <= 59) return 5;
    if (age <= 69) return 6;
    return 7;
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: "Age Pyramid (by gender)",
      tabHint: "Mirrored bars",
      child: SizedBox(
        height: 280,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('dengue_cases')
              .where('patient_moh_area', whereIn: areaKeys(mohArea))
              .snapshots(),
          builder: (context, snap) {
            final male = List<int>.filled(_bands.length, 0);
            final female = List<int>.filled(_bands.length, 0);

            if (snap.hasData) {
              for (final d in snap.data!.docs) {
                final m = d.data();
                final dobTs = m['date_of_birth'];
                if (dobTs is! Timestamp) continue;
                final g = (m['gender'] ?? '').toString().toLowerCase().trim();
                final age = _ageFromDob(dobTs.toDate());
                final idx = _bandIndex(age);
                if (idx < 0 || idx >= _bands.length) continue;
                if (g.startsWith('f')) {
                  female[idx] += 1;
                } else if (g.startsWith('m')) {
                  male[idx] += 1;
                }
              }
            }

            final absMax = [
              ...male.map((e) => e.abs()),
              ...female.map((e) => e.abs()),
            ].fold<int>(0, (p, c) => c > p ? c : p);
            final maxY = (absMax == 0 ? 1 : (absMax * 1.2)).toDouble();

            final groups = <BarChartGroupData>[];
            for (int i = 0; i < _bands.length; i++) {
              groups.add(
                BarChartGroupData(
                  x: i,
                  barsSpace: 6,
                  barRods: [
                    // male: negative
                    BarChartRodData(
                      toY: -male[i].toDouble(),
                      width: 12,
                      color: const Color(0xFF6EA8FE),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    // female: positive
                    BarChartRodData(
                      toY: female[i].toDouble(),
                      width: 12,
                      color: const Color(0xFFFF6B6B),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: BarChart(
                    BarChartData(
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) =>
                            FlLine(color: AnalyticsPage.border, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (v, m) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                v.abs().toInt().toString(),
                                style: const TextStyle(
                                  color: AnalyticsPage.subtext,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, m) {
                              final idx = v.toInt();
                              if (idx < 0 || idx >= _bands.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _bands[idx],
                                  style: const TextStyle(
                                    color: AnalyticsPage.subtext,
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: groups,
                      minY: -maxY,
                      maxY: maxY,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    _LegendDot(color: Color(0xFF6EA8FE), label: 'Male'),
                    SizedBox(width: 14),
                    _LegendDot(color: Color(0xFFFF6B6B), label: 'Female'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ================== Bottom: PUBLIC HEALTH RISK INDICATORS ==================
// Top 5 MOH areas by new cases in last 14 days (global)
class _HighRiskZonesCard extends StatelessWidget {
  const _HighRiskZonesCard();

  String _short(String s) {
    final t = s.trim();
    if (t.length <= 10) return t;
    return t.substring(0, 10) + '…';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 14));

    return _Panel(
      title: "High-Risk Zones",
      tabHint: "Top 5 MOH areas • last 14d",
      child: SizedBox(
        height: 260,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('dengue_cases')
              .where(
                'date_of_admission',
                isGreaterThanOrEqualTo: Timestamp.fromDate(
                  DateTime(start.year, start.month, start.day),
                ),
              )
              .snapshots(),
          builder: (context, snap) {
            final counts = <String, int>{};
            if (snap.hasData) {
              for (final d in snap.data!.docs) {
                final m = d.data();
                final ts = m['date_of_admission'];
                final area = (m['patient_moh_area'] ?? '').toString().trim();
                if (area.isEmpty || ts is! Timestamp) continue;
                // only "New" cases
                final type = (m['type'] ?? '').toString().toLowerCase();
                if (type.isNotEmpty &&
                    !(type == 'new' || type == 'case' || type == 'admission')) {
                  continue;
                }
                counts[area] = (counts[area] ?? 0) + 1;
              }
            }

            final top = counts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final top5 = top.take(5).toList();
            final maxVal = top5.isEmpty
                ? 1
                : top5.map((e) => e.value).reduce((a, b) => a > b ? a : b);

            final groups = <BarChartGroupData>[];
            for (int i = 0; i < top5.length; i++) {
              groups.add(
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: top5[i].value.toDouble(),
                      width: 18,
                      color: const Color(0xFFFFAA5B),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }

            return BarChart(
              BarChartData(
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: AnalyticsPage.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, m) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                            color: AnalyticsPage.subtext,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, m) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= top5.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _short(top5[idx].key),
                            style: const TextStyle(
                              color: AnalyticsPage.subtext,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: groups,
                maxY: (maxVal == 0 ? 1 : (maxVal * 1.2)).toDouble(),
                minY: 0,
              ),
              swapAnimationDuration: const Duration(milliseconds: 350),
            );
          },
        ),
      ),
    );
  }
}

// This month vs same month last year (MOH-scoped)
class _SeasonalTrendTrackerCard extends StatelessWidget {
  final String mohArea;
  const _SeasonalTrendTrackerCard({required this.mohArea});

  int _daysInMonth(int year, int month) {
    final first = DateTime(year, month, 1);
    final next = DateTime(year, month + 1, 1);
    return next.difference(first).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisYear = now.year;
    final month = now.month;
    final lastYear = thisYear - 1;
    final daysThis = _daysInMonth(thisYear, month);
    final daysLast = _daysInMonth(lastYear, month);
    final maxDays = (daysThis > daysLast ? daysThis : daysLast);

    return _Panel(
      title: "Seasonal Trend Tracker",
      tabHint: "This month vs last year",
      child: SizedBox(
        height: 260,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('dengue_cases')
              .where('patient_moh_area', whereIn: areaKeys(mohArea))
              .snapshots(),
          builder: (context, snap) {
            final cur = List<int>.filled(maxDays, 0);
            final prev = List<int>.filled(maxDays, 0);

            if (snap.hasData) {
              for (final d in snap.data!.docs) {
                final ts = d.data()['date_of_admission'];
                if (ts is! Timestamp) continue;
                final dt = ts.toDate();
                if (dt.month != month) continue;
                final di = dt.day - 1;
                if (dt.year == thisYear && di >= 0 && di < maxDays)
                  cur[di] += 1;
                if (dt.year == lastYear && di >= 0 && di < maxDays)
                  prev[di] += 1;
              }
            }

            final maxY = [
              ...cur,
              ...prev,
            ].fold<int>(0, (p, c) => c > p ? c : p);

            List<FlSpot> _spots(List<int> a) => [
              for (int i = 0; i < maxDays; i++)
                FlSpot((i + 1).toDouble(), a[i].toDouble()),
            ];

            return LineChart(
              LineChartData(
                minX: 1,
                maxX: maxDays.toDouble(),
                minY: 0,
                maxY: (maxY == 0 ? 1 : (maxY * 1.2)).toDouble(),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: AnalyticsPage.border, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, m) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                            color: AnalyticsPage.subtext,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (maxDays / 6).ceilToDouble(),
                      getTitlesWidget: (v, m) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                            color: AnalyticsPage.subtext,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  border: const Border(
                    left: BorderSide(color: AnalyticsPage.border),
                    bottom: BorderSide(color: AnalyticsPage.border),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    barWidth: 3,
                    color: AnalyticsPage.purple,
                    dotData: const FlDotData(show: false),
                    spots: _spots(cur),
                  ),
                  LineChartBarData(
                    isCurved: true,
                    barWidth: 2,
                    color: AnalyticsPage.purpleDim.withOpacity(.6),
                    dashArray: [6, 4],
                    dotData: const FlDotData(show: false),
                    spots: _spots(prev),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ================== Bottom: DATA QUALITY & OPS ==================
class _AvgReportingLagCard extends StatelessWidget {
  final String mohArea;
  const _AvgReportingLagCard({required this.mohArea});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));

    return _Panel(
      title: "Reporting Lag (Days)",
      tabHint: "Avg • last 30d",
      child: SizedBox(
        height: 140,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('dengue_cases')
              .where('patient_moh_area', whereIn: areaKeys(mohArea))
              .snapshots(),
          builder: (context, snap) {
            double sum = 0;
            int n = 0;
            if (snap.hasData) {
              for (final d in snap.data!.docs) {
                final m = d.data();
                final doa = m['date_of_admission'];
                final created = m['created_at'];
                if (doa is! Timestamp || created is! Timestamp) continue;
                final dt = doa.toDate();
                if (dt.isBefore(start)) continue;
                var lag = created.toDate().difference(dt).inDays.toDouble();
                if (lag < 0) lag = 0; // clamp negatives
                sum += lag;
                n++;
              }
            }
            final avg = n == 0 ? 0.0 : (sum / n);
            return _BigNumber(
              value: "${avg.toStringAsFixed(1)} d",
              caption: "$n records",
            );
          },
        ),
      ),
    );
  }
}

class _DuplicateComplaintRatioCard extends StatelessWidget {
  final String mohArea;
  const _DuplicateComplaintRatioCard({required this.mohArea});

  bool _isDup(String s) {
    final t = s.toLowerCase();
    return t.contains('duplicate') || t.contains('dup') || t.contains('dupe');
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));

    return _Panel(
      title: "Duplicate Complaint Ratio",
      tabHint: "% of complaints • last 30d",
      child: SizedBox(
        height: 140,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('complaints')
              .where('moh_area', whereIn: areaKeys(mohArea))
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snap) {
            int total = 0;
            int dups = 0;
            if (snap.hasData) {
              for (final d in snap.data!.docs) {
                final m = d.data();
                final ts = m['timestamp'];
                if (ts is! Timestamp) continue;
                final dt = ts.toDate();
                if (dt.isBefore(start)) break; // list is ordered desc
                total++;
                final status = (m['status'] ?? '').toString();
                if (_isDup(status)) dups++;
              }
            }
            final pct = total == 0 ? 0.0 : (dups / total) * 100.0;
            return _BigNumber(
              value: "${pct.toStringAsFixed(1)}%",
              caption: "$dups / $total flagged",
            );
          },
        ),
      ),
    );
  }
}

// =============== shared panel bits ===============
class _ReportCard extends StatelessWidget {
  const _ReportCard();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: "Report Summary",
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: AnalyticsPage.panelAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AnalyticsPage.border),
            ),
            child: const Center(
              child: Icon(
                Icons.insert_chart_outlined,
                size: 64,
                color: AnalyticsPage.purple,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C2F3A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {},
              icon: const Icon(Icons.download_outlined, color: Colors.white),
              label: const Text(
                "Download",
                style: TextStyle(color: AnalyticsPage.text),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String? tabHint;
  final Widget child;

  const _Panel({required this.title, this.tabHint, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AnalyticsPage.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AnalyticsPage.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AnalyticsPage.text,
                ),
              ),
              const Spacer(),
              if (tabHint != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AnalyticsPage.panelAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AnalyticsPage.border),
                  ),
                  child: Text(
                    tabHint!,
                    style: const TextStyle(
                      color: AnalyticsPage.subtext,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class KpiCardBig extends StatelessWidget {
  final String title;
  final String value;
  final String hint;
  final List<double> series;
  final Color color;
  final double height;

  const KpiCardBig({
    super.key,
    required this.title,
    required this.value,
    required this.hint,
    required this.series,
    required this.color,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AnalyticsPage.panelAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AnalyticsPage.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: AnalyticsPage.subtext, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AnalyticsPage.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  hint,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AnalyticsPage.subtext,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _MiniAreaChart(data: series, color: color),
          ),
        ],
      ),
    );
  }
}

class _MiniAreaChart extends StatelessWidget {
  final List<double> data;
  final Color color;
  const _MiniAreaChart({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final double maxVal = data.isEmpty
        ? 1
        : data.reduce((a, b) => a > b ? a : b);
    final double top = maxVal <= 0 ? 1 : maxVal * 1.25;

    return LineChart(
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
    );
  }
}

class _BigNumber extends StatelessWidget {
  final String value;
  final String caption;
  const _BigNumber({required this.value, required this.caption});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AnalyticsPage.text,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            caption,
            style: const TextStyle(color: AnalyticsPage.subtext, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// =============== tiny legend helper ===============
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AnalyticsPage.subtext, fontSize: 12),
        ),
      ],
    );
  }
}
