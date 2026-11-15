import { describe, expect, it } from 'vitest';
import type { Workout } from './db';
import { driftLevel, driftRuns, rolling, weeklyDrift } from './aerobic';

const run = (date: string, decoupling: number | undefined, extra: Partial<Workout> = {}): Workout =>
  ({ id: date + decoupling, date, kind: 'run', title: 'Loop', durationMin: 45, distanceKm: 8, elevationM: 40, decoupling, source: 'intervals', updatedAt: 1, ...extra });

describe('basisconditie (hartslagdrift)', () => {
  it('neemt alleen rustige, lange genoeg en vlakke lopen mee', () => {
    const runs = driftRuns([
      run('2026-11-17', 6.2),
      run('2026-11-18', 3.1, { slotId: 'run-quality' }),
      run('2026-11-19', 2.0, { durationMin: 25 }),
      run('2026-11-21', 4.4, { elevationM: 300, distanceKm: 14 }),
      run('2026-11-22', undefined),
      run('2026-11-24', 4.0, { slotId: 'run-easy' }),
    ]);
    expect(runs.map(r => r.date)).toEqual(['2026-11-17', '2026-11-24']);
  });

  it('slaat een loop zonder koppeling over op een dag met tempo of intervallen', () => {
    const runs = driftRuns([run('2026-11-17', 6), run('2026-11-18', 3)], d => d === '2026-11-18');
    expect(runs.map(r => r.date)).toEqual(['2026-11-17']);
  });

  it('beoordeelt volgens de 5-10% vuistregel', () => {
    expect(driftLevel(3.9)).toBe('goed');
    expect(driftLevel(7)).toBe('groeit');
    expect(driftLevel(12)).toBe('hoog');
  });

  it('maakt een rustige trend en weekgemiddelden', () => {
    const runs = driftRuns([run('2026-11-17', 8), run('2026-11-19', 6), run('2026-11-24', 4)]);
    expect(rolling(runs, 2)).toEqual([8, 7, 5]);
    expect(weeklyDrift(runs).get('2026-11-16')).toBe(7);
    expect(weeklyDrift(runs).get('2026-11-23')).toBe(4);
  });
});
