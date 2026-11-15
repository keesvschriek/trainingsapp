import { useLiveQuery } from 'dexie-react-hooks';
import { getSetting, setSetting } from './db';
import { fromISO, type ISODate } from './dates';
import type { Block } from './db';

// Werkdagen: op die dagen ben je weg van start tot eind. Per dag kun je het omzetten (vrij of toch werken).

export interface WorkSettings {
  days: number[]; // 1 = maandag ... 7 = zondag
  start: string; // 'HH:MM'
  end: string;
  overrides: Record<ISODate, boolean>; // true = werk, false = vrij
}

export const DEFAULT_WORK: WorkSettings = { days: [1, 2, 3, 4, 5], start: '07:30', end: '18:00', overrides: {} };

export async function getWork(): Promise<WorkSettings> {
  return { ...DEFAULT_WORK, ...(await getSetting<Partial<WorkSettings>>('work', {})) };
}

export async function saveWork(w: WorkSettings) {
  // Oude uitzonderingen opruimen
  const cutoff = new Date(Date.now() - 60 * 86400000).toISOString().slice(0, 10);
  const overrides = Object.fromEntries(Object.entries(w.overrides).filter(([d]) => d >= cutoff));
  await setSetting('work', { ...w, overrides });
}

export function useWork(): WorkSettings {
  return useLiveQuery(getWork, [], DEFAULT_WORK);
}

/** Werk je op deze dag? Vakantie en ziek tellen als vrij. */
export function isWorkDay(date: ISODate, w: WorkSettings, events: Block[] = []): boolean {
  if (date in w.overrides) return w.overrides[date];
  const off = events.some(b => !b.deleted && (b.kind === 'vakantie' || b.kind === 'ziek' || b.kind === 'defensie') && b.start <= date && b.end >= date);
  if (off) return false;
  const dow = fromISO(date).getDay() || 7;
  return w.days.includes(dow);
}

export const toMin = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + (m || 0);
};
export const fmtMin = (min: number) => `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(Math.round(min % 60)).padStart(2, '0')}`;
