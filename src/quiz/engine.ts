import { getSetting, setSetting } from '../db';
import { BANK } from './bank';
import { geoSet, type GeoKind } from './gen';
import type { Region } from './geo/countries';
import { CATS, shuffle, type MC } from './model';
import { extraQuestions, getExtra } from './packs';

// Vragen kiezen: eerst wat je nog niet (recent) had, fouten komen later terug.

export interface Memory { seen: string[]; wrong: string[] }
const KEY = 'quiz.memory';

export async function getMemory(): Promise<Memory> {
  return { seen: [], wrong: [], ...(await getSetting<Partial<Memory>>(KEY, {})) };
}

export async function remember(id: string, right: boolean) {
  if (id.startsWith('gen-')) return; // gegenereerde vragen hoeven niet onthouden te worden
  const m = await getMemory();
  const seen = [...m.seen.filter(x => x !== id), id].slice(-1500);
  const wrong = right ? m.wrong.filter(x => x !== id) : [...m.wrong.filter(x => x !== id), id].slice(-300);
  await setSetting(KEY, { seen, wrong });
}

export async function allQuestions(): Promise<MC[]> {
  const extra = await getExtra();
  const removed = new Set(extra.removed);
  return [...BANK.filter(q => !removed.has(q.id)), ...extraQuestions(extra)];
}

export async function countsByCat(): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (const q of await allQuestions()) out[q.cat] = (out[q.cat] ?? 0) + 1;
  return out;
}

/** Kies n vragen uit de categorieën, liefst nog niet gezien. */
export async function pickQuestions(cats: string[], n: number, rnd: () => number = Math.random): Promise<MC[]> {
  const all = await allQuestions();
  const pool = cats.length ? all.filter(q => cats.includes(q.cat)) : all;
  const m = await getMemory();
  const seenAt = new Map(m.seen.map((id, i) => [id, i]));
  const fresh = shuffle(pool.filter(q => !seenAt.has(q.id)), rnd);
  const old = pool.filter(q => seenAt.has(q.id)).sort((a, b) => seenAt.get(a.id)! - seenAt.get(b.id)!); // langst geleden eerst
  return [...fresh, ...old].slice(0, n);
}

export async function wrongQuestions(n: number): Promise<MC[]> {
  const all = await allQuestions();
  const m = await getMemory();
  const byId = new Map(all.map(q => [q.id, q]));
  return shuffle(m.wrong.map(id => byId.get(id)).filter((q): q is MC => !!q)).slice(0, n);
}

// Samengestelde quizzen ----------------------------------------------------

export interface Theme { key: string; name: string; cats: string[]; geo?: GeoKind[] }

export const THEMES: Theme[] = [
  { key: 'geo', name: 'Geografie en topografie', cats: ['aardrijkskunde'], geo: ['capital', 'countryOfCapital', 'flag', 'highlight', 'borders', 'area', 'landlocked', 'region'] },
  { key: 'hist', name: 'Geschiedenis en wereldleiders', cats: ['geschiedenis', 'wereldgeschiedenis', 'wereldleiders'] },
  { key: 'world', name: 'Geopolitiek en actualiteit', cats: ['geopolitiek', 'actueel', 'politiek', 'economie'] },
  { key: 'def', name: 'Defensie: ZHKH, wapenleer, AAW en Search', cats: ['defensie', 'zhkh', 'wapenleer', 'aaw', 'search'] },
  { key: 'sci', name: 'Wetenschap, natuur en techniek', cats: ['wetenschap', 'natuur', 'ict', 'uitvindingen'] },
  { key: 'cult', name: 'Cultuur, sport en eten', cats: ['cultuur', 'muziekfilm', 'eten', 'sport', 'religie'] },
  { key: 'nl', name: 'Nederland', cats: ['nederland', 'geschiedenis', 'politiek'] },
];

/** Een quiz met vragen uit de bank en, bij topografie, gegenereerde vragen. */
export async function buildQuiz(cats: string[], geo: GeoKind[] | undefined, n: number, region?: Region): Promise<MC[]> {
  const nGeo = geo?.length ? Math.round(n * (cats.length ? 0.6 : 1)) : 0;
  const fromBank = await pickQuestions(cats, n - nGeo);
  const gen = nGeo ? geoSet(geo!, nGeo + (n - nGeo - fromBank.length), region) : [];
  return shuffle([...fromBank, ...gen]).slice(0, n);
}

export const allCatKeys = () => CATS.map(c => c.key);
