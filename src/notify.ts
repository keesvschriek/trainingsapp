import { LocalNotifications } from '@capacitor/local-notifications';
import { db, alive, getSetting } from './db';
import { addDays, fromISO, today } from './dates';
import { planForDay, weekOf } from './plan';
import { matchDay } from './match';
import { sortOpen } from './opvolg';
import { isNative } from './native';

// Ochtendmelding met de training van de dag. Er staan steeds 14 meldingen vooruit klaar;
// bij elke wijziging (verschuiven, blok, schema) worden ze opnieuw ingepland.

export interface NotifySettings {
  on: boolean;
  time: string; // 'HH:MM'
  evening?: boolean; // seintje na school, alleen als er iets open staat
  eveningTime?: string;
}

const BASE_ID = 7000;
const DAYS = 14;

export async function getNotifySettings(): Promise<NotifySettings> {
  return getSetting<NotifySettings>('notify', { on: false, time: '07:00', evening: false, eveningTime: '18:00' });
}

export async function scheduleMorning(): Promise<number> {
  if (!isNative) return 0;
  const s = await getNotifySettings();
  const pending = await LocalNotifications.getPending();
  const ours = pending.notifications.filter(n => n.id >= BASE_ID && n.id < BASE_ID + 100);
  if (ours.length) await LocalNotifications.cancel({ notifications: ours.map(n => ({ id: n.id })) });
  if (!s.on && !s.evening) return 0;
  const perm = await LocalNotifications.checkPermissions();
  if (perm.display !== 'granted') return 0;

  const events = (await db.blocks.toArray()).filter(alive);
  const moves = (await db.moves.toArray()).filter(alive);
  const [hh, mm] = s.time.split(':').map(Number);
  const list = [];
  for (let i = 0; i < DAYS && s.on; i++) {
    const date = addDays(today(), i);
    const at = fromISO(date);
    at.setHours(hh, mm, 0, 0);
    if (at.getTime() <= Date.now() + 60_000) continue;
    const items = planForDay(date, events, moves).items.filter(x => x.kind !== 'free' && x.kind !== 'rest' && !x.optional);
    const body = items.length
      ? `Vandaag: ${items.map(x => x.title + (x.minutes ? ` (${x.minutes} min)` : '')).join(', ')}. Tik voor je check-in.`
      : 'Rustdag. Tik voor je check-in.';
    list.push({
      id: BASE_ID + i,
      title: 'Goedemorgen',
      body,
      schedule: { at, allowWhileIdle: true },
      smallIcon: 'ic_stat_training',
      iconColor: '#111111',
    });
  }
  // Na school: alleen als er die dag nog iets open staat (training of opvolgpunten)
  if (s.evening) {
    const [eh, em] = (s.eveningTime ?? '18:00').split(':').map(Number);
    const open = sortOpen((await db.opvolg.toArray()).filter(alive));
    const day0 = today();
    const doneToday = matchDay(
      planForDay(day0, events, moves).items,
      (await db.workouts.where('date').equals(day0).toArray()).filter(alive),
      (await db.checks.where('date').equals(day0).toArray()).filter(alive),
    ).statuses;
    for (let i = 0; i < DAYS; i++) {
      const date = addDays(day0, i);
      const at = fromISO(date);
      at.setHours(eh, em, 0, 0);
      if (at.getTime() <= Date.now() + 60_000) continue;
      const items = planForDay(date, events, moves).items.filter(x => x.kind !== 'free' && x.kind !== 'rest' && !x.optional);
      const todo = i === 0 ? items.filter(x => !doneToday.find(st => st.item.slotId === x.slotId)?.done) : items;
      const pts = open.filter(o => o.due <= date);
      const parts: string[] = [];
      if (todo.length) parts.push(`Training nog open: ${todo.map(x => x.title).join(', ')}`);
      if (pts.length) parts.push(pts.length === 1 ? `Opvolgen: ${pts[0].title}` : `${pts.length} punten om op te volgen`);
      if (!parts.length) continue;
      list.push({
        id: BASE_ID + 20 + i,
        title: 'Na school',
        body: parts.join(' · ') + '.',
        schedule: { at, allowWhileIdle: true },
        smallIcon: 'ic_stat_training',
        iconColor: '#111111',
      });
    }
  }
  // Zondagavond: terugblik op de week
  for (let i = 0, n = 0; i < DAYS && n < 2 && s.on; i++) {
    const date = addDays(today(), i);
    const at = fromISO(date);
    if (at.getDay() !== 0) continue;
    at.setHours(19, 0, 0, 0);
    if (at.getTime() <= Date.now() + 60_000) continue;
    const week = weekOf(date);
    if (week < 1) continue;
    list.push({
      id: BASE_ID + 60 + n++,
      title: 'Je week zit erop',
      body: `Bekijk je terugblik op week ${week}: wat je deed en wat er volgende week komt.`,
      schedule: { at, allowWhileIdle: true },
      smallIcon: 'ic_stat_training',
      iconColor: '#111111',
    });
  }
  if (list.length) await LocalNotifications.schedule({ notifications: list });
  return list.length;
}

export async function requestNotifyPermission(): Promise<boolean> {
  if (!isNative) return false;
  const p = await LocalNotifications.requestPermissions();
  return p.display === 'granted';
}
