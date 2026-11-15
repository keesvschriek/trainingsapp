import { describe, expect, it } from 'vitest';
import type { Workout } from './db';
import { DEFAULT_CAR, savedFor } from './savings';

const w = (date: string, carFree: boolean): Workout => ({ id: date, date, kind: 'run', title: 'Loop naar huis', carFree, source: 'manual', updatedAt: 1 });

describe('besparing', () => {
  it('telt alleen ritten waarbij de auto bleef staan', () => {
    const s = savedFor([w('2026-11-17', true), w('2026-11-18', false), w('2026-11-24', true)], DEFAULT_CAR);
    expect(s.trips).toBe(2);
    expect(s.km).toBe(30);
    expect(s.liters).toBe(2); // 30 km x 6,5 l/100 km = 1,95 l
    expect(s.euro).toBeCloseTo(4.485, 1);
    expect(s.co2).toBeCloseTo(5.5, 1);
  });
  it('filtert op periode', () => {
    const s = savedFor([w('2026-11-17', true), w('2026-12-01', true)], DEFAULT_CAR, '2026-12-01', '2026-12-31');
    expect(s.trips).toBe(1);
  });
});
