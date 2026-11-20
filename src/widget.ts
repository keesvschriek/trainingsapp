import { easyText } from './zones';
import { registerPlugin } from '@capacitor/core';
import { App as CapApp } from '@capacitor/app';
import { db, alive, getSetting, save, type Metric } from './db';
import { addDays, today, type ISODate } from './dates';
import { planForDay, type PlannedItem } from './plan';
import { autoSetSize, dayTotal, DEFAULT_GOAL, DEFAULT_SET, newSetId, pullupDay, PULLUP_SETS_PER_DAY, restReason, setsByDay } from './pushups';
import { isNative } from './native';

// Koppeling met de widget op het startscherm (Android).
// De app schrijft een momentopname weg; de widget leest die en bewaart getikte sets tot de app ze ophaalt.

interface WidgetBridge {
  update(o: { snapshot: string }): Promise<void>;
  takePending(): Promise<{ sets: string }>;
  takeShared(): Promise<{ text: string; subject: string }>;
}
const Bridge = registerPlugin<WidgetBridge>('WidgetBridge');

/** Tekst of link die via Delen naar K is gestuurd, of null. */
export async function takeShared(): Promise<{ text: string; subject: string } | null> {
  if (!isNative) return null;
  try {
    const r = await Bridge.takeShared();
    return r.text ? r : null;
  } catch {
    return null;
  }
}

export interface WidgetDay { title: string; sub: string; rest: boolean; pull: boolean }
export interface WidgetSnapshot {
  updated: number;
  goal: number;
  setSize: number;
  days: Record<ISODate, WidgetDay>;
  counts: Record<ISODate, number>;
  pullSet: number;
  pullGoal: number;
  pullCounts: Record<ISODate, number>;
}

/** Wat de widget voor een dag laat zien. */
export function describeDay(items: PlannedItem[], status: 'voor' | 'actief'): Omit<WidgetDay, 'rest' | 'pull'> {
  const training = items.filter(i => i.kind !== 'rest' && i.kind !== 'free');
  const main = training.find(i => !i.optional) ?? training[0] ?? items[0];
  if (!main) return { title: 'Rust', sub: '' };
  const parts: string[] = [];
  if (main.minutes && main.kind !== 'rest') parts.push(`${main.minutes} min`);
  if (main.kind === 'run') parts.push(main.slotId === 'run-quality' && main.title.startsWith('Tempo') ? '90-96% LTHR' : easyText());
  if (main.kind === 'strength' && main.exercises) parts.push(`${main.exercises.length} oefeningen`);
  const more = training.filter(i => i !== main && !i.optional).length;
  if (more) parts.push(`+ ${more} meer`);
  if (status === 'voor') parts.push(main.detail ?? '');
  return { title: main.title, sub: parts.filter(Boolean).join(' · ') };
}

export async function buildSnapshot(now: ISODate = today()): Promise<WidgetSnapshot> {
  const [events, moves, records, goal, manualSet, auto, maxes] = await Promise.all([
    db.blocks.toArray().then(r => r.filter(alive)),
    db.moves.toArray().then(r => r.filter(alive)),
    db.metrics.where('kind').equals('pushups').toArray().then(r => r.filter(alive)),
    getSetting('pushupGoal', DEFAULT_GOAL),
    getSetting('pushupSet', DEFAULT_SET),
    getSetting('pushupSetAuto', true),
    db.metrics.where('kind').equals('pushupMax').toArray().then(r => r.filter(alive)),
  ]);
  const [pullMaxes, gtgs] = await Promise.all([
    db.metrics.where('kind').equals('pullupMax').toArray().then(r => r.filter(alive)),
    db.metrics.where('kind').equals('gtg').toArray().then(r => r.filter(alive)),
  ]);
  const lastPullMax = pullMaxes.sort((a, b) => a.date.localeCompare(b.date) || a.updatedAt - b.updatedAt).slice(-1)[0]?.value;
  const pullSet = autoSetSize(lastPullMax, 3);
  const pullCounts: Record<ISODate, number> = {};
  const lastMax = maxes.sort((a, b) => a.date.localeCompare(b.date) || a.updatedAt - b.updatedAt).slice(-1)[0]?.value;
  const byDay = setsByDay(records);
  const days: Record<ISODate, WidgetDay> = {};
  const counts: Record<ISODate, number> = {};
  for (let i = 0; i < 8; i++) {
    const d = addDays(now, i);
    const plan = planForDay(d, events, moves);
    days[d] = { ...describeDay(plan.items, plan.status), rest: restReason(plan.items) !== null, pull: pullupDay(plan) };
    counts[d] = dayTotal(byDay.get(d));
    pullCounts[d] = gtgs.find(m => m.id === `gtg-${d}`)?.value ?? 0;
  }
  return { updated: Date.now(), goal, setSize: auto ? autoSetSize(lastMax, manualSet) : manualSet, days, counts, pullSet, pullGoal: pullSet * PULLUP_SETS_PER_DAY, pullCounts };
}

/** Sets die via de widget zijn getikt in de app zetten. */
export async function importWidgetSets(): Promise<number> {
  if (!isNative) return 0;
  try {
    const { sets } = await Bridge.takePending();
    const list = JSON.parse(sets || '[]') as { date: ISODate; value: number; ts: number; type?: 'pushups' | 'pullups' }[];
    for (const s of list) {
      if (!s.date || !(s.value > 0)) continue;
      if (s.type === 'pullups') {
        // Pull-ups tussendoor staan als één totaal per dag
        const id = `gtg-${s.date}`;
        const cur = await db.metrics.get(id);
        const base = cur && !cur.deleted ? cur.value : 0;
        await save('metrics', { id, date: s.date, kind: 'gtg', value: base + s.value } as Metric);
      } else {
        await save('metrics', { id: newSetId(s.date, s.ts), date: s.date, kind: 'pushups', value: s.value } as Metric);
      }
    }
    return list.length;
  } catch {
    return 0;
  }
}

export async function pushWidget() {
  if (!isNative) return;
  try {
    await Bridge.update({ snapshot: JSON.stringify(await buildSnapshot()) });
  } catch {
    /* oude app zonder widget-koppeling: niets doen */
  }
}

let timer: number | undefined;
function pushSoon() {
  window.clearTimeout(timer);
  timer = window.setTimeout(() => void pushWidget(), 800);
}

/** Bij starten, terugkomen in de app en na elke wijziging de widget bijwerken. */
export function setupWidget() {
  if (!isNative) return;
  const sync = async () => {
    await importWidgetSets();
    await pushWidget();
  };
  void sync();
  window.addEventListener('data-changed', pushSoon);
  window.addEventListener('settings-changed', pushSoon);
  void CapApp.addListener('resume', () => void sync());
  void CapApp.addListener('pause', () => void pushWidget());
}
