// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// In-app bilingual strings (contract/strings/en.json and ar.json, bundled by Metro).
export class Strings {
  constructor(public readonly lang: string, private readonly map: Record<string, string>) {}

  get rtl(): boolean {
    return this.map['_meta.direction'] === 'rtl';
  }

  /** The string for key with {name} placeholders replaced; a missing key is returned as "[key]" (caught by the tests). */
  t(key: string, params: Record<string, unknown> = {}): string {
    let s = this.map[key];
    if (s === undefined) return `[${key}]`;
    for (const [k, v] of Object.entries(params)) s = s.split(`{${k}}`).join(String(v));
    return s;
  }

  has(key: string): boolean {
    return Object.prototype.hasOwnProperty.call(this.map, key);
  }

  keys(): string[] {
    return Object.keys(this.map);
  }
}
