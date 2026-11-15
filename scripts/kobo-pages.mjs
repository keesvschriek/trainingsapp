// Zet de Kobo-app op GitHub Pages (dist/kobo) met een manifest, zodat de app zichzelf via wifi kan bijwerken.
// Gebruik na het exporteren van de data: node scripts/kobo-pages.mjs dist/kobo
import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const out = process.argv[2] ?? 'dist/kobo';
const version = process.env.KOBO_VERSION ?? new Date().toISOString().slice(0, 10);
const files = [];

function add(src, path) {
  const dest = join(out, 'files', path);
  mkdirSync(dirname(dest), { recursive: true });
  copyFileSync(src, dest);
  const buf = readFileSync(src);
  files.push({ p: path, md5: createHash('md5').update(buf).digest('hex'), size: statSync(src).size });
}

for (const f of readdirSync('kobo/app')) if (f.endsWith('.lua')) add(join('kobo/app', f), f);
for (const f of readdirSync('kobo/app/data')) if (f.endsWith('.json')) add(join('kobo/app/data', f), 'data/' + f);
add('kobo/install/patches/2-kees-study.lua', 'patches/2-kees-study.lua');
// NickelMenu-item (de app slaat dit over als NickelMenu er niet is)
add('kobo/install/nm/kees_study', 'nm/kees_study');

// Wat er nieuw is: de punten onder de eerste ## in kobo/CHANGELOG.md
const log = readFileSync('kobo/CHANGELOG.md', 'utf8').split('\n## ')[1] ?? '';
const changes = log.split('\n').filter((l) => l.startsWith('- ')).map((l) => l.slice(2).trim());

writeFileSync(join(out, 'manifest.json'), JSON.stringify({ version, changes, files }, null, 1));
console.log(`kobo: ${files.length} bestanden, versie ${version}`);
