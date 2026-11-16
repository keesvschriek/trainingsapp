// Fragmenten uit rechtenvrije klassiekers (Project Gutenberg) voor "Fragment van de dag" op de Kobo.
// Draait in GitHub Actions (workflow "Fragmenten maken"); de Kobo haalt alleen deze kleine bestanden op.
import { writeFileSync, mkdirSync } from 'node:fs';

const BOOKS = [7142, 1946, 2680, 132, 1232, 11024];
// Waar de eigenlijke tekst begint (na de inleiding van de vertaler)
const START = { 132: /^\s*(Chapter )?I\.\s+LAYING PLANS/gim, 1232: /^\s*CHAPTER I\b/gm };
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

// Delen die je niet als fragment wilt: inhoudsopgave, register, noten, bronnen
const SKIP_SECTION = /^(introduction|preface|translator|contents|table of contents|index|notes|footnotes|bibliography|appendix|glossary|chronolog|inhoud|register|aanteekening|aantekening|noten|bijlage|transcriber)/i;

// Lijkt dit stuk op gewone lopende tekst?
function isProse(lines, joined) {
  const letters = joined.replace(/[^\p{L}]/gu, '');
  if (letters.length < 200) return false;
  const lower = joined.replace(/[^\p{Ll}]/gu, '').length;
  if (lower / letters.length < 0.85) return false;                 // veel hoofdletters: titels, opsommingen
  const digits = joined.replace(/[^0-9]/g, '').length;
  if (digits / joined.length > 0.02) return false;                  // paginanummers, jaartallen-lijsten
  const avgLine = lines.reduce((a, l) => a + l.length, 0) / lines.length;
  if (lines.length > 2 && avgLine < 45) return false;               // korte regels: inhoudsopgave of gedicht
  const sentences = (joined.match(/[.!?]["')\]]?(\s|$)/g) || []).length;
  if (sentences < 2) return false;
  if (/\.{4,}|\bp\.\s*\d|\bibid\b|\bop\. cit\b/i.test(joined)) return false;
  return true;
}

const isHeading = (l) => l.length > 0 && l.length <= 70 &&
  ((l === l.toUpperCase() && /\p{L}/u.test(l)) || /^(chapter|book)\b/i.test(l));

function cut(text, id) {
  text = text.replace(/\r\n/g, '\n');
  const a = text.search(/\*\*\* ?START OF[^\n]*\n/);
  if (a >= 0) text = text.slice(text.indexOf('\n', a) + 1);
  const b = text.search(/\*\*\* ?END OF/);
  if (b >= 0) text = text.slice(0, b);
  // laatste treffer: de eerste staat meestal in de inhoudsopgave
  if (START[id]) { const all = [...text.matchAll(START[id])]; if (all.length) text = text.slice(all[all.length - 1].index); }
  const all = [];
  let where = null, pos = 0, skipping = false;
  // korte alinea's (zoals de genummerde spreuken van Sun Tzu) samenvoegen tot een fragment
  let buf = [], bufWhere = null;
  const flushBuf = () => {
    if (buf.length) {
      const t = buf.join(' ');
      const n = t.split(' ').length;
      if (n >= 50) all.push({ t: t.replace(/\[\d+\]/g, '').replace(/_/g, ''), w: bufWhere, p: Math.floor((pos / text.length) * 100) });
    }
    buf = []; bufWhere = null;
  };
  for (const block of text.split(/\n\s*\n/)) {
    pos += block.length + 2;
    const lines = block.split('\n').map((l) => l.trim()).filter(Boolean);
    // kopjes bovenaan een blok (bijv. "39. GREAT SIMPLIFICATION") apart houden
    while (lines.length > 1 && isHeading(lines[0])) { flushBuf(); where = lines.shift().slice(0, 60); skipping = SKIP_SECTION.test(where); }
    const joined = lines.join(' ').replace(/\s+/g, ' ').trim();
    if (lines.length <= 2 && isHeading(joined)) { flushBuf(); where = joined.slice(0, 60); skipping = SKIP_SECTION.test(where); continue; }
    if (skipping) continue;
    const frac = pos / text.length;
    if (frac < 0.03 || frac > 0.94) continue;                       // voorwerk en nawerk overslaan
    const n = joined.split(' ').filter(Boolean).length;
    // korte gewone zin(nen): bewaren tot er genoeg is voor een fragment
    if (n >= 8 && n < 60 && !joined.startsWith('[') && /[.!?]["')]?$/.test(joined) && !/\d{3,}/.test(joined) && joined.replace(/[^\p{Ll}]/gu, '').length / Math.max(1, joined.replace(/[^\p{L}]/gu, '').length) > 0.85) {
      if (!buf.length) bufWhere = where;
      buf.push(joined);
      if (buf.join(' ').split(' ').length >= 110) flushBuf();
      continue;
    }
    flushBuf();
    if (n >= 60 && n <= 230 && !/Gutenberg|http/.test(joined) && !joined.startsWith('[') && isProse(lines, joined)) {
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
    const frags = cut(await fetchText(id), id);
    if (frags.length < 5) throw new Error('te weinig fragmenten');
    writeFileSync(`kobo/fragments/${id}.json`, JSON.stringify({ id, v: 2, frags }));
    console.log(id, frags.length, 'fragmenten');
  } catch (e) { console.log('MISLUKT', id, String(e)); failed++; }
  await new Promise((res) => setTimeout(res, 2000));
}
if (failed === BOOKS.length) process.exit(1);
