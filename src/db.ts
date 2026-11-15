import Dexie, { type Table } from 'dexie';
import type { ISODate } from './dates';

// Elk gesynchroniseerd record heeft een id, updatedAt (ms) en een deleted-vlag.
// Verwijderen = deleted op true zetten, zodat het ook op andere apparaten verdwijnt.
export interface Base {
  id: string;
  updatedAt: number;
  deleted?: boolean;
}

export type WorkoutKind = 'run' | 'strength' | 'boxing' | 'other';

export interface Workout extends Base {
  date: ISODate;
  kind: WorkoutKind;
  slotId?: string; // koppeling met een geplande training, bijv. 'run-long'
  title: string;
  distanceKm?: number;
  durationMin?: number;
  elevationM?: number;
  avgHr?: number;
  rpe?: number; // zwaarte 1-10
  rounds?: number; // boksrondes
  notes?: string;
  source: 'manual' | 'intervals';
  externalId?: string;
  sport?: string; // type uit intervals.icu, bijv. Run, TrailRun, Ride
}

export interface StrengthSet extends Base {
  workoutId: string;
  exercise: string;
  setNo: number;
  reps: number;
  weightKg: number;
}

export type MetricKind = 'weight' | 'waist' | 'pullupMax' | 'cooper' | 'tenK' | 'gtg' | 'pressReps' | 'pushups';

export interface Metric extends Base {
  date: ISODate;
  kind: MetricKind;
  value: number;
  note?: string;
}

export interface Check extends Base {
  date: ISODate;
  slotId: string;
  done: boolean;
}

export type BlockKind = 'defensie' | 'wedstrijd' | 'vakantie' | 'ziek' | 'anders';

export interface Block extends Base {
  start: ISODate;
  end: ISODate;
  label: string;
  kind: BlockKind;
}

/** Verschuiving in het schema. shift: dag a schuift een dag op (rest van de week schuift mee). swap: dag a en b ruilen. */
export interface Move extends Base {
  week: number;
  op: 'shift' | 'swap';
  a: number; // 0 = maandag
  b?: number;
  at: number; // volgorde van toepassen
}

/** Ochtend-check-in, scores 1-5 (hoger = beter). */
export interface Checkin extends Base {
  date: ISODate;
  sleep: number;
  legs: number;
  energy: number;
  calm: number;
}

export interface KV {
  key: string;
  value: unknown;
}

class TrainingDB extends Dexie {
  workouts!: Table<Workout, string>;
  sets!: Table<StrengthSet, string>;
  metrics!: Table<Metric, string>;
  checks!: Table<Check, string>;
  blocks!: Table<Block, string>;
  moves!: Table<Move, string>;
  checkins!: Table<Checkin, string>;
  kv!: Table<KV, string>;

  constructor() {
    super('trainingsapp');
    this.version(1).stores({
      workouts: 'id, date, kind, externalId, updatedAt',
      sets: 'id, workoutId, updatedAt',
      metrics: 'id, date, kind, updatedAt',
      checks: 'id, date, updatedAt',
      blocks: 'id, start, updatedAt',
      kv: 'key',
    });
    this.version(2).stores({
      moves: 'id, week, updatedAt',
      checkins: 'id, date, updatedAt',
    });
  }
}

export const db = new TrainingDB();

export const SYNC_TABLES = ['workouts', 'sets', 'metrics', 'checks', 'blocks', 'moves', 'checkins'] as const;
export type SyncTable = (typeof SYNC_TABLES)[number];

export function newId(): string {
  return crypto.randomUUID();
}

type RecordOf<T extends SyncTable> = TrainingDB[T] extends Table<infer R, string> ? R : never;

export async function save<T extends SyncTable>(table: T, rec: Omit<RecordOf<T>, 'updatedAt'> & { updatedAt?: number }) {
  const full = { ...rec, updatedAt: Date.now() } as RecordOf<T>;
  await (db[table] as Table<RecordOf<T>, string>).put(full);
  window.dispatchEvent(new Event('data-changed'));
  return full;
}

export async function remove(table: SyncTable, id: string) {
  const t = db[table] as Table<Base, string>;
  const rec = await t.get(id);
  if (rec) {
    await t.put({ ...rec, deleted: true, updatedAt: Date.now() });
    window.dispatchEvent(new Event('data-changed'));
  }
}

export async function getSetting<T>(key: string, fallback: T): Promise<T> {
  const row = await db.kv.get(key);
  return row ? (row.value as T) : fallback;
}

export async function setSetting(key: string, value: unknown) {
  await db.kv.put({ key, value });
}

export const alive = <T extends Base>(r: T | undefined): r is T => !!r && !r.deleted;
