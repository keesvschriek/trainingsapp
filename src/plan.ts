import { addDays, diffDays, inRange, mondayOf, type ISODate } from './dates';
import type { Block, Move } from './db';

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
  light?: boolean;
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
    return { nr: 1, firstWeek: 1, lastWeek: FIRST_BLOCK_WEEKS, name: 'Basis', focus: 'Vaker lopen, alles rustig. Drie korte krachttrainingen per week worden routine. Afsluiten met de eerste testweek.' };
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
// Krachtoefeningen: drie korte trainingen per week, per spiergroep.
// Niveau 0 = blok 1, daarna zwaarder (max niveau 2).
// "bijna max" = zoveel als je kunt, met 1 herhaling over.
// ---------------------------------------------------------------------------

const ex = (name: string, weight: string, sets: number, reps: string, defaultKg: number, defaultReps: number): Exercise => ({ name, weight, sets, reps, defaultKg, defaultReps });
const pick = <T,>(level: number, options: T[]): T => options[Math.min(level, options.length - 1)];

/** Maandag: rug, biceps en squats */
function backDay(level: number): Exercise[] {
  return [
    pick(level, [ex('Goblet squat', '28 kg', 3, '10', 28, 10), ex('Goblet squat', '28 kg', 3, '12', 28, 12), ex('Goblet squat, 3 sec zakken', '28 kg', 3, '10', 28, 10)]),
    pick(level, [ex('Pull-ups', 'lichaamsgewicht', 4, 'bijna max', 0, 5), ex('Pull-ups', 'lichaamsgewicht', 5, 'bijna max', 0, 6), ex('Pull-ups, 3 sec zakken', 'lichaamsgewicht', 5, 'bijna max', 0, 6)]),
    pick(level, [ex('Eenarmige row', '28 kg', 3, '10 per arm', 28, 10), ex('Eenarmige row', '28 kg', 4, '10 per arm', 28, 10), ex('Eenarmige row', '28 kg', 4, '12 per arm', 28, 12)]),
    pick(level, [ex('Kettlebell curl', '20 kg', 3, '8 tot 10', 20, 8), ex('Kettlebell curl', '20 kg', 3, '10 tot 12', 20, 10), ex('Kettlebell curl, 3 sec zakken', '20 kg', 3, '8 tot 10', 20, 8)]),
    ex('Face pulls met band', 'band', 2, '15 tot 20', 0, 15),
  ];
}

/** Woensdag: borst, schouders en triceps */
function chestDay(level: number): Exercise[] {
  return [
    pick(level, [ex('Push-ups', 'lichaamsgewicht', 4, 'bijna max', 0, 25), ex('Push-ups, voeten verhoogd', 'lichaamsgewicht', 4, 'bijna max', 0, 20), ex('Push-ups, voeten verhoogd, 3 sec zakken', 'lichaamsgewicht', 4, 'bijna max', 0, 15)]),
    pick(level, [ex('Floor press', '28 kg', 3, '8 tot 10 per arm', 28, 8), ex('Floor press', '28 kg', 3, '10 tot 12 per arm', 28, 10), ex('Floor press, 2 sec pauze onderin', '28 kg', 4, '8 per arm', 28, 8)]),
    pick(level, [ex('Strikte press', '20 kg', 3, '6 tot 8 per arm', 20, 6), ex('Strikte press', '20 kg', 3, '8 tot 10 per arm', 20, 8), ex('Strikte press', '28 kg', 4, '2 tot 4 per arm', 28, 3)]),
    ex('Zijwaarts heffen met band', 'band', 3, '15 tot 20', 0, 15),
    pick(level, [ex('Triceps extensie boven het hoofd', '20 kg', 3, '10 tot 12', 20, 10), ex('Triceps extensie boven het hoofd', '20 kg', 3, '12 tot 15', 20, 12), ex('Diamant push-ups', 'lichaamsgewicht', 3, 'bijna max', 0, 15)]),
  ];
}

/** Vrijdag: kort en gemengd */
function mixDay(level: number): Exercise[] {
  return [
    pick(level, [ex('Goblet squat', '28 kg', 2, '12', 28, 12), ex('Goblet squat', '28 kg', 3, '12', 28, 12), ex('Goblet squat, 3 sec zakken', '28 kg', 3, '12', 28, 12)]),
    pick(level, [ex('Chin-ups (onderhands)', 'lichaamsgewicht', 3, 'bijna max', 0, 6), ex('Chin-ups (onderhands)', 'lichaamsgewicht', 4, 'bijna max', 0, 7), ex('Chin-ups, 3 sec zakken', 'lichaamsgewicht', 4, 'bijna max', 0, 6)]),
    pick(level, [ex('Push-ups, brede greep', 'lichaamsgewicht', 3, 'bijna max', 0, 20), ex('Push-ups, brede greep', 'lichaamsgewicht', 4, 'bijna max', 0, 20), ex('Push-ups, 3 sec zakken', 'lichaamsgewicht', 4, 'bijna max', 0, 15)]),
    pick(level, [ex('Eenarmige row', '20 kg', 3, '15 per arm', 20, 15), ex('Eenarmige row', '28 kg', 3, '12 per arm', 28, 12), ex('Eenarmige row', '28 kg', 3, '15 per arm', 28, 15)]),
    ex('Kuitheffen op 1 been', 'lichaamsgewicht', 2, '20 per been', 0, 20),
  ];
}

type StrengthDay = 'rug' | 'borst' | 'mix';
const STRENGTH_DAY: Record<StrengthDay, { title: string; list: (l: number) => Exercise[]; minutes: number }> = {
  rug: { title: 'Kracht: rug, biceps en squats', list: backDay, minutes: 30 },
  borst: { title: 'Kracht: borst, schouders en triceps', list: chestDay, minutes: 30 },
  mix: { title: 'Kracht: kort en gemengd', list: mixDay, minutes: 25 },
};

const lighten = (list: Exercise[]): Exercise[] => list.map(e => ({ ...e, light: true, sets: Math.max(1, Math.ceil(e.sets / 2)), reps: e.reps.replace('bijna max', 'rustig, ver van falen') }));

const strengthItem = (day: StrengthDay, level: number, light = false): PlannedItem => {
  const d = STRENGTH_DAY[day];
  return {
    slotId: `kracht-${day}`,
    kind: 'strength',
    title: d.title,
    minutes: light ? 15 : d.minutes,
    exercises: light ? lighten(d.list(level)) : d.list(level),
    detail: light
      ? 'Licht: halve sets, ruim binnen je kunnen.'
      : 'Sets dicht bij falen (1 tot 2 herhalingen over). Combineer twee oefeningen om en om om tijd te besparen.',
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
      { slotId: 'test-pushups', kind: 'test', title: 'Test: push-ups', detail: 'Na de pull-uptest en voor de krachttraining. 1 set zo veel mogelijk, borst tot vlak boven de vloer, lichaam recht. Stop als je romp doorzakt. Vandaag geen push-ups tussendoor.' },
      strengthItem('rug', level, true),
    ],
    [{ slotId: 'test-cooper', kind: 'test', title: 'Test: Cooper (12 min)', minutes: 40, detail: '15 min inlopen met een paar versnellingen, dan 12 min zo ver mogelijk, daarna uitlopen. Vlak parcours. Doel: 3000 m.' }],
    [
      strengthItem('borst', level, true),
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
      [strengthItem('rug', o.level, o.light)],
      [o.tue],
      [strengthItem('borst', o.level, o.light)],
      [o.thu],
      [strengthItem('mix', o.level, o.light)],
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
      days: [[easy(40)], [strengthItem('rug', 0, true)], [rest()], [rest()], [rest()], [rest()], [rest('Rust', 'Morgen wandelen of 30 min heel rustig.')]],
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
// Verschuiven
// Een shift op dag a zet daar een rustdag neer; alles vanaf a schuift een dag op
// tot de eerstvolgende rust- of vrije dag, die verdwijnt. Is er geen vrije dag meer
// in de week, dan schuift de laatste dag door naar de maandag van de week erna.
// ---------------------------------------------------------------------------

const isEmptyDay = (d: PlannedItem[]) => d.every(i => i.kind === 'rest' || i.kind === 'free' || i.optional);

const shiftedRest = (): PlannedItem => ({ slotId: 'rust', kind: 'rest', title: 'Rust (verschoven)', detail: 'De training van vandaag staat nu op een latere dag.' });

function insertAt(days: PlannedItem[][], a: number, content: PlannedItem[]): PlannedItem[] | null {
  const j = days.findIndex((d, idx) => idx > a && isEmptyDay(d));
  if (j >= 0) {
    days.splice(j, 1);
    days.splice(a, 0, content);
    return null;
  }
  const overflow = days[6];
  days.splice(6, 1);
  days.splice(a, 0, content);
  return isEmptyDay(overflow) ? null : overflow;
}

const weekCache = new Map<string, { days: PlannedItem[][]; carry: PlannedItem[] | null; moved: boolean }>();

/** Dagen van een week na verschuivingen, plus wat doorschuift naar de week erna. */
export function daysOfWeek(week: number, moves: Move[] = [], depth = 0): { days: PlannedItem[][]; carry: PlannedItem[] | null; moved: boolean } {
  const live = moves.filter(m => !m.deleted);
  const key = `${week}|${live.map(m => `${m.id}:${m.updatedAt}:${m.op}:${m.week}:${m.a}:${m.b ?? ''}:${m.at}`).join(',')}`;
  const hit = weekCache.get(key);
  if (hit) return hit;

  const days = weekSpec(week).days.map(d => d.map(i => ({ ...i })));
  let carry: PlannedItem[] | null = null;
  let moved = false;

  // Doorgeschoven training uit de vorige week komt op maandag
  if (depth < 6 && live.some(m => m.week === week - 1 || m.week < week - 1)) {
    const prev = daysOfWeek(week - 1, live, depth + 1);
    if (prev.carry) {
      carry = insertAt(days, 0, prev.carry);
      moved = true;
    }
  }

  for (const m of live.filter(m => m.week === week).sort((x, y) => x.at - y.at)) {
    moved = true;
    if (m.op === 'swap' && m.b != null) {
      [days[m.a], days[m.b]] = [days[m.b], days[m.a]];
    } else if (m.op === 'shift') {
      const out = insertAt(days, m.a, [shiftedRest()]);
      if (out) carry = carry ? [...carry, ...out] : out;
    }
  }

  const result = { days, carry, moved };
  if (weekCache.size > 500) weekCache.clear();
  weekCache.set(key, result);
  return result;
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
  moved?: boolean;
}

const BLOCKING: Block['kind'][] = ['defensie', 'ziek', 'anders'];

export function eventOn(date: ISODate, events: Block[]): Block | undefined {
  return events.find(b => !b.deleted && inRange(date, b.start, b.end));
}

export function planForDay(date: ISODate, events: Block[] = [], moves: Move[] = []): DayPlan {
  const week = weekOf(date);
  const wd = (diffDays(date, mondayOf(date)) + 7) % 7;
  const event = eventOn(date, events);

  if (week < 1) {
    return { date, week, items: [rest('Nog niet begonnen', 'Het schema start maandag 16 november 2026.')], lightWeek: false, testWeek: false, status: 'voor', event };
  }

  const spec = weekSpec(week);
  const weekDays = daysOfWeek(week, moves);
  let items = weekDays.days[wd].map(i => ({ ...i }));

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

  return { date, week, block: blockOfWeek(week), items, event, lightWeek, testWeek: !!spec.test, weekNote, status: 'actief', moved: weekDays.moved };
}

export function planForWeek(week: number, events: Block[] = [], moves: Move[] = []): DayPlan[] {
  const start = mondayOfWeek(week);
  return Array.from({ length: 7 }, (_, i) => planForDay(addDays(start, i), events, moves));
}

/** Geplande loopminuten in een week (zonder optionele lopen). */
export function plannedRunMinutes(week: number, events: Block[] = [], moves: Move[] = []): number {
  return planForWeek(week, events, moves)
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
