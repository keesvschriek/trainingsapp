import { LocalNotifications } from '@capacitor/local-notifications';
import { db, alive, getSetting } from './db';
import { addDays, fromISO, today } from './dates';
import { planForDay } from './plan';
import { isNative } from './native';

// Ochtendmelding met de training van de dag. Er staan steeds 14 meldingen vooruit klaar;
// bij elke wijziging (verschuiven, blok, schema) worden ze opnieuw ingepland.

export interface NotifySettings {
  on: boolean;
  time: string; // 'HH:MM'
}

const BASE_ID = 7000;
const DAYS = 14;

export async function getNotifySettings(): Promise<NotifySettings> {
  return getSetting<NotifySettings>('notify', { on: false, time: '07:00' });
}

export async function scheduleMorning(): Promise<number> {
  if (!isNative) return 0;
  const s = await getNotifySettings();
  const pending = await LocalNotifications.getPending();
  const ours = pending.notifications.filter(n => n.id >= BASE_ID && n.id < BASE_ID + 100);
  if (ours.length) await LocalNotifications.cancel({ notifications: ours.map(n => ({ id: n.id })) });
  if (!s.on) return 0;
  const perm = await LocalNotifications.checkPermissions();
  if (perm.display !== 'granted') return 0;

  const events = (await db.blocks.toArray()).filter(alive);
  const moves = (await db.moves.toArray()).filter(alive);
  const [hh, mm] = s.time.split(':').map(Number);
  const list = [];
  for (let i = 0; i < DAYS; i++) {
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
      iconColor: '#1F4E79',
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
