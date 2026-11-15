import { COUNTRIES, REGIONS, byC3, type Country, type Region } from './geo/countries';
import { sample, shuffle, type MC } from './model';

// Generatoren: oneindig veel nieuwe vragen uit data en rekenregels.

type Rnd = () => number;
const R = Math.random;
const int = (a: number, b: number, rnd: Rnd = R) => a + Math.floor(rnd() * (b - a + 1));
const pick = <T,>(arr: T[], rnd: Rnd = R) => arr[Math.floor(rnd() * arr.length)];

// ---------------------------------------------------------------------------
// Topografie
// ---------------------------------------------------------------------------

const inRegion = (r?: Region) => COUNTRIES.filter(c => c.region !== 'Overig' && (!r || c.region === r));
const others = (c: Country, n: number, pool: Country[], rnd: Rnd) => sample(pool.filter(x => x.c3 !== c.c3), n, rnd);

export type GeoKind = 'capital' | 'countryOfCapital' | 'flag' | 'region' | 'area' | 'borders' | 'landlocked' | 'highlight';

/** Landen die groot genoeg zijn om op de kaart te zien en aan te tikken. */
export const mapPool = (r?: Region) => inRegion(r).filter(c => c.area >= (r ? (r === 'Europa' ? 2000 : r === 'Oceanië' ? 2000 : 9000) : 9000));

export function geoQuestion(kind: GeoKind, region?: Region, rnd: Rnd = R): MC | null {
  const pool = inRegion(region);
  if (pool.length < 4) return null;
  const c = pick(pool, rnd);
  const id = `gen-${kind}-${c.c3}-${Math.floor(rnd() * 1e6)}`;
  switch (kind) {
    case 'capital':
      return { id, cat: 'aardrijkskunde', q: `Wat is de hoofdstad van ${c.name}?`, a: [c.cap[0], ...others(c, 3, pool, rnd).map(x => x.cap[0])], why: c.cap.length > 1 ? `${c.name} heeft meerdere hoofdsteden: ${c.cap.join(', ')}.` : undefined, src: 'gen' };
    case 'countryOfCapital':
      return { id, cat: 'aardrijkskunde', q: `${c.cap[0]} is de hoofdstad van:`, a: [c.name, ...others(c, 3, pool, rnd).map(x => x.name)], src: 'gen' };
    case 'flag':
      return { id, cat: 'aardrijkskunde', q: 'Van welk land is deze vlag?', big: c.flag, a: [c.name, ...others(c, 3, pool, rnd).map(x => x.name)], src: 'gen' };
    case 'region': {
      const regs = sample(REGIONS.filter(r => r !== c.region), 3, rnd);
      return { id, cat: 'aardrijkskunde', q: `In welk werelddeel ligt ${c.name}?`, a: [c.region, ...regs], src: 'gen' };
    }
    case 'area': {
      const four = sample(pool.filter(x => x.area > 1000), 4, rnd).sort((a, b) => b.area - a.area);
      if (four.length < 4 || four[0].area < four[1].area * 1.15) return null; // duidelijk verschil
      return { id, cat: 'aardrijkskunde', q: 'Welk land is het grootst (oppervlakte)?', a: four.map(x => x.name), why: four.map(x => `${x.name} ${x.area.toLocaleString('nl-NL')} km²`).join(', '), src: 'gen' };
    }
    case 'borders': {
      const nb = c.borders.map(b => byC3.get(b)).filter((x): x is Country => !!x);
      if (nb.length < 3) return null;
      const not = sample(pool.filter(x => x.c3 !== c.c3 && !c.borders.includes(x.c3) && x.region === c.region), 1, rnd)[0];
      if (!not) return null;
      return { id, cat: 'aardrijkskunde', q: `Welk land grenst NIET aan ${c.name}?`, a: [not.name, ...sample(nb, 3, rnd).map(x => x.name)], why: `${c.name} grenst aan ${nb.map(x => x.name).join(', ')}.`, src: 'gen' };
    }
    case 'highlight': {
      const mp = mapPool(region);
      if (mp.length < 4) return null;
      const h = pick(mp, rnd);
      const near = mp.filter(x => x.c3 !== h.c3 && x.sub === h.sub);
      const opts = sample(near.length >= 3 ? near : mp.filter(x => x.c3 !== h.c3), 3, rnd);
      return { id: `gen-hl-${h.c3}-${Math.floor(rnd() * 1e6)}`, cat: 'aardrijkskunde', q: 'Welk land is gemarkeerd?', map: h.c3, a: [h.name, ...opts.map(x => x.name)], src: 'gen' };
    }
    case 'landlocked': {
      const ll = pool.filter(x => x.landlocked);
      const coast = pool.filter(x => !x.landlocked && x.area > 5000);
      if (!ll.length || coast.length < 3) return null;
      const l = pick(ll, rnd);
      return { id, cat: 'aardrijkskunde', q: 'Welk land heeft GEEN kust?', a: [l.name, ...sample(coast, 3, rnd).map(x => x.name)], src: 'gen' };
    }
  }
}

export function geoSet(kinds: GeoKind[], n: number, region?: Region, rnd: Rnd = R): MC[] {
  const out: MC[] = [];
  const seen = new Set<string>();
  for (let tries = 0; out.length < n && tries < n * 20; tries++) {
    const q = geoQuestion(pick(kinds, rnd), region, rnd);
    if (!q) continue;
    const key = q.q + q.a[0] + (q.big ?? '');
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(q);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Rekenen: korte sommen met een getypt antwoord
// ---------------------------------------------------------------------------

export interface Sum { q: string; answers: string[]; hint?: string }
export type MathKind = 'mix' | 'tafels' | 'procent' | 'tempo' | 'kwadraat';

const fmtPace = (min: number) => `${Math.floor(min)}:${String(Math.round((min % 1) * 60)).padStart(2, '0')}`;

export function sum(kind: MathKind, rnd: Rnd = R): Sum {
  switch (kind) {
    case 'tafels': {
      const a = int(3, 15, rnd), b = int(3, 15, rnd);
      return { q: `${a} × ${b}`, answers: [String(a * b)] };
    }
    case 'procent': {
      const p = pick([5, 10, 15, 20, 25, 30, 40, 50, 75, 12.5], rnd);
      const base = pick([40, 60, 80, 120, 160, 200, 240, 360, 400, 640, 800], rnd);
      const v = (p * base) / 100;
      return { q: `${String(p).replace('.', ',')}% van ${base}`, answers: [String(v), String(v).replace('.', ',')] };
    }
    case 'tempo': {
      const pairs: [number, number][] = [[6, 10], [5, 12], [4, 15], [3, 20], [7.5, 8], [10, 6], [4.5, 13.333]];
      const v = int(0, 2, rnd);
      if (v === 0) {
        const [pace, kmh] = pick(pairs.filter(p => Number.isInteger(p[1])), rnd);
        return { q: `Tempo ${fmtPace(pace)} per km is hoeveel km/u?`, answers: [String(kmh)] };
      }
      if (v === 1) {
        const [pace, kmh] = pick(pairs.filter(p => Number.isInteger(p[1])), rnd);
        return { q: `${kmh} km/u is welk tempo per km?`, answers: [fmtPace(pace), String(pace).replace('.', ',')], hint: 'min:sec' };
      }
      const km = pick([5, 10], rnd);
      const pace = pick([4, 4.5, 5, 5.5, 6], rnd);
      return { q: `${km} km in ${Math.round(km * pace)} minuten: welk tempo per km?`, answers: [fmtPace(pace), String(pace).replace('.', ',')], hint: 'min:sec' };
    }
    case 'kwadraat': {
      const n = int(11, 25, rnd);
      return rnd() < 0.6 ? { q: `${n}²`, answers: [String(n * n)] } : { q: `√${n * n}`, answers: [String(n)] };
    }
    case 'mix':
    default: {
      const op = int(0, 3, rnd);
      if (op === 0) { const a = int(12, 199, rnd), b = int(12, 199, rnd); return { q: `${a} + ${b}`, answers: [String(a + b)] }; }
      if (op === 1) { const a = int(50, 300, rnd), b = int(11, a - 1, rnd); return { q: `${a} − ${b}`, answers: [String(a - b)] }; }
      if (op === 2) { const a = int(3, 19, rnd), b = int(3, 25, rnd); return { q: `${a} × ${b}`, answers: [String(a * b)] }; }
      const b = int(3, 15, rnd), c = int(3, 20, rnd);
      return { q: `${b * c} : ${b}`, answers: [String(c)] };
    }
  }
}

export function sumMatches(input: string, s: Sum): boolean {
  const n = (x: string) => x.trim().replace(',', '.').replace(/^0+(?=\d)/, '');
  return s.answers.some(a => n(a) === n(input));
}

export { shuffle };
