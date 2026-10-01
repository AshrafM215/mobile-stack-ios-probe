// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-SEARCH-1.0 in TypeScript (NFKC through String.prototype.normalize of the JavaScript engine).
import type { Destination } from './bundleData';

const REMOVE = /[\u{0640}\u{064B}-\u{065F}\u{0670}\u{061C}\u{200B}-\u{200F}\u{202A}-\u{202E}\u{2060}-\u{2069}\u{FEFF}]/gu;
const SEPARATORS = /[\u{0009}-\u{000D}\u{0020}\u{0085}\u{00A0}\u{1680}\u{2000}-\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{002D}\u{2010}-\u{2015}\u{2212}]+/u;
const CODE = /^SB[0-9]+F[0-9]+R[0-9]+$/;

export function normalize(s: string): string {
  const nfkc = s.normalize('NFKC');
  let out = '';
  for (const ch of nfkc) {
    const r = ch.codePointAt(0)!;
    if (r >= 0x0660 && r <= 0x0669) out += String.fromCharCode(r - 0x0660 + 48);
    else if (r >= 0x06f0 && r <= 0x06f9) out += String.fromCharCode(r - 0x06f0 + 48);
    else if (r >= 0x41 && r <= 0x5a) out += String.fromCharCode(r + 32);
    else out += ch;
  }
  return out.replace(REMOVE, '');
}

export const tokens = (s: string): string[] => normalize(s).split(SEPARATORS).filter((t) => t.length > 0);

export const codeKey = (s: string): string => tokens(s).join('').replace(/[a-z]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 32));

export interface SearchResult {
  outcome: 'UNIQUE_MATCH' | 'AMBIGUOUS' | 'NO_MATCH';
  ids: string[];
}

interface Entry {
  id: string;
  codeKey: string;
  tokens: Set<string>;
}

export class SearchIndex {
  private readonly entries: Entry[];

  constructor(destinations: Destination[]) {
    this.entries = destinations.map((d) => {
      const set = new Set<string>([...tokens(d.nameEn), ...tokens(d.nameAr)]);
      set.add(d.building.toLowerCase());
      set.add(`f${d.floor}`);
      set.add(`r${d.roomNumber}`);
      set.add(d.roomNumber);
      set.add(codeKey(d.code).toLowerCase());
      return { id: d.id, codeKey: codeKey(d.code), tokens: set };
    });
  }

  search(query: string): SearchResult {
    const t = tokens(query);
    if (t.length === 0) return { outcome: 'NO_MATCH', ids: [] };
    const key = codeKey(query);
    const ids = CODE.test(key)
      ? this.entries.filter((e) => e.codeKey === key).map((e) => e.id)
      : this.entries.filter((e) => t.every((tok) => e.tokens.has(tok))).map((e) => e.id);
    ids.sort();
    if (ids.length === 0) return { outcome: 'NO_MATCH', ids: [] };
    return { outcome: ids.length === 1 ? 'UNIQUE_MATCH' : 'AMBIGUOUS', ids };
  }
}
