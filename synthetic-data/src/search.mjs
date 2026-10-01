// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Reference implementation of the search contract G1-SEARCH-1.0 (every candidate implements the same contract).
//
// normalize(s): NFKC; Eastern-Arabic (U+0660-0669) and Persian (U+06F0-06F9) digits -> ASCII; remove tatweel
// (U+0640), Arabic marks U+064B-U+065F and U+0670, and invisible format characters (U+061C, U+200B-U+200F,
// U+202A-U+202E, U+2060-U+2069, U+FEFF); ASCII A-Z -> a-z only (no other case mapping); O/0 and I/1 never substituted.
// tokens(s): normalize(s) split at whitespace (U+0009-000D, U+0020, U+0085, U+00A0, U+1680, U+2000-200A, U+2028,
// U+2029, U+202F, U+205F, U+3000) and hyphen-like separators (U+002D, U+2010-U+2015, U+2212); empty tokens dropped.
// codeKey(s): concatenation of tokens(s), ASCII upper-cased.
// search(q): no tokens -> NO_MATCH. If codeKey(q) matches ^SB[0-9]+F[0-9]+R[0-9]+$ the result is the destination with
// exactly that code key (UNIQUE_MATCH) or NO_MATCH (no token fallback). Otherwise a destination matches when every query
// token equals one of its tokens: tokens(name_en), tokens(name_ar), "sb<b>", "f<f>", "r<nnn>", "<nnn>" and its lower-cased
// code key. 0 matches -> NO_MATCH, 1 -> UNIQUE_MATCH, more -> AMBIGUOUS. ids ascend by destination id. Ranking: none.

export const SEARCH_CONTRACT = 'G1-SEARCH-1.0';
const REMOVE = /[\u{0640}\u{064B}-\u{065F}\u{0670}\u{061C}\u{200B}-\u{200F}\u{202A}-\u{202E}\u{2060}-\u{2069}\u{FEFF}]/gu;
const SEPARATORS = /[\u{0009}-\u{000D}\u{0020}\u{0085}\u{00A0}\u{1680}\u{2000}-\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{002D}\u{2010}-\u{2015}\u{2212}]+/u;
const CODE = /^SB[0-9]+F[0-9]+R[0-9]+$/;

export function normalize(s) {
  let out = s.normalize('NFKC');
  out = out.replace(/[\u{0660}-\u{0669}]/gu, (c) => String.fromCharCode(c.charCodeAt(0) - 0x0660 + 48));
  out = out.replace(/[\u{06F0}-\u{06F9}]/gu, (c) => String.fromCharCode(c.charCodeAt(0) - 0x06F0 + 48));
  out = out.replace(REMOVE, '');
  out = out.replace(/[A-Z]/g, (c) => String.fromCharCode(c.charCodeAt(0) + 32));
  return out;
}

export const tokens = (s) => normalize(s).split(SEPARATORS).filter((t) => t.length > 0);
export const codeKey = (s) => tokens(s).join('').replace(/[a-z]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 32));

export function buildIndex(destinations) {
  return destinations.map((d) => {
    const set = new Set([...tokens(d.name_en), ...tokens(d.name_ar)]);
    const building = d.building.toLowerCase(); // "sb1"
    set.add(building);
    set.add(`f${d.floor}`);
    set.add(`r${d.room_number}`);
    set.add(d.room_number);
    set.add(codeKey(d.code).toLowerCase());
    return { id: d.id, code_key: codeKey(d.code), tokens: set };
  });
}

export function search(query, index) {
  const t = tokens(query);
  if (t.length === 0) return { outcome: 'NO_MATCH', ids: [] };
  const key = codeKey(query);
  let ids;
  if (CODE.test(key)) ids = index.filter((e) => e.code_key === key).map((e) => e.id);
  else ids = index.filter((e) => t.every((tok) => e.tokens.has(tok))).map((e) => e.id);
  ids.sort();
  if (ids.length === 0) return { outcome: 'NO_MATCH', ids: [] };
  return { outcome: ids.length === 1 ? 'UNIQUE_MATCH' : 'AMBIGUOUS', ids };
}
