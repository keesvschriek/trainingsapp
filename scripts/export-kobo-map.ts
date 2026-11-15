// Projecteert de wereldkaart vooraf per werelddeel naar pixelcoördinaten voor de Kobo.
// Gebruik: npx tsx scripts/export-kobo-map.ts kobo/app/data
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { geoMercator, geoNaturalEarth1, geoPath, type GeoProjection } from 'd3-geo';
import { feature } from 'topojson-client';
import type { Topology, GeometryCollection } from 'topojson-specification';
import type { FeatureCollection, Geometry } from 'geojson';
import { byC3, byN3, COUNTRIES } from '../src/quiz/geo/countries';
import { mapPool } from '../src/quiz/gen';

const out = process.argv[2] ?? 'kobo/app/data';
mkdirSync(out, { recursive: true });

const topo = JSON.parse(readFileSync('public/geo/world-50m.json', 'utf8')) as Topology;
const fc = feature(topo, topo.objects.countries as GeometryCollection<{ name: string }>) as FeatureCollection<Geometry, { name: string }>;
const FIX: Record<string, string | undefined> = { Kosovo: byC3.get('XKX')?.n3, Somaliland: '706', 'N. Cyprus': '196' };
const features = fc.features
  .map(f => ({ ...f, id: (f.id as string | undefined) || FIX[f.properties.name] }))
  .filter(f => f.id !== '010'); // zonder Antarctica

type Box = [number, number, number, number];
const REGIONS: { key: string; region?: Parameters<typeof mapPool>[0]; w: number; h: number; box?: Box; rotate?: number }[] = [
  { key: 'Wereld', w: 1000, h: 520 },
  { key: 'Europa', region: 'Europa', w: 1000, h: 1000, box: [-24, 34, 44, 71] },
  { key: 'Afrika', region: 'Afrika', w: 1000, h: 1000, box: [-19, -36, 53, 38] },
  { key: 'Azië', region: 'Azië', w: 1000, h: 820, box: [26, -11, 146, 55] },
  { key: 'Noord-Amerika', region: 'Noord-Amerika', w: 1000, h: 900, box: [-168, 6, -52, 72] },
  { key: 'Zuid-Amerika', region: 'Zuid-Amerika', w: 1000, h: 1100, box: [-83, -56, -34, 13] },
  { key: 'Oceanië', region: 'Oceanië', w: 1000, h: 820, box: [112, -48, -168, 2], rotate: -160 },
];

const corners = ([x0, y0, x1, y1]: Box) => ({ type: 'MultiPoint' as const, coordinates: [[x0, y0], [x1, y0], [x0, y1], [x1, y1]] });

const result: Record<string, unknown> = {};
let points = 0;
for (const R of REGIONS) {
  let proj: GeoProjection;
  if (R.box) proj = geoMercator().rotate([R.rotate ?? 0, 0]).fitExtent([[4, 4], [R.w - 4, R.h - 4]], corners(R.box));
  else proj = geoNaturalEarth1().fitExtent([[4, 4], [R.w - 4, R.h - 4]], corners([-169, -56, 179, 76]));
  proj.clipExtent([[-2, -2], [R.w + 2, R.h + 2]]);
  const pool = new Set((R.region ? mapPool(R.region) : mapPool(undefined)).map(c => c.c3));
  const countries: { c3?: string; n?: string; t: number; rings: number[][]; cx?: number; cy?: number; a: number }[] = [];
  for (const f of features) {
    const rings: number[][] = [];
    let cur: number[] | null = null;
    // Pad opvangen als losse ringen, afgerond op hele pixels
    const ctx = {
      moveTo(x: number, y: number) { cur = [Math.round(x), Math.round(y)]; rings.push(cur); },
      lineTo(x: number, y: number) {
        if (!cur) return;
        const rx = Math.round(x), ry = Math.round(y);
        if (cur[cur.length - 2] !== rx || cur[cur.length - 1] !== ry) cur.push(rx, ry);
      },
      closePath() { cur = null; },
      arc() {},
    };
    geoPath(proj, ctx as never)(f);
    const kept = rings.filter(r => r.length >= 6);
    if (!kept.length) continue;
    const c = f.id ? byN3.get(f.id) : undefined;
    const area = Math.abs(geoPath(proj).area(f));
    const [cx, cy] = geoPath(proj).centroid(f);
    countries.push({ c3: c?.c3, n: c?.name, t: c && pool.has(c.c3) ? 1 : 0, rings: kept, cx: Number.isFinite(cx) ? Math.round(cx) : undefined, cy: Number.isFinite(cy) ? Math.round(cy) : undefined, a: Math.round(area) });
    points += kept.reduce((s, r) => s + r.length / 2, 0);
  }
  result[R.key] = { w: R.w, h: R.h, countries };
}
writeFileSync(join(out, 'map.json'), JSON.stringify(result));
console.log(`kaart: ${points} punten, ${(JSON.stringify(result).length / 1024).toFixed(0)} kB`);
void COUNTRIES;
