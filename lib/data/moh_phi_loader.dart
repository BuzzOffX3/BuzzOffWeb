import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';

Future<Map<String, List<String>>> loadMohPhi() async {
  // 1) Try Firestore (ref/moh_phi)
  try {
    final snap = await FirebaseFirestore.instance
        .collection('ref')
        .doc('moh_phi')
        .get();
    final data = (snap.data() ?? {}) as Map<String, dynamic>;
    if (data.isNotEmpty) {
      return data.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    }
  } catch (_) {
    // ignore – we’ll fall back to asset
  }

  // 2) Fallback to asset
  final jsonStr = await rootBundle.loadString('images/phi_area.json');
  final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
  return obj.map((k, v) => MapEntry(k, List<String>.from(v as List)));
}
