import { describe, expect, it } from 'vitest';
import { splitShared } from './share';

describe('splitShared', () => {
  it('haalt de link uit Chrome-tekst', () => {
    expect(splitShared('Slag om Arnhem https://nl.wikipedia.org/wiki/Slag_om_Arnhem')).toEqual({ url: 'https://nl.wikipedia.org/wiki/Slag_om_Arnhem', title: 'Slag om Arnhem' });
  });
  it('onderwerp gaat voor', () => {
    expect(splitShared('https://nos.nl/l/123', 'Kabinet valt')).toEqual({ url: 'https://nos.nl/l/123', title: 'Kabinet valt' });
  });
  it('zonder link is het tekst', () => {
    expect(splitShared('  Lees dit even  ')).toEqual({ text: 'Lees dit even', title: undefined });
  });
});
