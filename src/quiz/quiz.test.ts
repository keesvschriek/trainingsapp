import { describe, expect, it } from 'vitest';
import { BANK } from './bank';
import { CATS } from './model';
import { COUNTRIES, matches, byC3 } from './geo/countries';
import { geoSet, sum, sumMatches, mapPool, type MathKind } from './gen';
import { LISTS } from './lists';
import { parse } from './ai';
import { valid } from './packs';
import packs from '../../quiz-packs/index.json';
import { dayStreak, level } from './records';

const seeded = (s: number) => () => ((s = (s * 16807) % 2147483647) - 1) / 2147483646;

describe('vragenbank', () => {
  it('heeft geldige vragen met vier unieke antwoorden en bekende categorie', () => {
    const cats = new Set(CATS.map(c => c.key));
    for (const q of BANK) {
      expect(cats.has(q.cat), q.q).toBe(true);
      expect(q.a.length, q.q).toBe(4);
      expect(new Set(q.a.map(a => a.toLowerCase())).size, q.q).toBe(4);
    }
  });
  it('heeft unieke ids en geen dubbele vragen', () => {
    expect(new Set(BANK.map(q => q.id)).size).toBe(BANK.length);
    expect(new Set(BANK.map(q => q.q)).size).toBe(BANK.length);
  });
  it('is flink gevuld en dekt elke categorie', () => {
    expect(BANK.length).toBeGreaterThan(550);
    for (const c of CATS) expect(BANK.filter(q => q.cat === c.key).length, c.key).toBeGreaterThanOrEqual(8);
  });
  it('geen gedachtestreepjes in teksten', () => {
    for (const q of BANK) expect(`${q.q} ${q.a.join(' ')} ${q.why ?? ''}`, q.q).not.toMatch(/[—–]/);
  });
});

describe('landen', () => {
  it('heeft 196 landen met hoofdstad en vlag', () => {
    expect(COUNTRIES.length).toBe(196);
    for (const c of COUNTRIES) {
      expect(c.cap.length, c.name).toBeGreaterThan(0);
      expect(c.flag, c.name).toBeTruthy();
    }
    expect(byC3.get('NLD')?.cap[0]).toBe('Amsterdam');
    expect(byC3.get('DEU')?.name).toBe('Duitsland');
  });
  it('herkent antwoorden ruim', () => {
    expect(matches('duitsland', ['Duitsland'])).toBe(true);
    expect(matches('Kopenhagen', ['Kopenhagen'])).toBe(true);
    expect(matches('Kopenhagn', ['Kopenhagen'])).toBe(true); // tikfout
    expect(matches('Ivoorkust', ['Ivoorkust'])).toBe(true);
    expect(matches('reykjavik', ['Reykjavík'])).toBe(true);
    expect(matches('Oostenrijk', ['Australië'])).toBe(false);
    expect(matches('Mali', ['Malawi'])).toBe(false);
  });
});

describe('generatoren', () => {
  it('maakt topografievragen zonder dubbele antwoorden', () => {
    const qs = geoSet(['capital', 'countryOfCapital', 'flag', 'highlight', 'borders', 'area', 'landlocked', 'region'], 60, undefined, seeded(3));
    expect(qs.length).toBe(60);
    for (const q of qs) expect(new Set(q.a).size, q.q).toBe(4);
  });
  it('werkt per werelddeel', () => {
    for (const r of ['Europa', 'Afrika', 'Azië', 'Noord-Amerika', 'Zuid-Amerika', 'Oceanië'] as const) {
      expect(geoSet(['flag', 'capital', 'highlight'], 10, r, seeded(7)).length, r).toBe(10);
      expect(mapPool(r).length, r).toBeGreaterThanOrEqual(7);
    }
  });
  it('rekensommen hebben kloppende antwoorden', () => {
    const rnd = seeded(11);
    for (const k of ['mix', 'tafels', 'procent', 'tempo', 'kwadraat'] as MathKind[])
      for (let i = 0; i < 50; i++) {
        const s = sum(k, rnd);
        expect(sumMatches(s.answers[0], s), s.q).toBe(true);
        if (s.q.includes('×')) {
          const [a, b] = s.q.split(' × ').map(Number);
          expect(Number(s.answers[0])).toBe(a * b);
        }
      }
    expect(sumMatches('7,5', { q: '', answers: ['7.5'] })).toBe(true);
    expect(sumMatches('08', { q: '', answers: ['8'] })).toBe(true);
  });
});

describe('lijstjes', () => {
  it('hebben antwoorden en kloppende aantallen', () => {
    const by = Object.fromEntries(LISTS.map(l => [l.key, l]));
    expect(by.provincies.items.length).toBe(12);
    expect(by.eu.items.length).toBe(27);
    expect(by['navo-alfabet'].items.length).toBe(26);
    expect(by.g7.items.length).toBe(7);
    expect(by['buren-de'].items.length).toBe(9);
    expect(by.planeten.items.length).toBe(8);
    for (const l of LISTS) for (const it of l.items) expect(it.answers.length, l.key).toBeGreaterThan(0);
  });
  it('accepteert gangbare varianten', () => {
    const it = LISTS.find(l => l.key === 'provhoofdsteden')!.items.find(i => i.hint === 'Noord-Brabant')!;
    expect(matches('Den Bosch', it.answers)).toBe(true);
  });
});

describe('pakketten en AI', () => {
  it('het pakketbestand in de repo is geldig', () => {
    for (const p of packs.packs) for (const q of p.questions) expect(valid(q), q.q).toBe(true);
  });
  it('leest AI-antwoord met tekst eromheen en filtert slechte vragen', () => {
    const txt = 'Hier: {"questions":[{"q":"Welke kleur heeft de lucht?","a":["Blauw","Rood","Groen","Geel"],"why":"Verstrooiing."},{"q":"Kapot","a":["x","x","y","z"]}]} klaar';
    const out = parse(txt, 'natuur');
    expect(out.length).toBe(1);
    expect(out[0].src).toBe('ai');
  });
});

describe('records', () => {
  it('niveau en dagreeks', () => {
    expect(level(0)).toBe(1);
    expect(level(250)).toBe(2);
    expect(dayStreak(['2026-11-13', '2026-11-14', '2026-11-15'], '2026-11-15')).toBe(3);
    expect(dayStreak(['2026-11-13', '2026-11-14'], '2026-11-15')).toBe(2);
    expect(dayStreak(['2026-11-12'], '2026-11-15')).toBe(0);
  });
});
