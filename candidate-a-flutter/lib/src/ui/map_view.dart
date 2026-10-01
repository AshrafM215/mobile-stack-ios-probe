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
  // the label language the binding acknowledged (style built with it, or setLayerProperties completed)
  String? _appliedLang;
  // the empty style is shown (bundle.remove): its load is not the bundle style load
  bool _empty = false;

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
    _appliedLang = lang;
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
      _appliedLang = null;
      _empty = false;
      _generation++;
      _c = null;
    });
  }

  @override
  Future<void> clear() async {
    final current = _style;
    final center = current == null ? const <num>[0, 0] : ((jsonDecode(current) as Map<String, Object?>)['center'] as List).cast<num>();
    final zoom = current == null ? 1 : (jsonDecode(current) as Map<String, Object?>)['zoom'] as num;
    setState(() {
      _style = style.emptyStyle(center, zoom);
      _appliedLang = null;
      _empty = true;
      _generation++;
      _c = null;
    });
  }

  @override
  Future<Map<String, Object?>> inspect() async {
    final c = _c;
    final box = context.findRenderObject() as RenderBox?;
    if (c == null || box == null || !box.hasSize) return {'available': false};
    // queryRenderedFeaturesInRect takes view pixels on Android
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final rect = Rect.fromLTWH(0, 0, box.size.width * dpr, box.size.height * dpr);
    final out = <String, Object?>{'available': true, 'style_loaded': !_empty && state.styleLoaded};
    final cam = await c.queryCameraPosition();
    out['camera'] = cam == null
        ? null
        : {'lon': cam.target.longitude, 'lat': cam.target.latitude, 'zoom': cam.zoom, 'bearing': cam.bearing, 'pitch': cam.tilt};
    // gesture policy as configured on the binding's map widget (the binding has no getter)
    out['gestures'] = {'pan': true, 'zoom': true, 'rotate': false, 'tilt': false};
    out['gestures_source'] = 'configured';
    if (_empty || !state.styleLoaded) return out;
    out['floor'] = style.floorOfFilter(await c.getFilter('rooms'));
    out['floor_source'] = 'live';
    final lang = _appliedLang;
    final labelField = lang == null ? null : (lang == 'ar' ? 'name_ar' : 'name_en');
    out['label_field'] = labelField;
    out['label_field_source'] = 'acknowledged';
    final rendered = <Map<String, Object?>>[];
    for (final layer in style.inspectLayers) {
      final seen = <String>{};
      for (final f in await c.queryRenderedFeaturesInRect(rect, [layer], null)) {
        final p = ((f as Map)['properties'] as Map?) ?? const {};
        final id = p['id'];
        if (id is! String || !seen.add(id)) continue; // a feature split across tiles is reported once
        rendered.add({
          'layer': layer,
          'id': id,
          'kind': p['kind'],
          'building': p['building'],
          'floor': (p['floor'] as num?)?.toInt(),
          'label': layer == 'room-labels' && labelField != null ? p[labelField] : null,
        });
      }
    }
    out['rendered'] = rendered;
    return out;
  }

  Future<void> _onStyleLoaded() async {
    if (_empty) return; // the empty style of the no-bundle state
    _appliedLang = _builtLang;
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
