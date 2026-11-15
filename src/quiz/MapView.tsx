import { useEffect, useMemo, useRef, useState, type PointerEvent as RPE, type WheelEvent as RWE } from 'react';
import { geoMercator, geoNaturalEarth1, geoPath, type GeoProjection } from 'd3-geo';
import { feature } from 'topojson-client';
import type { Feature, FeatureCollection, Geometry } from 'geojson';
import type { GeometryCollection, Topology } from 'topojson-specification';
import { byC3, byN3, type Region } from './geo/countries';

// Wereldkaart uit Natural Earth (via world-atlas). Wordt pas geladen als je een kaartvraag opent.

type F = Feature<Geometry, { name: string }> & { id?: string };
let cache: Promise<F[]> | null = null;

// Gebieden zonder eigen code tekenen we bij het land waar ze in de praktijk bij horen.
const FIX: Record<string, string | undefined> = { Kosovo: byC3.get('XKX')?.n3, Somaliland: '706', 'N. Cyprus': '196' };

export function loadWorld(): Promise<F[]> {
  if (!cache) {
    cache = fetch(`${import.meta.env.BASE_URL}geo/world-50m.json`)
      .then(r => {
        if (!r.ok) throw new Error('Kaart niet gevonden');
        return r.json() as Promise<Topology>;
      })
      .then(topo => {
        const fc = feature(topo, topo.objects.countries as GeometryCollection<{ name: string }>) as FeatureCollection<Geometry, { name: string }>;
        return fc.features.map(f => ({ ...f, id: (f.id as string | undefined) || FIX[f.properties.name] })) as F[];
      })
      .catch(e => {
        cache = null;
        throw e;
      });
  }
  return cache;
}

const BOX: Record<Region, [number, number, number, number]> = {
  Europa: [-24, 34, 44, 71],
  Afrika: [-19, -36, 53, 38],
  Azië: [26, -11, 146, 55],
  'Noord-Amerika': [-168, 6, -52, 72],
  'Zuid-Amerika': [-83, -56, -34, 13],
  Oceanië: [112, -48, -168, 2], // over de datumgrens heen
};

export type Mark = 'target' | 'right' | 'wrong' | 'dim';

interface Props {
  region?: Region;
  marks?: Record<string, Mark>; // op c3
  clickable?: Set<string>; // c3-codes die je mag aantikken
  onPick?: (c3: string) => void;
  focus?: string; // c3: kaart op dit land richten (voor een klein kaartje bij een vraag)
  height?: number;
  zoom?: boolean; // knijpen, slepen en knoppen om in te zoomen
}

export function MapView({ region, marks = {}, clickable, onPick, focus, height = 320, zoom = false }: Props) {
  const [world, setWorld] = useState<F[] | null>(null);
  const [err, setErr] = useState('');
  useEffect(() => {
    let live = true;
    loadWorld().then(w => live && setWorld(w), e => live && setErr(String(e.message ?? e)));
    return () => { live = false; };
  }, []);

  const W = 600;
  const H = Math.round((W * height) / 360);
  const z = useZoom(W, H, zoom); // voor de vroege returns: hooks altijd in dezelfde volgorde
  const paths = useMemo(() => {
    if (!world) return [];
    let proj: GeoProjection;
    if (focus) {
      const f = world.find(x => x.id === byC3.get(focus)?.n3);
      proj = geoMercator();
      if (f) {
        // Ruime uitsnede rond het land zodat je de omgeving herkent
        const [[x0, y0], [x1, y1]] = boundsDeg(f);
        const pad = Math.max(8, (x1 - x0) * 1.6, (y1 - y0) * 1.6);
        proj.fitExtent([[6, 6], [W - 6, H - 6]], box([x0 - pad, Math.max(-75, y0 - pad * 0.7), x1 + pad, Math.min(80, y1 + pad * 0.7)]));
      }
    } else if (region) {
      proj = geoMercator().rotate([region === 'Oceanië' ? -160 : 0, 0]).fitExtent([[4, 4], [W - 4, H - 4]], box(BOX[region]));
    } else {
      proj = geoNaturalEarth1().fitExtent([[4, 4], [W - 4, H - 4]], box([-169, -56, 179, 76]));
    }
    const path = geoPath(proj);
    const items = world.filter(f => f.id !== '010').map(f => { // zonder Antarctica
      const c = f.id ? byN3.get(f.id) : undefined;
      return { f, key: `${f.id ?? f.properties.name}-${f.properties.name}`, c3: c?.c3, d: path(f) ?? '', area: path.area(f), dot: null as [number, number] | null };
    });
    // Een rondje bij landen die als geheel te klein zijn om aan te tikken (alleen op het grootste stuk)
    const biggest = new Map<string, (typeof items)[number]>();
    for (const it of items) if (it.c3 && (!biggest.has(it.c3) || biggest.get(it.c3)!.area < it.area)) biggest.set(it.c3, it);
    for (const it of biggest.values()) if (it.area < 60) it.dot = path.centroid(it.f);
    return items;
  }, [world, region, focus, H]);

  if (err) return <div className="empty">Kaart laden mislukt: {err}</div>;
  if (!world) return <div className="map-wrap" style={{ aspectRatio: `${W} / ${H}` }}><div className="empty">Kaart laden...</div></div>;

  const showDots = !!(region || focus || z.t.k >= 2.5);

  return (
    <div className="map-wrap">
      <svg
        ref={z.ref}
        viewBox={`0 0 ${W} ${H}`}
        className={`map${zoom ? ' zoomable' : ''}`}
        role="img"
        aria-label="Kaart"
        onPointerDown={z.down}
        onPointerMove={z.move}
        onPointerUp={z.up}
        onPointerCancel={z.up}
        onWheel={z.wheel}
      >
        <rect width={W} height={H} className="map-sea" />
        <g transform={`translate(${z.t.x} ${z.t.y}) scale(${z.t.k})`}>
          {paths.map(p => {
            const m = p.c3 ? marks[p.c3] : undefined;
            const can = !!(p.c3 && onPick && (!clickable || clickable.has(p.c3)));
            return (
              <g key={p.key} data-c3={p.c3} onClick={can ? () => !z.dragged() && onPick!(p.c3!) : undefined}>
                <path d={p.d} className={`map-land${m ? ' ' + m : ''}${can ? ' can' : ''}`} />
                {/* Kleine landen krijgen een rondje, zodat je ze kunt zien en aantikken */}
                {p.dot && showDots && (can || m) && Number.isFinite(p.dot[0]) && (
                  <circle cx={p.dot[0]} cy={p.dot[1]} r={(can ? 9 : 6) / Math.sqrt(z.t.k)} className={`map-dot${m ? ' ' + m : ''}`} />
                )}
              </g>
            );
          })}
        </g>
      </svg>
      {zoom && (
        <div className="map-zoom">
          <button type="button" onClick={() => z.step(1.6)} aria-label="Inzoomen">+</button>
          <button type="button" onClick={() => z.step(1 / 1.6)} aria-label="Uitzoomen">−</button>
          {z.t.k > 1.01 && <button type="button" onClick={z.reset} aria-label="Hele kaart">⤢</button>}
        </div>
      )}
    </div>
  );
}

// Inzoomen met twee vingers, slepen met één vinger, scrollwiel op de computer.
interface T { k: number; x: number; y: number }
const MAXK = 14;

function useZoom(W: number, H: number, on: boolean) {
  const ref = useRef<SVGSVGElement>(null);
  const [t, setT] = useState<T>({ k: 1, x: 0, y: 0 });
  const pts = useRef(new Map<number, { x: number; y: number }>());
  const last = useRef<{ t: T; d: number; mx: number; my: number; sx: number; sy: number } | null>(null);
  const moved = useRef(false);

  const clamp = (n: T): T => {
    const k = Math.min(MAXK, Math.max(1, n.k));
    return { k, x: Math.min(0, Math.max(W - W * k, n.x)), y: Math.min(0, Math.max(H - H * k, n.y)) };
  };
  // schermpunt naar svg-coördinaat
  const toSvg = (cx: number, cy: number) => {
    const r = ref.current!.getBoundingClientRect();
    return { x: ((cx - r.left) / r.width) * W, y: ((cy - r.top) / r.height) * H };
  };
  const zoomAt = (base: T, factor: number, px: number, py: number): T => {
    const k = Math.min(MAXK, Math.max(1, base.k * factor));
    const f = k / base.k;
    return clamp({ k, x: px - (px - base.x) * f, y: py - (py - base.y) * f });
  };
  const snapshot = (cur: T) => {
    const p = [...pts.current.values()];
    const mx = p.reduce((a, b) => a + b.x, 0) / p.length;
    const my = p.reduce((a, b) => a + b.y, 0) / p.length;
    const d = p.length > 1 ? Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y) : 0;
    last.current = { t: cur, d, mx, my, sx: mx, sy: my };
  };

  return {
    ref,
    t,
    dragged: () => moved.current,
    down: (e: RPE<SVGSVGElement>) => {
      if (!on) return;
      if (pts.current.size === 0) moved.current = false;
      pts.current.set(e.pointerId, toSvg(e.clientX, e.clientY));
      snapshot(t);
    },
    move: (e: RPE<SVGSVGElement>) => {
      if (!on || !pts.current.has(e.pointerId) || !last.current) return;
      pts.current.set(e.pointerId, toSvg(e.clientX, e.clientY));
      const p = [...pts.current.values()];
      const mx = p.reduce((a, b) => a + b.x, 0) / p.length;
      const my = p.reduce((a, b) => a + b.y, 0) / p.length;
      const L = last.current;
      if (Math.hypot(mx - L.sx, my - L.sy) > 8 || p.length > 1) moved.current = true;
      if (!moved.current) return;
      let n: T = { ...L.t, x: L.t.x + (mx - L.mx), y: L.t.y + (my - L.my) };
      if (p.length > 1 && L.d > 0) {
        const d = Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y);
        n = zoomAt(n, d / L.d, mx, my);
      }
      setT(clamp(n));
    },
    up: (e: RPE<SVGSVGElement>) => {
      if (!on) return;
      pts.current.delete(e.pointerId);
      setT(cur => {
        if (pts.current.size) snapshot(cur);
        else last.current = null;
        return cur;
      });
    },
    wheel: (e: RWE<SVGSVGElement>) => {
      if (!on) return;
      const p = toSvg(e.clientX, e.clientY);
      setT(cur => zoomAt(cur, e.deltaY < 0 ? 1.25 : 0.8, p.x, p.y));
    },
    step: (f: number) => setT(cur => zoomAt(cur, f, W / 2, H / 2)),
    reset: () => setT({ k: 1, x: 0, y: 0 }),
  };
}

function box([x0, y0, x1, y1]: [number, number, number, number]) {
  return { type: 'MultiPoint' as const, coordinates: [[x0, y0], [x1, y0], [x0, y1], [x1, y1]] };
}

/** Grenzen in graden, met het grootste deel van een land (geen verre eilanden). */
function boundsDeg(f: F): [[number, number], [number, number]] {
  const polys: number[][][][] = f.geometry.type === 'Polygon' ? [(f.geometry as { coordinates: number[][][] }).coordinates] : f.geometry.type === 'MultiPolygon' ? (f.geometry as { coordinates: number[][][][] }).coordinates : [];
  // grootste ring op aantal punten als benadering van het hoofdland
  const main = polys.sort((a, b) => b[0].length - a[0].length)[0]?.[0] ?? [[0, 0]];
  let x0 = 180, y0 = 90, x1 = -180, y1 = -90;
  for (const [x, y] of main) {
    x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
  }
  return [[x0, y0], [x1, y1]];
}
