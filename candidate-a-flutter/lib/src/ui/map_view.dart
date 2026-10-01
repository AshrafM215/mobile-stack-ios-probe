// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The home map through the candidate's MapLibre binding (maplibre_gl), following G1-STYLE-1.0 and the map policy.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app_state.dart';
import '../core/style.dart' as style;

class MapView extends StatefulWidget {
  const MapView({super.key, required this.state});

  final AppState state;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> implements MapPort {
  MapLibreMapController? _c;
  String? _style;
  int _generation = 0;
  int _builtFloor = 1;
  String _builtLang = 'ar';

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.map = this;
    _style = state.initialStyle;
    _builtFloor = state.floor;
    _builtLang = state.lang;
  }

  @override
  void dispose() {
    if (identical(state.map, this)) state.map = null;
    super.dispose();
  }

  CameraPosition _initialCamera() {
    final s = jsonDecode(_style!) as Map<String, Object?>;
    final center = (s['center'] as List).cast<num>();
    return CameraPosition(target: LatLng(center[1].toDouble(), center[0].toDouble()), zoom: (s['zoom'] as num).toDouble());
  }

  @override
  Future<void> setFloor(int floor) async {
    final c = _c;
    final data = state.data;
    if (c == null || data == null || !state.styleLoaded) return;
    for (final e in style.floorFilters(data.styleJson, floor).entries) {
      await c.setFilter(e.key, e.value);
    }
  }

  @override
  Future<void> setLanguage(String lang) async {
    final c = _c;
    if (c == null || !state.styleLoaded) return;
    // maplibre_gl sends every layer property (unset ones as null), so the whole label layout and paint is restated.
    await c.setLayerProperties(
      'room-labels',
      SymbolLayerProperties(
        textField: style.textField(lang),
        textFont: const ['G1Sans'],
        textSize: 12,
        textMaxWidth: 8,
        textColor: '#1b1b1b',
        textHaloColor: '#ffffff',
        textHaloWidth: 1.5,
      ),
    );
  }

  @override
  Future<void> setRoute(Map<String, Object?> featureCollection) async {
    final c = _c;
    if (c == null || !state.styleLoaded) return;
    await c.setGeoJsonSource('route', featureCollection);
  }

  @override
  Future<void> moveCamera(double lon, double lat, double zoom, int durationMs) async {
    final c = _c;
    if (c == null) return;
    await c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lon), zoom), duration: Duration(milliseconds: durationMs));
  }

  @override
  Future<void> reload(String styleJson) async {
    setState(() {
      _style = styleJson;
      _builtFloor = state.floor;
      _builtLang = state.lang;
      _generation++;
      _c = null;
    });
  }

  Future<void> _onStyleLoaded() async {
    // the style was built for the floor and language current at build time; re-apply in case they changed meanwhile
    state.onStyleLoaded();
    if (state.floor != _builtFloor) await setFloor(state.floor);
    if (state.lang != _builtLang) await setLanguage(state.lang);
  }

  @override
  Widget build(BuildContext context) {
    final s = state.s;
    if (_style == null && state.initialStyle != null) {
      // the bundle finished loading after the first frame
      _style = state.initialStyle;
      _builtFloor = state.floor;
      _builtLang = state.lang;
    }
    final st = _style;
    return Semantics(
      identifier: 'home.map',
      container: true,
      label: s.t('home.map.label', {'floor': state.floor}),
      child: st == null
          ? const SizedBox.expand()
          : MapLibreMap(
              key: ValueKey(_generation),
              styleString: st,
              initialCameraPosition: _initialCamera(),
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              myLocationEnabled: false,
              onMapCreated: (c) => _c = c,
              onStyleLoadedCallback: _onStyleLoaded,
            ),
    );
  }
}
