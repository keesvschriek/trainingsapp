// Alle datums als lokale 'YYYY-MM-DD'-strings, zodat tijdzones nooit een dag verschuiven.

export type ISODate = string;

export function toISO(d: Date): ISODate {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function fromISO(s: ISODate): Date {
  const [y, m, d] = s.split('-').map(Number);
  return new Date(y, m - 1, d, 12); // 12:00 voorkomt zomertijdproblemen
}

export function today(): ISODate {
  return toISO(new Date());
}

export function addDays(s: ISODate, n: number): ISODate {
  const d = fromISO(s);
  d.setDate(d.getDate() + n);
  return toISO(d);
}

export function diffDays(a: ISODate, b: ISODate): number {
  return Math.round((fromISO(a).getTime() - fromISO(b).getTime()) / 86400000);
}

/** Maandag = 0 ... zondag = 6 */
export function weekday(s: ISODate): number {
  return (fromISO(s).getDay() + 6) % 7;
}

export function mondayOf(s: ISODate): ISODate {
  return addDays(s, -weekday(s));
}

const DAGEN = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];
const DAGEN_KORT = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
const MAANDEN = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];

export function dayName(s: ISODate): string {
  return DAGEN[weekday(s)];
}
export function dayShort(s: ISODate): string {
  return DAGEN_KORT[weekday(s)];
}
export function shortDate(s: ISODate): string {
  const d = fromISO(s);
  return `${d.getDate()} ${MAANDEN[d.getMonth()]}`;
}
export function longDate(s: ISODate): string {
  const d = fromISO(s);
  return `${dayName(s)} ${d.getDate()} ${MAANDEN[d.getMonth()]} ${d.getFullYear()}`;
}

export function inRange(s: ISODate, start: ISODate, end: ISODate): boolean {
  return s >= start && s <= end;
}

export function minutesToText(min: number): string {
  if (min < 60) return `${Math.round(min)} min`;
  const h = Math.floor(min / 60);
  const m = Math.round(min % 60);
  return m === 0 ? `${h} uur` : `${h}u${String(m).padStart(2, '0')}`;
}
