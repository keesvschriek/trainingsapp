import { QUESTIONS as TRIVIA } from '../../trivia/questions';
import type { MC } from '../model';
import type { Raw } from './raw';
import { WERELD } from './wereld';
import { MAATSCHAPPIJ } from './maatschappij';
import { OVERIG } from './overig';

const AS_OF = 'november 2026';

/** Korte, stabiele id op basis van de vraagtekst. */
export function hashId(s: string): string {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return (h >>> 0).toString(36);
}

const fromRaw = (cat: string, [q, a, why]: Raw): MC => ({ id: 'b' + hashId(q), cat, q, a, why, src: 'bank', asOf: cat === 'actueel' ? AS_OF : undefined });

export const BANK: MC[] = [
  ...TRIVIA.map(t => ({ id: t.id, cat: t.cat, q: t.q, a: [...t.a], why: t.why, src: 'bank' as const })),
  ...[WERELD, MAATSCHAPPIJ, OVERIG].flatMap(group => Object.entries(group).flatMap(([cat, list]) => list.map(r => fromRaw(cat, r)))),
];
