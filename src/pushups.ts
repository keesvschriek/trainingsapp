import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, getSetting, type Metric } from './db';
import { addDays, type ISODate } from './dates';
import { gtgDay, type DayPlan, type PlannedItem } from './plan';

// Push-ups tussendoor. Elke set is een eigen record (kind 'pushups'), zodat je per dag
// ziet hoeveel sets je deed en de laatste set ongedaan kunt maken.

export const DEFAULT_GOAL = 100;
export const DEFAULT_SET = 20;

export function newSetId(date: ISODate, now = Date.now()) {
  return `pushups-${date}-${now.toString(36)}`;
}

/** Sets per dag, op volgorde van invoer. */
export function setsByDay(records: Metric[]): Map<ISODate, Metric[]> {
  const map = new Map<ISODate, Metric[]>();
  for (const r of records) {
    if (r.kind !== 'pushups' || r.deleted) continue;
    const list = map.get(r.date) ?? [];
    list.push(r);
    map.set(r.date, list);
  }
  for (const list of map.values()) list.sort((a, b) => a.id.localeCompare(b.id));
  return map;
}

export const dayTotal = (sets: Metric[] | undefined) => (sets ?? []).reduce((s, m) => s + m.value, 0);

/**
 * Aantal dagen op rij dat het doel gehaald is. Vandaag telt mee zodra het doel gehaald is,
 * anders begint de reeks gisteren. Rustdagen (borst-dag, testdag) breken de reeks niet en tellen niet mee.
 */
export function goalStreak(byDay: Map<ISODate, Metric[]>, goal: number, today: ISODate, isRest: (d: ISODate) => boolean = () => false): number {
  let d = dayTotal(byDay.get(today)) >= goal ? today : addDays(today, -1);
  let n = 0;
  for (let guard = 0; guard < 3660; guard++) {
    if (dayTotal(byDay.get(d)) >= goal) n++;
    else if (!isRest(d)) break;
    d = addDays(d, -1);
  }
  return n;
}

/** Waarom vandaag geen push-ups tussendoor, of null als het gewoon een push-updag is. */
export function restReason(items: PlannedItem[]): string | null {
  if (items.some(i => i.slotId === 'test-pushups')) return 'Testdag: vandaag geen sets tussendoor, dan ben je fris voor je maxtest.';
  if (items.some(i => i.slotId === 'kracht-borst')) return 'Borst-dag: sla de sets tussendoor vandaag over, dan haal je meer uit je training.';
  return null;
}

/** Grote knop: de helft van je laatste maxtest, afgerond op 5. */
export function autoSetSize(max: number | undefined, fallback: number): number {
  if (!max || max < 4) return fallback;
  return Math.max(2, Math.round(max / 2 / (max >= 20 ? 5 : 1)) * (max >= 20 ? 5 : 1));
}

export function lastDays(byDay: Map<ISODate, Metric[]>, n: number, today: ISODate) {
  return Array.from({ length: n }, (_, i) => {
    const date = addDays(today, i - n + 1);
    const sets = byDay.get(date) ?? [];
    return { date, total: dayTotal(sets), sets: sets.length };
  });
}

// Pull-ups tussendoor: ma t/m vr, niet op dagen met Defensie, ziek of een ander blok.
export const PULLUP_SETS_PER_DAY = 5;
export function pullupDay(plan: DayPlan): boolean {
  const blocking = plan.event && ['defensie', 'ziek', 'anders'].includes(plan.event.kind);
  return plan.status === 'actief' && gtgDay(plan.date) && !blocking;
}

export function usePullupSet() {
  const lastMax = useLiveQuery(async () => {
    const all = (await db.metrics.where('kind').equals('pullupMax').toArray()).filter(alive);
    return all.sort((a, b) => a.date.localeCompare(b.date) || a.updatedAt - b.updatedAt).slice(-1)[0]?.value;
  }, [], undefined);
  const setSize = autoSetSize(lastMax, 3);
  return { setSize, goal: setSize * PULLUP_SETS_PER_DAY, lastMax };
}

export function usePushupSettings() {
  const goal = useLiveQuery(() => getSetting('pushupGoal', DEFAULT_GOAL), [], DEFAULT_GOAL);
  const manualSet = useLiveQuery(() => getSetting('pushupSet', DEFAULT_SET), [], DEFAULT_SET);
  const auto = useLiveQuery(() => getSetting('pushupSetAuto', true), [], true);
  const show = useLiveQuery(() => getSetting('pushupShow', true), [], true);
  const lastMax = useLiveQuery(async () => {
    const all = (await db.metrics.where('kind').equals('pushupMax').toArray()).filter(alive);
    return all.sort((a, b) => a.date.localeCompare(b.date) || a.updatedAt - b.updatedAt).slice(-1)[0]?.value;
  }, [], undefined);
  const setSize = auto ? autoSetSize(lastMax, manualSet) : manualSet;
  return { goal, setSize, manualSet, auto, lastMax, show };
}

export function usePushupRecords() {
  return useLiveQuery(async () => (await db.metrics.where('kind').equals('pushups').toArray()).filter(alive), [], []);
}
