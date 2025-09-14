// integration_test/map_page_web_test.dart
import 'dart:html' as html; // web-only

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:buzzoffwebnew/MOH/map.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Inject a fake Google Maps key so _apiKey isn't empty during the test
    // Good for UI-only tests (prevents real HTTP):
    final meta = html.MetaElement()
      ..name = 'gmaps-key'
      ..content = ''; // keep empty to skip HTTP in _geocodeAddress/_routes
    html.document.head!.append(meta);
  });

  testWidgets('MapPage builds and shows header/controls (web)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    // allow initState -> _boot() to start; UI should still build even if data fails
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Header
    expect(find.textContaining('Dengue Risk Zones'), findsOneWidget);

    // Directions panel + fields/buttons
    expect(find.text('Directions'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'From (address / My location / lat,lng)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'To (address or lat,lng)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ElevatedButton, 'Route'), findsOneWidget);
  });
}
