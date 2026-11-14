import { describe, expect, it } from 'vitest';
import { PLAN_START, RACE_DATE, TOTAL_WEEKS, WEEKS, planForDay, planForWeek, plannedRunMinutes, weekOf } from './plan';
import type { Block } from './db';

describe('schema', () => {
  it('heeft 34 weken en de race op 10 juli 2027', () => {
    expect(WEEKS.length).toBe(TOTAL_WEEKS);
    expect(RACE_DATE).toBe('2027-07-10');
    expect(planForDay(RACE_DATE).items[0].kind).toBe('race');
  });

  it('elke week heeft 7 dagen', () => {
    WEEKS.forEach(w => expect(w.days.length).toBe(7));
  });

  it('week 1 klopt met het document', () => {
    expect(weekOf(PLAN_START)).toBe(1);
    const w = planForWeek(1);
    expect(w[1].items[0].minutes).toBe(35);
    expect(w[3].items[0].minutes).toBe(40);
    expect(w[5].items[0].minutes).toBe(90);
    expect(plannedRunMinutes(1)).toBe(165);
  });

  it('week 3 en 5 hebben teruglopen van werk op donderdag', () => {
    expect(planForWeek(3)[3].items[0].slotId).toBe('run-commute');
    expect(planForWeek(5)[3].items[0].slotId).toBe('run-commute');
  });

  it('Defensieblok maakt dagen rust en de week lichter', () => {
    const blocks: Block[] = [{ id: 'x', start: '2026-12-03', end: '2026-12-05', label: 'Oefening', kind: 'defensie', updatedAt: 0 }];
    // week 3: 30 nov - 6 dec
    expect(planForDay('2026-12-03', blocks).items[0].title).toBe('Oefening');
    expect(planForDay('2026-12-06', blocks).items[0].title).toBe('Herstel na Defensie');
    expect(planForDay('2026-12-01', blocks).items[0].minutes).toBe(30); // 45 * 0.7 = 31,5 -> 30
    expect(planForDay('2026-12-01', blocks).lightWeek).toBe(true);
  });

  it('voor de start en na de race geen fout', () => {
    expect(planForDay('2026-11-14').status).toBe('voor');
    expect(planForDay('2027-08-01').status).toBe('klaar');
  });

  it('lange loop groeit niet meer dan 15 min per week buiten lichte weken', () => {
    let prev = 0;
    for (let w = 1; w <= 32; w++) {
      const sat = planForWeek(w)[5].items.find(i => i.slotId === 'run-long');
      if (!sat || WEEKS[w - 1].light) continue;
      if (prev) expect(sat.minutes! - prev).toBeLessThanOrEqual(30);
      prev = sat.minutes!;
    }
  });
});
