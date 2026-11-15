import data from './countries.json';

export interface Country {
  c2: string; c3: string; n3: string; name: string; alt: string[]; cap: string[]; capAlt: string[];
  region: 'Europa' | 'Azië' | 'Afrika' | 'Noord-Amerika' | 'Zuid-Amerika' | 'Oceanië' | 'Overig';
  sub: string; area: number; flag: string; borders: string[]; eu: boolean; landlocked: boolean;
}

export const COUNTRIES = data as Country[];
export const REGIONS = ['Europa', 'Azië', 'Afrika', 'Noord-Amerika', 'Zuid-Amerika', 'Oceanië'] as const;
export type Region = (typeof REGIONS)[number];
export const byC3 = new Map(COUNTRIES.map(c => [c.c3, c]));
export const byN3 = new Map(COUNTRIES.map(c => [c.n3, c]));

/** Tekst vergelijken zonder hoofdletters, accenten, leestekens en lidwoorden. */
export function norm(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/^(de|het|the|la|le|el)\s+/, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/** Klopt een getypt antwoord met een van de goede antwoorden? Kleine typfouten bij langere woorden mogen. */
export function matches(input: string, answers: string[]): boolean {
  const a = norm(input);
  if (!a) return false;
  return answers.some(x => {
    const b = norm(x);
    if (a === b) return true;
    if (b.length >= 7 && lev(a, b) <= 1) return true;
    if (b.length >= 11 && lev(a, b) <= 2) return true;
    return false;
  });
}

function lev(a: string, b: string): number {
  if (Math.abs(a.length - b.length) > 2) return 9;
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++)
    for (let j = 1; j <= b.length; j++)
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return d[a.length][b.length];
}

export const countryAnswers = (c: Country) => [c.name, ...c.alt];
export const capitalAnswers = (c: Country) => [...c.cap, ...c.capAlt];
