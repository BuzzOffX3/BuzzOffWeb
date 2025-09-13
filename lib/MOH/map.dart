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
import 'dart:html' as dom show document, window; // web: meta key + geolocation

import 'analytics.dart';
import 'complaints.dart';

/// ----- MODEL -----
class _CasePoint {
  const _CasePoint({
    required this.id,
    required this.pos,
    required this.ageDays,
    required this.locationType,
    required this.locationAddress,
    required this.reviewStatus,
    required this.reviewAt,
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

/// ----- STATE -----
class _MapPageState extends State<MapPage> {
  // Theme
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

  // Map
  final Completer<GoogleMapController> _mapCtl = Completer();
  final Set<Circle> _circles = {};
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng _mapCenter = const LatLng(6.9271, 79.8612);
  double _mapZoom = 11;

  // Sri Lanka bounds
  static final LatLngBounds _lkBounds = LatLngBounds(
    southwest: const LatLng(5.7, 79.3),
    northeast: const LatLng(10.1, 82.1),
  );

  bool _loading = true;
  String _statusMsg = 'Loading…';
  String? _currentMohArea;

  // UI panel toggle
  bool _showMohPanel = true;

  // Caches
  final Map<String, BitmapDescriptor> _markerIconCache = {};
  final Map<String, LatLng> _geoCache = {};

  // cluster radius
  static const double clusterRadiusM = 300.0;

  // Directions UI/state
  final TextEditingController _fromCtl = TextEditingController();
  final TextEditingController _toCtl = TextEditingController();
  PolylineId get _routeId => const PolylineId('route_line');
  String? _routeSummary;

  // Browser geolocation
  LatLng? _myLocation;
  bool _gettingMyLoc = false;

  // Browser key from <meta name="gmaps-key" content="...">
  String get _apiKey {
    final el = dom.document.querySelector('meta[name="gmaps-key"]');
    return el?.getAttribute('content') ?? '';
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _fromCtl.dispose();
    _toCtl.dispose();
    super.dispose();
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

  /// ---------- Geocoding (enabled for ALL platforms via REST) ----------
  Future<LatLng?> _geocodeAddress(String address) async {
    final key = address.trim().toLowerCase();
    if (_geoCache.containsKey(key)) return _geoCache[key];
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

  // Haversine
  double _metersBetween(LatLng a, LatLng b) {
    const double R = 6371000.0;
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

  /// ---------- Load data and draw circles/markers ----------
  Future<void> _loadCasesAndDraw() async {
    setState(() {
      _loading = true;
      _statusMsg = 'Loading MOH actions…';
      _circles.clear();
      _markers.clear();
      _markerIconCache.clear();
    });

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
        'moh_actions',
      );

      if (_currentMohArea != null && _currentMohArea!.isNotEmpty) {
        q = q.where('patient_moh_area', isEqualTo: _currentMohArea);
      }

      final since = DateTime.now().subtract(const Duration(days: 60));
      q = q.where(
        'created_at',
        isGreaterThanOrEqualTo: Timestamp.fromDate(since),
      );

      final qs = await q.get();
      if (qs.docs.isEmpty) {
        setState(() {
          _loading = false;
          _statusMsg = 'No actions for ${_currentMohArea ?? "all areas"}';
        });
        return;
      }

      // latest per address
      final latestByAddr =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      for (final d in qs.docs) {
        final m = d.data();
        final addr = (m['location_address'] ?? '').toString().trim();
        if (addr.isEmpty) continue;

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

      // Build points
      final points = <_CasePoint>[];

      for (final entry in latestByAddr.entries) {
        final m = entry.value.data();
        final addr = (m['location_address'] ?? '').toString();
        final locType = (m['location_type'] ?? 'home').toString();
        final action = (m['action'] ?? 'no_signs').toString().toLowerCase();

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

      // clusters
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

      // draw
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
    return const _ZoneStyle(
      innerFill: Color(0x00000000),
      innerStroke: Color(0x00000000),
      outerFill: Color(0x00000000),
      outerStroke: Color(0x00000000),
      pinColor: Color(0x00000000),
      visible: false,
    );
  }

  /// ----- Custom pins -----
  Future<BitmapDescriptor> _mosquitoPinWithDays({
    required int days,
    required Color baseColor,
  }) async {
    const double s = 0.35;
    final key = 'mosq2x_s${s}_$days${baseColor.value.toRadixString(16)}';
    final cached = _markerIconCache[key];
    if (cached != null) return cached;

    const int baseLogical = 130;
    const double scale = 2.0;
    final int size = (baseLogical * s * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = Paint()..color = baseColor;

    final cx = size / 2.0;
    final cy = size / 2.0 - 16 * s * scale / 2.0;

    canvas.drawCircle(Offset(cx, cy), 22 * s * scale, paint);

    final tail = Path()
      ..moveTo(cx, size - 24 * s * scale / 2.0)
      ..lineTo(cx - 11 * s * scale, size / 2.0 + 12 * s * scale / 2.0)
      ..lineTo(cx + 11 * s * scale, size / 2.0 + 12 * s * scale / 2.0)
      ..close();
    canvas.drawPath(tail, paint);

    final inner = Paint()..color = Colors.black.withOpacity(0.75);
    canvas.drawCircle(Offset(cx, cy), 16 * s * scale, inner);

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
    const double s = 0.35;
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

  // bounds helper
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

  /// ---------- Routes API v2 helpers ----------
  Future<LatLng?> _getBrowserLocation() async {
    if (!kIsWeb) return null;
    try {
      final pos = await dom.window.navigator.geolocation.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 12),
      );
      final lat = pos.coords?.latitude;
      final lng = pos.coords?.longitude;
      if (lat == null || lng == null) return null;
      return LatLng(lat.toDouble(), lng.toDouble());
    } catch (e) {
      print('Geolocation failed: $e');
      return null;
    }
  }

  Future<void> _useMyLocationAsFrom() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Browser location is only available on web'),
        ),
      );
      return;
    }
    setState(() => _gettingMyLoc = true);
    final loc = await _getBrowserLocation();
    setState(() => _gettingMyLoc = false);
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t get your location (permission/timeout)'),
        ),
      );
      return;
    }
    _myLocation = loc;
    _fromCtl.text = 'My location';
    if (_toCtl.text.trim().isNotEmpty) {
      _drawRouteFromTo(
        fromText: _fromCtl.text.trim(),
        toText: _toCtl.text.trim(),
      );
    }
  }

  Future<LatLng?> _resolveInputToLatLng(String input) async {
    final t = input.trim();
    if (t.isEmpty) return null;

    if (t.toLowerCase().contains('my location')) {
      if (_myLocation != null) return _myLocation;
      if (kIsWeb) {
        _myLocation = await _getBrowserLocation();
        return _myLocation;
      }
      return null;
    }

    final m = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(t);
    if (m != null) {
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    return await _geocodeAddress(t);
  }

  String _fmtDuration(String? s) {
    if (s == null) return '';
    final m = RegExp(r'^(\d+)s$').firstMatch(s);
    if (m == null) return s;
    final sec = int.parse(m.group(1)!);
    final h = sec ~/ 3600;
    final min = (sec % 3600) ~/ 60;
    if (h > 0) return '$h h ${min.toString().padLeft(2, '0')} mins';
    return '$min mins';
  }

  // Polyline decoder (fallback if API returns encoded)
  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  Future<Map<String, dynamic>> _computeRouteViaRoutesApi(
    LatLng origin,
    LatLng dest,
  ) async {
    final uri = Uri.parse(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
    );

    final body = jsonEncode({
      "origin": {
        "location": {
          "latLng": {
            "latitude": origin.latitude,
            "longitude": origin.longitude,
          },
        },
      },
      "destination": {
        "location": {
          "latLng": {"latitude": dest.latitude, "longitude": dest.longitude},
        },
      },
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": false,

      // ✅ correct enum values
      "polylineEncoding": "GEO_JSON_LINESTRING",
      "polylineQuality": "HIGH_QUALITY",
    });

    final res = await http.post(
      uri,
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": _apiKey,
        "X-Goog-FieldMask":
            "routes.distanceMeters,routes.duration,"
            "routes.polyline.geoJsonLinestring,"
            "routes.polyline.encodedPolyline",
      },
      body: body,
    );

    if (res.statusCode != 200) {
      throw 'Routes API ${res.statusCode}: ${res.body}';
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _clearRoute() async {
    setState(() {
      _polylines.clear();
      _routeSummary = null;
    });
  }

  Future<void> _drawRouteFromTo({
    required String fromText,
    required String toText,
  }) async {
    if (_apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Missing Google API key')));
      }
      return;
    }

    setState(() => _routeSummary = 'Finding route…');

    final from = await _resolveInputToLatLng(fromText);
    final to = await _resolveInputToLatLng(toText);

    if (from == null || to == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t resolve origin or destination'),
          ),
        );
      }
      setState(() => _routeSummary = null);
      return;
    }

    try {
      final j = await _computeRouteViaRoutesApi(from, to);

      final routes = (j['routes'] as List?) ?? const [];
      if (routes.isEmpty) {
        setState(() => _routeSummary = 'No route found');
        return;
      }
      final r0 = routes.first as Map;

      final distanceMeters = (r0['distanceMeters'] as num?)?.toDouble();
      final duration = _fmtDuration(r0['duration']?.toString());
      final parts = <String>[];
      if (distanceMeters != null) {
        final km = distanceMeters / 1000.0;
        parts.add('${km.toStringAsFixed(km >= 10 ? 0 : 1)} km');
      }
      if (duration.isNotEmpty) parts.add(duration);
      final summary = parts.join(' · ');

      // Build points from either GeoJSON or an encoded polyline
      final poly = (r0['polyline'] as Map?) ?? const {};
      List<LatLng> points = [];

      final gj = poly['geoJsonLinestring'] as Map?;
      final coords = gj?['coordinates'] as List?;
      if (coords != null && coords.isNotEmpty) {
        for (final c in coords) {
          if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
            final lng = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            points.add(LatLng(lat, lng));
          }
        }
      } else {
        final enc = poly['encodedPolyline'];
        if (enc is String && enc.isNotEmpty) {
          points = _decodePolyline(enc);
        }
      }

      if (points.isEmpty) {
        setState(() => _routeSummary = 'No path in route');
        return;
      }

      final line = Polyline(
        polylineId: _routeId,
        color: Colors.lightBlueAccent,
        width: 6,
        points: points,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
        geodesic: true,
      );

      setState(() {
        _polylines
          ..clear()
          ..add(line);
        _routeSummary = summary.isEmpty ? 'Route ready' : summary;
      });

      // Fit camera to route
      LatLngBounds? bounds;
      for (final p in points) {
        bounds = _extend(bounds, p);
      }
      if (bounds != null) {
        final c = await _mapCtl.future;
        await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
      }
    } catch (e) {
      setState(() => _routeSummary = 'Directions error: $e');
    }
  }

  /// ----- Firestore writes & logging -----
  Future<void> _setReviewStatus({
    required String caseId,
    required String? status,
    required String locationType,
    required String locationAddress,
  }) async {
    try {
      final caseRef = FirebaseFirestore.instance
          .collection('dengue_cases')
          .doc(caseId);

      Map<String, dynamic>? caseData;
      final snap = await caseRef.get();
      if (snap.exists) caseData = snap.data();

      if (status == null) {
        await caseRef.set({
          'review_status': FieldValue.delete(),
          'review_updated_at': FieldValue.delete(),
        }, SetOptions(merge: true));
      } else if (status == 'no_signs' || status == 'cleaned') {
        await caseRef.set({
          'review_status': status,
          'review_updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

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
          'action': status,
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

      await _loadCasesAndDraw();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == null
                  ? 'Status cleared'
                  : (status == 'new_case'
                        ? 'Logged Possible Site'
                        : 'Marked $locationType: $status'),
            ),
          ),
        );
      }
    } on FirebaseException catch (e) {
      String msg = 'Failed: ${e.code}';
      if (e.code == 'permission-denied') {
        msg =
            'Permission denied. Only hospitals can log "Possible Site" (new_case).';
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  /// ----- UI -----
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showPanel = _showMohPanel && width >= 1100;

    return Scaffold(
      backgroundColor: bg,
      body: Row(
        children: [
          // Sidebar
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

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  LayoutBuilder(
                    builder: (ctx, cons) {
                      final isNarrow = cons.maxWidth < 900;

                      Widget legends() => Wrap(
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
                                Expanded(child: legends()),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
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
                                  onPressed: () => setState(
                                    () => _showMohPanel = !_showMohPanel,
                                  ),
                                  icon: const Icon(
                                    Icons.admin_panel_settings,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _showMohPanel
                                        ? 'Hide MOH Review'
                                        : 'MOH Review',
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
                          Flexible(child: legends()),
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
                      );
                    },
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
                                  polylines: _polylines,
                                  onMapCreated: (c) => _mapCtl.complete(c),
                                ),

                                // status chip
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

                                // Directions panel
                                Positioned(
                                  top: 54,
                                  right: 10,
                                  child: Container(
                                    width: 320,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: panelAlt,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: border),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Directions',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _fromCtl,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          decoration: InputDecoration(
                                            hintText:
                                                'From (address / My location / lat,lng)',
                                            hintStyle: const TextStyle(
                                              color: Colors.white54,
                                            ),
                                            isDense: true,
                                            filled: true,
                                            fillColor: Colors.black26,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: BorderSide(
                                                color: border,
                                              ),
                                            ),
                                            prefixIcon: const Icon(
                                              Icons.my_location,
                                              color: Colors.white54,
                                              size: 18,
                                            ),
                                            suffixIcon: IconButton(
                                              tooltip: 'Use my location',
                                              icon: _gettingMyLoc
                                                  ? const SizedBox(
                                                      height: 18,
                                                      width: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color:
                                                                Colors.white70,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.gps_fixed,
                                                      color: Colors.white70,
                                                      size: 18,
                                                    ),
                                              onPressed: _gettingMyLoc
                                                  ? null
                                                  : _useMyLocationAsFrom,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _toCtl,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'To (address or lat,lng)',
                                            hintStyle: const TextStyle(
                                              color: Colors.white54,
                                            ),
                                            isDense: true,
                                            filled: true,
                                            fillColor: Colors.black26,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: BorderSide(
                                                color: border,
                                              ),
                                            ),
                                            prefixIcon: const Icon(
                                              Icons.place,
                                              color: Colors.white54,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            ElevatedButton.icon(
                                              onPressed: () {
                                                final from = _fromCtl.text
                                                    .trim();
                                                final to = _toCtl.text.trim();
                                                if (from.isNotEmpty &&
                                                    to.isNotEmpty) {
                                                  _drawRouteFromTo(
                                                    fromText: from,
                                                    toText: to,
                                                  );
                                                } else {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Enter both From and To',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.route,
                                                size: 18,
                                                color: Colors.black,
                                              ),
                                              label: const Text(
                                                'Route',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.lightBlueAccent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            OutlinedButton.icon(
                                              onPressed: _clearRoute,
                                              icon: const Icon(
                                                Icons.clear,
                                                size: 18,
                                                color: Colors.white70,
                                              ),
                                              label: const Text(
                                                'Clear',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(color: border),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                          ],
                                        ),
                                        if (_routeSummary != null) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            _routeSummary!,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // MOH review panel
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
                              onRouteTo: (address) {
                                _toCtl.text = address;
                                if (_fromCtl.text.isEmpty) {
                                  _fromCtl.text = 'My location';
                                  if (_myLocation == null)
                                    _useMyLocationAsFrom();
                                }
                                _drawRouteFromTo(
                                  fromText: _fromCtl.text.trim(),
                                  toText: _toCtl.text.trim(),
                                );
                              },
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

/// ===== MOH REVIEW PANEL =====

class _MohActionArgs {
  _MohActionArgs({
    required this.caseId,
    required this.status,
    required this.locationType,
    required this.locationAddress,
  });
  final String caseId;
  final String? status; // 'new_case' | 'no_signs' | 'cleaned' | null
  final String locationType; // home|work|school
  final String locationAddress;
}

class _MohReviewPanel extends StatefulWidget {
  const _MohReviewPanel({
    required this.mohArea,
    required this.onAction,
    required this.onRouteTo,
  });

  final String? mohArea;
  final Future<void> Function(_MohActionArgs args) onAction;
  final void Function(String address) onRouteTo;

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
    const Color red = _MapPageState.red;

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
                    .toList();

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
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
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
                                    IconButton(
                                      tooltip: 'Route to here',
                                      icon: const Icon(
                                        Icons.directions,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () {
                                        widget.onRouteTo(
                                          locations[selectedType]!,
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Routing to selected address…',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _actionBtn(
                                  label: 'Possible Site',
                                  icon: Icons.place,
                                  color: red,
                                  onTap: () => widget.onAction(
                                    _MohActionArgs(
                                      caseId: d.id,
                                      status: 'new_case',
                                      locationType: selectedType,
                                      locationAddress:
                                          locations[selectedType] ?? '',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
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

/// ----- Small reused bits -----
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
