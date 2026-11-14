import { db, getSetting, newId, save, type Workout, type WorkoutKind } from './db';
import { addDays, today } from './dates';

// Koppeling met intervals.icu (dat synchroniseert zelf met Garmin Connect).
// Persoonlijke API-sleutel via basic auth: gebruikersnaam "API_KEY", wachtwoord = de sleutel.

export interface IntervalsSettings {
  key: string;
  athlete: string; // '0' = jezelf
  proxy: string; // optioneel, bijv. https://intervals-proxy.jouwnaam.workers.dev
}

export async function getIntervalsSettings(): Promise<IntervalsSettings> {
  return getSetting<IntervalsSettings>('intervals', { key: '', athlete: '0', proxy: '' });
}

interface IcuActivity {
  id: string | number;
  start_date_local?: string;
  name?: string;
  type?: string;
  distance?: number;
  moving_time?: number;
  elapsed_time?: number;
  total_elevation_gain?: number;
  average_heartrate?: number;
  icu_rpe?: number;
}

function kindFor(type = ''): WorkoutKind {
  if (/run/i.test(type)) return 'run';
  if (/weight|strength/i.test(type)) return 'strength';
  if (/box/i.test(type)) return 'boxing';
  return 'other';
}

const SPORT_NL: Record<string, string> = {
  Run: 'Hardlopen', TrailRun: 'Trailrun', VirtualRun: 'Loopband', Ride: 'Fietsen', VirtualRide: 'Fietsen binnen',
  GravelRide: 'Gravel', MountainBikeRide: 'MTB', Walk: 'Wandelen', Hike: 'Hiken', WeightTraining: 'Kracht',
};

export function mapActivity(a: IcuActivity): Omit<Workout, 'id' | 'updatedAt'> {
  const date = (a.start_date_local ?? '').slice(0, 10);
  const sport = a.type ?? 'Other';
  return {
    date,
    kind: kindFor(sport),
    title: a.name || SPORT_NL[sport] || sport,
    sport,
    distanceKm: a.distance ? Math.round(a.distance / 10) / 100 : undefined,
    durationMin: a.moving_time ? Math.round(a.moving_time / 6) / 10 : a.elapsed_time ? Math.round(a.elapsed_time / 6) / 10 : undefined,
    elevationM: a.total_elevation_gain ? Math.round(a.total_elevation_gain) : undefined,
    avgHr: a.average_heartrate ? Math.round(a.average_heartrate) : undefined,
    rpe: a.icu_rpe ?? undefined,
    source: 'intervals',
    externalId: String(a.id),
  };
}

export class IntervalsError extends Error {}

export async function fetchActivities(s: IntervalsSettings, oldest: string, newest: string): Promise<IcuActivity[]> {
  if (!s.key) throw new IntervalsError('Vul eerst je API-sleutel in bij Instellingen.');
  const base = (s.proxy || 'https://intervals.icu').replace(/\/$/, '');
  const url = `${base}/api/v1/athlete/${encodeURIComponent(s.athlete || '0')}/activities?oldest=${oldest}&newest=${newest}`;
  let res: Response;
  try {
    res = await fetch(url, { headers: { Authorization: 'Basic ' + btoa(`API_KEY:${s.key}`), Accept: 'application/json' } });
  } catch {
    throw new IntervalsError(
      s.proxy
        ? 'Geen verbinding met je proxy. Controleer de proxy-URL.'
        : 'intervals.icu blokkeert directe verzoeken vanuit de browser (CORS). Zet de gratis proxy op (zie README) en vul de proxy-URL in.',
    );
  }
  if (res.status === 401 || res.status === 403) throw new IntervalsError('Sleutel geweigerd. Controleer je API-sleutel en athlete-ID.');
  if (!res.ok) throw new IntervalsError(`intervals.icu gaf fout ${res.status}.`);
  return res.json();
}

/** Haalt activiteiten op en voegt nieuwe toe of werkt bestaande bij. Geeft het aantal nieuwe terug. */
export async function importActivities(days = 42): Promise<{ added: number; updated: number }> {
  const s = await getIntervalsSettings();
  const newest = today();
  const last = await getSetting<string>('intervalsLastImport', '');
  const oldest = last && last > addDays(newest, -days) ? addDays(last, -3) : addDays(newest, -days);
  const list = await fetchActivities(s, oldest, newest);

  let added = 0;
  let updated = 0;
  for (const a of list) {
    const mapped = mapActivity(a);
    if (!mapped.date) continue;
    const existing = await db.workouts.where('externalId').equals(mapped.externalId!).first();
    if (existing) {
      if (existing.deleted) continue; // zelf verwijderd: niet terugzetten
      // Eigen aanvullingen (slot, notities, zwaarte) blijven staan
      await save('workouts', { ...existing, ...mapped, slotId: existing.slotId, notes: existing.notes, rpe: existing.rpe ?? mapped.rpe });
      updated++;
    } else {
      await save('workouts', { id: newId(), ...mapped });
      added++;
    }
  }
  await db.kv.put({ key: 'intervalsLastImport', value: newest });
  return { added, updated };
}
