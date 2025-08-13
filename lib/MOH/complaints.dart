import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'analytics.dart';
import 'MapPage.dart';

class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage({super.key});

  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  // ===== THEME =====
  static const Color bg = Color(0xFF0F1115);
  static const Color sidebar = Color(0xFF14161B);
  static const Color panel = Color(0xFF171A21);
  static const Color panelAlt = Color(0xFF1B1F2A);
  static const Color border = Color(0xFF242A36);
  static const Color purple = Color(0xFF8C52FF);
  static const Color text = Color(0xFFE8E9F1);
  static const Color subtext = Color(0xFFA9AAB5);

  String username = 'Loading...';
  String? _role;
  String? _mohArea;
  Stream<QuerySnapshot>? _complaintsStream;

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  String? _readStr(Map<String, dynamic> m, String k1, [String? k2]) {
    if (m[k1] is String && (m[k1] as String).trim().isNotEmpty) {
      return (m[k1] as String).trim();
    }
    if (k2 != null && m[k2] is String && (m[k2] as String).trim().isNotEmpty) {
      return (m[k2] as String).trim();
    }
    return null;
  }

  Future<void> fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      setState(() {
        username = 'Unknown User';
        _role = null;
        _mohArea = null;
        _complaintsStream = complaintsBase()
            .orderBy('timestamp', descending: true)
            .snapshots();
      });
      return;
    }

    final data = (userDoc.data() as Map<String, dynamic>);
    final displayName = _readStr(data, 'username', 'name') ?? 'User';
    final role = _readStr(data, 'role');
    final mohArea = _readStr(data, 'moh_area', 'mohArea');

    setState(() {
      username = displayName;
      _role = role;
      _mohArea = mohArea;
      _complaintsStream = complaintsBase()
          .orderBy('timestamp', descending: true)
          .snapshots();
    });
  }

  Query complaintsBase() {
    final col = FirebaseFirestore.instance.collection('complaints');

    // MOH sees only their own area using snake_case field
    if ((_role?.toLowerCase() == 'moh') && (_mohArea?.isNotEmpty ?? false)) {
      return col.where('moh_area', isEqualTo: _mohArea);
    }
    return col;
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Row(
        children: [
          // ===== SIDEBAR =====
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
                      Expanded(
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
                  label: 'Analytics',
                  // already here
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const AnalyticsPage(),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  }, // no-op since we're on Analytics
                ),
                _SideNavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Complaints',
                  active: true,
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
                        child: Text(
                          username,
                          style: TextStyle(color: subtext, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.more_vert,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // ===== CONTENT =====
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header line
                  Text(
                    _role?.toLowerCase() == 'moh' &&
                            (_mohArea?.isNotEmpty ?? false)
                        ? 'Complaints in ${_mohArea!}'
                        : 'Complaints',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '“Complaints are not setbacks; they’re unfiltered insights that guide our evolution and strengthen our service.”',
                    style: TextStyle(color: subtext, fontSize: 13),
                  ),
                  const SizedBox(height: 18),

                  // ===== KPI ROW =====
                  SizedBox(
                    height: 110,
                    child: Row(
                      children: [
                        Expanded(
                          child: _KpiCard(
                            title: 'Total Complaints',
                            query: complaintsBase(),
                            color: purple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _KpiCard(
                            title: 'Pending',
                            query: complaintsBase().where(
                              'status',
                              isEqualTo: 'Pending',
                            ),
                            color: const Color(0xFFFFB020),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _KpiCard(
                            title: 'Under Investigation',
                            query: complaintsBase().where(
                              'status',
                              isEqualTo: 'Under Investigation',
                            ),
                            color: const Color(0xFFFF5C5C),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _KpiCard(
                            title: 'Reviewed',
                            query: complaintsBase().where(
                              'status',
                              isEqualTo: 'Reviewed',
                            ),
                            color: const Color(0xFF3DDC97),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===== TABLE HEADER =====
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        _th('#', flex: 1),
                        _th('Name', flex: 3),
                        _th('Description', flex: 4),
                        _th('Image', flex: 2),
                        _th('Map Link', flex: 2),
                        _th('Date', flex: 2),
                        _th('Time', flex: 2),
                        _th('Status', flex: 3),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ===== TABLE BODY =====
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: panelAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: _complaintsStream == null
                          ? const Center(child: CircularProgressIndicator())
                          : StreamBuilder<QuerySnapshot>(
                              stream: _complaintsStream,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (!snapshot.hasData ||
                                    snapshot.data!.docs.isEmpty) {
                                  return Center(
                                    child: Text(
                                      'No Complaints Found',
                                      style: TextStyle(color: subtext),
                                    ),
                                  );
                                }

                                final docs = snapshot.data!.docs;
                                return ListView.separated(
                                  itemCount: docs.length,
                                  separatorBuilder: (_, __) => Divider(
                                    color: border.withOpacity(.6),
                                    height: 1,
                                  ),
                                  itemBuilder: (context, index) {
                                    final doc = docs[index];
                                    final data =
                                        doc.data() as Map<String, dynamic>;

                                    final isAnonymous =
                                        (data['isAnonymous'] ?? true) as bool;
                                    final userId = _readStr(data, 'uid');
                                    final location = _readStr(data, 'location');
                                    final description = _readStr(
                                      data,
                                      'description',
                                    );
                                    final imageUrl = _readStr(data, 'imageUrl');
                                    final ts = data['timestamp'] is Timestamp
                                        ? data['timestamp'] as Timestamp
                                        : null;
                                    final initialStatus =
                                        _readStr(data, 'status') ?? 'Pending';

                                    if (isAnonymous ||
                                        userId == null ||
                                        userId.isEmpty) {
                                      return _complaintRow(
                                        index: index,
                                        name: 'Anonymous',
                                        location: location,
                                        description: description,
                                        imageUrl: imageUrl,
                                        timestamp: ts,
                                        docId: doc.id,
                                        initialStatus: initialStatus,
                                      );
                                    } else {
                                      return FutureBuilder<DocumentSnapshot>(
                                        future: FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(userId)
                                            .get(),
                                        builder: (context, userSnap) {
                                          String displayName = 'Unknown User';
                                          if (userSnap.connectionState ==
                                                  ConnectionState.done &&
                                              userSnap.hasData &&
                                              userSnap.data != null &&
                                              userSnap.data!.exists) {
                                            final u =
                                                userSnap.data!.data()
                                                    as Map<String, dynamic>;
                                            displayName =
                                                _readStr(
                                                  u,
                                                  'name',
                                                  'username',
                                                ) ??
                                                'Unknown User';
                                          }
                                          return _complaintRow(
                                            index: index,
                                            name: displayName,
                                            location: location,
                                            description: description,
                                            imageUrl: imageUrl,
                                            timestamp: ts,
                                            docId: doc.id,
                                            initialStatus: initialStatus,
                                          );
                                        },
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // footer (static for now)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '1-10 of 97',
                        style: TextStyle(color: subtext, fontSize: 12),
                      ),
                      Row(
                        children: [
                          Text(
                            'Rows per page: 10',
                            style: TextStyle(color: subtext, fontSize: 12),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '1/10',
                            style: TextStyle(color: subtext, fontSize: 12),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.chevron_left,
                              color: Colors.white54,
                              size: 18,
                            ),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.chevron_right,
                              color: Colors.white54,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== TABLE HELPERS =====
  Widget _th(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _complaintRow({
    required int index,
    required String name,
    required String? location,
    required String? description,
    required String? imageUrl,
    required Timestamp? timestamp,
    required String docId,
    required String initialStatus,
  }) {
    final dt = timestamp?.toDate() ?? DateTime.now();
    final dateStr = '${dt.day}/${dt.month}/${dt.year}';
    final timeStr = DateFormat('hh:mm a').format(dt);

    String selectedStatus = initialStatus;

    Color statusColor(String status) {
      switch (status) {
        case 'Pending':
          return const Color(0xFFFFB020);
        case 'Under Investigation':
          return const Color(0xFFFF5C5C);
        case 'Reviewed':
          return const Color(0xFF3DDC97);
        default:
          return Colors.white;
      }
    }

    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: Row(
                  children: [
                    Checkbox(
                      value: false,
                      onChanged: (v) {},
                      side: BorderSide(color: border),
                      checkColor: Colors.black,
                      activeColor: purple,
                    ),
                    Text('${index + 1}', style: TextStyle(color: text)),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      location ?? 'No Location',
                      style: TextStyle(color: subtext, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  description ?? 'No Description',
                  style: TextStyle(color: text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: null, // TODO: wire your map url field
                  child: Text(
                    'Map Link',
                    style: TextStyle(
                      color: purple,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(dateStr, style: TextStyle(color: text)),
              ),
              Expanded(
                flex: 2,
                child: Text(timeStr, style: TextStyle(color: text)),
              ),
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: border.withOpacity(.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border),
                  ),
                  child: DropdownButton<String>(
                    value: selectedStatus,
                    isExpanded: true,
                    dropdownColor: panel,
                    underline: const SizedBox(),
                    iconEnabledColor: text,
                    style: TextStyle(
                      color: statusColor(selectedStatus),
                      fontWeight: FontWeight.w700,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Pending',
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'Under Investigation',
                        child: Text('Under Investigation'),
                      ),
                      DropdownMenuItem(
                        value: 'Reviewed',
                        child: Text('Reviewed'),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => selectedStatus = v);
                      try {
                        await FirebaseFirestore.instance
                            .collection('complaints')
                            .doc(docId)
                            .update({'status': v});
                      } catch (_) {}
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===== WIDGETS =====

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
    const Color purple = Color(0xFF8C52FF);
    const Color text = Color(0xFFE8E9F1);
    const Color subtext = Color(0xFFA9AAB5);

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

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.query,
    required this.color,
  });

  final String title;
  final Query query;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const Color panel = Color(0xFF171A21);
    const Color border = Color(0xFF242A36);
    const Color text = Color(0xFFE8E9F1);
    const Color subtext = Color(0xFFA9AAB5);

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(14),
      child: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snap) {
          final count = (snap.hasData) ? snap.data!.size : 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: subtext, fontSize: 12)),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: text,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          );
        },
      ),
    );
  }
}
