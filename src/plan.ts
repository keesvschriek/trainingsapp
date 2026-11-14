import { addDays, diffDays, inRange, mondayOf, type ISODate } from './dates';
import type { Block } from './db';

// ---------------------------------------------------------------------------
// Trainingsschema richting de eerste 50 km trail.
// Week 1 begint maandag 16 november 2026, de 50 km staat op zaterdag 10 juli 2027.
// ---------------------------------------------------------------------------

export const PLAN_START: ISODate = '2026-11-16';
export const TOTAL_WEEKS = 34;
export const RACE_DATE: ISODate = addDays(PLAN_START, (TOTAL_WEEKS - 1) * 7 + 5);

export type ItemKind = 'run' | 'strength' | 'boxing' | 'rest' | 'free' | 'race';

export interface PlannedItem {
  slotId: string;
  kind: ItemKind;
  title: string;
  detail?: string;
  minutes?: number;
  optional?: boolean;
  strength?: StrengthKey;
}

export type StrengthKey = 'A' | 'B' | 'kort';

export interface Phase {
  nr: number;
  name: string;
  firstWeek: number;
  lastWeek: number;
  focus: string;
}

export const PHASES: Phase[] = [
  { nr: 1, name: 'Basis', firstWeek: 1, lastWeek: 8, focus: 'Vaste routine, alles rustig, kracht 2 keer per week.' },
  { nr: 2, name: 'Opbouw', firstWeek: 9, lastWeek: 20, focus: 'Tempoloop op dinsdag, heuvels in je trailloop, af en toe teruglopen van werk.' },
  { nr: 3, name: 'Ultra-specifiek', firstWeek: 21, lastWeek: 32, focus: 'Lange lopen tot 4,5 uur, back-to-back op zondag, eten en drinken onderweg oefenen.' },
  { nr: 4, name: 'Afbouw', firstWeek: 33, lastWeek: 34, focus: 'Fris aan de start. Minder volume, kracht alleen licht.' },
];

export function phaseOf(week: number): Phase | undefined {
  return PHASES.find(p => week >= p.firstWeek && week <= p.lastWeek);
}

/** Weeknummer (1..34) voor een datum, 0 voor de start en > 34 erna. */
export function weekOf(date: ISODate): number {
  return Math.floor(diffDays(date, PLAN_START) / 7) + 1;
}

export function mondayOfWeek(week: number): ISODate {
  return addDays(PLAN_START, (week - 1) * 7);
}

// ---------------------------------------------------------------------------
// Bouwstenen
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
  minutes: 85,
  detail: '15 km rustig. Je vriendin neemt de auto mee terug.',
});

const tempo = (minutes = 55): PlannedItem => ({
  slotId: 'run-tempo',
  kind: 'run',
  title: 'Tempoloop',
  minutes,
  detail: '15 min inlopen, 20 tot 30 min comfortabel hard (losse woorden, geen zinnen), rest uitlopen.',
});

const long = (minutes: number, terrain: 'weg' | 'trail', detail?: string): PlannedItem => ({
  slotId: 'run-long',
  kind: 'run',
  title: `Lange loop (${terrain})`,
  minutes,
  detail: detail ?? (terrain === 'trail'
    ? 'Rustig. Heuvels omhoog stevig, omlaag rustig. Vanaf 90 min eten en drinken oefenen.'
    : 'Rustig, je moet kunnen praten. Vanaf 90 min eten en drinken oefenen.'),
});

const backToBack = (minutes: number): PlannedItem => ({
  slotId: 'run-b2b',
  kind: 'run',
  title: 'Back-to-back loop',
  minutes,
  detail: 'Rustig op vermoeide benen, de dag na je lange loop.',
});

const strength = (key: StrengthKey, light = false): PlannedItem => ({
  slotId: `kracht-${key}`,
  kind: 'strength',
  strength: key,
  title: key === 'kort' ? 'Kracht kort (A en B)' : `Kracht ${key}${light ? ' (licht)' : ''}`,
  minutes: key === 'kort' ? 30 : 40,
  detail: light ? 'Halve sets, ruim binnen je kunnen.' : 'Stop elke set 1 tot 2 herhalingen voor je niet meer kunt.',
});

const boxing = (rounds: number, optional = false, slot = 'boksen'): PlannedItem => ({
  slotId: slot,
  kind: 'boxing',
  title: `Boksen, ${rounds} rondes`,
  minutes: rounds * 4,
  optional,
  detail: 'Rondes van 3 min, 1 min rust.',
});

const rest = (title = 'Rust', detail?: string): PlannedItem => ({ slotId: 'rust', kind: 'rest', title, detail });
const free = (): PlannedItem => ({
  slotId: 'vrij',
  kind: 'free',
  title: 'Vrij',
  detail: 'Rustig fietsen, wandelen of niks. Niet hard fietsen na een lange zaterdag.',
});
const optionalEasy = (minutes: number): PlannedItem => ({ ...easy(minutes), slotId: 'run-extra', title: 'Extra rustige loop', optional: true });

// ---------------------------------------------------------------------------
// Weekschema's
// ---------------------------------------------------------------------------

interface WeekSpec {
  light?: boolean;
  note?: string;
  days: PlannedItem[][]; // ma t/m zo
}

function standardWeek(o: {
  tue: PlannedItem | null;
  thu: PlannedItem | null;
  sat: PlannedItem | null;
  sun?: PlannedItem[];
  rounds?: number;
  mon?: PlannedItem[];
  wed?: PlannedItem[];
  fri?: PlannedItem[];
  light?: boolean;
  note?: string;
}): WeekSpec {
  const r = o.rounds ?? 3;
  return {
    light: o.light,
    note: o.note,
    days: [
      o.mon ?? [boxing(r), strength('A', o.light)],
      o.tue ? [o.tue] : [rest()],
      o.wed ?? [boxing(r), strength('B', o.light)],
      o.thu ? [o.thu] : [rest()],
      o.fri ?? [rest('Rust', 'Of 4 tot 6 rondes boksen als je zin hebt.')],
      o.sat ? [o.sat] : [rest()],
      o.sun ?? [free()],
    ],
  };
}

function buildWeeks(): WeekSpec[] {
  const w: WeekSpec[] = [];

  // Fase 1: basis (week 1-8)
  w.push(standardWeek({ tue: easy(35), thu: easy(40), sat: long(90, 'weg') }));
  w.push(standardWeek({ tue: easy(40), thu: easy(45), sat: long(95, 'trail') }));
  w.push(standardWeek({ tue: easy(45, true), thu: commute(), sat: long(95, 'weg') }));
  w.push(standardWeek({ tue: easy(40), thu: null, sat: null, sun: [rest()], light: true, note: 'Lichte week.' }));
  w.push(standardWeek({ tue: easy(45, true), thu: commute(), sat: long(105, 'trail'), rounds: 4 }));
  w.push(standardWeek({ tue: easy(50, true), thu: easy(50), sat: long(115, 'weg'), rounds: 4 }));
  w.push(standardWeek({ tue: easy(50, true), thu: easy(55), sat: long(125, 'trail'), rounds: 4 }));
  w.push({
    light: true,
    note: 'Lichte week.',
    days: [[easy(40)], [strength('kort', true)], [rest()], [rest()], [rest()], [rest()], [rest('Rust', 'Morgen wandelen of 30 min heel rustig. Daarna start fase 2.')]],
  });

  // Fase 2: opbouw (week 9-20)
  const longs2 = [130, 140, 150, 115, 155, 165, 175, 125, 170, 180, 180, 130];
  longs2.forEach((min, i) => {
    const week = 9 + i;
    const light = (week % 4) === 0;
    const terrain = i % 2 === 0 ? 'trail' : 'weg';
    const thu = [10, 14, 18].includes(week) ? commute() : easy(light ? 45 : 55);
    w.push(standardWeek({
      tue: light ? easy(45, true) : tempo(),
      thu,
      sat: long(min, terrain),
      sun: !light && week >= 13 ? [optionalEasy(40), free()] : [free()],
      rounds: light ? 3 : 5,
      light,
      note: light ? 'Lichte week.' : undefined,
    }));
  });

  // Fase 3: ultra-specifiek (week 21-32)
  const longs3 = [195, 210, 225, 150, 225, 240, 255, 170, 240, 270, 240, 160];
  const b2b = [60, 70, 80, 0, 80, 90, 90, 0, 45, 90, 80, 0];
  longs3.forEach((min, i) => {
    const week = 21 + i;
    const light = (week % 4) === 0;
    const terrain = i % 2 === 0 ? 'trail' : 'weg';
    const sat = week === 29
      ? long(min, 'trail', 'Generale repetitie: 35 tot 40 km. Zelfde schoenen, rugzak en eten als op de dag zelf.')
      : long(min, terrain);
    const thu = [22, 26, 30].includes(week) ? commute() : easy(light ? 45 : 60);
    w.push(standardWeek({
      mon: [boxing(3), strength('kort', light)],
      tue: light ? easy(45, true) : tempo(60),
      wed: [{ ...strength('B'), optional: true, title: 'Kracht B (optioneel)' }],
      thu,
      sat: sat,
      sun: b2b[i] ? [backToBack(b2b[i])] : [free()],
      light,
      note: light ? 'Lichte week.' : week === 29 ? 'Generale repetitie op zaterdag.' : undefined,
    }));
  });

  // Fase 4: afbouw (week 33-34)
  w.push(standardWeek({
    mon: [strength('kort', true)],
    tue: easy(45, true),
    wed: [boxing(3, true)],
    thu: easy(50),
    sat: long(90, 'trail'),
    sun: [optionalEasy(40)],
    note: 'Afbouw: minder volume, niets nieuws meer proberen.',
  }));
  w.push({
    note: 'Racedag op zaterdag.',
    days: [
      [rest()],
      [easy(40, true)],
      [rest()],
      [easy(30)],
      [rest('Rust', 'Spullen klaarleggen, goed eten, vroeg naar bed.')],
      [{ slotId: 'race', kind: 'race', title: '50 km trail', minutes: 420, detail: 'Rustig starten. Eten vanaf het eerste uur, elke 20 tot 30 min iets.' }],
      [rest('Herstel', 'Wandelen. De komende week alleen rustig bewegen.')],
    ],
  });

  return w;
}

export const WEEKS: WeekSpec[] = buildWeeks();

// ---------------------------------------------------------------------------
// Plan voor een dag, rekening houdend met blokken (Defensie, ziek, vakantie)
// ---------------------------------------------------------------------------

export interface DayPlan {
  date: ISODate;
  week: number;
  phase?: Phase;
  items: PlannedItem[];
  block?: Block;
  lightWeek: boolean;
  weekNote?: string;
  status: 'voor' | 'actief' | 'klaar';
}

const BLOCKING: Block['kind'][] = ['defensie', 'ziek', 'anders'];

export function blockOn(date: ISODate, blocks: Block[]): Block | undefined {
  return blocks.find(b => !b.deleted && inRange(date, b.start, b.end));
}

export function planForDay(date: ISODate, blocks: Block[] = []): DayPlan {
  const week = weekOf(date);
  const wd = (diffDays(date, mondayOf(date)) + 7) % 7;
  const block = blockOn(date, blocks);

  if (week < 1) {
    return { date, week, items: [rest('Nog niet begonnen', 'Het schema start maandag 16 november 2026.')], lightWeek: false, status: 'voor', block };
  }
  if (week > TOTAL_WEEKS) {
    return { date, week, items: [free()], lightWeek: false, status: 'klaar', block };
  }

  const spec = WEEKS[week - 1];
  let items = spec.days[wd].map(i => ({ ...i }));

  // Defensieweek telt als lichte week: lopen 30% korter
  const weekStart = mondayOfWeek(week);
  const weekEnd = addDays(weekStart, 6);
  const defensieInWeek = blocks.some(b => !b.deleted && b.kind === 'defensie' && b.start <= weekEnd && b.end >= weekStart);
  let lightWeek = !!spec.light;
  let weekNote = spec.note;
  if (defensieInWeek && !spec.light) {
    lightWeek = true;
    weekNote = 'Defensieweek: lichte week, lopen 30% korter.';
    items = items.map(i => (i.kind === 'run' && i.minutes ? { ...i, minutes: Math.round((i.minutes * 0.7) / 5) * 5 } : i));
  }

  if (block && BLOCKING.includes(block.kind)) {
    const detail = block.kind === 'defensie' ? 'Geen training. Dit telt als belasting.' : block.kind === 'ziek' ? 'Herstellen. Niet inhalen.' : undefined;
    items = [rest(block.label, detail)];
  } else {
    // Dag na een Defensieblok: rust of wandelen
    const after = blocks.find(b => !b.deleted && b.kind === 'defensie' && addDays(b.end, 1) === date);
    if (after) {
      items = [rest('Herstel na Defensie', 'Rust of wandelen. Je eerste loop daarna is rustig en kort.')];
    }
  }

  return { date, week, phase: phaseOf(week), items, block, lightWeek, weekNote, status: 'actief' };
}

export function planForWeek(week: number, blocks: Block[] = []): DayPlan[] {
  const start = mondayOfWeek(week);
  return Array.from({ length: 7 }, (_, i) => planForDay(addDays(start, i), blocks));
}

/** Geplande loopminuten in een week (zonder optionele lopen). */
export function plannedRunMinutes(week: number, blocks: Block[] = []): number {
  return planForWeek(week, blocks)
    .flatMap(d => d.items)
    .filter(i => (i.kind === 'run' || i.kind === 'race') && !i.optional)
    .reduce((s, i) => s + (i.minutes ?? 0), 0);
}

/** Pull-ups 'grease the groove' alleen op ma t/m vr, binnen het schema. */
export function gtgDay(date: ISODate): boolean {
  const w = weekOf(date);
  const wd = (diffDays(date, mondayOf(date)) + 7) % 7;
  return w >= 1 && w <= TOTAL_WEEKS && wd < 5;
}

// ---------------------------------------------------------------------------
// Krachtoefeningen
// ---------------------------------------------------------------------------

export interface Exercise {
  name: string;
  weight: string;
  sets: number;
  reps: string;
  defaultKg: number;
  defaultReps: number;
  why: string;
}

export const STRENGTH: Record<StrengthKey, Exercise[]> = {
  A: [
    { name: 'Swings', weight: '28 kg', sets: 8, reps: '10, elke minuut starten', defaultKg: 28, defaultReps: 10, why: 'heupkracht, conditie' },
    { name: 'Goblet squat', weight: '28 kg', sets: 3, reps: '8 tot 10', defaultKg: 28, defaultReps: 8, why: 'benen' },
    { name: 'Bulgarian split squat', weight: '20 kg', sets: 3, reps: '8 per been', defaultKg: 20, defaultReps: 8, why: 'eenbenige kracht, kniestabiliteit' },
    { name: 'Pull-ups', weight: 'lichaamsgewicht', sets: 4, reps: '3 tot 5', defaultKg: 0, defaultReps: 4, why: 'rug, grip' },
    { name: 'Kuitheffen 1 been', weight: 'lichaamsgewicht', sets: 3, reps: '15 per been, langzaam zakken', defaultKg: 0, defaultReps: 15, why: 'achillespees en kuit' },
  ],
  B: [
    { name: 'Clean en press', weight: '20 kg', sets: 5, reps: '5 per arm, naar 5 x 8', defaultKg: 20, defaultReps: 5, why: 'schouders, hele keten' },
    { name: 'Eenbenige RDL', weight: '20 of 28 kg', sets: 3, reps: '8 per been', defaultKg: 20, defaultReps: 8, why: 'hamstrings, balans' },
    { name: 'Step-ups', weight: '20 kg', sets: 3, reps: '10 per been', defaultKg: 20, defaultReps: 10, why: 'klimmen op trail' },
    { name: 'Push-ups, 3 sec zakken', weight: 'lichaamsgewicht', sets: 3, reps: '20', defaultKg: 0, defaultReps: 20, why: 'borst, romp' },
    { name: 'Suitcase carry', weight: '28 kg', sets: 4, reps: '40 m per kant', defaultKg: 28, defaultReps: 40, why: 'romp, grip' },
    { name: 'Hanging knee raises', weight: 'lichaamsgewicht', sets: 3, reps: '10', defaultKg: 0, defaultReps: 10, why: 'romp' },
  ],
  kort: [
    { name: 'Swings', weight: '28 kg', sets: 5, reps: '10, elke minuut starten', defaultKg: 28, defaultReps: 10, why: 'heupkracht' },
    { name: 'Bulgarian split squat', weight: '20 kg', sets: 2, reps: '8 per been', defaultKg: 20, defaultReps: 8, why: 'eenbenige kracht' },
    { name: 'Step-ups', weight: '20 kg', sets: 2, reps: '10 per been', defaultKg: 20, defaultReps: 10, why: 'klimmen' },
    { name: 'Kuitheffen 1 been', weight: 'lichaamsgewicht', sets: 3, reps: '15 per been', defaultKg: 0, defaultReps: 15, why: 'achillespees en kuit' },
    { name: 'Clean en press', weight: '20 kg', sets: 3, reps: '5 per arm', defaultKg: 20, defaultReps: 5, why: 'schouders' },
  ],
};

// ---------------------------------------------------------------------------
// Doelen
// ---------------------------------------------------------------------------

export interface Goal {
  id: string;
  title: string;
  deadline: ISODate;
  metric?: 'pullupMax' | 'cooper' | 'pressReps';
  target?: number;
  unit?: string;
}

export const GOALS: Goal[] = [
  { id: 'freq', title: 'Elke week 3 keer lopen', deadline: '2027-01-11' },
  { id: 'pullups', title: '10 strikte pull-ups', deadline: '2027-03-31', metric: 'pullupMax', target: 10, unit: 'herhalingen' },
  { id: 'cooper', title: '3000 m in 12 minuten', deadline: '2027-04-30', metric: 'cooper', target: 3000, unit: 'm' },
  { id: 'press', title: 'Press 28 kg, 1 tot 3 keer per arm', deadline: '2027-08-31', metric: 'pressReps', target: 1, unit: 'herhalingen met 28 kg' },
  { id: 'race', title: 'Eerste 50 km trail', deadline: RACE_DATE },
];
