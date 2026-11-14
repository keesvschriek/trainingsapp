import { useEffect, useRef, type ReactNode } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, type Block, type Move } from './db';

// ---------- Iconen (eenvoudige lijnen) ----------
const svg = (d: ReactNode) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">{d}</svg>
);
export const Icon = {
  today: svg(<><rect x="3" y="4.5" width="18" height="16" rx="2" /><path d="M3 9.5h18M8 2.5v4M16 2.5v4" /><path d="M8.5 14.5l2.2 2.2 4.8-4.8" /></>),
  plan: svg(<><path d="M4 6h16M4 12h16M4 18h10" /></>),
  log: svg(<><path d="M6 3.5h9l3 3V20.5H6z" /><path d="M9 10h6M9 14h6M9 18h4" /></>),
  chart: svg(<><path d="M4 20V4M4 20h16" /><path d="M7.5 15l4-5 3 3 4.5-6" /></>),
  gear: svg(<><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z" /></>),
  left: svg(<path d="M15 5l-7 7 7 7" />),
  right: svg(<path d="M9 5l7 7-7 7" />),
  close: svg(<path d="M6 6l12 12M18 6L6 18" />),
  check: svg(<path d="M5 12.5l4.5 4.5L19 7.5" />),
  plus: svg(<path d="M12 5v14M5 12h14" />),
  trash: svg(<><path d="M4 7h16M10 11v6M14 11v6" /><path d="M6 7l1 13h10l1-13M9 7V4h6v3" /></>),
  run: svg(<><circle cx="14.5" cy="4.5" r="1.8" /><path d="M10 21l2.5-5.5L15 17v4M7.5 12.5l2-3.5 4 1 2.5 3.5 3 .5" /><path d="M9.5 9L7 8.5 5 11" /></>),
  kettlebell: svg(<><path d="M8.5 8.5a3.5 3.5 0 1 1 7 0" /><path d="M7 9.5h10l1.5 3.5a6.5 6.5 0 0 1-13 0z" /><path d="M7.5 20.5h9" /></>),
  flag: svg(<><path d="M5 21V4" /><path d="M5 4h11l-2 4 2 4H5" /></>),
  moon: svg(<path d="M19 14.5A7.5 7.5 0 0 1 9.5 5a7.5 7.5 0 1 0 9.5 9.5z" />),
  down: svg(<path d="M6 9l6 6 6-6" />),
  dash: svg(<path d="M7 12h10" />),
  dotc: svg(<circle cx="12" cy="12" r="3.2" />),
};

/** Hoogtelijnen, als lichte achtergrond. */
export function Contour(props: { className?: string }) {
  return (
    <svg className={props.className} viewBox="0 0 280 220" fill="none" stroke="currentColor" strokeWidth={1.2} aria-hidden="true">
      {[0, 1, 2, 3, 4, 5, 6, 7].map(i => (
        <path key={i} d={`M ${-20 + i * 6} ${200 - i * 4} C ${40 + i * 4} ${150 - i * 14}, ${80 + i * 6} ${190 - i * 22}, ${140} ${120 - i * 12} S ${230 - i * 4} ${60 - i * 6}, ${300} ${70 - i * 9}`} />
      ))}
      {[0, 1, 2, 3].map(i => (
        <ellipse key={`e${i}`} cx={190} cy={70} rx={18 + i * 14} ry={11 + i * 9} transform={`rotate(-18 190 70)`} />
      ))}
    </svg>
  );
}

// ---------- Volledig-scherm sheet ----------
export function Sheet(props: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode; action?: ReactNode }) {
  const closeRef = useRef(props.onClose);
  closeRef.current = props.onClose;
  useEffect(() => {
    document.body.style.overflow = 'hidden';
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && closeRef.current();
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = '';
      window.removeEventListener('keydown', onKey);
    };
  }, []);
  return (
    <div className="sheet" role="dialog" aria-label={props.title}>
      <header>
        <h1>{props.title}</h1>
        <div className="row">
          {props.action}
          <button className="icon-btn" onClick={props.onClose} aria-label="Sluiten">{Icon.close}</button>
        </div>
      </header>
      <div className="content">{props.children}</div>
      {props.footer && <footer>{props.footer}</footer>}
    </div>
  );
}

// ---------- Data-hooks ----------
export function useBlocks(): Block[] {
  return useLiveQuery(async () => (await db.blocks.toArray()).filter(alive).sort((a, b) => a.start.localeCompare(b.start)), [], []);
}

export function useMoves(): Move[] {
  return useLiveQuery(async () => (await db.moves.toArray()).filter(alive), [], []);
}

export function num(v: string): number | undefined {
  if (v.trim() === '') return undefined;
  const n = Number(v.replace(',', '.'));
  return Number.isFinite(n) ? n : undefined;
}

export const fmt = {
  km: (v?: number) => (v == null ? '' : `${v.toLocaleString('nl-NL', { maximumFractionDigits: 1 })} km`),
  n1: (v?: number) => (v == null ? '' : v.toLocaleString('nl-NL', { maximumFractionDigits: 1 })),
};
