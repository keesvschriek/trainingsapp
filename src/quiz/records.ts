import { useLiveQuery } from 'dexie-react-hooks';
import { getSetting, setSetting } from '../db';
import { today } from '../dates';

// Records en statistieken van de quiz. Alleen op deze telefoon.

export interface Rec { best: number; unit: string; plays: number; lastAt: string; bestAt: string }
export interface QuizStats { answered: number; correct: number; xp: number; days: string[] }

const EMPTY: QuizStats = { answered: 0, correct: 0, xp: 0, days: [] };

export async function getRecords(): Promise<Record<string, Rec>> {
  return getSetting<Record<string, Rec>>('quiz.records', {});
}
export async function getStats(): Promise<QuizStats> {
  return { ...EMPTY, ...(await getSetting<Partial<QuizStats>>('quiz.stats', {})) };
}
export function useRecords() {
  return useLiveQuery(getRecords, [], {} as Record<string, Rec>);
}
export function useStats() {
  return useLiveQuery(getStats, [], EMPTY);
}

export const level = (xp: number) => Math.floor(Math.sqrt(xp / 250)) + 1;
export const xpForLevel = (l: number) => (l - 1) ** 2 * 250;

/** Dagen op rij dat je een quiz deed (vandaag of gisteren als laatste). */
export function dayStreak(days: string[], t = today()): number {
  const set = new Set(days);
  const d = new Date(t + 'T12:00:00');
  if (!set.has(t)) d.setDate(d.getDate() - 1);
  let n = 0;
  while (set.has(d.toISOString().slice(0, 10))) {
    n++;
    d.setDate(d.getDate() - 1);
  }
  return n;
}

/** Sla een resultaat op. Hoger is beter. Geeft terug of het een record is. */
export async function saveResult(key: string, score: number, unit: string, answered: number, correct: number, xp: number): Promise<{ record: boolean; previous?: number }> {
  const recs = await getRecords();
  const prev = recs[key];
  const t = today();
  const record = !prev || score > prev.best;
  recs[key] = { best: record ? score : prev.best, unit, plays: (prev?.plays ?? 0) + 1, lastAt: t, bestAt: record ? t : prev.bestAt };
  await setSetting('quiz.records', recs);
  const s = await getStats();
  await setSetting('quiz.stats', { answered: s.answered + answered, correct: s.correct + correct, xp: s.xp + xp, days: [...new Set([...s.days.slice(-400), t])] });
  return { record: record && !!prev, previous: prev?.best };
}
