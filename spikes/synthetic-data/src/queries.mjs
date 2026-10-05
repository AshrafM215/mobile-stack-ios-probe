// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Query corpus G1-QUERY-1.0: 500 queries in 8 categories; order shuffled with DRBG domain "queries".
import { Stream } from './drbg.mjs';
import { TYPES, DIACRITIZED_FIRST_WORDS } from './destinations.mjs';

const EASTERN = '٠١٢٣٤٥٦٧٨٩';
const PERSIAN = '۰۱۲۳۴۵۶۷۸۹';
const toDigits = (s, set) => s.replace(/[0-9]/g, (c) => set[c.charCodeAt(0) - 48]);
const firstWordDiacritized = (ar) => {
  const words = ar.split(' ');
  if (words[0] in DIACRITIZED_FIRST_WORDS) words[0] = DIACRITIZED_FIRST_WORDS[words[0]];
  return words.join(' ');
};
const withTatweel = (ar) => (ar.length > 1 ? ar[0] + '\u{0640}' + ar.slice(1) : ar);

export const MIX = {
  exact_code: 150, code_variants_case_space_hyphen: 60, eastern_arabic_digits: 40, arabic_names: 80,
  english_names: 80, mixed_script: 30, ambiguous: 30, no_match: 30,
};

export function buildQueries(dests) {
  const byId = new Map(dests.map((d) => [d.id, d]));
  const ids = dests.map((d) => d.id);
  const out = [];
  const push = (category, form, text) => out.push({ category, form, text });

  for (const id of new Stream('q-exact').sample(ids, 150)) push('exact_code', 'stored', byId.get(id).code);
  new Stream('q-variant').sample(ids, 60).forEach((id, i) => {
    const d = byId.get(id);
    const [b, f, r] = d.code.split('-');
    const forms = [
      ['lower', d.code.toLowerCase()], ['spaces', `${b} ${f} ${r}`], ['compact', `${b}${f}${r}`],
      ['mixed_case', `${b[0]}${b.slice(1).toLowerCase()}-${f.toLowerCase()}-${r}`], ['spaced_hyphens', `${b} - ${f} - ${r}`],
      ['padded_lower', `  ${b.toLowerCase()} ${f.toLowerCase()} ${r.toLowerCase()}  `],
    ];
    push('code_variants_case_space_hyphen', ...forms[i % 6]);
  });
  new Stream('q-digits').sample(ids, 40).forEach((id, i) => {
    const persian = i % 4 === 3;
    push('eastern_arabic_digits', persian ? 'persian_digits' : 'eastern_arabic_digits', toDigits(byId.get(id).code, persian ? PERSIAN : EASTERN));
  });
  new Stream('q-ar').sample(ids, 80).forEach((id, i) => {
    const d = byId.get(id);
    const forms = [
      ['stored', d.name_ar],
      ['first_word_diacritized', firstWordDiacritized(d.name_ar)],
      ['tatweel', withTatweel(d.name_ar)],
      ['eastern_arabic_digits', toDigits(d.name_ar, EASTERN)],
    ];
    push('arabic_names', ...forms[i % 4]);
  });
  new Stream('q-en').sample(ids, 80).forEach((id, i) => {
    const d = byId.get(id);
    const forms = [
      ['stored', d.name_en], ['lower', d.name_en.toLowerCase()], ['upper', d.name_en.toUpperCase()],
      ['fullwidth_digits_double_space', d.name_en.replace(/[0-9]/g, (c) => String.fromCodePoint(0xFF10 + c.charCodeAt(0) - 48)).split(' ').join('  ')],
    ];
    push('english_names', ...forms[i % 4]);
  });
  new Stream('q-mixed').sample(ids, 30).forEach((id, i) => {
    const d = byId.get(id);
    const [ar, en] = TYPES[d.type];
    if (i % 2 === 0) push('mixed_script', 'arabic_type_latin_room', `${ar} R${d.number}`);
    else push('mixed_script', 'english_type_eastern_digits', `${en} ${toDigits(d.number, EASTERN)}`);
  });
  dests.filter((d) => d.building === 1 && d.lookalike_of).forEach((d, i) => {
    const forms = [['room_code', `R${d.number}`], ['room_number', d.number], ['room_number_eastern_digits', toDigits(d.number, EASTERN)]];
    push('ambiguous', ...forms[i % 3]);
  });
  // no_match: ten forms x three instances
  const codes = new Set(dests.map((d) => d.code));
  const nm = new Stream('q-nomatch');
  const unknownEn = ['Planetarium', 'Observatory', 'Aquarium'];
  const unknownAr = ['مرصد', 'مسبح', 'حديقة'];
  const outOfRange = ['999', '301', '500'];
  for (let inst = 0; inst < 3; inst += 1) {
    const pick = () => byId.get(ids[nm.randbelow(ids.length)]);
    let d = pick();
    push('no_match', 'nonexistent_building', `SB4-F${d.floor}-R${d.number}`);
    d = pick();
    push('no_match', 'nonexistent_floor', `SB${d.building}-F4-R${d.number}`);
    for (const [form, from, to] of [['letter_o_for_zero', '0', 'O'], ['letter_i_for_one', '1', 'I']]) {
      for (;;) {
        d = pick();
        if (d.number.includes(from)) {
          push('no_match', form, `SB${d.building}-F${d.floor}-R${d.number.replace(from, to)}`);
          break;
        }
      }
    }
    for (;;) {
      d = pick();
      const f2 = (d.floor % 3) + 1;
      const code = `SB${d.building}-F${f2}-R${d.number}`;
      if (!codes.has(code)) { push('no_match', 'valid_format_wrong_floor', code); break; }
    }
    push('no_match', 'unknown_english_word', unknownEn[inst]);
    push('no_match', 'unknown_arabic_word', unknownAr[inst]);
    d = pick();
    push('no_match', 'english_type_out_of_range', `${TYPES[d.type][1]} ${outOfRange[inst]}`);
    d = pick();
    push('no_match', 'arabic_type_out_of_range', `${TYPES[d.type][0]} ${toDigits(outOfRange[inst], EASTERN)}`);
    push('no_match', 'room_out_of_range', `R${outOfRange[inst]}`);
  }
  new Stream('queries').shuffle(out);
  out.forEach((q, i) => { q.id = `Q${String(i + 1).padStart(3, '0')}`; });
  return out;
}
