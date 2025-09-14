import 'dart:html'
    as html; // web-only open; your project already uses this elsewhere
import 'package:buzzoffwebnew/MOH/map.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'analytics.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

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

  String? _readStr(
    Map<String, dynamic> m,
    String k1, [
    String? k2,
    String? k3,
  ]) {
    for (final k in [k1, k2, k3]) {
      if (k == null) continue;
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
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
        _complaintsStream =
            complaintsBase().orderBy('timestamp', descending: true).snapshots();
      });
      return;
    }

    final data = userDoc.data() as Map<String, dynamic>;
    final displayName = _readStr(data, 'username', 'name') ?? 'User';
    final role = _readStr(data, 'role');
    final mohArea = _readStr(data, 'moh_area', 'mohArea');

    setState(() {
      username = displayName;
      _role = role;
      _mohArea = mohArea;
      _complaintsStream =
          complaintsBase().orderBy('timestamp', descending: true).snapshots();
    });
  }

  /// MOH users scoped to their own `moh_area`. Others see all.
  Query complaintsBase() {
    final col = FirebaseFirestore.instance.collection('complaints');
    final role = _role?.toLowerCase();
    if (role == 'moh' && (_mohArea?.isNotEmpty ?? false)) {
      return col.where('moh_area', isEqualTo: _mohArea);
    }
    return col;
  }

  @override
  Widget build(BuildContext context) {
    final roleLower = _role?.toLowerCase();
    final orgTitle = roleLower == 'moh' ? 'MOH COMPLAINTS' : 'COMPLAINTS';

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
                            Text(
                              orgTitle,
                              style: const TextStyle(
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
                              children: [
                                _RoleChip(role: roleLower ?? 'guest'),
                                if (roleLower == 'moh' &&
                                    (_mohArea?.isNotEmpty ?? false))
                                  _AreaChip(area: _mohArea!),
                              ],
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
                _SideNavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Complaints',
                  active: true,
                  onTap: () {},
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
                  Builder(
                    builder: (_) {
                      final role = _role?.toLowerCase();
                      final title =
                          (role == 'moh' && (_mohArea?.isNotEmpty ?? false))
                              ? 'Complaints in ${_mohArea!}'
                              : 'Complaints';
                      return Text(
                        title,
                        style: const TextStyle(
                          color: text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '“Complaints are not setbacks; they’re unfiltered insights that guide our evolution and strengthen our service.”',
                    style: TextStyle(color: subtext, fontSize: 13),
                  ),
                  const SizedBox(height: 18),

                  // ===== KPI ROW =====
                  SizedBox(
                    height: 100,
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
                  const SizedBox(height: 14),

                  // ===== CARDS GRID (smaller "podak") =====
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: panelAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      padding: const EdgeInsets.all(12),
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

                                return LayoutBuilder(
                                  builder: (_, c) {
                                    final w = c.maxWidth;
                                    int cross = 3;
                                    if (w < 720) {
                                      cross = 1;
                                    } else if (w < 1100) {
                                      cross = 2;
                                    }
                                    return GridView.builder(
                                      itemCount: docs.length,
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: cross,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        // Smaller cards: more compact ratio
                                        childAspectRatio: 1.9,
                                      ),
                                      itemBuilder: (context, index) {
                                        final doc = docs[index];
                                        final data =
                                            doc.data() as Map<String, dynamic>;

                                        final isAnonymous =
                                            (data['isAnonymous'] ?? true)
                                                as bool;
                                        final userId = _readStr(data, 'uid');

                                        // Address from complaints collection
                                        final address = _readStr(
                                              data,
                                              'address',
                                              'location',
                                              'addr',
                                            ) ??
                                            '';

                                        final description = _readStr(
                                          data,
                                          'description',
                                        );

                                        final imageUrl = _readStr(
                                          data,
                                          'imageUrl',
                                          'image_url',
                                          'image',
                                        );

                                        final mapUrl = _readStr(
                                          data,
                                          'mapUrl',
                                          'map_link',
                                          'location_url',
                                        );

                                        final ts =
                                            data['timestamp'] is Timestamp
                                                ? data['timestamp'] as Timestamp
                                                : null;
                                        final initialStatus =
                                            _readStr(data, 'status') ??
                                                'Pending';

                                        final dt =
                                            ts?.toDate() ?? DateTime.now();
                                        final dateStr = DateFormat(
                                          'dd/MM/yyyy',
                                        ).format(dt);
                                        final timeStr = DateFormat(
                                          'hh:mm a',
                                        ).format(dt);

                                        // Resolve display name
                                        Future<Widget> buildCard(
                                          String name,
                                        ) async {
                                          return _ComplaintCard(
                                            docId: doc.id,
                                            displayName: name,
                                            address: address,
                                            description: description,
                                            imageUrl: imageUrl,
                                            mapUrl: mapUrl,
                                            dateStr: dateStr,
                                            timeStr: timeStr,
                                            initialStatus: initialStatus,
                                            onDirections: () =>
                                                _showDirectionsDialog(
                                              address: address,
                                              mapUrl: mapUrl,
                                            ),
                                          );
                                        }

                                        if (isAnonymous ||
                                            userId == null ||
                                            userId.isEmpty) {
                                          return FutureBuilder<Widget>(
                                            future: buildCard('Anonymous'),
                                            builder: (_, snap) =>
                                                snap.data ?? const SizedBox(),
                                          );
                                        } else {
                                          return FutureBuilder<
                                              DocumentSnapshot>(
                                            future: FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(userId)
                                                .get(),
                                            builder: (context, userSnap) {
                                              String displayName =
                                                  'Unknown User';
                                              if (userSnap.connectionState ==
                                                      ConnectionState.done &&
                                                  userSnap.hasData &&
                                                  userSnap.data != null &&
                                                  userSnap.data!.exists) {
                                                final u = userSnap.data!.data()
                                                    as Map<String, dynamic>;
                                                displayName = _readStr(
                                                      u,
                                                      'name',
                                                      'username',
                                                    ) ??
                                                    'Unknown User';
                                              }
                                              return FutureBuilder<Widget>(
                                                future: buildCard(displayName),
                                                builder: (_, snap) =>
                                                    snap.data ??
                                                    const SizedBox(),
                                              );
                                            },
                                          );
                                        }
                                      },
                                    );
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

  // ===== Directions dialog (no extra packages) =====
  void _showDirectionsDialog({
    required String? address,
    required String? mapUrl,
  }) {
    final addr = (address ?? '').trim();
    final hasAddr = addr.isNotEmpty;
    final hasMap = (mapUrl ?? '').trim().isNotEmpty;

    // Build Google Maps directions URL (web-friendly)
    final String? googleDir = hasAddr
        ? "https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(addr)}&travelmode=driving"
        : (hasMap ? mapUrl!.trim() : null);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Directions', style: TextStyle(color: text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasAddr) ...[
              const Text(
                'Address:',
                style: TextStyle(color: subtext, fontSize: 12),
              ),
              const SizedBox(height: 4),
              SelectableText(addr, style: const TextStyle(color: text)),
              const SizedBox(height: 12),
            ],
            if (hasMap)
              const Text(
                'A stored map link is available.',
                style: TextStyle(color: subtext, fontSize: 12),
              ),
            if (!hasAddr && !hasMap)
              const Text(
                'No address or map link is available for this complaint.',
                style: TextStyle(color: subtext),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (hasAddr) {
                await Clipboard.setData(ClipboardData(text: addr));
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address copied')),
                  );
                }
              } else {
                Navigator.pop(context);
              }
            },
            child: const Text(
              'Copy Address',
              style: TextStyle(color: Colors.white),
            ),
          ),
          if (googleDir != null)
            TextButton(
              onPressed: () {
                // Open externally on web; on other platforms user can paste the copied link
                if (kIsWeb) {
                  html.window.open(googleDir, '_blank');
                } else {
                  Clipboard.setData(ClipboardData(text: googleDir));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copied. Open it in Google Maps.'),
                    ),
                  );
                }
              },
              child: const Text(
                'Open Directions',
                style: TextStyle(color: Colors.white),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(12),
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
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          );
        },
      ),
    );
  }
}

// Role/area chips
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;

  Color get _bg {
    switch (role) {
      case 'moh':
        return const Color(0xFF123B2A);
      default:
        return const Color(0xFF2A2D36);
    }
  }

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
        (role.isEmpty ? 'guest' : role).toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AreaChip extends StatelessWidget {
  const _AreaChip({required this.area});
  final String area;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2430),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _ComplaintsPageState.border.withOpacity(.5)),
      ),
      child: Text(
        'Area: $area',
        style: const TextStyle(
          fontSize: 11,
          color: _ComplaintsPageState.subtext,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Thumbnail supporting https and gs:// (smaller podak size)
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
    const double h = 84; // smaller
    const double w = 120; // smaller

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
            borderRadius: BorderRadius.circular(10),
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

/// A single (smaller) complaint card
class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({
    required this.docId,
    required this.displayName,
    required this.address,
    required this.description,
    required this.imageUrl,
    required this.mapUrl,
    required this.dateStr,
    required this.timeStr,
    required this.initialStatus,
    required this.onDirections,
  });

  final String docId;
  final String displayName;
  final String address;
  final String? description;
  final String? imageUrl;
  final String? mapUrl;
  final String dateStr;
  final String timeStr;
  final String initialStatus;
  final VoidCallback onDirections;

  Color _statusColor(String status) {
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
    String selectedStatus = initialStatus;

    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          decoration: BoxDecoration(
            color: _ComplaintsPageState.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _ComplaintsPageState.border),
          ),
          padding: const EdgeInsets.all(12), // smaller padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top: name + status dropdown
              Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        color: _ComplaintsPageState.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _ComplaintsPageState.border.withOpacity(.22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _ComplaintsPageState.border),
                    ),
                    child: DropdownButton<String>(
                      value: selectedStatus,
                      isDense: true,
                      dropdownColor: _ComplaintsPageState.panel,
                      underline: const SizedBox(),
                      iconEnabledColor: _ComplaintsPageState.text,
                      style: TextStyle(
                        color: _statusColor(selectedStatus),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
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
                ],
              ),

              const SizedBox(height: 8),

              // Mid: image + right content
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ImageThumb(url: imageUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (address.isNotEmpty)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.place,
                                color: _ComplaintsPageState.purple,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  address,
                                  style: const TextStyle(
                                    color: _ComplaintsPageState.text,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 6),
                        Text(
                          description ?? 'No Description',
                          style: const TextStyle(
                            color: _ComplaintsPageState.subtext,
                            fontSize: 12.5,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          children: [
                            _ChipIcon(
                              icon: Icons.calendar_month,
                              label: dateStr,
                            ),
                            _ChipIcon(icon: Icons.access_time, label: timeStr),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Actions
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ComplaintsPageState.purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text(
                      'Directions',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if ((mapUrl ?? '').isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        final link = mapUrl!.trim();
                        if (kIsWeb) {
                          html.window.open(link, '_blank');
                        } else {
                          Clipboard.setData(ClipboardData(text: link));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Map link copied. Open it in Google Maps.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.map,
                        color: Colors.white70,
                        size: 16,
                      ),
                      label: const Text(
                        'Open Map',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChipIcon extends StatelessWidget {
  const _ChipIcon({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _ComplaintsPageState.panelAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _ComplaintsPageState.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _ComplaintsPageState.subtext),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _ComplaintsPageState.subtext,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
