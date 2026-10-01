// G1 candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

const MethodChannel _arChannel = MethodChannel('com.example.g1bench/ar');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProbeApp());
}

/// Text shown for the AR capability result; unsupported devices keep the safe 2D/text fallback.
String describeAr(bool supported) => supported ? 'supported' : 'unsupported (safe 2D/text fallback)';

/// Synthetic log marker for feasibility evidence; no personal or device data.
void mark(String event, [String detail = '']) {
  // ignore: avoid_print
  print('G1_PROBE app=candidate-a-flutter event=$event $detail');
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'G1 Candidate A', home: ProbeHome());
  }
}

class ProbeHome extends StatefulWidget {
  const ProbeHome({super.key});

  @override
  State<ProbeHome> createState() => _ProbeHomeState();
}

class _ProbeHomeState extends State<ProbeHome> {
  String _mapStatus = 'loading';
  String _arStatus = 'not checked';
  String? _style;

  @override
  void initState() {
    super.initState();
    mark('launch');
    rootBundle.loadString('assets/probe-style-v0.json').then((value) {
      if (mounted) setState(() => _style = value);
    });
  }

  Future<void> _checkAr() async {
    final supported = await _arChannel.invokeMethod<bool>('isSupported') ?? false;
    mark('ar_check', 'supported=$supported');
    if (mounted) setState(() => _arStatus = describeAr(supported));
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('G1 Candidate A - synthetic probe', key: Key('title')),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: style == null
                    ? const Center(child: CircularProgressIndicator())
                    : Semantics(
                        label: 'Synthetic map',
                        child: MapLibreMap(
                          styleString: style,
                          initialCameraPosition: const CameraPosition(target: LatLng(0.0003, 0.0007), zoom: 16),
                          myLocationEnabled: false,
                          onStyleLoadedCallback: () {
                            mark('style_loaded');
                            setState(() => _mapStatus = 'style loaded');
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Text('Map: $_mapStatus', key: const Key('mapStatus')),
              ElevatedButton(key: const Key('checkAR'), onPressed: _checkAr, child: const Text('Check AR')),
              Text('AR: $_arStatus', key: const Key('arStatus')),
            ],
          ),
        ),
      ),
    );
  }
}
