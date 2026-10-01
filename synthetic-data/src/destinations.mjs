// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Destinations: room numbers with 30 cross-building lookalikes, bilingual synthetic names, codes SB<b>-F<f>-R<nnn>.
import { Stream } from './drbg.mjs';

export const NAME_WORDS_VERSION = 'G1-SYNTH-NAMES-0.1';
export const TYPES = [
  ['قاعة محاضرات', 'Lecture Hall'], ['مختبر حاسوب', 'Computer Lab'], ['مختبر كيمياء', 'Chemistry Lab'],
  ['مختبر فيزياء', 'Physics Lab'], ['مكتب إداري', 'Administrative Office'], ['قاعة اجتماعات', 'Meeting Room'],
  ['غرفة دراسة', 'Study Room'], ['مكتبة فرعية', 'Branch Library'], ['استوديو تصميم', 'Design Studio'],
  ['ورشة هندسية', 'Engineering Workshop'], ['قاعة عرض', 'Exhibition Hall'], ['مركز خدمات', 'Service Center'],
  ['غرفة خوادم', 'Server Room'], ['عيادة', 'Clinic'], ['مقهى', 'Cafe'], ['قاعة رياضية', 'Sports Hall'],
  ['غرفة تخزين', 'Storage Room'], ['مختبر لغات', 'Language Lab'], ['قاعة مطالعة', 'Reading Hall'],
  ['مكتب استقبال', 'Reception Desk'],
];
export const LONG_QUALIFIER = ['متعددة الاستخدامات للدراسات العليا والبحث التطبيقي', 'Multi-Purpose Graduate and Applied Research'];
export const DIACRITIZED_FIRST_WORDS = {
  'قاعة': 'قَاعَة',
  'مختبر': 'مُخْتَبَر',
  'مكتب': 'مَكْتَب',
  'غرفة': 'غُرْفَة',
};

/** Build the 300 destination records in canonical order from the graph nodes. */
export function buildDestinations(nodes) {
  const dests = nodes.filter((n) => n.kind === 'destination').map((n, i) => ({
    id: n.dest_id,
    node: n.id,
    building: n.building,
    floor: n.floor,
    wing: n.wing,
    number: String(i + 1).padStart(3, '0'),
  }));
  // lookalikes: shuffle SB2+SB3 destinations, then (same stream) SB1 destinations; first 30 pairs share numbers
  const s = new Stream('lookalikes');
  const sb23 = s.shuffle(dests.filter((d) => d.building !== 1));
  const sb1 = s.shuffle(dests.filter((d) => d.building === 1));
  for (let i = 0; i < 30; i += 1) {
    sb23[i].number = sb1[i].number;
    sb23[i].lookalike_of = sb1[i].id;
    sb1[i].lookalike_of = sb23[i].id;
  }
  // names: type sequence [0..19] x 15 shuffled
  const types = [];
  for (let rep = 0; rep < 15; rep += 1) for (let t = 0; t < 20; t += 1) types.push(t);
  new Stream('names').shuffle(types);
  dests.forEach((d, i) => { d.type = types[i]; });
  const longSet = new Set(new Stream('long-names').sample(dests.map((d) => d.id), 12));
  const eligibleDiacritics = dests.filter((d) => !longSet.has(d.id) && TYPES[d.type][0].split(' ')[0] in DIACRITIZED_FIRST_WORDS)
    .map((d) => d.id);
  const diaSet = new Set(new Stream('diacritics').sample(eligibleDiacritics, 12));
  for (const d of dests) {
    const [ar, en] = TYPES[d.type];
    let typeAr = ar;
    if (diaSet.has(d.id)) {
      const words = ar.split(' ');
      words[0] = DIACRITIZED_FIRST_WORDS[words[0]];
      typeAr = words.join(' ');
    }
    d.code = `SB${d.building}-F${d.floor}-R${d.number}`;
    d.name_en = `${en} ${d.number}` + (longSet.has(d.id) ? ` ${LONG_QUALIFIER[1]}` : '');
    d.name_ar = `${typeAr} ${d.number}` + (longSet.has(d.id) ? ` ${LONG_QUALIFIER[0]}` : '');
    d.long_name = longSet.has(d.id);
    d.diacritized = diaSet.has(d.id);
  }
  return dests;
}

/** Public record for destinations.json (fixed key order). */
export const destinationRecord = (d) => ({
  id: d.id, code: d.code, building: `SB${d.building}`, floor: d.floor, node: d.node, room_number: d.number,
  name_en: d.name_en, name_ar: d.name_ar, type_index: d.type, wing: d.wing, reachable_from_entrances: !d.wing,
  lookalike_of: d.lookalike_of ?? null, long_name: d.long_name, diacritized: d.diacritized,
});
