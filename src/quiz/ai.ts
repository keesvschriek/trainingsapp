import { hashId } from './bank';
import { catName, type MC } from './model';
import { valid, type PackQuestion } from './packs';

// Nieuwe vragen laten maken met je eigen Anthropic API-sleutel.
// De sleutel blijft op deze telefoon (localStorage) en wordt niet gesynchroniseerd.

const KEY = 'kees.anthropicKey';
export const MODEL = 'claude-haiku-5-5';

export const getKey = () => {
  try { return localStorage.getItem(KEY) ?? ''; } catch { return ''; }
};
export const setKey = (k: string) => {
  try { k ? localStorage.setItem(KEY, k.trim()) : localStorage.removeItem(KEY); } catch { /* geen opslag */ }
};

export function prompt(cat: string, topic: string, n: number, avoid: string[]): string {
  return [
    `Maak ${n} meerkeuzevragen in het Nederlands voor een quiz-app.`,
    `Categorie: ${catName(cat)}${topic ? `. Onderwerp: ${topic}` : ''}.`,
    'Eisen:',
    '- Alleen vaststaande feiten die je zeker weet. Geen actuele cijfers, records of huidige functiehouders.',
    '- Precies vier antwoorden; het eerste is het goede. Foute antwoorden moeten geloofwaardig zijn.',
    '- Een korte uitleg van één zin in "why".',
    '- Varieer in moeilijkheid, van makkelijk tot pittig.',
    '- Geen vragen die lijken op deze: ' + avoid.slice(0, 40).join(' | '),
    `Antwoord uitsluitend met JSON in deze vorm: {"questions":[{"q":"...","a":["goed","fout","fout","fout"],"why":"..."}]}`,
  ].join('\n');
}

export async function generate(key: string, cat: string, topic: string, n: number, avoid: string[]): Promise<MC[]> {
  if (!key) throw new Error('Vul eerst je API-sleutel in.');
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    },
    body: JSON.stringify({ model: MODEL, max_tokens: 4000, messages: [{ role: 'user', content: prompt(cat, topic, n, avoid) }] }),
  });
  if (res.status === 401) throw new Error('Sleutel geweigerd.');
  if (res.status === 429) throw new Error('Te veel verzoeken of tegoed op. Probeer het later.');
  if (!res.ok) throw new Error(`Fout ${res.status} van de API.`);
  const data = (await res.json()) as { content?: { type: string; text?: string }[] };
  const text = (data.content ?? []).filter(c => c.type === 'text').map(c => c.text ?? '').join('');
  return parse(text, cat);
}

export function parse(text: string, cat: string): MC[] {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error('Geen bruikbaar antwoord ontvangen.');
  let json: { questions?: Partial<PackQuestion>[] };
  try {
    json = JSON.parse(text.slice(start, end + 1));
  } catch {
    throw new Error('Antwoord was geen geldige JSON.');
  }
  return (json.questions ?? [])
    .map(q => ({ ...q, cat }))
    .filter(valid)
    .map(q => ({ id: 'a' + hashId(q.q), cat, q: q.q.trim(), a: q.a.map(x => x.trim()), why: q.why, src: 'ai' as const }));
}
