// Maakt een slanke landenlijst (Nederlandse namen, hoofdsteden, regio) en kopieert de wereldkaart.
// Draaien: node scripts/build-geo.mjs
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const all = require('world-countries');
const EXTRA = ['XKX', 'TWN', 'PSE', 'VAT'];

const CAP_NL = {
  Brussels: 'Brussel', Copenhagen: 'Kopenhagen', Vienna: 'Wenen', Prague: 'Praag', Warsaw: 'Warschau', Lisbon: 'Lissabon',
  Athens: 'Athene', Moscow: 'Moskou', Beijing: 'Peking', Bucharest: 'Boekarest', Belgrade: 'Belgrado', Kyiv: 'Kiev',
  'Mexico City': 'Mexico-Stad', Cairo: 'Caïro', Baghdad: 'Bagdad', Tehran: 'Teheran', Riyadh: 'Riyad', Tokyo: 'Tokio',
  Luxembourg: 'Luxemburg', 'Kuwait City': 'Koeweit-Stad', Beirut: 'Beiroet', Muscat: 'Masqat', Yerevan: 'Jerevan',
  'Addis Ababa': 'Addis Abeba', Khartoum: 'Khartoem', 'Washington D.C.': 'Washington', 'Vatican City': 'Vaticaanstad',
  'Guatemala City': 'Guatemala-Stad', 'Panama City': 'Panama-Stad', 'Mogadishu': 'Mogadishu', Algiers: 'Algiers',
  'Sanaʽa': 'Sanaa', "Sana'a": 'Sanaa', Havana: 'Havana', Tunis: 'Tunis', Tripoli: 'Tripoli', Damascus: 'Damascus',
  'City of San Marino': 'San Marino', Monaco: 'Monaco', Singapore: 'Singapore', 'Port Louis': 'Port Louis',
  'Kingstown': 'Kingstown', Nicosia: 'Nicosia', Valletta: 'Valletta', Reykjavik: 'Reykjavik', Chișinău: 'Chisinau',
  'Tbilisi': 'Tbilisi', Ulan: 'Ulaanbaatar', 'Ulan Bator': 'Ulaanbaatar', Pyongyang: 'Pyongyang', Seoul: 'Seoel',
  London: 'Londen', Paris: 'Parijs', Berlin: 'Berlijn', 'Cape Town': 'Kaapstad', 'New Delhi': 'New Delhi', 'Kathmandu': 'Kathmandu', 'Hanoi': 'Hanoi', 'Taipei': 'Taipei', 'Jerusalem': 'Jeruzalem', 'Rome': 'Rome',
};
const REGION = c => {
  if (c.region === 'Europe') return 'Europa';
  if (c.region === 'Asia') return 'Azië';
  if (c.region === 'Africa') return 'Afrika';
  if (c.region === 'Oceania') return 'Oceanië';
  if (c.region === 'Americas') return c.subregion === 'South America' ? 'Zuid-Amerika' : 'Noord-Amerika';
  return 'Overig';
};
const EXTRA_CAP = { BOL: ['La Paz'], CIV: ['Abidjan'] };
const list = all
  .filter(c => c.unMember || EXTRA.includes(c.cca3))
  .map(c => {
    const name = c.translations?.nld?.common ?? c.name.common;
    const caps = (c.capital ?? []).filter(Boolean);
    const capNl = caps.map(x => CAP_NL[x] ?? x);
    const alt = [...new Set([c.name.common, c.name.official, c.translations?.nld?.official, ...(c.altSpellings ?? [])].filter(x => x && x !== name))].slice(0, 6);
    return {
      c2: c.cca2, c3: c.cca3, n3: c.ccn3, name, alt, cap: capNl, capAlt: [...caps.filter((x, i) => x !== capNl[i]), ...(EXTRA_CAP[c.cca3] ?? [])],
      region: REGION(c), sub: c.subregion, area: Math.round(c.area), flag: c.flag, borders: c.borders ?? [],
      eu: false, landlocked: !!c.landlocked,
    };
  })
  .sort((a, b) => a.name.localeCompare(b.name, 'nl'));
const EU = ['AUT','BEL','BGR','HRV','CYP','CZE','DNK','EST','FIN','FRA','DEU','GRC','HUN','IRL','ITA','LVA','LTU','LUX','MLT','NLD','POL','PRT','ROU','SVK','SVN','ESP','SWE'];
for (const c of list) c.eu = EU.includes(c.c3);
fs.writeFileSync('src/quiz/geo/countries.json', JSON.stringify(list));
fs.copyFileSync(require.resolve('world-atlas/countries-50m.json'), 'public/geo/world-50m.json');
console.log(list.length, 'landen', (JSON.stringify(list).length / 1024).toFixed(0) + 'KB');
