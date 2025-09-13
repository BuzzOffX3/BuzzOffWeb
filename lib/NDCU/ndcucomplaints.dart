import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'ndcuanalytic.dart';
import 'mapnd.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:url_launcher/url_launcher.dart';

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

  double? _readNum(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v);
      return parsed;
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

  // NDCU scope: all complaints
  Query complaintsBase() {
    return FirebaseFirestore.instance.collection('complaints');
  }

  // ===== Helpers for directions =====
  // Build a Google Maps directions URL using the best available destination field.
  String? _buildDirectionsUrl(Map<String, dynamic> data) {
    // Priority 1: explicit direction address
    final directionAddress = _readStr(data, 'directionAddress');
    if (directionAddress != null && directionAddress.isNotEmpty) {
      final dest = Uri.encodeComponent(directionAddress);
      return 'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving';
    }

    // Priority 2: lat/lng numbers
    final lat = _readNum(data, 'lat') ?? _readNum(data, 'latitude');
    final lng = _readNum(data, 'lng') ?? _readNum(data, 'longitude');
    if (lat != null && lng != null) {
      final dest = Uri.encodeComponent('$lat,$lng');
      return 'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving';
    }

    // Priority 3: a saved mapUrl that might already be a Google Maps/short link
    final mapUrl =
        _readStr(data, 'mapUrl') ??
        _readStr(data, 'map_link') ??
        _readStr(data, 'maplink') ??
        _readStr(data, 'location_url');
    if (mapUrl != null && mapUrl.isNotEmpty) {
      // If it already looks like a /dir URL, use it as-is. Otherwise pass as destination.
      if (mapUrl.contains('/dir') || mapUrl.contains('maps.app.goo.gl')) {
        return mapUrl;
      } else {
        final dest = Uri.encodeComponent(mapUrl);
        return 'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving';
      }
    }

    // Priority 4: plain text location string
    final location = _readStr(data, 'location');
    if (location != null && location.isNotEmpty) {
      final dest = Uri.encodeComponent(location);
      return 'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving';
    }

    return null;
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open directions link.')),
      );
    }
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
                _SideNavItem(
                  icon: Icons.map_outlined,
                  label: 'Map',
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const MapPage(),
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

                  // ===== CARDS GRID =====
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
                                // Responsive columns
                                final width = MediaQuery.of(context).size.width;
                                int crossAxisCount = 3;
                                if (width < 900)
                                  crossAxisCount = 1;
                                else if (width < 1300)
                                  crossAxisCount = 2;

                                return GridView.builder(
                                  padding: const EdgeInsets.all(16),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 16,
                                        childAspectRatio: 1.8,
                                      ),
                                  itemCount: docs.length,
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
                                    final ts = data['timestamp'] is Timestamp
                                        ? data['timestamp'] as Timestamp
                                        : null;
                                    final initialStatus =
                                        _readStr(data, 'status') ?? 'Pending';

                                    final directionsUrl = _buildDirectionsUrl(
                                      data,
                                    );

                                    if (isAnonymous ||
                                        userId == null ||
                                        userId.isEmpty) {
                                      return _ComplaintCard(
                                        name: 'Anonymous',
                                        location: location,
                                        description: description,
                                        imageUrl: imageUrl,
                                        timestamp: ts,
                                        docId: doc.id,
                                        initialStatus: initialStatus,
                                        directionsUrl: directionsUrl,
                                        onOpenDirections: directionsUrl == null
                                            ? null
                                            : () => _openExternalUrl(
                                                directionsUrl,
                                              ),
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
                                          return _ComplaintCard(
                                            name: displayName,
                                            location: location,
                                            description: description,
                                            imageUrl: imageUrl,
                                            timestamp: ts,
                                            docId: doc.id,
                                            initialStatus: initialStatus,
                                            directionsUrl: directionsUrl,
                                            onOpenDirections:
                                                directionsUrl == null
                                                ? null
                                                : () => _openExternalUrl(
                                                    directionsUrl,
                                                  ),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== CARD WIDGET (VIEW-ONLY STATUS) =====
class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({
    required this.name,
    required this.location,
    required this.description,
    required this.imageUrl,
    required this.timestamp,
    required this.docId,
    required this.initialStatus,
    required this.directionsUrl,
    required this.onOpenDirections,
  });

  final String name;
  final String? location;
  final String? description;
  final String? imageUrl;
  final Timestamp? timestamp;
  final String docId;
  final String initialStatus;
  final String? directionsUrl;
  final VoidCallback? onOpenDirections;

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

  @override
  Widget build(BuildContext context) {
    const Color panel = _ComplaintsPageState.panel;
    const Color border = _ComplaintsPageState.border;
    const Color text = _ComplaintsPageState.text;
    const Color subtext = _ComplaintsPageState.subtext;
    const Color purple = _ComplaintsPageState.purple;

    final dt = timestamp?.toDate() ?? DateTime.now();
    final dateStr = '${dt.day}/${dt.month}/${dt.year}';
    final timeStr = DateFormat('hh:mm a').format(dt);

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Image
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _ImageThumb(url: imageUrl),
            ),
          ),
          const SizedBox(width: 14),

          // Main info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + status chip (VIEW ONLY)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: text,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: border.withOpacity(.25),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor(initialStatus),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            initialStatus,
                            style: TextStyle(
                              color: statusColor(initialStatus),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Location
                Row(
                  children: [
                    const Icon(Icons.place, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        location ?? 'No Location',
                        style: const TextStyle(color: subtext, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  description ?? 'No Description',
                  style: const TextStyle(color: text),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),

                // Date/Time + Directions
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: border.withOpacity(.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month,
                            color: Colors.white60,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              color: subtext,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.access_time,
                            color: Colors.white60,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              color: subtext,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: directionsUrl == null
                          ? 'No directions available'
                          : 'Open directions',
                      child: InkWell(
                        onTap: onOpenDirections,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: directionsUrl == null
                                ? Colors.white12
                                : purple.withOpacity(.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: directionsUrl == null
                                  ? border
                                  : purple.withOpacity(.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.directions,
                                size: 18,
                                color: directionsUrl == null
                                    ? Colors.white38
                                    : purple,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Directions',
                                style: TextStyle(
                                  color: directionsUrl == null
                                      ? Colors.white38
                                      : purple,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    const double h = 120;
    const double w = 120;

    if (url == null || url!.isEmpty) {
      return Container(
        height: h,
        width: w,
        color: const Color(0xFF232938),
        child: const Center(
          child: Text(
            'No Image',
            style: TextStyle(color: _ComplaintsPageState.subtext),
          ),
        ),
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
          return Container(
            height: h,
            width: w,
            color: const Color(0xFF232938),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: Colors.white54, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Load failed',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
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
        );
      },
    );
  }
}
