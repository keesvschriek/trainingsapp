import { describe, expect, it } from 'vitest';
import type { Metric } from './db';
import { goalStreak, lastDays, newSetId, setsByDay, dayTotal } from './pushups';

const set = (date: string, value: number, t: number, deleted = false): Metric =>
  ({ id: newSetId(date, t), date, kind: 'pushups', value, updatedAt: t, deleted });

describe('push-ups tussendoor', () => {
  const recs = [
    set('2026-11-13', 20, 1), set('2026-11-13', 20, 2), set('2026-11-13', 20, 3), set('2026-11-13', 20, 4), set('2026-11-13', 20, 5),
    set('2026-11-14', 20, 6), set('2026-11-14', 20, 7), set('2026-11-14', 20, 8), set('2026-11-14', 20, 9), set('2026-11-14', 25, 10),
    set('2026-11-15', 20, 12), set('2026-11-15', 15, 11), set('2026-11-15', 20, 13, true),
  ];
  const byDay = setsByDay(recs);

  it('telt sets per dag en slaat verwijderde over', () => {
    expect(dayTotal(byDay.get('2026-11-13'))).toBe(100);
    expect(dayTotal(byDay.get('2026-11-15'))).toBe(35);
    expect(byDay.get('2026-11-15')!.map(s => s.value)).toEqual([15, 20]); // op volgorde van invoer
  });

  it('reeks telt vandaag alleen mee als het doel gehaald is', () => {
    expect(goalStreak(byDay, 100, '2026-11-15')).toBe(2);
    expect(goalStreak(byDay, 100, '2026-11-14')).toBe(2);
    expect(goalStreak(byDay, 100, '2026-11-17')).toBe(0);
    expect(goalStreak(byDay, 30, '2026-11-15')).toBe(3);
  });

  it('geeft de laatste dagen inclusief lege dagen', () => {
    const days = lastDays(byDay, 4, '2026-11-15');
    expect(days.map(d => d.total)).toEqual([0, 100, 105, 35]);
    expect(days[3].sets).toBe(2);
  });
});
