import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'ndcuanalytic.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;

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
        _complaintsStream = complaintsBase()
            .orderBy('timestamp', descending: true)
            .snapshots();
      });
      return;
    }

    final data = (userDoc.data() as Map<String, dynamic>);
    final displayName = _readStr(data, 'username', 'name') ?? 'User';
    final role = _readStr(data, 'role');

    setState(() {
      username = displayName;
      _role = role;
      _complaintsStream = complaintsBase()
          .orderBy('timestamp', descending: true)
          .snapshots();
    });
  }

  // NDCU: see everything (no MOH scoping)
  Query complaintsBase() {
    return FirebaseFirestore.instance.collection('complaints');
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final roleLower = _role?.toLowerCase();
    const orgTitle = 'NDCU COMPLAINTS';

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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              orgTitle,
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [_RoleChip(role: roleLower ?? 'ndcu')],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SideNavItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Analytics',
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const AnalyticsPage(),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  },
                ),
                const _SideNavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Complaints',
                  active: true,
                  onTap: null,
                ),
                // (No Maps entry here unless you still want it for NDCU)
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
                  const Text(
                    'All Complaints (NDCU)',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
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
                        _th('Description', flex: 2),
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
                                  return const Center(
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
                                    final imageUrl =
                                        _readStr(data, 'imageUrl') ??
                                        _readStr(data, 'image_url') ??
                                        _readStr(data, 'image');
                                    final mapUrl =
                                        _readStr(data, 'mapUrl') ??
                                        _readStr(data, 'map_link') ??
                                        _readStr(data, 'maplink') ??
                                        _readStr(data, 'location_url');
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
                                        mapUrl: mapUrl,
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
                                            mapUrl: mapUrl,
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
                      const Text(
                        '1-10 of 97',
                        style: TextStyle(color: subtext, fontSize: 12),
                      ),
                      Row(
                        children: [
                          const Text(
                            'Rows per page: 10',
                            style: TextStyle(color: subtext, fontSize: 12),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 16),
                          const Text(
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
        style: const TextStyle(
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
    required String? mapUrl,
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
                      side: const BorderSide(color: border),
                      checkColor: Colors.black,
                      activeColor: purple,
                    ),
                    Text('${index + 1}', style: const TextStyle(color: text)),
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
                      style: const TextStyle(
                        color: text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      location ?? 'No Location',
                      style: const TextStyle(color: subtext, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  description ?? 'No Description',
                  style: const TextStyle(color: text),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              SizedBox(
                width: 120,
                child: Padding(
                  padding: const EdgeInsets.only(right: 50.0),
                  child: _ImageThumb(url: imageUrl),
                ),
              ),
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: (mapUrl != null && mapUrl.isNotEmpty)
                      ? () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: panel,
                              title: const Text(
                                'Map Link',
                                style: TextStyle(color: text),
                              ),
                              content: SelectableText(
                                mapUrl!,
                                style: const TextStyle(color: subtext),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        }
                      : null,
                  child: Text(
                    (mapUrl != null && mapUrl!.isNotEmpty)
                        ? 'Open'
                        : 'Map Link',
                    style: const TextStyle(
                      color: purple,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(dateStr, style: const TextStyle(color: text)),
              ),
              Expanded(
                flex: 2,
                child: Text(timeStr, style: const TextStyle(color: text)),
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
  final VoidCallback? onTap;
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
              Text(title, style: const TextStyle(color: subtext, fontSize: 12)),
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
                    style: const TextStyle(
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

// Small pill for role
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;

  Color get _bg {
    return const Color(0xFF2A1F4D); // NDCU theme
  }

  Color get _fg => Colors.white.withOpacity(.9);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _ComplaintsPageState.border.withOpacity(.5)),
      ),
      child: Text(
        (role.isEmpty ? 'ndcu' : role).toUpperCase(),
        style: TextStyle(fontSize: 11, color: _fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Thumbnail that supports https and gs://
class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.url});
  final String? url;

  bool get _isGs => (url ?? '').startsWith('gs://');

  Future<String?> _resolveUrl() async {
    if (url == null || url!.isEmpty) return null;
    if (_isGs) {
      try {
        final ref = firebase_storage.FirebaseStorage.instance.refFromURL(url!);
        return await ref.getDownloadURL();
      } catch (_) {
        return null;
      }
    }
    return url!;
  }

  @override
  Widget build(BuildContext context) {
    const double h = 48;
    const double w = 72;

    if (url == null || url!.isEmpty) {
      return const Text(
        'No Image',
        style: TextStyle(color: _ComplaintsPageState.subtext),
      );
    }

    return FutureBuilder<String?>(
      future: _resolveUrl(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: h,
            width: w,
            child: Center(
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final resolved = snap.data;
        if (resolved == null || resolved.isEmpty) {
          return Row(
            children: const [
              Icon(Icons.broken_image, color: Colors.white54, size: 18),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Load failed',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ],
          );
        }

        return InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1117),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _ComplaintsPageState.border),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(
                      resolved,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 240,
                        child: Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              resolved,
              height: h,
              width: w,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: h,
                width: w,
                color: const Color(0xFF232938),
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 18,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
