import { addDays, diffDays, type ISODate } from './dates';
import type { Block, Checkin, Move, Workout } from './db';
import { planForDay, type PlannedItem } from './plan';

// ---------------------------------------------------------------------------
// Herstel en belasting
//
// Belasting per training = duur (min) x zwaarte (1-10), de session-RPE-methode van Foster.
// Fitheid = gemiddelde belasting over ~6 weken, vermoeidheid = over ~1 week
// (exponentieel gewogen, zoals het fitness/fatigue-model van Banister dat ook
// TrainingPeaks en intervals.icu gebruiken). Vorm = fitheid - vermoeidheid.
//
// Dit is een indicatie, geen diagnose. Je eigen gevoel (check-in) weegt het zwaarst.
// ---------------------------------------------------------------------------

const ATL_DAYS = 7;
const CTL_DAYS = 42;

/** Standaard zwaarte als je zelf niets invult. */
export function defaultRpe(w: Pick<Workout, 'kind' | 'slotId' | 'title' | 'distanceKm' | 'durationMin'>): number {
  if (w.kind === 'strength') return 6;
  if (w.kind === 'run') {
    if (w.slotId === 'test-cooper' || w.slotId === 'test-10k' || w.slotId === 'race') return 8;
    if (w.slotId === 'run-quality') return 6;
    if (w.slotId === 'run-long') return 4;
    // Uit Garmin zonder slot: schat aan de hand van het tempo
    if (w.distanceKm && w.durationMin) {
      const pace = w.durationMin / w.distanceKm; // min per km
      if (pace < 4.6) return 7;
      if (pace < 5.2) return 5;
    }
    return 3;
  }
  return 3;
}

export function workoutLoad(w: Workout): number {
  const minutes = w.durationMin ?? (w.kind === 'strength' ? 30 : 0);
  return minutes * (w.rpe ?? defaultRpe(w));
}

function itemRpe(i: PlannedItem): number {
  if (i.kind === 'strength') return 6;
  if (i.kind === 'race' || i.slotId === 'test-cooper' || i.slotId === 'test-10k') return 8;
  if (i.slotId === 'run-quality') return 6;
  if (i.slotId === 'run-long') return 4;
  if (i.kind === 'run') return 3;
  return 0;
}

export function plannedLoad(date: ISODate, events: Block[], moves: Move[]): number {
  return planForDay(date, events, moves).items
    .filter(i => !i.optional)
    .reduce((s, i) => s + (i.minutes ?? (i.kind === 'race' ? 50 : 0)) * itemRpe(i), 0);
}

export interface LoadDay {
  date: ISODate;
  load: number;
  fitness: number; // CTL
  fatigue: number; // ATL
  form: number; // TSB = CTL - ATL (van de dag ervoor, zoals gebruikelijk)
  formPct: number | null; // TSB / CTL x 100
  planned: boolean;
}

/**
 * Berekent fitheid, vermoeidheid en vorm per dag, van `from` tot `to`.
 * Dagen na vandaag gebruiken de geplande trainingen: dat is de voorspelling.
 */
export function loadSeries(workouts: Workout[], from: ISODate, to: ISODate, today: ISODate, events: Block[] = [], moves: Move[] = []): LoadDay[] {
  const byDate = new Map<string, number>();
  for (const w of workouts) byDate.set(w.date, (byDate.get(w.date) ?? 0) + workoutLoad(w));

  // Opwarmen: begin 120 dagen eerder zodat fitheid al een waarde heeft
  let start = addDays(from, -120);
  const first = [...byDate.keys()].sort()[0];
  if (first && first > start) start = first;

  // Pas na 3 weken gelogde trainingen zegt vorm (TSB%) iets
  const enoughHistory = !!first && diffDays(today, first) >= 21;
  let ctl = 0;
  let atl = 0;
  const out: LoadDay[] = [];
  for (let d = start; d <= to; d = addDays(d, 1)) {
    const planned = d > today;
    const load = planned ? plannedLoad(d, events, moves) : byDate.get(d) ?? 0;
    const form = ctl - atl; // vorm aan het begin van de dag
    ctl += (load - ctl) / CTL_DAYS;
    atl += (load - atl) / ATL_DAYS;
    if (d >= from) out.push({ date: d, load, fitness: ctl, fatigue: atl, form, formPct: enoughHistory && ctl >= 15 ? Math.max(-80, Math.min(80, (form / ctl) * 100)) : null, planned });
  }
  return out;
}

export interface Physio {
  restingHR?: number;
  restingBase?: number;
  hrv?: number;
  hrvBase?: number;
  sleepHours?: number;
}

export interface Recovery {
  score: number;
  level: 'groen' | 'oranje' | 'rood';
  advice: string;
  short: string;
  parts: { label: string; value: string; score: number | null }[];
  enoughData: boolean;
}

const clamp = (v: number, lo = 0, hi = 100) => Math.max(lo, Math.min(hi, v));

/** Vorm (TSB%) naar een score: licht negatief is normaal tijdens trainen. */
export function formScore(formPct: number | null): number | null {
  if (formPct == null) return null;
  if (formPct >= -10) return 100;
  if (formPct >= -30) return clamp(100 - ((-10 - formPct) / 20) * 50); // -10 -> 100, -30 -> 50
  return clamp(50 - ((-30 - formPct) / 20) * 40); // -50 -> 10
}

export function recoveryFor(opts: { checkin?: Checkin; formPct: number | null; physio?: Physio; yesterdayLoad: number }): Recovery {
  const parts: Recovery['parts'] = [];
  const weighted: [number, number][] = [];

  if (opts.checkin) {
    const c = opts.checkin;
    const avg = (c.sleep + c.legs + c.energy + c.calm) / 4;
    const s = clamp(((avg - 1) / 4) * 100);
    // Eén heel slechte score (1) trekt het geheel extra omlaag
    const worst = Math.min(c.sleep, c.legs, c.energy, c.calm);
    const sAdj = worst === 1 ? Math.min(s, 45) : s;
    parts.push({ label: 'Gevoel (check-in)', value: `${avg.toLocaleString('nl-NL', { maximumFractionDigits: 1 })} van 5`, score: sAdj });
    weighted.push([sAdj, 0.5]);
  } else {
    parts.push({ label: 'Gevoel (check-in)', value: 'nog niet ingevuld', score: null });
  }

  const fs = formScore(opts.formPct);
  parts.push({
    label: 'Belasting (vorm)',
    value: opts.formPct == null ? 'nog te weinig data' : `${Math.round(opts.formPct)}%`,
    score: fs,
  });
  if (fs != null) weighted.push([fs, 0.35]);

  const p = opts.physio;
  if (p?.restingHR && p.restingBase) {
    const diff = p.restingHR - p.restingBase;
    const s = diff >= 7 ? 20 : diff >= 4 ? 55 : diff >= 2 ? 80 : 100;
    parts.push({ label: 'Rusthartslag', value: `${p.restingHR} (normaal ${Math.round(p.restingBase)})`, score: s });
    weighted.push([s, 0.1]);
  }
  if (p?.hrv && p.hrvBase) {
    const pct = ((p.hrv - p.hrvBase) / p.hrvBase) * 100;
    const s = pct <= -20 ? 25 : pct <= -10 ? 60 : 100;
    parts.push({ label: 'HRV', value: `${Math.round(p.hrv)} ms (normaal ${Math.round(p.hrvBase)})`, score: s });
    weighted.push([s, 0.1]);
  }

  // Zware dag gisteren (> 300 = bijv. 75 min op zwaarte 4)
  if (opts.yesterdayLoad > 300) {
    parts.push({ label: 'Gisteren', value: 'zware dag', score: 60 });
    weighted.push([60, 0.1]);
  }

  const total = weighted.reduce((s, [, w]) => s + w, 0);
  const score = total ? Math.round(weighted.reduce((s, [v, w]) => s + v * w, 0) / total) : 75;
  const level: Recovery['level'] = score >= 70 ? 'groen' : score >= 50 ? 'oranje' : 'rood';
  const advice = level === 'groen'
    ? 'Train zoals gepland.'
    : level === 'oranje'
      ? 'Train, maar houd het rustig: een tempoloop wordt een rustige loop, bij kracht 1 set minder per oefening.'
      : 'Neem rust of wandel. Schuif de training van vandaag een dag op.';
  const short = level === 'groen' ? 'train zoals gepland' : level === 'oranje' ? 'houd het rustig' : 'rust vandaag';
  return { score, level, advice, short, parts, enoughData: !!opts.checkin || fs != null };
}

/** Basislijn: gemiddelde over de afgelopen 30 dagen, zonder vandaag. */
export function baseline(values: { date: ISODate; v?: number | null }[], today: ISODate, days = 30): number | undefined {
  const list = values.filter(x => x.v != null && x.date < today && diffDays(today, x.date) <= days).map(x => x.v as number);
  if (list.length < 5) return undefined;
  return list.reduce((a, b) => a + b, 0) / list.length;
}
