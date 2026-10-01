// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Screens S01-S09 of G1-CIC-1.0 plus the anchor-code result and data/trust screens. Every contract id is a Flutter
// semantics identifier (resource-id on Android, accessibilityIdentifier on iOS).
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import 'map_view.dart';

Widget gid(String id, Widget child, {String? label, bool? selected}) =>
    Semantics(identifier: id, container: true, label: label, selected: selected, child: child);

class G1App extends StatelessWidget {
  const G1App({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final s = state.s;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: s.t('app.title'),
          theme: ThemeData(colorSchemeSeed: const Color(0xFF1F4E79), useMaterial3: true, brightness: Brightness.light),
          home: Directionality(
            textDirection: s.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: _Root(state: state),
          ),
        );
      },
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final top = state.top;
    Widget? page;
    switch (top.kind) {
      case ScreenKind.home:
        page = null;
      case ScreenKind.details:
        page = DetailsScreen(state: state, destinationId: top.destination!);
      case ScreenKind.route:
        page = RouteScreen(state: state, destinationId: top.destination!);
      case ScreenKind.fallback:
        page = FallbackScreen(state: state);
      case ScreenKind.qr:
        page = QrScreen(state: state);
      case ScreenKind.settings:
        page = SettingsScreen(state: state);
    }
    return PopScope(
      canPop: state.stack.length == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) state.back();
      },
      child: Stack(
        children: [
          // the home screen (with its map) stays alive under the other screens
          Offstage(offstage: page != null, child: TickerMode(enabled: page == null, child: HomeScreen(state: state))),
          if (page != null) Positioned.fill(child: page),
        ],
      ),
    );
  }
}

AppBar _bar(Strings s, String title, {String? backId, VoidCallback? onBack, List<Widget> actions = const []}) => AppBar(
      title: Text(title),
      leading: backId == null
          ? null
          : gid(backId, IconButton(icon: const BackButtonIcon(), tooltip: s.t('common.back'), onPressed: onBack)),
      actions: actions,
    );

// ---------------------------------------------------------------- S01/S02/S03/S06

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _field = TextEditingController();
  int _epoch = -1;

  AppState get state => widget.state;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = state.s;
    if (_epoch != state.queryEpoch) {
      _epoch = state.queryEpoch;
      _field.text = state.query;
    }
    final enabled = state.trusted && state.index != null;
    // home shown: the first frame callback after the frame that built the enabled home screen (G1-CIC-1.0 frame rule)
    if (enabled) {
      SchedulerBinding.instance.addPostFrameCallback((_) => SchedulerBinding.instance.scheduleFrameCallback((_) => state.homeShown()));
    }
    final results = state.results;
    return Scaffold(
      appBar: AppBar(
        title: gid('home.title', Text(s.t('app.title'))),
        actions: [
          gid('home.lang', TextButton(onPressed: state.toggleLang, child: Text(s.t('lang.toggle'))), label: s.t('lang.toggle.a11y')),
          gid('home.qr', IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: s.t('home.qr.scan'), onPressed: state.scanQr)),
          gid('home.settings', IconButton(icon: const Icon(Icons.verified_user_outlined), tooltip: s.t('home.settings'), onPressed: state.openSettings)),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(s.t('app.subtitle'), style: Theme.of(context).textTheme.bodySmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: gid('home.trust', Text(trustText(s, state.bundleInfo))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: gid(
                      'home.search.field',
                      TextField(
                        controller: _field,
                        enabled: enabled,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(labelText: s.t('home.search.label'), hintText: s.t('home.search.hint')),
                        onChanged: (v) => state.setQuery(v),
                        onSubmitted: (_) => state.submitSearch(),
                      ),
                    ),
                  ),
                  if (state.query.isNotEmpty)
                    gid('home.search.clear',
                        IconButton(icon: const Icon(Icons.clear), tooltip: s.t('home.search.clear'), onPressed: state.clearSearch)),
                  gid('home.search.submit',
                      FilledButton(onPressed: enabled ? state.submitSearch : null, child: Text(s.t('home.search.submit')))),
                ],
              ),
            ),
            Flexible(
              flex: 2,
              child: results == null
                  ? Padding(padding: const EdgeInsets.all(16), child: gid('home.empty', Text(s.t('home.empty'))))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: gid('home.results.status', Text(_resultStatus(s, results.outcome, results.ids.length))),
                        ),
                        Expanded(
                          child: gid(
                            'home.results.list',
                            ListView(
                              children: [
                                for (final id in results.ids)
                                  gid(
                                    'home.result.$id',
                                    ListTile(
                                      title: Text(s.t('home.result.item', {
                                        'code': state.data!.byId[id]!.code,
                                        'name': state.data!.byId[id]!.name(s.lang),
                                      })),
                                      subtitle: Text(s.t('common.building_floor', {
                                        'building': state.data!.byId[id]!.building,
                                        'floor': state.data!.byId[id]!.floor,
                                      })),
                                      onTap: () => state.openDetails(id),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(s.t('home.floor.label')),
                  for (final f in const [1, 2, 3])
                    gid(
                      'home.floor.$f',
                      ChoiceChip(
                        label: Text(s.t('home.floor.option', {'floor': f})),
                        selected: state.floor == f,
                        onSelected: (_) => state.setFloor(f),
                      ),
                      label: state.floor == f ? s.t('home.floor.selected', {'floor': f}) : s.t('home.floor.option', {'floor': f}),
                      selected: state.floor == f,
                    ),
                ],
              ),
            ),
            Expanded(flex: 3, child: MapView(state: state)),
          ],
        ),
      ),
    );
  }

  String _resultStatus(Strings s, String outcome, int count) {
    switch (outcome) {
      case 'UNIQUE_MATCH':
        return s.t('home.results.unique');
      case 'AMBIGUOUS':
        return s.t('home.results.ambiguous', {'count': count});
      default:
        return s.t('home.results.none', {'query': state.query});
    }
  }
}

// ---------------------------------------------------------------- S04/S05

class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key, required this.state, required this.destinationId});

  final AppState state;
  final String destinationId;

  @override
  Widget build(BuildContext context) {
    final s = state.s;
    final d = state.data?.byId[destinationId];
    if (d == null) return Scaffold(appBar: _bar(s, s.t('details.title'), backId: 'details.back', onBack: state.back));
    final schedule = state.data!.scheduleFor(d.id);
    Widget row(String labelKey, String id, String value) => ListTile(
          title: Text(s.t(labelKey)),
          subtitle: gid(id, Text(value)),
        );
    return Scaffold(
      appBar: _bar(s, s.t('details.title'), backId: 'details.back', onBack: state.back),
      body: SafeArea(
        child: ListView(
          children: [
            row('details.code', 'details.code', d.code),
            row('details.name', 'details.name', d.name(s.lang)),
            row('details.building', 'details.building', d.building),
            row('details.floor', 'details.floor', '${d.floor}'),
            row('details.status', 'details.status', s.t(d.reachable ? 'details.status.reachable' : 'details.status.unreachable')),
            ListTile(title: Text(s.t('details.schedule'), style: Theme.of(context).textTheme.titleMedium)),
            if (schedule.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: gid('details.schedule.none', Text(s.t('details.schedule.none'))),
              )
            else
              gid(
                'details.schedule.list',
                Column(
                  children: [
                    for (final e in schedule)
                      gid('details.schedule.item.${e.code}', ListTile(dense: true, title: Text(scheduleItem(s, e)))),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  gid('details.route', FilledButton(onPressed: () => state.openRoute(d.id), child: Text(s.t('details.route')))),
                  gid('details.showmap', OutlinedButton(onPressed: () => state.showOnMap(d.id), child: Text(s.t('details.showmap')))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- S07

class RouteScreen extends StatelessWidget {
  const RouteScreen({super.key, required this.state, required this.destinationId});

  final AppState state;
  final String destinationId;

  @override
  Widget build(BuildContext context) {
    final s = state.s;
    final d = state.data?.byId[destinationId];
    final r = state.route;
    final entrances = state.data?.entrances ?? const <String>[];
    return Scaffold(
      appBar: _bar(s, s.t('route.title'), backId: 'route.back', onBack: state.back),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(title: Text(s.t('route.from'), style: Theme.of(context).textTheme.titleMedium)),
            for (final e in entrances)
              gid(
                'route.from.$e',
                ListTile(
                  leading: Icon(state.origin == e ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  title: Text(s.t('route.from.option', {'entrance': e})),
                  selected: state.origin == e,
                  onTap: () => state.setOrigin(e),
                ),
                selected: state.origin == e,
              ),
            ListTile(
              title: Text(s.t('route.to')),
              subtitle: gid('route.to', Text(d == null ? destinationId : s.t('home.result.item', {'code': d.code, 'name': d.name(s.lang)}))),
            ),
            gid(
              'route.stepfree',
              SwitchListTile(value: state.stepFree, onChanged: state.setStepFree, title: Text(s.t('route.stepfree'))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: gid('route.compute', FilledButton(onPressed: state.computeRoute, child: Text(s.t('route.compute')))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: gid('route.trust', Text(trustText(s, state.bundleInfo))),
            ),
            if (r != null && r.outcome == 'PATH') ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: gid('route.summary', Text(summaryText(s, state.summary!), style: Theme.of(context).textTheme.titleMedium)),
              ),
              ListTile(title: Text(s.t('route.steps'))),
              gid(
                'route.steps',
                Column(
                  children: [
                    for (var i = 0; i < state.steps.length; i++)
                      gid('route.step.$i', ListTile(dense: true, leading: Text('${i + 1}'), title: Text(stepText(s, state.steps[i])))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: gid('route.ar', OutlinedButton(onPressed: () => state.openAr(), child: Text(s.t('route.ar')))),
              ),
            ] else if (r != null)
              Padding(padding: const EdgeInsets.all(16), child: gid('route.reject', Text(rejectText(s, r.outcome)))),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- S09

class FallbackScreen extends StatelessWidget {
  const FallbackScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.s;
    return Scaffold(
      appBar: AppBar(title: gid('fallback.title', Text(s.t('fallback.title'))), automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: gid('fallback.message', Text(s.t('ar.unsupported')))),
            gid(
              'fallback.steps',
              Column(
                children: [
                  for (var i = 0; i < state.steps.length; i++)
                    ListTile(dense: true, leading: Text('${i + 1}'), title: Text(stepText(s, state.steps[i]))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: gid('fallback.back', FilledButton(onPressed: state.back, child: Text(s.t('fallback.back')))),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- anchor code result

class QrScreen extends StatelessWidget {
  const QrScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('qr.title')), automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: gid('qr.result', Text(qrText(s, state.qrOutcome ?? const {})))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: gid('qr.close', FilledButton(onPressed: state.back, child: Text(s.t('common.close')))),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- data and trust

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.s;
    final info = state.bundleInfo;
    final valid = info?['state'] == 'VALID';
    String? update;
    switch (state.updateStatus) {
      case 'pending':
        update = s.t('settings.update.pending', {'percent': state.updatePercent});
      case 'slow':
        update = s.t('settings.update.slow');
      case 'none':
        update = s.t('settings.update.none');
      case 'failed':
        update = s.t('settings.update.failed');
    }
    return Scaffold(
      appBar: _bar(s, s.t('settings.title'), backId: 'settings.back', onBack: state.back),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(title: Text(s.t('settings.version')), subtitle: gid('settings.version', Text('${info?['version'] ?? '-'}'))),
            if (valid)
              ListTile(
                title: gid(
                  'settings.validity',
                  Text(s.t('settings.validity', {
                    'from': isoDate(info!['valid_from_ms'] as int),
                    'until': isoDate(info['valid_until_ms'] as int),
                  })),
                ),
              ),
            ListTile(title: gid('settings.status', Text(trustText(s, info)))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: gid('settings.update', FilledButton(onPressed: () => state.update(), child: Text(s.t('settings.update')))),
            ),
            if (update != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: gid('settings.update.status', Text(update))),
            if (state.lastResult != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: gid('settings.result', Text(s.has('result.${state.lastResult}') ? s.t('result.${state.lastResult}') : s.t('error.generic'))),
              ),
          ],
        ),
      ),
    );
  }
}
