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
    expect(w[4].items[0].kind).toBe('strength');
    expect(w[6].items[0].kind).toBe('free');
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

describe('kracht', () => {
  it('drie korte trainingen per week, max 30 min, benen alleen squats en kuiten', () => {
    for (const w of [1, 12, 30]) {
      const st = planForWeek(w).flatMap(d => d.items).filter(i => i.kind === 'strength');
      expect(st.length).toBe(3);
      st.forEach(i => expect(i.minutes!).toBeLessThanOrEqual(30));
      const names = st.flatMap(i => i.exercises!.map(e => e.name.toLowerCase()));
      expect(names.some(n => n.includes('push-up'))).toBe(true);
      expect(names.some(n => /swing|split|step-up|rdl/.test(n))).toBe(false);
    }
  });
});

describe('verschuiven', () => {
  const mv = (week: number, op: 'shift' | 'swap', a: number, b?: number, at = 1) => ({ id: `${week}-${a}-${at}`, week, op, a, b, at, updatedAt: at });

  it('dinsdag naar woensdag: rest schuift op tot de vrije zondag', () => {
    const before = planForWeek(2).map(d => d.items[0].title);
    const after = planForWeek(2, [], [mv(2, 'shift', 1)]).map(d => d.items[0].title);
    expect(after[1]).toBe('Rust (verschoven)');
    expect(after[2]).toBe(before[1]); // loop van dinsdag staat nu op woensdag
    expect(after[3]).toBe(before[2]);
    expect(after[6]).toBe(before[5]); // lange loop van zaterdag naar zondag, vrije zondag verdwijnt
  });

  it('ruilen wisselt twee dagen', () => {
    const before = planForWeek(2).map(d => d.items[0].title);
    const after = planForWeek(2, [], [mv(2, 'swap', 1, 3)]).map(d => d.items[0].title);
    expect(after[1]).toBe(before[3]);
    expect(after[3]).toBe(before[1]);
  });

  it('als er geen vrije dag meer is, schuift het door naar de week erna', () => {
    // twee keer schuiven in week 2: eerste gebruikt de vrije zondag, tweede moet doorschuiven
    const moves = [mv(2, 'shift', 1, undefined, 1), mv(2, 'shift', 2, undefined, 2)];
    const w2 = planForWeek(2, [], moves).map(d => d.items[0].title);
    const w3 = planForWeek(3, [], moves).map(d => d.items[0].title);
    const orig2 = planForWeek(2).map(d => d.items[0].title);
    expect(w2[6]).toBe(orig2[4]);
    expect(w3[0]).toBe(orig2[5]); // lange loop staat nu op maandag week 3
  });

  it('zonder verschuivingen verandert er niks', () => {
    expect(planForWeek(5, [], []).map(d => d.items[0].title)).toEqual(planForWeek(5).map(d => d.items[0].title));
  });
});

import { formScore, loadSeries, recoveryFor } from './recovery';

describe('herstel', () => {
  it('vorm: licht negatief is normaal, sterk negatief is slecht', () => {
    expect(formScore(0)).toBe(100);
    expect(formScore(-10)).toBe(100);
    expect(formScore(-30)).toBe(50);
    expect(formScore(-50)).toBeLessThan(20);
    expect(formScore(null)).toBe(null);
  });

  it('slechte check-in geeft rood advies', () => {
    const r = recoveryFor({ checkin: { id: 'c', date: '2026-12-01', sleep: 1, legs: 2, energy: 2, calm: 2, updatedAt: 0 }, formPct: -35, yesterdayLoad: 400 });
    expect(r.level).toBe('rood');
  });

  it('goede check-in en normale belasting geeft groen', () => {
    const r = recoveryFor({ checkin: { id: 'c', date: '2026-12-01', sleep: 4, legs: 4, energy: 5, calm: 4, updatedAt: 0 }, formPct: -5, yesterdayLoad: 100 });
    expect(r.level).toBe('groen');
  });

  it('belastingsreeks voorspelt komende dagen met het schema', () => {
    const workouts = Array.from({ length: 40 }, (_, i) => ({ id: `w${i}`, date: `2026-10-${String((i % 30) + 1).padStart(2, '0')}`, kind: 'run' as const, title: 'Loop', durationMin: 45, source: 'manual' as const, updatedAt: 0 }));
    const s = loadSeries(workouts, '2026-11-20', '2026-11-27', '2026-11-22');
    expect(s.length).toBe(8);
    expect(s.filter(d => d.planned).length).toBe(5);
    expect(s.find(d => d.date === '2026-11-23')!.load).toBeGreaterThan(0); // maandag: kracht gepland
  });
});

import { progressionHint, repRange } from './progression';

describe('automatisch zwaarder', () => {
  const floor = { name: 'Floor press', weight: '20 kg', sets: 3, reps: '8 tot 10 per arm', defaultKg: 20, defaultReps: 8 };
  it('leest de range', () => {
    expect(repRange('8 tot 10 per arm')).toEqual({ lo: 8, hi: 10 });
    expect(repRange('12')).toEqual({ lo: 12, hi: 12 });
    expect(repRange('bijna max')).toBe(null);
  });
  it('alle sets aan de bovenkant: naar 28 kg', () => {
    const h = progressionHint(floor, [{ reps: 10, weightKg: 20 }, { reps: 10, weightKg: 20 }, { reps: 10, weightKg: 20 }]);
    expect(h?.kg).toBe(28);
    expect(h?.reps).toBe(8);
  });
  it('nog niet alles gehaald: zelfde gewicht', () => {
    const h = progressionHint(floor, [{ reps: 10, weightKg: 20 }, { reps: 9, weightKg: 20 }, { reps: 8, weightKg: 20 }]);
    expect(h?.kg).toBe(20);
    expect(h?.text).toContain('2 sets');
  });
  it('op 28 kg: meer herhalingen of langzamer', () => {
    const h = progressionHint({ ...floor, weight: '28 kg' }, [{ reps: 10, weightKg: 28 }, { reps: 10, weightKg: 28 }, { reps: 10, weightKg: 28 }]);
    expect(h?.text).toContain('langzaam');
  });
  it('bijna max: totaal omhoog', () => {
    const h = progressionHint({ ...floor, reps: 'bijna max', weight: 'lichaamsgewicht' }, [{ reps: 8, weightKg: 0 }, { reps: 7, weightKg: 0 }]);
    expect(h?.text).toContain('17');
  });
});

import { workoutText } from './garmin';

describe('Garmin-trainingen', () => {
  it('tempoloop krijgt inlopen, tempo en uitlopen met hartslagdoelen', () => {
    const t = workoutText({ slotId: 'run-quality', kind: 'run', title: 'Tempoloop, 25 min tempo', minutes: 50 })!;
    expect(t).toContain('- 15m 80-88% LTHR');
    expect(t).toContain('- 25m 90-96% LTHR');
    expect(t).toContain('- 10m 80-88% LTHR');
  });
  it('kracht gaat niet naar Garmin', () => {
    expect(workoutText({ slotId: 'kracht-rug', kind: 'strength', title: 'Kracht', minutes: 30 })).toBe(null);
  });
});

describe('lichte week', () => {
  it('geen zwaarder-advies in een lichte week', () => {
    const h = progressionHint({ name: 'Floor press', weight: '20 kg', sets: 2, reps: '8 tot 10', defaultKg: 20, defaultReps: 8, light: true }, [{ reps: 10, weightKg: 20 }, { reps: 10, weightKg: 20 }]);
    expect(h?.kg).toBe(20);
    expect(h?.text).toContain('Lichte week');
  });
});

import { busyKeep, planForWeek as pfw, BUSY_NOTE } from './plan';
describe('drukke week', () => {
  const busy = [{ id: 'b', week: 2, op: 'busy' as const, a: 0, at: 1, updatedAt: 1 }];
  it('houdt de lange loop (korter), één andere loop en één krachttraining over', () => {
    const before = pfw(2);
    const after = pfw(2, [], busy);
    const train = (d: typeof after) => d.flatMap(x => x.items.filter(i => i.kind !== 'rest' && i.kind !== 'free' && !i.optional));
    const kept = train(after);
    expect(kept.filter(i => i.slotId === 'run-long')).toHaveLength(1);
    expect(kept.filter(i => i.kind === 'run')).toHaveLength(2);
    expect(kept.filter(i => i.kind === 'strength')).toHaveLength(1);
    const longBefore = train(before).find(i => i.slotId === 'run-long')!.minutes!;
    expect(kept.find(i => i.slotId === 'run-long')!.minutes).toBeLessThan(longBefore);
    expect(after[0].weekNote).toBe(BUSY_NOTE);
    expect(after.flatMap(d => d.items).some(i => i.title.startsWith('Vervallen'))).toBe(true);
  });
  it('raakt andere weken en testweken niet', () => {
    expect(pfw(3, [], busy)[0].busy).toBeFalsy();
    const test = [{ ...busy[0], week: 9 }];
    expect(pfw(9, [], test).some(d => d.busy)).toBe(false);
  });
  it('kiest de kern ook als er geen kwaliteitsloop is', () => {
    expect(busyKeep([[], [{ slotId: 'run-easy', kind: 'run', title: 'R' }], [{ slotId: 'kracht-rug', kind: 'strength', title: 'K' }]]).size).toBe(2);
  });
});

describe('drukke week halverwege', () => {
  it('laat gedane dagen staan en telt ze mee voor de kern', () => {
    // Vanaf woensdag: maandag (kracht) en dinsdag (loop) zijn al geweest
    const busy = [{ id: 'b', week: 2, op: 'busy' as const, a: 2, at: 1, updatedAt: 1 }];
    const before = pfw(2);
    const after = pfw(2, [], busy);
    expect(after[0].items).toEqual(before[0].items);
    expect(after[1].items).toEqual(before[1].items);
    const rest = after.slice(2).flatMap(d => d.items.filter(i => i.kind !== 'rest' && i.kind !== 'free' && !i.optional));
    expect(rest.map(i => i.slotId)).toEqual(['run-long']); // kracht en loop zijn al gedaan, alleen de lange loop blijft
  });
});
