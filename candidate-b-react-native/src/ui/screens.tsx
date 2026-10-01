// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Screens S01-S09 of G1-CIC-1.0 plus the anchor-code result and data/trust screens. Every contract id is a testID
// (resource-id on Android, accessibilityIdentifier on iOS).
import React, { createContext, useContext, useLayoutEffect } from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, Switch, Text, TextInput, View, type StyleProp, type TextStyle } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { AppState } from '../state';
import { isoDate, qrText, rejectText, scheduleItem, stepText, summaryText, trustText } from '../core/format';
import type { Strings } from '../core/strings';
import { MapPanel } from './MapPanel';

const Rtl = createContext(false);

const C = {
  primary: '#1F4E79',
  onPrimary: '#ffffff',
  text: '#1b1b1b',
  muted: '#4a4f55',
  border: '#c4c9cf',
  surface: '#ffffff',
  selected: '#dce8f5',
};

function T({ id, style, children, label }: { id?: string; style?: StyleProp<TextStyle>; children: React.ReactNode; label?: string }) {
  const rtl = useContext(Rtl);
  return (
    <Text
      testID={id}
      accessibilityLabel={label}
      style={[ui.text, { textAlign: rtl ? 'right' : 'left', writingDirection: rtl ? 'rtl' : 'ltr' }, style]}
    >
      {children}
    </Text>
  );
}

function Btn(props: {
  id: string;
  label: string;
  onPress: () => void;
  disabled?: boolean;
  a11yLabel?: string;
  selected?: boolean;
  outline?: boolean;
  role?: 'button' | 'radio';
}) {
  const { id, label, onPress, disabled, a11yLabel, selected, outline, role } = props;
  const filled = !outline && !selected;
  return (
    <Pressable
      testID={id}
      accessibilityRole={role ?? 'button'}
      accessibilityLabel={a11yLabel ?? label}
      accessibilityState={role === 'radio' ? { checked: !!selected, disabled: !!disabled } : { selected: !!selected, disabled: !!disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        ui.btn,
        filled ? ui.btnFilled : ui.btnOutline,
        selected && ui.btnSelected,
        disabled && ui.btnDisabled,
        pressed && ui.pressed,
      ]}
    >
      <Text style={[ui.btnText, filled ? ui.btnTextFilled : ui.btnTextOutline]}>{label}</Text>
    </Pressable>
  );
}

function Header({ s, title, backId, onBack, titleId }: { s: Strings; title: string; backId?: string; onBack?: () => void; titleId?: string }) {
  return (
    <View style={ui.header}>
      {backId && onBack ? <Btn id={backId} label={s.t('common.back')} onPress={onBack} outline /> : null}
      <T id={titleId} style={ui.headerTitle}>
        {title}
      </T>
    </View>
  );
}

// ---------------------------------------------------------------- S01/S02/S03/S06

function resultStatus(s: Strings, outcome: string, count: number, query: string): string {
  switch (outcome) {
    case 'UNIQUE_MATCH':
      return s.t('home.results.unique');
    case 'AMBIGUOUS':
      return s.t('home.results.ambiguous', { count });
    default:
      return s.t('home.results.none', { query });
  }
}

function HomeScreen({ state, covered }: { state: AppState; covered: boolean }) {
  const s = state.s;
  const enabled = state.trusted && state.index !== null;
  // home shown: the first frame callback after the frame that mounted the enabled home screen (G1-CIC-1.0 frame rule)
  useLayoutEffect(() => {
    if (enabled) requestAnimationFrame(() => requestAnimationFrame(() => state.homeShown()));
  }, [enabled, state]);
  const results = state.results;
  const data = state.data;
  return (
    <View
      style={ui.fill}
      importantForAccessibility={covered ? 'no-hide-descendants' : 'auto'}
      accessibilityElementsHidden={covered}
      pointerEvents={covered ? 'none' : 'auto'}
    >
      <View style={ui.header}>
        <T id="home.title" style={ui.headerTitle}>
          {s.t('app.title')}
        </T>
        <Btn id="home.lang" label={s.t('lang.toggle')} a11yLabel={s.t('lang.toggle.a11y')} onPress={state.toggleLang} outline />
        <Btn id="home.qr" label={s.t('home.qr.scan')} onPress={() => void state.scanQr()} outline />
        <Btn id="home.settings" label={s.t('home.settings')} onPress={state.openSettings} outline />
      </View>
      <T style={ui.small}>{s.t('app.subtitle')}</T>
      <T id="home.trust" style={ui.pad}>
        {trustText(s, state.bundleInfo)}
      </T>
      <View style={ui.row}>
        <TextInput
          testID="home.search.field"
          accessibilityLabel={s.t('home.search.label')}
          placeholder={s.t('home.search.hint')}
          placeholderTextColor={C.muted}
          editable={enabled}
          value={state.query}
          onChangeText={(v) => state.setQuery(v)}
          onSubmitEditing={() => state.submitSearch()}
          returnKeyType="search"
          autoCorrect={false}
          autoCapitalize="none"
          style={[ui.input, { textAlign: state.s.rtl ? 'right' : 'left' }]}
        />
        {state.query.length > 0 ? <Btn id="home.search.clear" label={s.t('home.search.clear')} onPress={state.clearSearch} outline /> : null}
        <Btn id="home.search.submit" label={s.t('home.search.submit')} onPress={() => state.submitSearch()} disabled={!enabled} />
      </View>
      <View style={ui.results}>
        {results === null ? (
          <T id="home.empty" style={ui.pad}>
            {s.t('home.empty')}
          </T>
        ) : (
          <>
            <T id="home.results.status" style={ui.pad}>
              {resultStatus(s, results.outcome, results.ids.length, state.query)}
            </T>
            <FlatList
              testID="home.results.list"
              data={results.ids}
              keyExtractor={(id) => id}
              renderItem={({ item: id }) => {
                const d = data?.byId.get(id);
                if (!d) return null;
                return (
                  <Pressable
                    testID={`home.result.${id}`}
                    accessibilityRole="button"
                    onPress={() => state.openDetails(id)}
                    style={({ pressed }) => [ui.item, pressed && ui.pressed]}
                  >
                    <T>{s.t('home.result.item', { code: d.code, name: s.lang === 'ar' ? d.nameAr : d.nameEn })}</T>
                    <T style={ui.small}>{s.t('common.building_floor', { building: d.building, floor: d.floor })}</T>
                  </Pressable>
                );
              }}
            />
          </>
        )}
      </View>
      <View style={ui.row}>
        <T>{s.t('home.floor.label')}</T>
        {[1, 2, 3].map((f) => (
          <Btn
            key={f}
            id={`home.floor.${f}`}
            label={s.t('home.floor.option', { floor: f })}
            a11yLabel={state.floor === f ? s.t('home.floor.selected', { floor: f }) : s.t('home.floor.option', { floor: f })}
            selected={state.floor === f}
            onPress={() => state.setFloor(f)}
            outline
          />
        ))}
      </View>
      <MapPanel state={state} />
    </View>
  );
}

// ---------------------------------------------------------------- S04/S05

function DetailsScreen({ state, destinationId }: { state: AppState; destinationId: string }) {
  const s = state.s;
  const d = state.data?.byId.get(destinationId);
  if (!d) return <Header s={s} title={s.t('details.title')} backId="details.back" onBack={state.back} />;
  const schedule = state.data!.scheduleFor(d.id);
  const row = (labelKey: string, id: string, value: string) => (
    <View style={ui.item}>
      <T style={ui.label}>{s.t(labelKey)}</T>
      <T id={id}>{value}</T>
    </View>
  );
  return (
    <>
      <Header s={s} title={s.t('details.title')} backId="details.back" onBack={state.back} />
      <ScrollView>
        {row('details.code', 'details.code', d.code)}
        {row('details.name', 'details.name', s.lang === 'ar' ? d.nameAr : d.nameEn)}
        {row('details.building', 'details.building', d.building)}
        {row('details.floor', 'details.floor', String(d.floor))}
        {row('details.status', 'details.status', s.t(d.reachable ? 'details.status.reachable' : 'details.status.unreachable'))}
        <T style={[ui.pad, ui.section]}>{s.t('details.schedule')}</T>
        {schedule.length === 0 ? (
          <T id="details.schedule.none" style={ui.pad}>
            {s.t('details.schedule.none')}
          </T>
        ) : (
          <View testID="details.schedule.list">
            {schedule.map((e) => (
              <View key={e.code} testID={`details.schedule.item.${e.code}`} style={ui.item}>
                <T>{scheduleItem(s, e)}</T>
              </View>
            ))}
          </View>
        )}
        <View style={ui.row}>
          <Btn id="details.route" label={s.t('details.route')} onPress={() => state.openRoute(d.id)} />
          <Btn id="details.showmap" label={s.t('details.showmap')} onPress={() => state.showOnMap(d.id)} outline />
        </View>
      </ScrollView>
    </>
  );
}

// ---------------------------------------------------------------- S07

function RouteScreen({ state, destinationId }: { state: AppState; destinationId: string }) {
  const s = state.s;
  const d = state.data?.byId.get(destinationId);
  const r = state.route;
  const entrances = state.data?.entrances ?? [];
  return (
    <>
      <Header s={s} title={s.t('route.title')} backId="route.back" onBack={state.back} />
      <ScrollView>
        <T style={[ui.pad, ui.section]}>{s.t('route.from')}</T>
        {entrances.map((e) => (
          <Btn
            key={e}
            id={`route.from.${e}`}
            role="radio"
            label={s.t('route.from.option', { entrance: e })}
            selected={state.origin === e}
            onPress={() => state.setOrigin(e)}
            outline
          />
        ))}
        <View style={ui.item}>
          <T style={ui.label}>{s.t('route.to')}</T>
          <T id="route.to">{d ? s.t('home.result.item', { code: d.code, name: s.lang === 'ar' ? d.nameAr : d.nameEn }) : destinationId}</T>
        </View>
        <View style={ui.row}>
          <T style={ui.grow}>{s.t('route.stepfree')}</T>
          <Switch
            testID="route.stepfree"
            accessibilityLabel={s.t('route.stepfree')}
            value={state.stepFree}
            onValueChange={state.setStepFree}
          />
        </View>
        <View style={ui.row}>
          <Btn id="route.compute" label={s.t('route.compute')} onPress={() => state.computeRoute()} />
        </View>
        <T id="route.trust" style={ui.pad}>
          {trustText(s, state.bundleInfo)}
        </T>
        {r !== null && r.outcome === 'PATH' && state.summary !== null ? (
          <>
            <T id="route.summary" style={[ui.pad, ui.section]}>
              {summaryText(s, state.summary)}
            </T>
            <T style={ui.pad}>{s.t('route.steps')}</T>
            <View testID="route.steps">
              {state.steps.map((st, i) => (
                <View key={i} testID={`route.step.${i}`} style={ui.item}>
                  <T>{`${i + 1}. ${stepText(s, st)}`}</T>
                </View>
              ))}
            </View>
            <View style={ui.row}>
              <Btn id="route.ar" label={s.t('route.ar')} onPress={() => void state.openAr()} outline />
            </View>
          </>
        ) : r !== null ? (
          <T id="route.reject" style={ui.pad}>
            {rejectText(s, r.outcome)}
          </T>
        ) : null}
      </ScrollView>
    </>
  );
}

// ---------------------------------------------------------------- S09

function FallbackScreen({ state }: { state: AppState }) {
  const s = state.s;
  return (
    <>
      <Header s={s} title={s.t('fallback.title')} titleId="fallback.title" />
      <ScrollView>
        <T id="fallback.message" style={ui.pad}>
          {s.t('ar.unsupported')}
        </T>
        <View testID="fallback.steps">
          {state.steps.map((st, i) => (
            <View key={i} style={ui.item}>
              <T>{`${i + 1}. ${stepText(s, st)}`}</T>
            </View>
          ))}
        </View>
        <View style={ui.row}>
          <Btn id="fallback.back" label={s.t('fallback.back')} onPress={state.back} />
        </View>
      </ScrollView>
    </>
  );
}

// ---------------------------------------------------------------- anchor code result

function QrScreen({ state }: { state: AppState }) {
  const s = state.s;
  return (
    <>
      <Header s={s} title={s.t('qr.title')} />
      <ScrollView>
        <T id="qr.result" style={ui.pad}>
          {qrText(s, state.qrOutcome ?? {})}
        </T>
        <View style={ui.row}>
          <Btn id="qr.close" label={s.t('common.close')} onPress={state.back} />
        </View>
      </ScrollView>
    </>
  );
}

// ---------------------------------------------------------------- data and trust

function updateText(s: Strings, state: AppState): string | null {
  switch (state.updateStatus) {
    case 'pending':
      return s.t('settings.update.pending', { percent: state.updatePercent });
    case 'slow':
      return s.t('settings.update.slow');
    case 'none':
      return s.t('settings.update.none');
    case 'failed':
      return s.t('settings.update.failed');
    default:
      return null;
  }
}

function SettingsScreen({ state }: { state: AppState }) {
  const s = state.s;
  const info = state.bundleInfo;
  const valid = info?.state === 'VALID';
  const update = updateText(s, state);
  return (
    <>
      <Header s={s} title={s.t('settings.title')} backId="settings.back" onBack={state.back} />
      <ScrollView>
        <View style={ui.item}>
          <T style={ui.label}>{s.t('settings.version')}</T>
          <T id="settings.version">{String(info?.version ?? '-')}</T>
        </View>
        {valid ? (
          <T id="settings.validity" style={ui.pad}>
            {s.t('settings.validity', { from: isoDate(info!.valid_from_ms as number), until: isoDate(info!.valid_until_ms as number) })}
          </T>
        ) : null}
        <T id="settings.status" style={ui.pad}>
          {trustText(s, info)}
        </T>
        <View style={ui.row}>
          <Btn id="settings.update" label={s.t('settings.update')} onPress={() => void state.update()} />
        </View>
        {update !== null ? (
          <T id="settings.update.status" style={ui.pad}>
            {update}
          </T>
        ) : null}
        {state.lastResult !== null ? (
          <T id="settings.result" style={ui.pad}>
            {s.has(`result.${state.lastResult}`) ? s.t(`result.${state.lastResult}`) : s.t('error.generic')}
          </T>
        ) : null}
      </ScrollView>
    </>
  );
}

// ---------------------------------------------------------------- root

export function Root({ state }: { state: AppState }): React.JSX.Element {
  const s = state.s;
  const insets = useSafeAreaInsets();
  const top = state.top;
  let page: React.JSX.Element | null = null;
  switch (top.kind) {
    case 'details':
      page = <DetailsScreen state={state} destinationId={top.destination!} />;
      break;
    case 'route':
      page = <RouteScreen state={state} destinationId={top.destination!} />;
      break;
    case 'fallback':
      page = <FallbackScreen state={state} />;
      break;
    case 'qr':
      page = <QrScreen state={state} />;
      break;
    case 'settings':
      page = <SettingsScreen state={state} />;
      break;
    default:
      page = null;
  }
  const pad = { paddingTop: insets.top, paddingBottom: insets.bottom, paddingLeft: insets.left, paddingRight: insets.right };
  return (
    <Rtl.Provider value={s.rtl}>
      <View style={[ui.fill, ui.screen, { direction: s.rtl ? 'rtl' : 'ltr' }]}>
        {/* the home screen (with its map) stays mounted under the other screens */}
        <View style={[ui.fill, pad]}>
          <HomeScreen state={state} covered={page !== null} />
        </View>
        {page !== null ? <View style={[StyleSheet.absoluteFill, ui.screen, pad]}>{page}</View> : null}
      </View>
    </Rtl.Provider>
  );
}

const ui = StyleSheet.create({
  fill: { flex: 1 },
  screen: { backgroundColor: C.surface },
  text: { color: C.text, fontSize: 16 },
  small: { color: C.muted, fontSize: 13, paddingHorizontal: 16 },
  label: { color: C.muted, fontSize: 13 },
  section: { fontSize: 17, fontWeight: '600' },
  pad: { paddingHorizontal: 16, paddingVertical: 6 },
  grow: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 6, paddingHorizontal: 12, paddingVertical: 6 },
  headerTitle: { flex: 1, fontSize: 20, fontWeight: '600', minWidth: 120 },
  row: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8, paddingHorizontal: 16, paddingVertical: 6 },
  results: { flex: 2, minHeight: 80 },
  input: {
    flexGrow: 1,
    flexBasis: 160,
    minHeight: 48,
    borderWidth: 1,
    borderColor: C.border,
    borderRadius: 6,
    paddingHorizontal: 12,
    color: C.text,
    fontSize: 16,
  },
  item: { paddingHorizontal: 16, paddingVertical: 10, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: C.border, minHeight: 48 },
  btn: { minHeight: 48, minWidth: 48, paddingHorizontal: 14, justifyContent: 'center', alignItems: 'center', borderRadius: 6 },
  btnFilled: { backgroundColor: C.primary },
  btnOutline: { borderWidth: 1, borderColor: C.primary, backgroundColor: C.surface },
  btnSelected: { backgroundColor: C.selected, borderWidth: 2, borderColor: C.primary },
  btnDisabled: { opacity: 0.45 },
  btnText: { fontSize: 16, fontWeight: '600' },
  btnTextFilled: { color: C.onPrimary },
  btnTextOutline: { color: C.primary },
  pressed: { opacity: 0.7 },
});
