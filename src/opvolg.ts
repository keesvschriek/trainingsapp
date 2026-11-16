import { addDays, fromISO, weekday, type ISODate } from './dates';
import type { Opvolg } from './db';

// Opvolgen: kleine punten die je niet wilt vergeten (mailen, navragen, regelen).
// Geen leerlingnamen: hooguit initialen of een rol. Gedeeld met de Kobo via Supabase.

export const GROUPS = ['Mentoraat', 'Tutoren', 'Burgerschap', 'Digitale geletterdheid', 'Sectie', 'Defensie', 'Thuis'] as const;

const DAY_NAMES = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
const DAY_FULL = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];

/** Eerstvolgende dag met weekdag wd (0 = maandag), nooit vandaag zelf. */
export function nextWeekday(from: ISODate, wd: number): ISODate {
  const cur = weekday(from);
  let n = (wd - cur + 7) % 7;
  if (n === 0) n = 7;
  return addDays(from, n);
}

/** Snelle keuzes voor de datum, vanaf vandaag. */
export function dueChoices(from: ISODate): { label: string; date: ISODate }[] {
  const out = [
    { label: 'Vandaag', date: from },
    { label: 'Morgen', date: addDays(from, 1) },
  ];
  for (let i = 2; i <= 6; i++) {
    const d = addDays(from, i);
    out.push({ label: DAY_FULL[weekday(d)].replace(/^./, c => c.toUpperCase()), date: d });
  }
  out.push({ label: 'Over 1 week', date: addDays(from, 7) });
  out.push({ label: 'Over 2 weken', date: addDays(from, 14) });
  return out;
}

/**
 * Datum uit een woord halen aan het eind van een regel, zodat je in één keer kunt typen:
 * "ouders AB bellen morgen", "verslag rondsturen vr", "rooster checken over 3 dagen".
 * Geeft de tekst zonder datumwoord terug.
 */
export function parseLine(line: string, from: ISODate, fallback: ISODate): { title: string; due: ISODate } {
  let t = line.trim().replace(/\s+/g, ' ');
  let due = fallback;
  const lower = t.toLowerCase();
  const m = lower.match(/\s(vandaag|morgen|overmorgen|volgende week|over (\d+) (dagen|dag|weken|week)|(ma|di|wo|do|vr|za|zo|maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag))$/);
  if (m) {
    const w = m[1];
    if (w === 'vandaag') due = from;
    else if (w === 'morgen') due = addDays(from, 1);
    else if (w === 'overmorgen') due = addDays(from, 2);
    else if (w === 'volgende week') due = nextWeekday(from, 0);
    else if (m[2]) due = addDays(from, Number(m[2]) * (m[3].startsWith('we') ? 7 : 1));
    else {
      const idx = DAY_NAMES.indexOf(w.slice(0, 2));
      if (idx >= 0) due = nextWeekday(from, idx);
    }
    t = t.slice(0, t.length - m[0].length).trim();
  }
  return { title: t.charAt(0).toUpperCase() + t.slice(1), due };
}

/** "vandaag", "morgen", "vr 21 nov", "2 dagen te laat". */
export function dueText(due: ISODate, from: ISODate): string {
  const diff = Math.round((fromISO(due).getTime() - fromISO(from).getTime()) / 86400000);
  if (diff < -1) return `${-diff} dagen te laat`;
  if (diff === -1) return 'gisteren';
  if (diff === 0) return 'vandaag';
  if (diff === 1) return 'morgen';
  const d = fromISO(due);
  const mon = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'][d.getMonth()];
  return `${DAY_NAMES[weekday(due)]} ${d.getDate()} ${mon}`;
}

/** Open punten in volgorde: te laat en vandaag eerst, dan op datum. */
export function sortOpen(list: Opvolg[]): Opvolg[] {
  return list.filter(o => !o.done && !o.deleted).sort((a, b) => (a.due < b.due ? -1 : a.due > b.due ? 1 : a.createdAt - b.createdAt));
}

/** Punten die vandaag aandacht vragen: te laat of vandaag. */
export function dueNow(list: Opvolg[], day: ISODate): Opvolg[] {
  return sortOpen(list).filter(o => o.due <= day);
}
