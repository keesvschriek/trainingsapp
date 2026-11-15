import { describe, expect, it } from 'vitest';
import { describeDay } from './widget';
import { planForDay, mondayOfWeek } from './plan';
import { addDays } from './dates';

describe('widget', () => {
  it('beschrijft een loopdag, een krachtdag en de dag voor de start', () => {
    const mon = mondayOfWeek(1);
    const days = Array.from({ length: 7 }, (_, i) => planForDay(addDays(mon, i)));
    const strength = days.find(d => d.items.some(i => i.kind === 'strength'))!;
    const ds = describeDay(strength.items, strength.status);
    expect(ds.title).toMatch(/Kracht/);
    expect(ds.sub).toMatch(/oefeningen/);
    const run = days.find(d => d.items.some(i => i.kind === 'run' && !i.optional) && !d.items.some(i => i.kind === 'strength'))!;
    expect(describeDay(run.items, run.status).sub).toMatch(/LTHR/);
    const before = planForDay(addDays(mon, -1));
    expect(describeDay(before.items, before.status).title).toBe('Nog niet begonnen');
  });
});

import { pullupDay } from './pushups';
describe('pull-ups tussendoor in de widget', () => {
  it('alleen op werkdagen binnen het schema', () => {
    const mon = mondayOfWeek(1);
    expect(pullupDay(planForDay(mon))).toBe(true);
    expect(pullupDay(planForDay(addDays(mon, 5)))).toBe(false); // zaterdag
    expect(pullupDay(planForDay(addDays(mon, -1)))).toBe(false); // voor de start
  });
});
