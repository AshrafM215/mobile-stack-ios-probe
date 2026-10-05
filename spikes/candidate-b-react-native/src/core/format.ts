// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Deterministic presentation helpers (no device time zone or locale involved).
import type { ScheduleEntry } from './bundleData';
import type { RouteStep, RouteSummary } from './steps';
import type { Strings } from './strings';

const two = (v: number) => String(v).padStart(2, '0');

/** UTC calendar date "YYYY-MM-DD" of epoch milliseconds. */
export function isoDate(epochMs: number): string {
  const d = new Date(epochMs);
  return `${String(d.getUTCFullYear()).padStart(4, '0')}-${two(d.getUTCMonth() + 1)}-${two(d.getUTCDate())}`;
}

/** ISO weekday (1 = Monday) of the date part of "YYYY-MM-DDTHH:MM:SS+03:00". */
export function weekdayOf(iso: string): number {
  const day = new Date(Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10)))).getUTCDay();
  return day === 0 ? 7 : day;
}

export const hhmm = (iso: string): string => iso.slice(11, 16);

export const scheduleItem = (s: Strings, e: ScheduleEntry): string =>
  s.t('details.schedule.item', {
    label: s.lang === 'ar' ? e.labelAr : e.labelEn,
    day: s.t(`day.${weekdayOf(e.start)}`),
    start: hhmm(e.start),
    end: hhmm(e.end),
  });

export function stepText(s: Strings, st: RouteStep): string {
  switch (st.kind) {
    case 'walk':
      return s.t('route.step.walk', { length: st.m });
    case 'stairs':
      return s.t('route.step.stairs', { floor: st.floor });
    case 'elevator':
      return s.t('route.step.elevator', { floor: st.floor });
    case 'exit':
      return s.t('route.step.exit', { building: st.building });
    case 'enter':
      return s.t('route.step.enter', { building: st.building });
    default:
      return s.t('route.step.arrive', { code: st.code });
  }
}

export const summaryText = (s: Strings, m: RouteSummary): string => s.t('route.summary', { length: m.length_m, steps: m.steps, floors: m.floors });

export function rejectText(s: Strings, outcome: string): string {
  switch (outcome) {
    case 'REJECT_STEP_FREE_UNAVAILABLE':
      return s.t('route.reject.stepfree');
    case 'REJECT_BLOCKED':
      return s.t('route.reject.blocked');
    case 'REJECT_UNREACHABLE':
      return s.t('route.reject.unreachable');
    case 'REJECT_UNTRUSTED':
      return s.t('route.reject.untrusted');
    default:
      return s.t('route.reject.unknown');
  }
}

export type BundleInfo = Record<string, unknown>;

export function trustText(s: Strings, info: BundleInfo | null): string {
  switch (info?.state) {
    case 'VALID':
      return s.t('trust.status.valid', { version: info.version, until: isoDate(info.valid_until_ms as number) });
    case 'EXPIRED':
      return s.t('trust.status.expired');
    case 'TIME_UNTRUSTED':
      return s.t('trust.status.time_untrusted');
    case 'NOT_YET_VALID':
      return s.t('trust.status.not_yet_valid');
    case 'INVALID':
      return s.t('trust.status.invalid');
    default:
      return s.t('trust.status.none');
  }
}

export function qrText(s: Strings, o: Record<string, unknown>): string {
  switch (o.outcome) {
    case 'IDENTITY_VALID':
      return s.t('qr.identity', { anchor: o.anchor, building: o.building, floor: o.floor, kind: s.t(`kind.${o.kind}`) });
    case 'REJECT_BAD_SIGNATURE':
      return s.t('qr.reject.signature');
    case 'REJECT_EXPIRED':
      return s.t('qr.reject.expired');
    case 'REJECT_FOREIGN_PAYLOAD':
      return s.t('qr.reject.foreign');
    case 'REJECT_UNKNOWN_ANCHOR':
      return s.t('qr.reject.unknown');
    case 'REJECT_BUNDLE_MISMATCH':
      return s.t('qr.reject.bundle');
    case 'REJECT_UNTRUSTED_TIME':
      return s.t('qr.reject.time');
    case 'REJECT_NO_BUNDLE':
      return s.t('qr.reject.nobundle');
    case 'CAMERA_UNAVAILABLE':
      return s.t('qr.camera.unavailable');
    case 'PERMISSION_DENIED':
      return s.t('qr.camera.denied');
    case 'CANCELLED':
      return s.t('qr.cancelled');
    default:
      return s.t('qr.reject.malformed');
  }
}
