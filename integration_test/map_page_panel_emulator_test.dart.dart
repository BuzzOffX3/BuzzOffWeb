// integration_test/map_page_panel_emulator_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// CHANGE ME:
import 'package:buzzoffwebnew/NDCU/mapnd.dart';
import 'package:buzzoffwebnew/firebase_options.dart'; // from flutterfire configure

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> _initFirebaseToEmulator() async {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    // Point Firestore to emulator (works on web & mobile)
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    // Optional: disable persistence on web
    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: false);
  }

  testWidgets('shows Cases panel items from emulator', (tester) async {
    await _initFirebaseToEmulator();

    // Seed one fake case
    await FirebaseFirestore.instance.collection('dengue_cases').add({
      'patient_name': 'Alice Perera',
      'case_code': 'CASE-001',
      'date_of_admission':
          Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 2))),
      'address': '123 Example Street, Colombo',
    });

    // Wide screen so panel is visible
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Still pass FLUTTER_TEST=true to keep Google Map off, but panel will build (and stream Firestore)
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Panel title
    expect(find.text('Cases (Read-only)'), findsOneWidget);
    // Seeded row content appears
    expect(find.textContaining('Alice Perera'), findsOneWidget);
    expect(find.textContaining('CASE-001'), findsOneWidget);
  });
}
