// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart'; // not needed in read-only mode
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as dom show document; // web meta-key

import 'ndcuanalytic.dart';
import 'ndcucomplaints.dart';

/// Map point (sourced from `moh_actions`)
class _CasePoint {
  const _CasePoint({
    required this.id,
    required this.pos,
    required this.ageDays, // days since admission (fallback: since action)
    required this.locationType, // 'home' | 'work' | 'school'
    required this.locationAddress, // plain address string
    required this.reviewStatus, // 'new_case' | 'no_signs' | 'cleaned'
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

  // Lock to Sri Lanka (generous padding)
  static final LatLngBounds _lkBounds = LatLngBounds(
    southwest: const LatLng(5.7, 79.3),
    northeast: const LatLng(10.1, 82.1),
  );

  bool _loading = true;
  String _statusMsg = 'Loading…';

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
      _statusMsg = 'Loading cases…';
    });
    // NOTE: area restriction removed – don’t resolve/filter by MOH area here.
    await _loadCasesAndDraw();
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
      // 1) Fetch moh_actions for a recent window – NO MOH AREA FILTER.
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
        'moh_actions',
      );

      // cover windows (we'll show up to 60 days)
      final since = DateTime.now().subtract(const Duration(days: 60));
      q = q.where(
        'created_at',
        isGreaterThanOrEqualTo: Timestamp.fromDate(since),
      );

      final qs = await q.get();
      if (qs.docs.isEmpty) {
        setState(() {
          _loading = false;
          _statusMsg = 'No actions in the last 60 days';
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

        // include 'new_case' alongside MOH reviews
        final action = (m['action'] ?? '').toString().toLowerCase();
        const allowed = {'no_signs', 'cleaned', 'new_case'};
        if (!allowed.contains(action)) continue;

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
          _statusMsg = 'No actionable locations';
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
              snippet: '${p.locationAddress}\n${p.ageDays} days',
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
        _statusMsg = '${markers.length} locations';
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
  // - 'new_case' → RED ≤60d → disappear
  // - 'no_signs' → YELLOW 3w → GREEN 1w → disappear
  // - 'cleaned'  → GREEN 1w → disappear
  _ZoneStyle _styleFromAction({
    required String reviewStatus,
    required DateTime reviewAt,
  }) {
    final d = DateTime.now().difference(reviewAt).inDays.clamp(0, 9999);

    if (reviewStatus == 'new_case') {
      if (d <= 60) {
        return const _ZoneStyle(
          innerFill: Color(0x55FF3B30),
          innerStroke: Color(0xFFFF3B30),
          outerFill: Color(0x22FF3B30),
          outerStroke: Color(0xFFFF3B30),
          pinColor: Color(0xFFFF3B30),
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
                      const Expanded(
                        child: Text(
                          'MAP',
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
                  // ======= HEADER (overflow-safe) =======
                  LayoutBuilder(
                    builder: (ctx, cons) {
                      final isNarrow = cons.maxWidth < 900;

                      final legendWrap = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _legendDot(color: red, label: 'New case (≤60d)'),
                          _legendDot(color: amber, label: 'No-signs (≤21d)'),
                          _legendDot(color: green, label: 'Green (≤7d)'),
                        ],
                      );

                      if (isNarrow) {
                        // Stack into two rows on narrow screens
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                Expanded(child: legendWrap),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
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
                                  onPressed: () => setState(
                                    () => _showMohPanel = !_showMohPanel,
                                  ),
                                  icon: const Icon(
                                    Icons.list_alt,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _showMohPanel
                                        ? 'Hide Cases List'
                                        : 'Show Cases List',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
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
                          ],
                        );
                      }

                      // Wide layout
                      return Row(
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
                          Flexible(child: legendWrap),
                          const Spacer(),
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
                              Icons.list_alt,
                              color: Colors.white70,
                              size: 18,
                            ),
                            label: Text(
                              _showMohPanel
                                  ? 'Hide Cases List'
                                  : 'Show Cases List',
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
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // ===== Map + Cases (read-only) panel =====
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
                                  cameraTargetBounds: CameraTargetBounds(
                                    _lkBounds,
                                  ),
                                  minMaxZoomPreference:
                                      const MinMaxZoomPreference(6, 18),
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

                        // READ-ONLY CASES LIST PANEL
                        if (showPanel) ...[
                          const SizedBox(width: 16),
                          const SizedBox(
                            width: 420,
                            child: _MohReviewPanelReadOnly(),
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

// ===== Read-only Cases Panel =====

class _MohReviewPanelReadOnly extends StatefulWidget {
  const _MohReviewPanelReadOnly();

  @override
  State<_MohReviewPanelReadOnly> createState() =>
      _MohReviewPanelReadOnlyState();
}

class _MohReviewPanelReadOnlyState extends State<_MohReviewPanelReadOnly> {
  String _query = '';

  Query<Map<String, dynamic>> _baseQuery() {
    // NO MOH AREA FILTER – global, newest first
    return FirebaseFirestore.instance
        .collection('dengue_cases')
        .orderBy('date_of_admission', descending: true)
        .limit(100);
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
              Icon(Icons.list_alt, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                'Cases (Read-only)',
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

                    // read-only compact card
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (homeAddr.trim().isNotEmpty) _kv('Home', homeAddr),
                        if (workAddr.trim().isNotEmpty) _kv('Work', workAddr),
                        if (schoolAddr.trim().isNotEmpty)
                          _kv('School', schoolAddr),
                      ],
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

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 2.0),
      child: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
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
