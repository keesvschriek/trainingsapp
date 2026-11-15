import { useLiveQuery } from 'dexie-react-hooks';
import { getSetting, setSetting } from '../db';
import { QUESTIONS, type Category, type Question } from './questions';

// Trivia in de rustpauze: vragen die je nog niet had eerst, antwoorden gehusseld, score bijgehouden.

export interface TriviaSettings {
  on: boolean;
  restSec: number;
  cats: Category[];
}
export const ALL_CATS = [...new Set(QUESTIONS.map(q => q.cat))] as Category[];
export const DEFAULT_TRIVIA: TriviaSettings = { on: true, restSec: 90, cats: ALL_CATS };

export interface TriviaScore {
  asked: string[];
  right: number;
  total: number;
  streak: number;
  best: number;
}
const EMPTY: TriviaScore = { asked: [], right: 0, total: 0, streak: 0, best: 0 };

export async function getTrivia(): Promise<TriviaSettings> {
  return { ...DEFAULT_TRIVIA, ...(await getSetting<Partial<TriviaSettings>>('trivia', {})) };
}
export function useTrivia(): TriviaSettings {
  return useLiveQuery(getTrivia, [], DEFAULT_TRIVIA);
}
export async function getScore(): Promise<TriviaScore> {
  return { ...EMPTY, ...(await getSetting<Partial<TriviaScore>>('triviaScore', {})) };
}

export interface Shown { q: Question; options: string[]; correct: number }

/** Kies een vraag die je nog niet had (binnen je categorieën) en hussel de antwoorden. */
export function pick(asked: string[], cats: Category[], rnd: () => number = Math.random): Shown {
  const pool = QUESTIONS.filter(q => cats.includes(q.cat));
  const list = pool.length ? pool : QUESTIONS;
  const fresh = list.filter(q => !asked.includes(q.id));
  const from = fresh.length ? fresh : list;
  const q = from[Math.floor(rnd() * from.length)];
  const order = [0, 1, 2, 3];
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  return { q, options: order.map(i => q.a[i]), correct: order.indexOf(0) };
}

export async function record(id: string, right: boolean, cats: Category[]): Promise<TriviaScore> {
  const s = await getScore();
  const poolSize = QUESTIONS.filter(q => cats.includes(q.cat)).length || QUESTIONS.length;
  let asked = [...s.asked.filter(x => x !== id), id];
  if (asked.filter(x => QUESTIONS.find(q => q.id === x && cats.includes(q.cat))).length >= poolSize) asked = [id]; // alles gehad: opnieuw beginnen
  const streak = right ? s.streak + 1 : 0;
  const next = { asked, right: s.right + (right ? 1 : 0), total: s.total + 1, streak, best: Math.max(s.best, streak) };
  await setSetting('triviaScore', next);
  return next;
}
