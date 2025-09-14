@Tags(['web'])
@TestOn('browser')

import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzzoffwebnew/NDCU/mapnd.dart'; // <-- CHANGE if different

void main() {
  setUpAll(() {
    // Inject a fake Google Maps key so _apiKey isn’t empty in tests
    html.document
        .querySelectorAll('meta[name="gmaps-key"]')
        .forEach((e) => e.remove());

    final meta = html.MetaElement()
      ..name = 'gmaps-key'
      ..content = 'fake_key_for_tests';
    html.document.head!.append(meta);
  });

  testWidgets('MapPage renders header + status in test mode', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapPage()));

    // Let first frame build (we don’t call pumpAndSettle to avoid waiting)
    await tester.pump(const Duration(milliseconds: 100));

    // Header present
    expect(find.text('Dengue Risk Zones'), findsOneWidget);

    // We short-circuit loader in kTestMode -> status shows "Test mode"
    expect(find.textContaining('Test mode'), findsOneWidget);

    // In test mode, we render a placeholder instead of GoogleMap
    expect(find.byKey(const Key('map-placeholder')), findsOneWidget);

    // Legend chips are there
    expect(find.textContaining('New case'), findsOneWidget);
    expect(find.textContaining('No-signs'), findsOneWidget);
    expect(find.textContaining('Green'), findsOneWidget);
  });
}
