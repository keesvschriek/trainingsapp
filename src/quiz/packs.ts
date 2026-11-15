import { useLiveQuery } from 'dexie-react-hooks';
import { getSetting, setSetting } from '../db';
import { hashId } from './bank';
import { CATS, type MC } from './model';

// Extra vragen die zonder nieuwe app-versie binnenkomen:
// 1. vragenpakketten uit de GitHub-repo (quiz-packs/index.json),
// 2. zelf gegenereerde vragen via je eigen Anthropic API-sleutel.

export const PACKS_URL = 'https://raw.githubusercontent.com/keesvschriek/trainingsapp/main/quiz-packs/index.json';

export interface PackQuestion { cat: string; q: string; a: string[]; why?: string; asOf?: string }
export interface Pack { id: string; title: string; version: number; questions: PackQuestion[] }
export interface Stored { packs: Pack[]; ai: MC[]; removed: string[]; checkedAt?: number }

const EMPTY: Stored = { packs: [], ai: [], removed: [] };
const KEY = 'quiz.extra';

export async function getExtra(): Promise<Stored> {
  return { ...EMPTY, ...(await getSetting<Partial<Stored>>(KEY, {})) };
}
export function useExtra(): Stored {
  return useLiveQuery(getExtra, [], EMPTY);
}

const known = new Set(CATS.map(c => c.key));

/** Een vraag is bruikbaar als hij een bekende categorie, een vraag en precies vier verschillende antwoorden heeft. */
export function valid(q: Partial<PackQuestion>): q is PackQuestion {
  return (
    !!q && typeof q.q === 'string' && q.q.trim().length > 5 && typeof q.cat === 'string' && known.has(q.cat) &&
    Array.isArray(q.a) && q.a.length === 4 && q.a.every(x => typeof x === 'string' && x.trim()) && new Set(q.a.map(x => x.trim().toLowerCase())).size === 4
  );
}

export function extraQuestions(s: Stored): MC[] {
  const removed = new Set(s.removed);
  const fromPacks = s.packs.flatMap(p => p.questions.filter(valid).map(q => ({ id: 'p' + hashId(q.q), cat: q.cat, q: q.q, a: q.a, why: q.why, asOf: q.asOf, src: 'pack' as const })));
  return [...fromPacks, ...s.ai].filter(q => !removed.has(q.id));
}

/** Haal pakketten op. Geeft aantal nieuwe vragen terug. */
export async function updatePacks(url = PACKS_URL): Promise<{ added: number; packs: number }> {
  const res = await fetch(url + '?t=' + Date.now(), { cache: 'no-store' });
  if (!res.ok) throw new Error(`Ophalen mislukt (${res.status}).`);
  const data = (await res.json()) as { packs?: Pack[] };
  if (!Array.isArray(data.packs)) throw new Error('Onverwacht bestand.');
  const s = await getExtra();
  const before = new Set(extraQuestions(s).map(q => q.id));
  const packs = data.packs.filter(p => p && typeof p.id === 'string' && Array.isArray(p.questions));
  const next = { ...s, packs, checkedAt: Date.now() };
  await setSetting(KEY, next);
  const added = extraQuestions(next).filter(q => !before.has(q.id)).length;
  return { added, packs: packs.length };
}

export async function removeQuestion(id: string) {
  const s = await getExtra();
  await setSetting(KEY, { ...s, removed: [...new Set([...s.removed, id])], ai: s.ai.filter(q => q.id !== id) });
}

export async function addAi(list: MC[]) {
  const s = await getExtra();
  const have = new Set(s.ai.map(q => q.id));
  await setSetting(KEY, { ...s, ai: [...s.ai, ...list.filter(q => !have.has(q.id))].slice(-600) });
}

export async function clearAi() {
  const s = await getExtra();
  await setSetting(KEY, { ...s, ai: [] });
}
