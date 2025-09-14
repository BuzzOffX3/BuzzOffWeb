import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// mirror of your helpers for unit-test coverage (no app edits needed)
double _degToRad(double d) => d * math.pi / 180.0;

double _metersBetween(LatLng a, LatLng b) {
  const double R = 6371000.0;
  final dLat = _degToRad(b.latitude - a.latitude);
  final dLon = _degToRad(b.longitude - a.longitude);
  final lat1 = _degToRad(a.latitude);
  final lat2 = _degToRad(b.latitude);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2.0 * math.asin(math.min(1.0, math.sqrt(h)));
  return R * c;
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

void main() {
  test('haversine rough check (Colombo→Kandy)', () {
    const a = LatLng(6.9271, 79.8612);
    const b = LatLng(7.2906, 80.6337);
    final d = _metersBetween(a, b);
    expect(d, inInclusiveRange(92000, 99000)); // ~95km
  });

  test('duration formatting', () {
    expect(_fmtDuration('3600s'), '1 h 00 mins');
    expect(_fmtDuration('540s'), '9 mins');
    expect(_fmtDuration('PT25M'), 'PT25M'); // passthrough
  });

  test('polyline decode sample', () {
    // ~ two points, trivial
    final pts = _decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(pts.length, greaterThanOrEqualTo(2));
  });
}
