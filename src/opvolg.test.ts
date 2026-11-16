import { describe, expect, it } from 'vitest';
import { dueChoices, dueText, nextWeekday, parseLine, sortOpen } from './opvolg';
import type { Opvolg } from './db';

const MA = '2026-11-16'; // maandag

describe('opvolg', () => {
  it('nextWeekday slaat vandaag over', () => {
    expect(nextWeekday(MA, 0)).toBe('2026-11-23');
    expect(nextWeekday(MA, 4)).toBe('2026-11-20');
  });
  it('parseLine haalt de datum van het eind', () => {
    expect(parseLine('ouders AB bellen morgen', MA, MA)).toEqual({ title: 'Ouders AB bellen', due: '2026-11-17' });
    expect(parseLine('verslag rondsturen vr', MA, MA)).toEqual({ title: 'Verslag rondsturen', due: '2026-11-20' });
    expect(parseLine('rooster checken over 3 dagen', MA, MA).due).toBe('2026-11-19');
    expect(parseLine('agenda maken over 2 weken', MA, MA).due).toBe('2026-11-30');
    expect(parseLine('notulen volgende week', MA, MA).due).toBe('2026-11-23');
    expect(parseLine('gewoon iets', MA, '2026-11-18')).toEqual({ title: 'Gewoon iets', due: '2026-11-18' });
  });
  it('dueText', () => {
    expect(dueText(MA, MA)).toBe('vandaag');
    expect(dueText('2026-11-14', MA)).toBe('2 dagen te laat');
    expect(dueText('2026-11-20', MA)).toBe('vr 20 nov');
  });
  it('dueChoices begint bij vandaag', () => {
    const c = dueChoices(MA);
    expect(c[0]).toEqual({ label: 'Vandaag', date: MA });
    expect(c[2].label).toBe('Woensdag');
  });
  it('sortOpen laat afgeronde weg en sorteert op datum', () => {
    const o = (id: string, due: string, done = false): Opvolg => ({ id, due, done, title: id, createdAt: 0, updatedAt: 0 });
    expect(sortOpen([o('b', '2026-11-20'), o('a', '2026-11-15'), o('c', '2026-11-10', true)]).map(x => x.id)).toEqual(['a', 'b']);
  });
});
