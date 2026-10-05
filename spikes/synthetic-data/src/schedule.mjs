// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// 60 synthetic schedule entries, fixed offset UTC+03:00 (IANA Etc/GMT-3, no DST), synthetic teaching week 2026-10-04 .. 2026-10-08.
import { Stream } from './drbg.mjs';

const DAYS = ['2026-10-04', '2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08'];

export function buildSchedule(dests) {
  const main = dests.filter((d) => !d.wing);
  if (main.length !== 268) throw new Error('expected 268 main destinations');
  const s = new Stream('schedule');
  const seen = new Set();
  const out = [];
  while (out.length < 60) {
    const day = s.randbelow(5);
    const slot = s.randbelow(8);
    const di = s.randbelow(268);
    const key = `${di}|${day}|${slot}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const n = String(out.length + 1).padStart(3, '0');
    const hh = String(8 + slot).padStart(2, '0');
    out.push({
      code: `SYN-COURSE-${n}`, label_en: `Synthetic Course ${n}`, label_ar: `مقرر اصطناعي ${n}`, destination: main[di].id,
      start: `${DAYS[day]}T${hh}:00:00+03:00`, end: `${DAYS[day]}T${hh}:50:00+03:00`, synthetic: true,
    });
  }
  return out;
}
