import { addDays, diffDays, inRange, mondayOf, type ISODate } from './dates';
import type { Block } from './db';

// ---------------------------------------------------------------------------
// Trainingsschema: de fitste versie van jezelf.
// Prioriteit: 1 uithouding, 2 kracht, 3 lichaamssamenstelling.
// Doelen: 3000 m op de Cooper-test, 10 km onder 43 minuten, fitte bouw.
//
// Opbouw in blokken. Blok 1 duurt 9 weken (incl. eindbivak), daarna steeds 8 weken:
//   week 1-3 opbouwen, week 4 licht, week 5-7 opbouwen, week 8 testweek.
// Het schema loopt door zonder einddatum.
// ---------------------------------------------------------------------------

export const PLAN_START: ISODate = '2026-11-16';

export type ItemKind = 'run' | 'strength' | 'rest' | 'free' | 'test' | 'race';

export interface Exercise {
  name: string;
  weight: string;
  sets: number;
  reps: string;
  defaultKg: number;
  defaultReps: number;
}

export interface PlannedItem {
  slotId: string;
  kind: ItemKind;
  title: string;
  detail?: string;
  minutes?: number;
  optional?: boolean;
  exercises?: Exercise[];
}

// ---------------------------------------------------------------------------
// Blokken
// ---------------------------------------------------------------------------

export interface PlanBlock {
  nr: number;
  firstWeek: number;
  lastWeek: number;
  name: string;
  focus: string;
}

const FIRST_BLOCK_WEEKS = 9;
const BLOCK_WEEKS = 8;

export function blockOfWeek(week: number): PlanBlock {
  if (week <= FIRST_BLOCK_WEEKS) {
    return { nr: 1, firstWeek: 1, lastWeek: FIRST_BLOCK_WEEKS, name: 'Basis', focus: 'Vaker lopen, alles rustig. Kracht wordt routine. Afsluiten met de eerste testweek.' };
  }
  const nr = 2 + Math.floor((week - FIRST_BLOCK_WEEKS - 1) / BLOCK_WEEKS);
  const firstWeek = FIRST_BLOCK_WEEKS + 1 + (nr - 2) * BLOCK_WEEKS;
  const hills = nr % 2 === 1;
  return {
    nr,
    firstWeek,
    lastWeek: firstWeek + BLOCK_WEEKS - 1,
    name: hills ? 'Heuvels en tempo' : 'Tempo',
    focus: hills
      ? 'Om de week een heuvelloop in plaats van de tempoloop. Kracht zwaarder.'
      : 'Elke dinsdag een tempoloop die langer wordt. Lange loop tot bijna 2 uur.',
  };
}

/** Weeknummer sinds de start (1 = week van 16 november 2026). */
export function weekOf(date: ISODate): number {
  return Math.floor(diffDays(date, PLAN_START) / 7) + 1;
}

export function mondayOfWeek(week: number): ISODate {
  return addDays(PLAN_START, (week - 1) * 7);
}

/** Week binnen het blok, 1-based. */
export function weekInBlock(week: number): number {
  return week - blockOfWeek(week).firstWeek + 1;
}

export function isTestWeek(week: number): boolean {
  return week >= 1 && week === blockOfWeek(week).lastWeek;
}

// ---------------------------------------------------------------------------
// Krachtoefeningen per niveau (niveau 0 = blok 1, daarna zwaarder, max 2)
// ---------------------------------------------------------------------------

const ex = (name: string, weight: string, sets: number, reps: string, defaultKg: number, defaultReps: number): Exercise => ({ name, weight, sets, reps, defaultKg, defaultReps });

function legsAndPull(level: number): Exercise[] {
  return [
    [ex('Swings', '28 kg', 8, '10, elke minuut starten', 28, 10), ex('Swings', '28 kg', 10, '10, elke minuut starten', 28, 10), ex('Swings', '28 kg', 10, '12, elke minuut starten', 28, 12)][level],
    [ex('Goblet squat', '28 kg', 3, '8', 28, 8), ex('Goblet squat', '28 kg', 4, '8', 28, 8), ex('Goblet squat', '28 kg', 4, '10', 28, 10)][level],
    [ex('Bulgarian split squat', '20 kg', 3, '8 per been', 20, 8), ex('Bulgarian split squat', '20 kg', 3, '10 per been', 20, 10), ex('Bulgarian split squat', '28 kg', 3, '8 per been', 28, 8)][level],
    [ex('Pull-ups', 'lichaamsgewicht', 4, '3 tot 5', 0, 4), ex('Pull-ups', 'lichaamsgewicht', 5, '4 tot 6', 0, 5), ex('Pull-ups', 'lichaamsgewicht', 5, '5 tot 8', 0, 6)][level],
    [ex('Kuitheffen op 1 been', 'lichaamsgewicht', 3, '15 per been', 0, 15), ex('Kuitheffen op 1 been', 'lichaamsgewicht', 3, '20 per been', 0, 20), ex('Kuitheffen op 1 been', '20 kg', 3, '15 per been', 20, 15)][level],
  ];
}

function pushAndCore(level: number): Exercise[] {
  return [
    [ex('Clean en press', '20 kg', 5, '5 per arm', 20, 5), ex('Clean en press', '20 kg', 5, '8 per arm', 20, 8), ex('Push press', '28 kg', 5, '3 per arm', 28, 3)][level],
    [ex('Eenbenige RDL', '20 kg', 3, '8 per been', 20, 8), ex('Eenbenige RDL', '28 kg', 3, '8 per been', 28, 8), ex('Eenbenige RDL', '28 kg', 3, '10 per been', 28, 10)][level],
    [ex('Step-ups op bank', '20 kg', 3, '10 per been', 20, 10), ex('Step-ups op bank', '20 kg', 3, '12 per been', 20, 12), ex('Step-ups op bank', '28 kg', 3, '8 per been', 28, 8)][level],
    [ex('Push-ups, 3 sec zakken', 'lichaamsgewicht', 3, '20', 0, 20), ex('Push-ups, 3 sec zakken', 'lichaamsgewicht', 4, '20', 0, 20), ex('Push-ups, voeten verhoogd', 'lichaamsgewicht', 4, '15', 0, 15)][level],
    [ex('Suitcase carry', '28 kg', 4, '40 m per kant', 28, 40), ex('Suitcase carry', '28 kg', 4, '60 m per kant', 28, 60), ex('Suitcase carry', '28 kg', 4, '80 m per kant', 28, 80)][level],
    [ex('Hanging knee raises', 'lichaamsgewicht', 3, '10', 0, 10), ex('Hanging knee raises', 'lichaamsgewicht', 3, '12', 0, 12), ex('Hanging leg raises', 'lichaamsgewicht', 3, '8', 0, 8)][level],
  ];
}

const lighten = (list: Exercise[]): Exercise[] => list.map(e => ({ ...e, sets: Math.max(2, Math.ceil(e.sets / 2)) }));

const strengthItem = (kind: 'benen' | 'duwen', level: number, light = false, extra?: string): PlannedItem => {
  const list = kind === 'benen' ? legsAndPull(level) : pushAndCore(level);
  return {
    slotId: `kracht-${kind}`,
    kind: 'strength',
    title: kind === 'benen' ? 'Kracht: benen en trekken' : 'Kracht: duwen, eenbenig en romp',
    minutes: light ? 25 : 40,
    exercises: light ? lighten(list) : list,
    detail: [light ? 'Licht: halve sets, ruim binnen je kunnen.' : 'Stop elke set 1 tot 2 herhalingen voor je niet meer kunt.', extra].filter(Boolean).join(' '),
  };
};

// ---------------------------------------------------------------------------
// Looptrainingen
// ---------------------------------------------------------------------------

const easy = (minutes: number, strides = false): PlannedItem => ({
  slotId: 'run-easy',
  kind: 'run',
  title: 'Rustige loop',
  minutes,
  detail: strides
    ? 'Zone 2, je kunt in hele zinnen praten. Sluit af met 6 keer 20 sec soepel versnellen, 1 min wandelen tussendoor.'
    : 'Zone 2, je kunt in hele zinnen praten.',
});

const commute = (): PlannedItem => ({
  slotId: 'run-commute',
  kind: 'run',
  title: 'Teruglopen van werk',
  minutes: 80,
  detail: '15 km rustig. De auto gaat met je vriendin mee terug. Lukt het niet, dan een rustige loop van 50 min.',
});

const progression = (minutes: number): PlannedItem => ({
  slotId: 'run-quality',
  kind: 'run',
  title: 'Progressieve duurloop',
  minutes,
  detail: 'Rustig beginnen, de laatste 10 min comfortabel hard (losse woorden, geen zinnen).',
});

const tempo = (tempoMin: number): PlannedItem => ({
  slotId: 'run-quality',
  kind: 'run',
  title: `Tempoloop, ${tempoMin} min tempo`,
  minutes: 25 + tempoMin,
  detail: `15 min inlopen, ${tempoMin} min comfortabel hard aan 1 stuk (rond je 10 km-tempo of iets langzamer), 10 min uitlopen. Geen baan nodig.`,
});

const hills = (minutes: number): PlannedItem => ({
  slotId: 'run-quality',
  kind: 'run',
  title: 'Heuvelloop',
  minutes,
  detail: 'Route met heuvels. Elke klim stevig omhoog, boven rustig herstellen, de rest rustig. Geen vaste herhalingen.',
});

const long = (minutes: number, terrain: 'weg' | 'trail'): PlannedItem => ({
  slotId: 'run-long',
  kind: 'run',
  title: `Lange loop (${terrain})`,
  minutes,
  detail: terrain === 'trail' ? 'Rustig. Heuvels omhoog mag stevig, omlaag rustig.' : 'Rustig, je moet kunnen praten.',
});

const optionalEasy = (minutes: number): PlannedItem => ({ ...easy(minutes), slotId: 'run-extra', title: 'Extra rustige loop', optional: true });
const rest = (title = 'Rust', detail?: string): PlannedItem => ({ slotId: 'rust', kind: 'rest', title, detail });
const free = (): PlannedItem => ({ slotId: 'vrij', kind: 'free', title: 'Vrij', detail: 'Rustig fietsen, wandelen of niks. Niet hard fietsen na een lange zaterdag.' });

// ---------------------------------------------------------------------------
// Testweek
// ---------------------------------------------------------------------------

function testWeek(level: number): PlannedItem[][] {
  return [
    [
      { slotId: 'test-pullups', kind: 'test', title: 'Test: strikte pull-ups', detail: 'Uitgerust, na een korte warming-up. Zoveel mogelijk strikte herhalingen in 1 set.' },
      strengthItem('benen', level, true),
    ],
    [{ slotId: 'test-cooper', kind: 'test', title: 'Test: Cooper (12 min)', minutes: 40, detail: '15 min inlopen met een paar versnellingen, dan 12 min zo ver mogelijk, daarna uitlopen. Vlak parcours. Doel: 3000 m.' }],
    [
      strengthItem('duwen', level, true),
      { slotId: 'test-press', kind: 'test', title: 'Test: press 28 kg', optional: true, detail: 'Strikte press met 28 kg, zwakste arm telt. Alleen als je fris bent.' },
    ],
    [easy(30)],
    [rest()],
    [{ slotId: 'test-10k', kind: 'test', title: 'Test: 10 km', minutes: 70, detail: '15 min inlopen, dan 10 km zo snel als je kunt, of een 10 km-wedstrijd. Doel: onder 43 min.' }],
    [{ slotId: 'test-meten', kind: 'test', title: 'Rust en meten', detail: 'Gewicht en buikomtrek op navelhoogte, na het opstaan en voor het ontbijt.' }],
  ];
}

// ---------------------------------------------------------------------------
// Weekschema
// ---------------------------------------------------------------------------

interface WeekSpec {
  light?: boolean;
  test?: boolean;
  note?: string;
  days: PlannedItem[][];
}

function standard(o: { level: number; tue: PlannedItem; thu: PlannedItem; sat: PlannedItem; sun?: PlannedItem[]; light?: boolean; note?: string }): WeekSpec {
  return {
    light: o.light,
    note: o.note,
    days: [
      [strengthItem('benen', o.level, o.light)],
      [o.tue],
      [strengthItem('duwen', o.level, o.light)],
      [o.thu],
      [rest()],
      [o.sat],
      o.sun ?? [free()],
    ],
  };
}

function block1Week(w: number): WeekSpec {
  switch (w) {
    case 1: return standard({ level: 0, tue: easy(35), thu: easy(40), sat: long(90, 'weg') });
    case 2: return standard({ level: 0, tue: easy(40), thu: easy(45), sat: long(95, 'trail') });
    case 3: return standard({ level: 0, tue: easy(45, true), thu: commute(), sat: long(95, 'weg') });
    case 4: return standard({ level: 0, tue: easy(40), thu: easy(40), sat: long(75, 'weg'), sun: [rest()], light: true, note: 'Lichte week.' });
    case 5: return standard({ level: 0, tue: progression(50), thu: commute(), sat: long(100, 'trail') });
    case 6: return standard({ level: 0, tue: progression(50), thu: easy(50), sat: long(105, 'weg') });
    case 7: return standard({ level: 0, tue: progression(55), thu: easy(55), sat: long(110, 'trail') });
    case 8: return {
      light: true,
      note: 'Lichte week.',
      days: [[easy(40)], [strengthItem('benen', 0, true)], [rest()], [rest()], [rest()], [rest()], [rest('Rust', 'Morgen wandelen of 30 min heel rustig.')]],
    };
    default: return { test: true, note: 'Testweek: meet waar je staat.', days: testWeek(0) };
  }
}

function laterWeek(blockNr: number, w: number): WeekSpec {
  const level = Math.min(blockNr - 1, 2);
  const extra = Math.min(blockNr - 2, 3) * 5; // elke blok iets langer, max +15 min
  const hillsBlock = blockNr % 2 === 1;
  if (w === 8) return { test: true, note: 'Testweek: meet waar je staat.', days: testWeek(level) };
  if (w === 4) {
    return standard({ level, tue: easy(40, true), thu: easy(40), sat: long(75, 'weg'), light: true, note: 'Lichte week.' });
  }
  const idx = w < 4 ? w - 1 : w - 2; // 0..5 voor de opbouwweken
  const tempoMin = Math.min([20, 20, 25, 25, 30, 30][idx] + extra, 40);
  const tue = hillsBlock && idx % 2 === 1 ? hills(50 + extra) : tempo(tempoMin);
  const thu = w === 2 || w === 6 ? commute() : easy(45 + idx * 2 + extra);
  const sat = long(Math.min([90, 95, 100, 100, 105, 110][idx] + extra, 120), idx % 2 === 0 ? 'trail' : 'weg');
  return standard({ level, tue, thu, sat, sun: [optionalEasy(40), free()] });
}

export function weekSpec(week: number): WeekSpec {
  const b = blockOfWeek(week);
  const w = week - b.firstWeek + 1;
  return b.nr === 1 ? block1Week(w) : laterWeek(b.nr, w);
}

// ---------------------------------------------------------------------------
// Plan voor een dag, rekening houdend met blokken (Defensie, ziek, wedstrijd)
// ---------------------------------------------------------------------------

export interface DayPlan {
  date: ISODate;
  week: number;
  block?: PlanBlock;
  items: PlannedItem[];
  event?: Block;
  lightWeek: boolean;
  testWeek: boolean;
  weekNote?: string;
  status: 'voor' | 'actief';
}

const BLOCKING: Block['kind'][] = ['defensie', 'ziek', 'anders'];

export function eventOn(date: ISODate, events: Block[]): Block | undefined {
  return events.find(b => !b.deleted && inRange(date, b.start, b.end));
}

export function planForDay(date: ISODate, events: Block[] = []): DayPlan {
  const week = weekOf(date);
  const wd = (diffDays(date, mondayOf(date)) + 7) % 7;
  const event = eventOn(date, events);

  if (week < 1) {
    return { date, week, items: [rest('Nog niet begonnen', 'Het schema start maandag 16 november 2026.')], lightWeek: false, testWeek: false, status: 'voor', event };
  }

  const spec = weekSpec(week);
  let items = spec.days[wd].map(i => ({ ...i }));

  // Defensieweek telt als lichte week: lopen 30% korter
  const weekStart = mondayOfWeek(week);
  const weekEnd = addDays(weekStart, 6);
  const defensieInWeek = events.some(b => !b.deleted && b.kind === 'defensie' && b.start <= weekEnd && b.end >= weekStart);
  let lightWeek = !!spec.light;
  let weekNote = spec.note;
  if (defensieInWeek && !spec.light && !spec.test) {
    lightWeek = true;
    weekNote = 'Defensieweek: lichte week, lopen 30% korter.';
    items = items.map(i => (i.kind === 'run' && i.minutes ? { ...i, minutes: Math.round((i.minutes * 0.7) / 5) * 5 } : i));
  }

  if (event && BLOCKING.includes(event.kind)) {
    const detail = event.kind === 'defensie' ? 'Geen training. Dit telt als belasting.' : event.kind === 'ziek' ? 'Herstellen. Niet inhalen.' : undefined;
    items = [rest(event.label, detail)];
  } else if (event && event.kind === 'wedstrijd') {
    items = [{ slotId: 'race', kind: 'race', title: event.label, detail: 'Wedstrijd. Rustig inlopen, de dag erna rustig of vrij.' }];
  } else {
    const after = events.find(b => !b.deleted && b.kind === 'defensie' && addDays(b.end, 1) === date);
    if (after) items = [rest('Herstel na Defensie', 'Rust of wandelen. Je eerste loop daarna is rustig en kort.')];
    // Dag voor een wedstrijd: kort en rustig
    const before = events.find(b => !b.deleted && b.kind === 'wedstrijd' && addDays(b.start, -1) === date);
    if (before) items = [easy(20, true)];
  }

  return { date, week, block: blockOfWeek(week), items, event, lightWeek, testWeek: !!spec.test, weekNote, status: 'actief' };
}

export function planForWeek(week: number, events: Block[] = []): DayPlan[] {
  const start = mondayOfWeek(week);
  return Array.from({ length: 7 }, (_, i) => planForDay(addDays(start, i), events));
}

/** Geplande loopminuten in een week (zonder optionele lopen). */
export function plannedRunMinutes(week: number, events: Block[] = []): number {
  return planForWeek(week, events)
    .flatMap(d => d.items)
    .filter(i => (i.kind === 'run' || (i.kind === 'test' && i.minutes)) && !i.optional)
    .reduce((s, i) => s + (i.minutes ?? 0), 0);
}

/** Pull-ups tussendoor ('grease the groove') op ma t/m vr. */
export function gtgDay(date: ISODate): boolean {
  const wd = (diffDays(date, mondayOf(date)) + 7) % 7;
  return weekOf(date) >= 1 && wd < 5;
}

/** Eerstvolgende testweek (maandag) vanaf een datum. */
export function nextTestWeek(date: ISODate): ISODate {
  let w = Math.max(weekOf(date), 1);
  while (!isTestWeek(w)) w++;
  return mondayOfWeek(w);
}

// ---------------------------------------------------------------------------
// Doelen
// ---------------------------------------------------------------------------

export type GoalMetric = 'cooper' | 'tenK' | 'waist';

export interface Goal {
  id: string;
  title: string;
  metric: GoalMetric;
  target?: number;
  lowerIsBetter?: boolean;
  unit: string;
}

export const GOALS: Goal[] = [
  { id: 'cooper', title: '3000 m op de Cooper-test', metric: 'cooper', target: 3000, unit: 'm' },
  { id: 'tenK', title: '10 km onder 43 minuten', metric: 'tenK', target: 43 * 60, lowerIsBetter: true, unit: '' },
  { id: 'build', title: 'Fitte bouw', metric: 'waist', lowerIsBetter: true, unit: 'cm buikomtrek' },
];
