// Zet de vragen van Kees Study om naar één JSON-bestand voor de Kobo-app.
// Gebruik: npx tsx scripts/export-kobo.ts kobo/app/data
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { BANK } from '../src/quiz/bank';
import { CATS, GROUPS } from '../src/quiz/model';
import { COUNTRIES } from '../src/quiz/geo/countries';

const out = process.argv[2] ?? 'kobo/app/data';
mkdirSync(out, { recursive: true });

const packs = JSON.parse(readFileSync('quiz-packs/index.json', 'utf8')) as { packs: { id: string; questions: { cat: string; q: string; a: string[]; why?: string; asOf?: string }[] }[] };
const known = new Set(CATS.map(c => c.key));

const questions = [
  ...BANK.map(q => ({ id: q.id, cat: q.cat, q: q.q, a: q.a, why: q.why ?? '', asOf: q.asOf ?? '' })),
  ...packs.packs.flatMap(p => p.questions.filter(q => known.has(q.cat)).map(q => ({ id: 'p:' + p.id + ':' + q.q.length + ':' + q.q.slice(0, 24), cat: q.cat, q: q.q, a: q.a, why: q.why ?? '', asOf: q.asOf ?? '' }))),
];

const data = {
  version: new Date().toISOString().slice(0, 10),
  groups: GROUPS,
  cats: CATS,
  questions,
  countries: COUNTRIES.filter(c => c.region !== 'Overig').map(c => ({ name: c.name, cap: c.cap[0], capAll: [...c.cap, ...c.capAlt], alt: c.alt, region: c.region })),
};
writeFileSync(join(out, 'quiz.json'), JSON.stringify(data));
console.log(`${questions.length} vragen, ${data.countries.length} landen -> ${join(out, 'quiz.json')}`);
