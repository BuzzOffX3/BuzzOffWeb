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

  // Palette
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

class _AnalyticsPageState extends State<AnalyticsPage> {
  // ==== Bucketing helper for mini KPI sparklines (last N days) ====
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

  // MOH-scoped streams (use 'admit_hospital_moh' if that’s your field)
  Stream<QuerySnapshot<Map<String, dynamic>>> _casesStreamForMoh(String moh) {
    return FirebaseFirestore.instance
        .collection('dengue_cases')
        .where('patient_moh_area', isEqualTo: moh)
        .orderBy('date_of_admission', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _complaintsStreamForMoh(
    String moh,
  ) {
    return FirebaseFirestore.instance
        .collection('complaints')
        .where('moh_area', isEqualTo: moh)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AnalyticsPage.bg,
      body: Row(
        children: [
          // ===== SIDEBAR =====
          _Sidebar(),

          // ===== MAIN =====
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
                          // MOH streams
                          final casesStream = _casesStreamForMoh(mohArea);
                          final complaintsStream = _complaintsStreamForMoh(
                            mohArea,
                          );

                          return Column(
                            children: [
                              const _Header(),
                              const SizedBox(height: 20),

                              // ==== KPIs (MOH-scoped) ====
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: casesStream,
                                builder: (context, casesSnap) {
                                  int totalCases = 0,
                                      activeCases = 0,
                                      last30 = 0,
                                      prev30 = 0;
                                  final admissions = <Timestamp>[];

                                  final now = DateTime.now();
                                  final startThis30 = DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                  ).subtract(const Duration(days: 29));
                                  final startPrev30 = startThis30.subtract(
                                    const Duration(days: 30),
                                  );

                                  if (casesSnap.hasData) {
                                    for (final d in casesSnap.data!.docs) {
                                      final m = d.data();
                                      final status = (m['status'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                      if (status == 'active') activeCases++;
                                      totalCases++;

                                      final ts = m['date_of_admission'];
                                      if (ts is Timestamp) {
                                        admissions.add(ts);
                                        final dt = ts.toDate();
                                        if (!dt.isBefore(startThis30)) {
                                          last30++;
                                        } else if (!dt.isBefore(startPrev30) &&
                                            dt.isBefore(startThis30)) {
                                          prev30++;
                                        }
                                      }
                                    }
                                  }

                                  final seriesCases = _bucketPerDay(admissions);
                                  final growthPct = prev30 == 0
                                      ? (last30 > 0 ? 100.0 : 0.0)
                                      : ((last30 - prev30) / prev30) * 100.0;

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
                                          if (ts is Timestamp)
                                            compTimes.add(ts);
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
                                              title: 'Case Growth (30d)',
                                              value:
                                                  '${growthPct.isNaN ? 0 : growthPct.toStringAsFixed(1)}%',
                                              hint: 'vs prev 30d • $mohArea',
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
                                              hint: 'last 30d series',
                                              series: seriesComplaints,
                                              color: const Color(0xFF5FD7C5),
                                              height: 160,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: KpiCardBig(
                                              title: 'Active Cases',
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

                              // ==== BODY ====
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      const SizedBox(height: 16),

                                      // UPDATED first chart: BAR chart scoped to MOH
                                      _RowWithReport(
                                        left: _YearlyCasesBarCard(
                                          mohArea: mohArea,
                                        ),
                                        right: const _ReportCard(),
                                      ),

                                      const SizedBox(height: 16),

                                      // You can keep the next two panels (static) or later scope them as well
                                      const _RowWithReport(
                                        left: _TrendsChartCard(),
                                        right: _ReportCard(),
                                      ),
                                      const SizedBox(height: 16),
                                      const _RowWithReport(
                                        left: _GrowthChartCard(),
                                        right: _ReportCard(),
                                      ),
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

/// Reads the signed-in user's profile to obtain `moh_area`, then builds child.
/// Shows loading / helpful messages if not signed in or no moh_area set.
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

// ======================= Sidebar =======================

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

// ===== SIDENAV ITEM =====
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

// ======================= Header =======================

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

// ---- wrapper to align large left panel + right report card
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

// ======================= UPDATED BAR CHART (MOH-scoped) =======================

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
              .where('patient_moh_area', isEqualTo: mohArea) // change if needed
              .snapshots(),
          builder: (context, snap) {
            // Build counts per year
            final now = DateTime.now();
            final years = List<int>.generate(
              6,
              (i) => now.year - 5 + i,
            ); // last 6 years
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
                      rodStackItems: [],
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
                        if (idx < 0 || idx >= years.length)
                          return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            years[idx].toString(),
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

// ======================= Other Panels (keep / tweak later) =======================

class _TrendsChartCard extends StatelessWidget {
  const _TrendsChartCard();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: "Trends",
      tabHint: "Case Trends",
      child: SizedBox(
        height: 260,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 11,
            minY: 0,
            maxY: 40,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: AnalyticsPage.border, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (v, m) {
                    if (v % 10 != 0) return const SizedBox.shrink();
                    return Text(
                      "${v.toInt()}k",
                      style: const TextStyle(
                        color: AnalyticsPage.subtext,
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  getTitlesWidget: (v, m) {
                    const months = [
                      "Jan",
                      "Feb",
                      "Mar",
                      "Apr",
                      "May",
                      "Jun",
                      "Jul",
                      "Aug",
                      "Sep",
                      "Oct",
                      "Nov",
                      "Dec",
                    ];
                    return Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        months[v.toInt()],
                        style: const TextStyle(
                          color: AnalyticsPage.subtext,
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
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
                spots: const [
                  FlSpot(0, 12),
                  FlSpot(1, 14),
                  FlSpot(2, 10),
                  FlSpot(3, 18),
                  FlSpot(4, 16),
                  FlSpot(5, 24),
                  FlSpot(6, 19),
                  FlSpot(7, 26),
                  FlSpot(8, 22),
                  FlSpot(9, 28),
                  FlSpot(10, 24),
                  FlSpot(11, 32),
                ],
              ),
              LineChartBarData(
                isCurved: true,
                barWidth: 2,
                color: AnalyticsPage.purpleDim.withOpacity(.5),
                dashArray: [6, 4],
                dotData: const FlDotData(show: false),
                spots: const [
                  FlSpot(0, 10),
                  FlSpot(1, 12),
                  FlSpot(2, 9),
                  FlSpot(3, 15),
                  FlSpot(4, 14),
                  FlSpot(5, 18),
                  FlSpot(6, 16),
                  FlSpot(7, 20),
                  FlSpot(8, 19),
                  FlSpot(9, 23),
                  FlSpot(10, 20),
                  FlSpot(11, 27),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrowthChartCard extends StatelessWidget {
  const _GrowthChartCard();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: "Case Growth",
      child: SizedBox(
        height: 260,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 11,
            minY: 0,
            maxY: 40,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: AnalyticsPage.border, strokeWidth: 1),
            ),
            titlesData: const FlTitlesData(show: false),
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
                spots: const [
                  FlSpot(0, 8),
                  FlSpot(1, 9),
                  FlSpot(2, 12),
                  FlSpot(3, 11),
                  FlSpot(4, 15),
                  FlSpot(5, 14),
                  FlSpot(6, 20),
                  FlSpot(7, 18),
                  FlSpot(8, 24),
                  FlSpot(9, 22),
                  FlSpot(10, 30),
                  FlSpot(11, 34),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

// ======================= KPI Card =======================

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
              Text(
                hint,
                style: const TextStyle(
                  color: AnalyticsPage.subtext,
                  fontSize: 11,
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
