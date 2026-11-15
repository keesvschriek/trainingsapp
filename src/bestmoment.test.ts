import { describe as d, expect, it } from 'vitest';
import { bestMoments, describe, pickMoments, type HourWeather } from './bestmoment';

const day = (rainAt: number[] = []): HourWeather[] =>
  Array.from({ length: 24 }, (_, hour) => ({ hour, temp: 6, rain: rainAt.includes(hour) ? 2 : 0, prob: rainAt.includes(hour) ? 80 : 10, wind: 12 }));

d('beste loopmoment', () => {
  const base = { minutes: 45, nowMin: 7 * 60, sunriseMin: 8 * 60, sunsetMin: 16 * 60 + 40, busy: [] as [number, number][] };

  it('kiest een droog en licht moment', () => {
    const { best } = pickMoments({ ...base, hours: day([12, 13]) });
    expect(best).toBeDefined();
    expect(best!.rain).toBe(0);
    expect(best!.dark).toBe(false);
    expect(best!.start >= 8 * 60 && best!.end <= 16 * 60 + 40).toBe(true);
    expect(best!.start >= 14 * 60 || best!.end <= 12 * 60).toBe(true);
  });

  it('plant niet tijdens werk en niet in het verleden', () => {
    const list = bestMoments({ ...base, nowMin: 6 * 60, hours: day(), busy: [[7 * 60 + 30, 18 * 60]] });
    expect(list.length).toBeGreaterThan(0);
    for (const m of list) expect(m.end <= 7 * 60 + 30 || m.start >= 18 * 60).toBe(true);
    const later = bestMoments({ ...base, nowMin: 19 * 60, hours: day() });
    for (const m of later) expect(m.start).toBeGreaterThanOrEqual(19 * 60 + 10);
  });

  it('kiest op een werkdag tussen ochtend en avond op basis van regen', () => {
    const { best, alt } = pickMoments({ ...base, nowMin: 6 * 60, hours: day([19, 20]), busy: [[7 * 60 + 30, 18 * 60]] });
    expect(best!.end).toBeLessThanOrEqual(7 * 60 + 30); // ochtend, want 's avonds regen
    expect(alt).toBeDefined();
  });

  it('beschrijft het moment in gewone woorden', () => {
    expect(describe({ start: 0, end: 45, score: 0, rain: 0, prob: 10, dark: false, temp: 6 })).toBe('droog, licht, voelt als 6°');
  });
});
