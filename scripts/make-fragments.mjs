// Fragmenten uit rechtenvrije klassiekers (Project Gutenberg) voor "Fragment van de dag" op de Kobo.
// Draait in GitHub Actions (workflow "Fragmenten maken"); de Kobo haalt alleen deze kleine bestanden op.
import { writeFileSync, mkdirSync } from 'node:fs';

const BOOKS = [7142, 1946, 2680, 132, 1232, 11024];
const KEEP = 250;

function mirrorPath(id) {
  const s = String(id);
  return s.length === 1 ? `0/${s}` : s.slice(0, -1).split('').join('/') + '/' + s;
}

async function fetchText(id) {
  const urls = [
    `https://www.gutenberg.org/cache/epub/${id}/pg${id}.txt`,
    `https://www.gutenberg.org/ebooks/${id}.txt.utf-8`,
    `https://gutenberg.pglaf.org/${mirrorPath(id)}/${id}-0.txt`,
    `https://gutenberg.pglaf.org/${mirrorPath(id)}/${id}.txt`,
    `https://aleph.pglaf.org/${mirrorPath(id)}/${id}-0.txt`,
  ];
  for (const u of urls) {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const r = await fetch(u, { headers: { 'User-Agent': 'KeesStudy/1.0 (persoonlijk gebruik)' } });
        if (r.ok) { const t = await r.text(); if (t.length > 10000) return t; }
        console.log(id, u, r.status);
      } catch (e) { console.log(id, u, String(e)); }
      await new Promise((res) => setTimeout(res, 3000 * (attempt + 1)));
    }
  }
  throw new Error('geen tekst voor ' + id);
}

const isHeading = (l) => l.length > 0 && l.length <= 70 &&
  ((l === l.toUpperCase() && /\p{L}/u.test(l)) || /^(chapter|book)\b/i.test(l));

function cut(text) {
  text = text.replace(/\r\n/g, '\n');
  const a = text.search(/\*\*\* ?START OF[^\n]*\n/);
  if (a >= 0) text = text.slice(text.indexOf('\n', a) + 1);
  const b = text.search(/\*\*\* ?END OF/);
  if (b >= 0) text = text.slice(0, b);
  const all = [];
  let where = null, pos = 0;
  for (const block of text.split(/\n\s*\n/)) {
    pos += block.length + 2;
    const lines = block.split('\n').map((l) => l.trim()).filter(Boolean);
    // kopjes bovenaan een blok (bijv. "39. GREAT SIMPLIFICATION") apart houden
    while (lines.length > 1 && isHeading(lines[0])) where = lines.shift().slice(0, 60);
    const joined = lines.join(' ').replace(/\s+/g, ' ').trim();
    if (lines.length <= 2 && isHeading(joined)) { where = joined.slice(0, 60); continue; }
    const n = joined.split(' ').filter(Boolean).length;
    if (n >= 60 && n <= 230 && !/Gutenberg|http/.test(joined) && !joined.startsWith('[')) {
      all.push({ t: joined.replace(/\[\d+\]/g, '').replace(/_/g, ''), w: where, p: Math.floor((pos / text.length) * 100) });
    }
  }
  if (all.length <= KEEP) return all;
  return Array.from({ length: KEEP }, (_, i) => all[Math.floor((i * all.length) / KEEP)]);
}

mkdirSync('kobo/fragments', { recursive: true });
let failed = 0;
for (const id of BOOKS) {
  try {
    const frags = cut(await fetchText(id));
    if (frags.length < 5) throw new Error('te weinig fragmenten');
    writeFileSync(`kobo/fragments/${id}.json`, JSON.stringify({ id, frags }));
    console.log(id, frags.length, 'fragmenten');
  } catch (e) { console.log('MISLUKT', id, String(e)); failed++; }
  await new Promise((res) => setTimeout(res, 2000));
}
if (failed === BOOKS.length) process.exit(1);
