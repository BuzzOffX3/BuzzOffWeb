// Safe stubs so importing code compiles on non-web platforms.

class _DummyEl {
  String? getAttribute(String _) => null;
}

class _DummyDocument {
  _DummyEl? querySelector(String _) => null;
}

class _DummyCoords {
  final num? latitude, longitude;
  const _DummyCoords({this.latitude, this.longitude});
}

class _DummyPosition {
  final _DummyCoords? coords;
  const _DummyPosition({this.coords});
}

class _DummyGeolocation {
  Future<_DummyPosition> getCurrentPosition(
      {bool? enableHighAccuracy, Duration? timeout}) async {
    return const _DummyPosition(coords: null); // no coords in stub
  }
}

class _DummyNavigator {
  final geolocation = _DummyGeolocation();
}

class _DummyWindow {
  final navigator = _DummyNavigator();
}

final document = _DummyDocument();
final window = _DummyWindow();
