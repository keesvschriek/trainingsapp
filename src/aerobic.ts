import type { Workout } from './db';
import { mondayOf, type ISODate } from './dates';

// Basisconditie: hartslagdrift (aerobic decoupling, Pa:Hr) op rustige lopen.
// intervals.icu vergelijkt tempo per hartslag in de eerste en de tweede helft van een loop.
// Vuistregel (Joe Friel): onder 5% is je basis goed voor die duur en intensiteit, 5-10% groeit nog, boven 10% te zwaar of te weinig basis.

export interface DriftRun { date: ISODate; title: string; drift: number; minutes: number; ef?: number }

const QUALITY = new Set(['run-quality']);

/** Lopen die bruikbaar zijn: rustig, minstens 35 minuten, niet te heuvelachtig. */
export function driftRuns(workouts: Workout[], isQualityDay: (d: ISODate) => boolean = () => false): DriftRun[] {
  return workouts
    .filter(w => !w.deleted && w.kind === 'run' && typeof w.decoupling === 'number')
    .filter(w => (w.slotId ? !QUALITY.has(w.slotId) : !isQualityDay(w.date)))
    .filter(w => (w.durationMin ?? 0) >= 35)
    .filter(w => !(w.distanceKm && w.elevationM && w.elevationM / w.distanceKm > 15))
    .filter(w => Math.abs(w.decoupling!) < 40) // meetfouten eruit
    .map(w => ({ date: w.date, title: w.title, drift: w.decoupling!, minutes: w.durationMin ?? 0, ef: w.efficiency }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

export type DriftLevel = 'goed' | 'groeit' | 'hoog';
export function driftLevel(drift: number): DriftLevel {
  if (drift < 5) return 'goed';
  if (drift <= 10) return 'groeit';
  return 'hoog';
}

export const DRIFT_TEXT: Record<DriftLevel, string> = {
  goed: 'Je hartslag blijft stabiel. Je basis is goed voor deze duur.',
  groeit: 'Je hartslag loopt in de tweede helft wat op. Je basis groeit nog.',
  hoog: 'Je hartslag loopt flink op. Rustiger lopen, of de loop was te lang of te warm.',
};

/** Gemiddelde van de laatste n lopen (voortschrijdend), voor een rustige trendlijn. */
export function rolling(runs: DriftRun[], n = 4): number[] {
  return runs.map((_, i) => {
    const part = runs.slice(Math.max(0, i - n + 1), i + 1);
    return Math.round((part.reduce((s, r) => s + r.drift, 0) / part.length) * 10) / 10;
  });
}

/** Gemiddelde drift per week (maandag als sleutel). */
export function weeklyDrift(runs: DriftRun[]): Map<ISODate, number> {
  const m = new Map<ISODate, number[]>();
  for (const r of runs) {
    const k = mondayOf(r.date);
    m.set(k, [...(m.get(k) ?? []), r.drift]);
  }
  return new Map([...m].map(([k, v]) => [k, Math.round((v.reduce((a, b) => a + b, 0) / v.length) * 10) / 10]));
}
