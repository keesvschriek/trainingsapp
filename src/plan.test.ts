import { describe, expect, it } from 'vitest';
import { PLAN_START, blockOfWeek, isTestWeek, nextTestWeek, planForDay, planForWeek, plannedRunMinutes, weekOf, weekSpec } from './plan';
import type { Block } from './db';

describe('schema', () => {
  it('blok 1 duurt 9 weken, daarna blokken van 8', () => {
    expect(blockOfWeek(1).nr).toBe(1);
    expect(blockOfWeek(9).nr).toBe(1);
    expect(blockOfWeek(10).nr).toBe(2);
    expect(blockOfWeek(17).nr).toBe(2);
    expect(blockOfWeek(18).nr).toBe(3);
    expect(isTestWeek(9)).toBe(true);
    expect(isTestWeek(17)).toBe(true);
    expect(isTestWeek(16)).toBe(false);
  });

  it('eerste testweek valt na het eindbivak (11 januari 2027)', () => {
    expect(nextTestWeek('2026-11-20')).toBe('2027-01-11');
  });

  it('loopt eindeloos door zonder fouten', () => {
    for (let w = 1; w <= 120; w++) {
      const spec = weekSpec(w);
      expect(spec.days.length).toBe(7);
      spec.days.forEach(d => expect(d.length).toBeGreaterThan(0));
    }
  });

  it('week 1 klopt', () => {
    expect(weekOf(PLAN_START)).toBe(1);
    const w = planForWeek(1);
    expect(w[0].items[0].kind).toBe('strength');
    expect(w[0].items[0].exercises!.length).toBe(5);
    expect(w[1].items[0].minutes).toBe(35);
    expect(plannedRunMinutes(1)).toBe(165);
  });

  it('krachttraining heeft uitgeschreven oefeningen en geen boksen', () => {
    for (let w = 1; w <= 40; w++) {
      planForWeek(w).flatMap(d => d.items).forEach(i => {
        expect(i.title.toLowerCase()).not.toContain('boks');
        if (i.kind === 'strength') expect(i.exercises?.length).toBeGreaterThan(0);
      });
    }
  });

  it('testweek bevat Cooper en 10 km', () => {
    const items = planForWeek(17).flatMap(d => d.items).map(i => i.slotId);
    expect(items).toContain('test-cooper');
    expect(items).toContain('test-10k');
    expect(items).toContain('test-pullups');
  });

  it('lange loop wordt nooit langer dan 2 uur', () => {
    for (let w = 1; w <= 120; w++) {
      planForWeek(w).flatMap(d => d.items).filter(i => i.slotId === 'run-long').forEach(i => expect(i.minutes!).toBeLessThanOrEqual(120));
    }
  });

  it('Defensieblok maakt dagen rust en de week lichter', () => {
    const blocks: Block[] = [{ id: 'x', start: '2026-12-03', end: '2026-12-05', label: 'Oefening', kind: 'defensie', updatedAt: 0 }];
    expect(planForDay('2026-12-03', blocks).items[0].title).toBe('Oefening');
    expect(planForDay('2026-12-06', blocks).items[0].title).toBe('Herstel na Defensie');
    expect(planForDay('2026-12-01', blocks).items[0].minutes).toBe(30);
  });

  it('wedstrijd vervangt de training en de dag ervoor is kort', () => {
    const blocks: Block[] = [{ id: 'y', start: '2027-03-06', end: '2027-03-06', label: '10 km van X', kind: 'wedstrijd', updatedAt: 0 }];
    expect(planForDay('2027-03-06', blocks).items[0].kind).toBe('race');
    expect(planForDay('2027-03-05', blocks).items[0].minutes).toBe(20);
  });

  it('voor de start geen fout', () => {
    expect(planForDay('2026-11-14').status).toBe('voor');
  });
});
