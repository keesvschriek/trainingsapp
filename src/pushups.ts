import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, getSetting, type Metric } from './db';
import { addDays, type ISODate } from './dates';

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

/** Aantal dagen op rij dat het doel gehaald is. Vandaag telt mee zodra het doel gehaald is, anders begint de reeks gisteren. */
export function goalStreak(byDay: Map<ISODate, Metric[]>, goal: number, today: ISODate): number {
  let d = dayTotal(byDay.get(today)) >= goal ? today : addDays(today, -1);
  let n = 0;
  while (dayTotal(byDay.get(d)) >= goal) {
    n++;
    d = addDays(d, -1);
  }
  return n;
}

export function lastDays(byDay: Map<ISODate, Metric[]>, n: number, today: ISODate) {
  return Array.from({ length: n }, (_, i) => {
    const date = addDays(today, i - n + 1);
    const sets = byDay.get(date) ?? [];
    return { date, total: dayTotal(sets), sets: sets.length };
  });
}

export function usePushupSettings() {
  const goal = useLiveQuery(() => getSetting('pushupGoal', DEFAULT_GOAL), [], DEFAULT_GOAL);
  const setSize = useLiveQuery(() => getSetting('pushupSet', DEFAULT_SET), [], DEFAULT_SET);
  const show = useLiveQuery(() => getSetting('pushupShow', true), [], true);
  return { goal, setSize, show };
}

export function usePushupRecords() {
  return useLiveQuery(async () => (await db.metrics.where('kind').equals('pushups').toArray()).filter(alive), [], []);
}
