import { describe, expect, it } from 'vitest';
import { QUESTIONS } from './questions';
import { ALL_CATS, pick } from './trivia';

describe('trivia', () => {
  it('heeft genoeg goede vragen, zonder dubbele antwoorden', () => {
    expect(QUESTIONS.length).toBeGreaterThan(150);
    for (const q of QUESTIONS) {
      expect(new Set(q.a).size, q.q).toBe(4);
      expect(q.why.length, q.q).toBeGreaterThan(5);
    }
    expect(new Set(QUESTIONS.map(q => q.q)).size).toBe(QUESTIONS.length);
  });

  it('husselt de antwoorden en onthoudt welk antwoord goed is', () => {
    let seed = 1;
    const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    for (let i = 0; i < 50; i++) {
      const s = pick([], ALL_CATS, rnd);
      expect(s.options[s.correct]).toBe(s.q.a[0]);
      expect([...s.options].sort()).toEqual([...s.q.a].sort());
    }
  });

  it('kiest eerst vragen die je nog niet had en blijft binnen je categorieën', () => {
    const sport = QUESTIONS.filter(q => q.cat === 'sport').map(q => q.id);
    const s = pick(sport.slice(1), ['sport']);
    expect(s.q.id).toBe(sport[0]);
    expect(pick([], ['ict']).q.cat).toBe('ict');
  });
});
