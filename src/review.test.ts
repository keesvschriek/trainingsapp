import { describe, expect, it } from 'vitest';
import type { Check, Metric, Workout } from './db';
import { weekReview } from './review';
import { mondayOfWeek, planForWeek } from './plan';
import { addDays } from './dates';

const mon = mondayOfWeek(1);
const d = (i: number) => addDays(mon, i);

describe('weekterugblik', () => {
  const plan = planForWeek(1);
  const trainingDays = plan.map((p, i) => ({ i, items: p.items.filter(x => x.kind !== 'rest' && x.kind !== 'free' && !x.optional) })).filter(x => x.items.length);

  it('telt gedaan, gemist en open', () => {
    // Alles van de eerste twee trainingsdagen gedaan via vinkjes, de rest niet
    const checks: Check[] = trainingDays.slice(0, 2).flatMap(t => t.items.map(it => ({ id: `${t.i}${it.slotId}`, date: d(t.i), slotId: it.slotId, done: true, updatedAt: 1 })));
    const r = weekReview(1, d(6), { workouts: [], checks, metrics: [], events: [], moves: [], pushupGoal: 100 });
    const total = trainingDays.reduce((s, t) => s + t.items.length, 0);
    expect(r.planned).toBe(total);
    expect(r.done).toBe(checks.length);
    expect(r.missed.length + r.openToday.length).toBe(total - checks.length);
    expect(r.verdict).toMatch(/van de/);
  });

  it('telt push-ups per dag tegen het doel en slaat rustdagen over', () => {
    const metrics: Metric[] = [0, 1, 3].map(i => ({ id: `p${i}`, date: d(i), kind: 'pushups', value: 100, updatedAt: 1 }));
    metrics.push({ id: 'g', date: d(0), kind: 'gtg', value: 12, updatedAt: 1 });
    const r = weekReview(1, d(6), { workouts: [], checks: [], metrics, events: [], moves: [], pushupGoal: 100 });
    expect(r.pushups).toBe(300);
    expect(r.pushupDays).toBe(3);
    expect(r.pushupDaysPossible).toBe(6); // woensdag is borst-dag
    expect(r.pullups).toBe(12);
  });

  it('telt lopen en kijkt vooruit naar volgende week', () => {
    const workouts: Workout[] = [{ id: 'w', date: d(1), kind: 'run', title: 'Loop', durationMin: 42, distanceKm: 7.6, source: 'intervals', updatedAt: 1 }];
    const r = weekReview(1, d(6), { workouts, checks: [], metrics: [], events: [], moves: [], pushupGoal: 100 });
    expect(r.runs).toBe(1);
    expect(r.runMin).toBe(42);
    expect(r.runKm).toBe(7.6);
    expect(r.next.some(n => /Lange loop/.test(n))).toBe(true);
  });
});
