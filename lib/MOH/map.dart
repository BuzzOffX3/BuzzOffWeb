// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as dom show document; // web meta-key

import 'analytics.dart';
import 'complaints.dart';

/// Map point (now sourced from `moh_actions`)
class _CasePoint {
  const _CasePoint({
    required this.id,
    required this.pos,
    required this.ageDays, // days since admission (fallback: since action)
    required this.locationType, // 'home' | 'work' | 'school'
    required this.locationAddress, // plain address string
    required this.reviewStatus, // 'no_signs' | 'cleaned'
    required this.reviewAt, // action timestamp
  });

  final String id;
  final LatLng pos;
  final int ageDays;
  final String locationType;
  final String locationAddress;
  final String reviewStatus;
  final DateTime reviewAt;
}

class MapPage extends StatefulWidget {
  const MapPage({super.key, this.mohArea});
  final String? mohArea;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _ZoneStyle {
  final Color innerFill, innerStroke, outerFill, outerStroke, pinColor;
  final bool visible;
  const _ZoneStyle({
    required this.innerFill,
    required this.innerStroke,
    required this.outerFill,
    required this.outerStroke,
    required this.pinColor,
    required this.visible,
  });
}

class _MapPageState extends State<MapPage> {
  // ===== THEME =====
  static const Color bg = Color(0xFF0F1115);
  static const Color sidebar = Color(0xFF14161B);
  static const Color panel = Color(0xFF171A21);
  static const Color panelAlt = Color(0xFF1B1F2A);
  static const Color border = Color(0xFF242A36);
  static const Color purple = Color(0xFF8C52FF);
  static const Color text = Color(0xFFE8E9F1);
  static const Color subtext = Color(0xFFA9AAB5);
  static const Color green = Color(0xFF32D74B);
  static const Color amber = Color(0xFFFFC107);
  static const Color red = Color(0xFFFF3B30);

  // ===== MAP =====
  final Completer<GoogleMapController> _mapCtl = Completer();
  final Set<Circle> _circles = {};
  final Set<Marker> _markers = {};
  LatLng _mapCenter = const LatLng(6.9271, 79.8612);
  double _mapZoom = 11;

  bool _loading = true;
  String _statusMsg = 'Loading…';
  String? _currentMohArea;

  // panel toggle
  bool _showMohPanel = true;

  // caches
  final Map<String, BitmapDescriptor> _markerIconCache = {};
  final Map<String, LatLng> _geoCache = {};

  // cluster radius
  static const double clusterRadiusM = 300.0;

  // Read Browser key from <meta name="gmaps-key" content="...">
  String get _apiKey {
    final el = dom.document.querySelector('meta[name="gmaps-key"]');
    return el?.getAttribute('content') ?? '';
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _statusMsg = 'Resolving MOH area…';
    });
    _currentMohArea = widget.mohArea ?? await _fetchUserMohArea();
    await _loadCasesAndDraw();
  }

  Future<String?> _fetchUserMohArea() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final m = doc.data();
      if (m == null) return null;
      final area = (m['moh_area'] ?? m['MOH_area'] ?? m['area'])
          ?.toString()
          .trim();
      return (area != null && area.isNotEmpty) ? area : null;
    } catch (e) {
      print('MOH area fetch failed: $e');
      return null;
    }
  }

  // ---- Geocoding (web REST) with session cache ----
  Future<LatLng?> _geocodeAddress(String address) async {
    final key = address.trim().toLowerCase();
    if (_geoCache.containsKey(key)) return _geoCache[key];

    if (!kIsWeb) return null;
    if (_apiKey.isEmpty) return null;

    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': address,
      'key': _apiKey,
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final results = j['results'] as List?;
    if (results == null || results.isEmpty) return null;

    final loc = results.first['geometry']?['location'];
    if (loc is Map && loc['lat'] is num && loc['lng'] is num) {
      final p = LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );
      _geoCache[key] = p;
      return p;
    }
    return null;
  }

  // ---- Distance helper (Haversine) ----
  double _metersBetween(LatLng a, LatLng b) {
    const double R = 6371000.0; // meters
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final sinDLat = math.sin(dLat / 2.0);
    final sinDLon = math.sin(dLon / 2.0);
    final h =
        sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
    final c = 2.0 * math.asin(math.min(1.0, math.sqrt(h)));
    return R * c;
  }

  double _degToRad(double d) => d * math.pi / 180.0;
  String _normAddr(String a) => a.trim().toLowerCase();

  // ==============================
  //    Drive map from moh_actions
  // ==============================
  Future<void> _loadCasesAndDraw() async {
    setState(() {
      _loading = true;
      _statusMsg = 'Loading MOH actions…';
      _circles.clear();
      _markers.clear();
      _markerIconCache.clear(); // ensure resized icons regenerate
    });

    try {
      // 1) Fetch moh_actions for this area and recent window
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
        'moh_actions',
      );

      if (_currentMohArea != null && _currentMohArea!.isNotEmpty) {
        q = q.where('patient_moh_area', isEqualTo: _currentMohArea);
      }

      // cover yellow(3w)+green(1w) windows
      final since = DateTime.now().subtract(const Duration(days: 60));
      q = q.where(
        'created_at',
        isGreaterThanOrEqualTo: Timestamp.fromDate(since),
      );

      final qs = await q.get();
      if (qs.docs.isEmpty) {
        setState(() {
          _loading = false;
          _statusMsg =
              'No review actions for ${_currentMohArea ?? "all areas"}';
        });
        return;
      }

      // 2) Keep only the latest action per *address string*
      final latestByAddr =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      for (final d in qs.docs) {
        final m = d.data();
        final addr = (m['location_address'] ?? '').toString().trim();
        if (addr.isEmpty) continue;

        final action = (m['action'] ?? '').toString().toLowerCase();
        if (action != 'no_signs' && action != 'cleaned') continue;

        final key = _normAddr(addr);

        DateTime at = DateTime.now();
        final ts = m['created_at'];
        if (ts is Timestamp) at = ts.toDate();
        if (ts is String && DateTime.tryParse(ts) != null) {
          at = DateTime.parse(ts);
        }

        final prev = latestByAddr[key];
        if (prev == null) {
          latestByAddr[key] = d;
        } else {
          DateTime prevAt = DateTime.fromMillisecondsSinceEpoch(0);
          final prevTs = prev.data()['created_at'];
          if (prevTs is Timestamp) prevAt = prevTs.toDate();
          if (prevTs is String && DateTime.tryParse(prevTs) != null) {
            prevAt = DateTime.parse(prevTs);
          }
          if (at.isAfter(prevAt)) latestByAddr[key] = d;
        }
      }

      // 3) Build points (geocode on the fly; no writes)
      final points = <_CasePoint>[];

      for (final entry in latestByAddr.entries) {
        final m = entry.value.data();
        final addr = (m['location_address'] ?? '').toString();
        final locType = (m['location_type'] ?? 'home').toString();
        final action = (m['action'] ?? 'no_signs').toString().toLowerCase();

        // admission date for day badge; fallback to action time
        DateTime? admit;
        final ad = m['date_of_admission'];
        if (ad is Timestamp) admit = ad.toDate();
        if (ad is String && DateTime.tryParse(ad) != null) {
          admit = DateTime.parse(ad);
        }

        DateTime actAt = DateTime.now();
        final ts = m['created_at'];
        if (ts is Timestamp) actAt = ts.toDate();
        if (ts is String && DateTime.tryParse(ts) != null) {
          actAt = DateTime.parse(ts);
        }

        final pos = await _geocodeAddress(addr);
        if (pos == null) continue;

        final ageDays =
            (admit != null
                    ? DateTime.now().difference(admit)
                    : DateTime.now().difference(actAt))
                .inDays
                .clamp(0, 9999);

        points.add(
          _CasePoint(
            id: '${entry.key}_$action',
            pos: pos,
            ageDays: ageDays,
            locationType: locType,
            locationAddress: addr,
            reviewStatus: action,
            reviewAt: actAt,
          ),
        );
      }

      if (points.isEmpty) {
        setState(() {
          _loading = false;
          _statusMsg =
              'No actionable locations for ${_currentMohArea ?? "all areas"}';
        });
        return;
      }

      // 4) Detect clusters (≥2 within 300 m)
      final clusterIds = <String>{};
      final neighborCount = <String, int>{};
      for (int i = 0; i < points.length; i++) {
        for (int j = i + 1; j < points.length; j++) {
          final d = _metersBetween(points[i].pos, points[j].pos);
          if (d <= clusterRadiusM) {
            clusterIds.add(points[i].id);
            clusterIds.add(points[j].id);
            neighborCount[points[i].id] =
                (neighborCount[points[i].id] ?? 0) + 1;
            neighborCount[points[j].id] =
                (neighborCount[points[j].id] ?? 0) + 1;
          }
        }
      }

      // 5) Draw (ONLY 300 m ring)
      final circles = <Circle>{};
      final markers = <Marker>{};
      LatLngBounds? bounds;

      for (final p in points) {
        final isCluster = clusterIds.contains(p.id);

        final style = _styleFromAction(
          reviewStatus: p.reviewStatus,
          reviewAt: p.reviewAt,
        );
        if (!style.visible) continue;

        // Ring: 0–300m ONLY
        circles.add(
          Circle(
            circleId: CircleId('${p.id}_300'),
            center: p.pos,
            radius: 300,
            fillColor: style.innerFill,
            strokeColor: style.innerStroke,
            strokeWidth: 2,
          ),
        );

        // Marker (very small; constant pixel size)
        final int nbh = (neighborCount[p.id] ?? 0) + 1;
        final BitmapDescriptor icon = isCluster
            ? await _clusterPin(nbh: nbh)
            : await _mosquitoPinWithDays(
                days: p.ageDays,
                baseColor: style.pinColor,
              );

        markers.add(
          Marker(
            markerId: MarkerId(p.id),
            position: p.pos,
            icon: icon,
            anchor: const Offset(0.5, 1.0),
            infoWindow: InfoWindow(
              title:
                  '${p.locationType[0].toUpperCase()}${p.locationType.substring(1)} · ${p.reviewStatus}',
              snippet:
                  '${_currentMohArea ?? ''}\n${p.locationAddress}\n${p.ageDays} days',
            ),
          ),
        );

        bounds = _extend(bounds, p.pos);
      }

      setState(() {
        _circles
          ..clear()
          ..addAll(circles);
        _markers
          ..clear()
          ..addAll(markers);
        _loading = false;
        _statusMsg =
            '${markers.length} locations${_currentMohArea != null ? " in $_currentMohArea" : ""}';
      });

      if (bounds != null) {
        final c = await _mapCtl.future;
        await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _statusMsg = 'Failed to load: $e';
      });
    }
  }

  // Style from action-only timeline
  // - 'no_signs' → YELLOW 3w → GREEN 1w → disappear
  // - 'cleaned'  → GREEN 1w → disappear
  _ZoneStyle _styleFromAction({
    required String reviewStatus,
    required DateTime reviewAt,
  }) {
    final d = DateTime.now().difference(reviewAt).inDays.clamp(0, 9999);

    if (reviewStatus == 'cleaned') {
      if (d <= 7) {
        return const _ZoneStyle(
          innerFill: Color(0x6632D74B),
          innerStroke: Color(0xFF32D74B),
          outerFill: Color(0x3332D74B),
          outerStroke: Color(0xFF32D74B),
          pinColor: Color(0xFF32D74B),
          visible: true,
        );
      } else {
        return const _ZoneStyle(
          innerFill: Color(0x00000000),
          innerStroke: Color(0x00000000),
          outerFill: Color(0x00000000),
          outerStroke: Color(0x00000000),
          pinColor: Color(0x00000000),
          visible: false,
        );
      }
    }

    if (reviewStatus == 'no_signs') {
      if (d <= 21) {
        return const _ZoneStyle(
          innerFill: Color(0x55FFC107),
          innerStroke: Color(0xFFFFC107),
          outerFill: Color(0x22FFE082),
          outerStroke: Color(0xFFFEF08A),
          pinColor: Color(0xFFFFC107),
          visible: true,
        );
      } else if (d <= 28) {
        return const _ZoneStyle(
          innerFill: Color(0x6632D74B),
          innerStroke: Color(0xFF32D74B),
          outerFill: Color(0x3332D74B),
          outerStroke: Color(0xFF32D74B),
          pinColor: Color(0xFF32D74B),
          visible: true,
        );
      } else {
        return const _ZoneStyle(
          innerFill: Color(0x00000000),
          innerStroke: Color(0x00000000),
          outerFill: Color(0x00000000),
          outerStroke: Color(0x00000000),
          pinColor: Color(0x00000000),
          visible: false,
        );
      }
    }

    // Fallback (shouldn't hit)
    return const _ZoneStyle(
      innerFill: Color(0x00000000),
      innerStroke: Color(0x00000000),
      outerFill: Color(0x00000000),
      outerStroke: Color(0x00000000),
      pinColor: Color(0x00000000),
      visible: false,
    );
  }

  // ---- Custom pins (very small; constant logical size; 2× backing) ----

  Future<BitmapDescriptor> _mosquitoPinWithDays({
    required int days,
    required Color baseColor,
  }) async {
    // shrink all geometry with a single scalar
    const double s = 0.35; // tweak 0.25–0.45 as you like
    final key = 'mosq2x_s${s}_$days${baseColor.value.toRadixString(16)}';
    final cached = _markerIconCache[key];
    if (cached != null) return cached;

    const int baseLogical = 130;
    const double scale = 2.0;
    final int size = (baseLogical * s * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = Paint()..color = baseColor;

    // pin shape (circle + tail), scaled
    final cx = size / 2.0;
    final cy = size / 2.0 - 16 * s * scale / 2.0;

    canvas.drawCircle(Offset(cx, cy), 22 * s * scale, paint);

    final tail = Path()
      ..moveTo(cx, size - 24 * s * scale / 2.0)
      ..lineTo(cx - 11 * s * scale, size / 2.0 + 12 * s * scale / 2.0)
      ..lineTo(cx + 11 * s * scale, size / 2.0 + 12 * s * scale / 2.0)
      ..close();
    canvas.drawPath(tail, paint);

    // inner dark disc
    final inner = Paint()..color = Colors.black.withOpacity(0.75);
    canvas.drawCircle(Offset(cx, cy), 16 * s * scale, inner);

    // mosquito emoji
    final emoji = TextSpan(
      text: '🦟',
      style: TextStyle(fontSize: 18 * s * scale),
    );
    final emojiPainter = TextPainter(
      text: emoji,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 40 * s * scale);
    emojiPainter.paint(
      canvas,
      Offset(cx - emojiPainter.width / 2, cy - 12 * s * scale),
    );

    // tiny badge
    final badgeW = 46.0 * s * scale;
    final badgeH = 22.0 * s * scale;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - badgeW / 2, cy - 46 * s * scale, badgeW, badgeH),
      Radius.circular(11 * s * scale),
    );
    final badgeBg = Paint()..color = Colors.black.withOpacity(0.85);
    canvas.drawRRect(badgeRect, badgeBg);
    final gloss = Paint()..color = Colors.white.withOpacity(0.07);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - badgeW / 2, cy - 46 * s * scale, badgeW, badgeH / 2),
        Radius.circular(11 * s * scale),
      ),
      gloss,
    );

    final span = TextSpan(
      text: '${days}d',
      style: TextStyle(
        color: Colors.white,
        fontSize: 12 * s * scale,
        fontWeight: FontWeight.w800,
        letterSpacing: .3,
      ),
    );
    final tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: badgeW);
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - 43 * s * scale));

    final img = await recorder.endRecording().toImage(size, size);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _markerIconCache[key] = icon;
    return icon;
  }

  Future<BitmapDescriptor> _clusterPin({required int nbh}) async {
    const double s = 0.35; // keep in sync with mosquito pin
    final key = 'cluster2x_s${s}_x$nbh';
    final cached = _markerIconCache[key];
    if (cached != null) return cached;

    const int baseLogical = 140;
    const double scale = 2.0;
    final int size = (baseLogical * s * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const red = Color(0xFFFF3B30);

    final cx = size / 2.0;
    final cy = size / 2.0 - 16 * s * scale / 2.0;

    final paint = Paint()..color = red;
    canvas.drawCircle(Offset(cx, cy), 26 * s * scale, paint);

    final tail = Path()
      ..moveTo(cx, size - 24 * s * scale / 2.0)
      ..lineTo(cx - 12 * s * scale, size / 2.0 + 12 * s * scale / 2.0)
      ..lineTo(cx + 12 * s * scale, size / 2.0 + 12 * s * scale / 2.0)
      ..close();
    canvas.drawPath(tail, paint);

    final inner = Paint()..color = Colors.black.withOpacity(0.78);
    canvas.drawCircle(Offset(cx, cy), 18 * s * scale, inner);

    final cl = TextSpan(
      text: 'CL',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: 16 * s * scale,
        letterSpacing: .5,
      ),
    );
    final tpCL = TextPainter(
      text: cl,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 40 * s * scale);
    tpCL.paint(canvas, Offset(cx - tpCL.width / 2, cy - 16 * s * scale));

    final ct = TextSpan(
      text: 'x$nbh',
      style: TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w700,
        fontSize: 12 * s * scale,
      ),
    );
    final tpCt = TextPainter(
      text: ct,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 40 * s * scale);
    tpCt.paint(canvas, Offset(cx - tpCt.width / 2, cy - 2 * s * scale));

    final img = await recorder.endRecording().toImage(size, size);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _markerIconCache[key] = icon;
    return icon;
  }

  // ---- bounds helper ----
  LatLngBounds _extend(LatLngBounds? b, LatLng p) {
    if (b == null) return LatLngBounds(southwest: p, northeast: p);
    final sw = LatLng(
      p.latitude < b.southwest.latitude ? p.latitude : b.southwest.latitude,
      p.longitude < b.southwest.longitude ? p.longitude : b.southwest.longitude,
    );
    final ne = LatLng(
      p.latitude > b.northeast.latitude ? p.latitude : b.northeast.latitude,
      p.longitude > b.northeast.longitude ? p.longitude : b.northeast.longitude,
    );
    return LatLngBounds(southwest: sw, northeast: ne);
  }

  // ===== Firestore writes for MOH panel + logging =====
  Future<void> _setReviewStatus({
    required String caseId,
    required String? status, // 'no_signs' | 'cleaned' | null
    required String locationType, // 'home'|'work'|'school'
    required String locationAddress,
  }) async {
    try {
      final caseRef = FirebaseFirestore.instance
          .collection('dengue_cases')
          .doc(caseId);

      Map<String, dynamic>? caseData;
      final snap = await caseRef.get();
      if (snap.exists) caseData = snap.data();

      // keep per-case fields (optional compatibility)
      if (status == null) {
        await caseRef.set({
          'review_status': FieldValue.delete(),
          'review_updated_at': FieldValue.delete(),
        }, SetOptions(merge: true));
      } else {
        await caseRef.set({
          'review_status': status,
          'review_updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // log moh_actions (what the map reads)
      if (status != null) {
        final homeAddr =
            (caseData?['address'] ?? caseData?['patient_address'] ?? '')
                .toString();
        final mohArea =
            (caseData?['patient_moh_area'] ?? caseData?['moh_area'] ?? '')
                .toString();
        final phiArea =
            (caseData?['patient_phi_area'] ?? caseData?['phi_area'] ?? '')
                .toString();
        final caseStatus = (caseData?['case_status'] ?? '').toString();

        DateTime? admitAt;
        final ad = caseData?['date_of_admission'];
        if (ad is Timestamp) admitAt = ad.toDate();
        if (ad is String && DateTime.tryParse(ad) != null) {
          admitAt = DateTime.parse(ad);
        }

        await FirebaseFirestore.instance.collection('moh_actions').add({
          'case_id': caseId,
          'action': status, // 'no_signs' or 'cleaned'
          'created_at': FieldValue.serverTimestamp(),
          'patient_address': homeAddr,
          'patient_moh_area': mohArea,
          'patient_phi_area': phiArea,
          'case_status': caseStatus,
          'date_of_admission': admitAt,
          'actor_uid': FirebaseAuth.instance.currentUser?.uid,
          'location_type': locationType,
          'location_address': locationAddress,
        });
      }

      _loadCasesAndDraw();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == null
                  ? 'Status cleared'
                  : 'Marked $locationType: $status',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showPanel = _showMohPanel && width >= 1100; // auto-hide on narrow

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
                        child: Text(
                          'MAP ${_currentMohArea != null ? "· ${_currentMohArea!}" : ""}',
                          style: const TextStyle(
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
                const _SideNavItem(
                  icon: Icons.map_outlined,
                  label: 'Map',
                  active: true,
                  onTap: null,
                ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: _UserFooter(),
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
                  // Header
                  Row(
                    children: [
                      const Text(
                        'Dengue Risk Zones',
                        style: TextStyle(
                          color: text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _legendDot(color: amber, label: 'No-signs (≤21d)'),
                      const SizedBox(width: 8),
                      _legendDot(color: green, label: 'Green (≤7d)'),
                      const Spacer(),
                      if (_currentMohArea != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: panelAlt,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: border),
                          ),
                          child: Text(
                            'MOH: ${_currentMohArea!}',
                            style: const TextStyle(
                              color: subtext,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _loadCasesAndDraw,
                        icon: const Icon(
                          Icons.refresh,
                          color: Colors.white70,
                          size: 18,
                        ),
                        label: const Text(
                          'Reload',
                          style: TextStyle(color: Colors.white70),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: border),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _showMohPanel = !_showMohPanel),
                        icon: const Icon(
                          Icons.admin_panel_settings,
                          color: Colors.white70,
                          size: 18,
                        ),
                        label: Text(
                          _showMohPanel ? 'Hide MOH Review' : 'MOH Review',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: border),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Map + MOH panel
                  Expanded(
                    child: Row(
                      children: [
                        // MAP
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: panel,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: border),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target: _mapCenter,
                                    zoom: _mapZoom,
                                  ),
                                  myLocationButtonEnabled: false,
                                  myLocationEnabled: false,
                                  zoomControlsEnabled: true,
                                  compassEnabled: true,
                                  markers: _markers,
                                  circles: _circles,
                                  onMapCreated: (c) => _mapCtl.complete(c),
                                ),
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    margin: const EdgeInsets.all(10),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: panelAlt,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_loading)
                                          const SizedBox(
                                            height: 14,
                                            width: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        if (_loading) const SizedBox(width: 8),
                                        Text(
                                          _statusMsg,
                                          style: const TextStyle(
                                            color: subtext,
                                            fontSize: 12,
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

                        // MOH REVIEW PANEL
                        if (showPanel) ...[
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 420,
                            child: _MohReviewPanel(
                              mohArea: _currentMohArea,
                              onAction: (args) => _setReviewStatus(
                                caseId: args.caseId,
                                status: args.status,
                                locationType: args.locationType,
                                locationAddress: args.locationAddress,
                              ),
                            ),
                          ),
                        ],
                      ],
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

  Widget _legendDot({required Color color, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: panelAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
          Text(label, style: const TextStyle(color: subtext, fontSize: 12)),
        ],
      ),
    );
  }
}

// ===== MOH Review Panel =====

class _MohActionArgs {
  _MohActionArgs({
    required this.caseId,
    required this.status, // 'no_signs' | 'cleaned' | null
    required this.locationType, // home|work|school
    required this.locationAddress,
  });
  final String caseId;
  final String? status;
  final String locationType;
  final String locationAddress;
}

class _MohReviewPanel extends StatefulWidget {
  const _MohReviewPanel({required this.mohArea, required this.onAction});

  final String? mohArea;
  final Future<void> Function(_MohActionArgs args) onAction;

  @override
  State<_MohReviewPanel> createState() => _MohReviewPanelState();
}

class _MohReviewPanelState extends State<_MohReviewPanel> {
  String _query = '';

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'dengue_cases',
    );

    if (widget.mohArea != null && widget.mohArea!.isNotEmpty) {
      q = q.where('patient_moh_area', isEqualTo: widget.mohArea);
    }
    q = q.orderBy('date_of_admission', descending: true).limit(100);
    return q;
  }

  bool _matches(Map<String, dynamic> m) {
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase();
    bool hit(String? v) => (v ?? '').toLowerCase().contains(q);
    return hit(m['patient_name']?.toString()) ||
        hit(m['case_code']?.toString()) ||
        hit(m['address']?.toString()) ||
        hit(m['patient_address']?.toString()) ||
        hit(m['work_address']?.toString()) ||
        hit(m['patient_work_address']?.toString()) ||
        hit(m['school_address']?.toString()) ||
        hit(m['patient_school_address']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    const Color panel = _MapPageState.panel;
    const Color border = _MapPageState.border;
    const Color subtext = _MapPageState.subtext;
    const Color green = _MapPageState.green;
    const Color amber = _MapPageState.amber;

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.admin_panel_settings, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                'MOH Review',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search name / code / address',
              hintStyle: const TextStyle(color: Colors.white38),
              isDense: true,
              filled: true,
              fillColor: _MapPageState.panelAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: Colors.white54,
                size: 18,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _baseQuery().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white54,
                      strokeWidth: 2,
                    ),
                  );
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No cases',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                final docs = snap.data!.docs
                    .where((d) => _matches(d.data()))
                    .toList(growable: false);

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: border, height: 16),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();

                    final name = (m['patient_name'] ?? m['case_code'] ?? 'Case')
                        .toString();

                    final homeAddr =
                        (m['address'] ?? m['patient_address'] ?? '').toString();
                    final workAddr =
                        (m['work_address'] ??
                                m['patient_work_address'] ??
                                m['office_address'] ??
                                '')
                            .toString();
                    final schoolAddr =
                        (m['school_address'] ??
                                m['patient_school_address'] ??
                                '')
                            .toString();

                    final locations = <String, String>{};
                    if (homeAddr.trim().isNotEmpty)
                      locations['home'] = homeAddr;
                    if (workAddr.trim().isNotEmpty)
                      locations['work'] = workAddr;
                    if (schoolAddr.trim().isNotEmpty) {
                      locations['school'] = schoolAddr;
                    }

                    String selectedType = locations.keys.isNotEmpty
                        ? locations.keys.first
                        : 'home';

                    return StatefulBuilder(
                      builder: (ctx, setRow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // title + location selector
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (locations.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _MapPageState.panelAlt,
                                      border: Border.all(color: border),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: DropdownButton<String>(
                                      dropdownColor: _MapPageState.panelAlt,
                                      borderRadius: BorderRadius.circular(8),
                                      value: selectedType,
                                      underline: const SizedBox.shrink(),
                                      icon: const Icon(
                                        Icons.expand_more,
                                        size: 16,
                                        color: Colors.white60,
                                      ),
                                      items: locations.keys.map((k) {
                                        final label =
                                            k[0].toUpperCase() + k.substring(1);
                                        return DropdownMenuItem<String>(
                                          value: k,
                                          child: Text(
                                            label,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (v) {
                                        if (v != null)
                                          setRow(() => selectedType = v);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                            if (locations.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  locations[selectedType]!,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _actionBtn(
                                  label: 'No Signs',
                                  icon: Icons.check_circle,
                                  color: amber,
                                  onTap: () => widget.onAction(
                                    _MohActionArgs(
                                      caseId: d.id,
                                      status: 'no_signs',
                                      locationType: selectedType,
                                      locationAddress:
                                          locations[selectedType] ?? '',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _actionBtn(
                                  label: 'Cleaned',
                                  icon: Icons.sanitizer,
                                  color: green,
                                  onTap: () => widget.onAction(
                                    _MohActionArgs(
                                      caseId: d.id,
                                      status: 'cleaned',
                                      locationType: selectedType,
                                      locationAddress:
                                          locations[selectedType] ?? '',
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(
                                    Icons.clear,
                                    size: 18,
                                    color: Colors.white54,
                                  ),
                                  onPressed: () => widget.onAction(
                                    _MohActionArgs(
                                      caseId: d.id,
                                      status: null,
                                      locationType: selectedType,
                                      locationAddress:
                                          locations[selectedType] ?? '',
                                    ),
                                  ),
                                ),
                              ],
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
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Small reused bits =====

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: InkWell(
        onTap: active ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? _MapPageState.purple.withOpacity(.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: active
                    ? _MapPageState.purple
                    : _MapPageState.text.withOpacity(.85),
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: active ? _MapPageState.purple : _MapPageState.subtext,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (active)
                const Icon(
                  Icons.chevron_right,
                  color: _MapPageState.purple,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        CircleAvatar(backgroundImage: AssetImage('images/pfp.png'), radius: 16),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'User',
            style: TextStyle(color: _MapPageState.subtext, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(Icons.more_vert, color: Colors.white54, size: 18),
      ],
    );
  }
}
