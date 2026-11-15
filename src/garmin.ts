import { db, alive, getSetting, setSetting } from './db';
import { addDays, today } from './dates';
import { planForDay, type PlannedItem } from './plan';
import { getIntervalsSettings, IntervalsError } from './intervals';

// Geplande lopen naar je Garmin.
// De app zet de komende 14 dagen als geplande trainingen in je intervals.icu-agenda.
// intervals.icu stuurt de komende 7 dagen door naar Garmin Connect (instelling
// "Upload planned workouts"), en na een sync staan ze op je horloge.
// Doelen in hartslag (% van je lactaatdrempel, LTHR), zodat het werkt met je hartslagband.

const PREFIX = 'trainingsapp-';
const DAYS_AHEAD = 14;
const EASY = '80-88% LTHR';
const TEMPO = '90-96% LTHR';
const STEADY = '89-94% LTHR';

export function workoutText(item: PlannedItem): string | null {
  const m = item.minutes ?? 0;
  const note = item.detail ? `${item.detail}\n\n` : '';
  switch (item.slotId) {
    case 'run-easy':
    case 'run-extra':
      if (item.detail?.includes('versnellen')) {
        return `${note}Rustig\n- ${Math.max(m - 8, 10)}m ${EASY}\n\nVersnellingen 6x\n- 20s ${TEMPO}\n- 1m ${EASY}`;
      }
      return `${note}Rustig\n- ${m}m ${EASY}`;
    case 'run-long':
    case 'run-commute':
      return `${note}Rustig\n- ${m}m ${EASY}`;
    case 'run-quality': {
      if (item.title.startsWith('Tempoloop')) {
        const t = Math.max(m - 25, 10);
        return `${note}Inlopen\n- 15m ${EASY}\n\nTempo\n- ${t}m ${TEMPO}\n\nUitlopen\n- 10m ${EASY}`;
      }
      if (item.title.startsWith('Progressieve')) {
        return `${note}Rustig\n- ${Math.max(m - 10, 10)}m ${EASY}\n\nLaatste stuk\n- 10m ${STEADY}`;
      }
      return `${note}Heuvelloop, klimmen stevig\n- ${m}m ${EASY}`;
    }
    case 'test-cooper':
      return `${note}Inlopen\n- 15m ${EASY}\n\nCooper-test, zo ver mogelijk\n- 12m\n\nUitlopen\n- 10m ${EASY}`;
    case 'test-10k':
      return `${note}Inlopen\n- 15m ${EASY}\n\n10 km zo snel mogelijk\n- 10km\n\nUitlopen\n- 10m ${EASY}`;
    default:
      return null;
  }
}

interface IcuEvent {
  category: 'WORKOUT' | 'NOTE';
  type?: string;
  start_date_local: string;
  name: string;
  description: string;
  external_id: string;
  moving_time?: number;
}

/** Kracht, tests en wedstrijden als notitie in de agenda: zichtbaar in intervals.icu en op de Kobo, niet op je horloge. */
export function noteText(item: PlannedItem): string | null {
  if (item.kind !== 'strength' && item.kind !== 'test' && item.kind !== 'race') return null;
  const lines: string[] = [];
  if (item.detail) lines.push(item.detail);
  if (item.exercises?.length) {
    if (lines.length) lines.push('');
    for (const e of item.exercises) lines.push(`- ${e.name}: ${e.sets} x ${e.reps}${e.weight ? ` (${e.weight})` : ''}`);
  }
  return lines.join('\n') || item.title;
}

export async function plannedEvents(): Promise<IcuEvent[]> {
  const events = (await db.blocks.toArray()).filter(alive);
  const moves = (await db.moves.toArray()).filter(alive);
  const start = today();
  const out: IcuEvent[] = [];
  for (let i = 0; i < DAYS_AHEAD; i++) {
    const date = addDays(start, i);
    for (const item of planForDay(date, events, moves).items) {
      const text = workoutText(item);
      const moving_time = item.minutes ? item.minutes * 60 : undefined;
      if (text) {
        out.push({
          category: 'WORKOUT',
          type: 'Run',
          start_date_local: `${date}T00:00:00`,
          name: item.title,
          description: text,
          external_id: `${PREFIX}${date}-${item.slotId}`,
          moving_time,
        });
        continue;
      }
      const note = noteText(item);
      if (!note) continue;
      out.push({
        category: 'NOTE',
        type: item.kind === 'strength' ? 'WeightTraining' : undefined,
        start_date_local: `${date}T00:00:00`,
        name: item.title,
        description: note,
        external_id: `${PREFIX}${date}-${item.slotId}`,
        moving_time,
      });
    }
  }
  return out;
}

async function call(path: string, method: 'POST' | 'PUT', body: unknown) {
  const s = await getIntervalsSettings();
  if (!s.key) throw new IntervalsError('Vul eerst je intervals.icu-sleutel in.');
  const base = (s.proxy || 'https://intervals.icu').replace(/\/$/, '');
  const res = await fetch(`${base}/api/v1/athlete/${encodeURIComponent(s.athlete || '0')}${path}`, {
    method,
    headers: { Authorization: 'Basic ' + btoa(`API_KEY:${s.key}`), 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  if (res.status === 401 || res.status === 403) throw new IntervalsError('Sleutel geweigerd door intervals.icu.');
  if (!res.ok) throw new IntervalsError(`intervals.icu gaf fout ${res.status}.`);
  return res.json().catch(() => null);
}

/** Zet de komende 14 dagen in intervals.icu en ruimt verschoven trainingen op. */
export async function pushToGarmin(): Promise<{ sent: number; removed: number }> {
  const events = await plannedEvents();
  const ids = new Set(events.map(e => e.external_id));
  const prev = await getSetting<string[]>('garmin.sent', []);
  const todayStr = today();
  // Eerder verstuurd, nog in de toekomst, maar niet meer gepland: weghalen
  const stale = prev.filter(id => !ids.has(id) && id.slice(PREFIX.length, PREFIX.length + 10) >= todayStr);

  if (events.length) await call('/events/bulk?upsert=true', 'POST', events);
  if (stale.length) await call('/events/bulk-delete', 'PUT', stale.map(external_id => ({ external_id })));

  const keep = prev.filter(id => id.slice(PREFIX.length, PREFIX.length + 10) >= todayStr && ids.has(id));
  await setSetting('garmin.sent', [...new Set([...keep, ...ids])]);
  await setSetting('garmin.last', Date.now());
  await setSetting('garmin.lastHash', hash(events));
  return { sent: events.length, removed: stale.length };
}

function hash(events: IcuEvent[]): string {
  return events.map(e => `${e.external_id}|${e.name}|${e.description.length}`).join(';');
}

/** Automatisch versturen als het aan staat en er iets veranderd is (of 1x per dag). */
export async function autoPushToGarmin() {
  if (!(await getSetting<boolean>('garmin.on', false))) return;
  if (!navigator.onLine) return;
  const events = await plannedEvents();
  const last = await getSetting<number>('garmin.last', 0);
  const lastHash = await getSetting<string>('garmin.lastHash', '');
  if (hash(events) === lastHash && Date.now() - last < 20 * 60 * 60 * 1000) return;
  try {
    await pushToGarmin();
  } catch {
    /* stil; de knop in Instellingen toont fouten */
  }
}
