import type { Block, Check, Metric, Move, Workout } from './db';
import { addDays, type ISODate } from './dates';
import { mondayOfWeek, planForWeek, weekOf as weekOfDate, type PlannedItem } from './plan';
import { matchDay } from './match';
import { driftRuns } from './aerobic';
import { restReason } from './pushups';

// Weekterugblik: wat stond er, wat is gedaan, en wat komt er volgende week.

const isTraining = (i: PlannedItem) => i.kind !== 'rest' && i.kind !== 'free' && !i.optional;

export interface WeekReview {
  week: number;
  monday: ISODate;
  sunday: ISODate;
  planned: number;
  done: number;
  missed: { date: ISODate; title: string }[];
  openToday: string[];
  runs: number;
  runsPlanned: number;
  runMin: number;
  runMinPlanned: number;
  runKm: number;
  strength: number;
  strengthPlanned: number;
  strengthRpe?: number;
  extra: string[];
  pushups: number;
  pushupDays: number;
  pushupDaysPossible: number;
  pullups: number;
  drift?: number;
  driftPrev?: number;
  next: string[];
  verdict: string;
}

export interface ReviewData {
  workouts: Workout[];
  checks: Check[];
  metrics: Metric[];
  events: Block[];
  moves: Move[];
  pushupGoal: number;
}

const avg = (a: number[]) => (a.length ? Math.round((a.reduce((s, x) => s + x, 0) / a.length) * 10) / 10 : undefined);

export function weekReview(week: number, today: ISODate, d: ReviewData): WeekReview {
  const monday = mondayOfWeek(week);
  const sunday = addDays(monday, 6);
  const days = planForWeek(week, d.events, d.moves);
  const inWeek = (x: { date: ISODate }) => x.date >= monday && x.date <= sunday;
  const workouts = d.workouts.filter(w => !w.deleted && inWeek(w));
  const checks = d.checks.filter(c => !c.deleted && inWeek(c));

  let planned = 0;
  let done = 0;
  let runsPlanned = 0;
  let runMinPlanned = 0;
  let strengthPlanned = 0;
  const missed: WeekReview['missed'] = [];
  const openToday: string[] = [];
  const extra: string[] = [];
  for (const day of days) {
    if (day.date > today) continue;
    const items = day.items.filter(isTraining);
    const { statuses, extra: ex } = matchDay(items, workouts.filter(w => w.date === day.date), checks.filter(c => c.date === day.date));
    for (const st of statuses) {
      planned++;
      if (st.item.kind === 'run') {
        runsPlanned++;
        runMinPlanned += st.item.minutes ?? 0;
      }
      if (st.item.kind === 'strength') strengthPlanned++;
      if (st.done) done++;
      else if (day.date === today) openToday.push(st.item.title);
      else missed.push({ date: day.date, title: st.item.title });
    }
    for (const w of ex) extra.push(w.title);
  }

  const runs = workouts.filter(w => w.kind === 'run');
  const strengthW = workouts.filter(w => w.kind === 'strength');
  const pushupSets = d.metrics.filter(m => !m.deleted && m.kind === 'pushups' && inWeek(m));
  const perDay = new Map<ISODate, number>();
  for (const m of pushupSets) perDay.set(m.date, (perDay.get(m.date) ?? 0) + m.value);
  let pushupDaysPossible = 0;
  let pushupDays = 0;
  for (const day of days) {
    if (day.date > today) continue;
    if (restReason(day.items)) continue;
    pushupDaysPossible++;
    if ((perDay.get(day.date) ?? 0) >= d.pushupGoal) pushupDays++;
  }
  const pullups = d.metrics.filter(m => !m.deleted && m.kind === 'gtg' && inWeek(m)).reduce((s, m) => s + m.value, 0);

  const isQuality = (date: ISODate) => {
    const items = planForWeek(weekOfDate(date), d.events, d.moves).find(x => x.date === date)?.items ?? [];
    return items.some(i => i.slotId === 'run-quality') && !items.some(i => i.kind === 'run' && i.slotId !== 'run-quality');
  };
  const drifts = driftRuns(d.workouts, isQuality);
  const drift = avg(drifts.filter(inWeek).map(r => r.drift));
  const prevMon = addDays(monday, -7);
  const driftPrev = avg(drifts.filter(r => r.date >= prevMon && r.date < monday).map(r => r.drift));

  // Volgende week
  const nextDays = planForWeek(week + 1, d.events, d.moves);
  const next: string[] = [];
  const nd = nextDays[0];
  if (nd?.testWeek) next.push('Testweek: je meet je vooruitgang. Kracht is licht, de tests staan op Vandaag.');
  else if (nd?.lightWeek) next.push('Lichte week: minder volume, zodat je herstelt.');
  if (nd?.weekNote && !nd.testWeek) next.push(nd.weekNote);
  const nextItems = nextDays.flatMap(x => x.items.filter(isTraining).map(i => ({ i, date: x.date })));
  const long = nextItems.find(x => x.i.slotId === 'run-long');
  if (long?.i.minutes) next.push(`Lange loop: ${long.i.minutes} minuten.`);
  const quality = nextItems.find(x => x.i.slotId === 'run-quality');
  if (quality) next.push(`Kwaliteit: ${quality.i.title}${quality.i.minutes ? `, ${quality.i.minutes} minuten` : ''}.`);
  const blocks = nextDays.filter(x => x.event).map(x => x.event!.label || x.event!.kind);
  if (blocks.length) next.push(`In je agenda: ${[...new Set(blocks)].join(', ')}.`);

  const ratio = planned ? done / planned : 1;
  const verdict =
    planned === 0
      ? 'Er stond deze week niets op het schema.'
      : ratio >= 0.9
        ? `Je hebt ${done} van de ${planned} trainingen gedaan. Het schema past.`
        : ratio >= 0.7
          ? `Je hebt ${done} van de ${planned} trainingen gedaan. Kijk of de gemiste dagen een patroon hebben.`
          : `Je hebt ${done} van de ${planned} trainingen gedaan. Kijk of het schema past naast werk en Defensie, of dat er iets anders speelde.`;

  return {
    week, monday, sunday, planned, done, missed, openToday,
    runs: runs.length, runsPlanned,
    runMin: Math.round(runs.reduce((s, w) => s + (w.durationMin ?? 0), 0)),
    runMinPlanned,
    runKm: Math.round(runs.reduce((s, w) => s + (w.distanceKm ?? 0), 0) * 10) / 10,
    strength: strengthW.length, strengthPlanned,
    strengthRpe: avg(strengthW.map(w => w.rpe).filter((x): x is number => typeof x === 'number')),
    extra,
    pushups: [...perDay.values()].reduce((s, x) => s + x, 0), pushupDays, pushupDaysPossible,
    pullups, drift, driftPrev, next, verdict,
  };
}
