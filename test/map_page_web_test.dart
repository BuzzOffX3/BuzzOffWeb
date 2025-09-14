@TestOn('browser') // run this test in Chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Make sure the package name matches your pubspec.yaml `name:`
import 'package:buzzoffwebnew/MOH/map.dart';

void main() {
  testWidgets('MapPage renders in test mode', (tester) async {
    // Width < 1100 so the MOH panel won't build (avoids Firestore streams)
    const app = MediaQuery(
      data: MediaQueryData(size: Size(800, 600)),
      // Pass mohArea:'' to skip user lookup + forceTestMode:true to guarantee placeholder
      child: MaterialApp(home: MapPage(mohArea: '', forceTestMode: true)),
    );

    await tester.pumpWidget(app);

    // Quick sanity check that we are in placeholder path
    expect(find.text('Map placeholder (test mode)'), findsOneWidget,
        reason: 'Map should render placeholder in test mode, not GoogleMap.');

    // Don’t use pumpAndSettle (can hang with streams/animations)
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Smoke checks
    expect(find.textContaining('Dengue Risk Zones'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
