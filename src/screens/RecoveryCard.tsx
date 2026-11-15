import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, getSetting, newId, save, type Checkin } from '../db';
import { addDays, dayName, diffDays, mondayOf, today as todayFn } from '../dates';
import { loadSeries, recoveryFor, baseline, type Physio } from '../recovery';
import { planForDay, weekOf } from '../plan';
import { Icon, useBlocks, useMoves } from '../ui';
import type { WellnessDay } from '../intervals';
import { Why } from '../explain';

const QUESTIONS: { key: keyof Pick<Checkin, 'sleep' | 'legs' | 'energy' | 'calm'>; label: string; low: string; high: string }[] = [
  { key: 'sleep', label: 'Slaap', low: 'slecht', high: 'top' },
  { key: 'legs', label: 'Benen en spieren', low: 'zwaar, pijn', high: 'fris' },
  { key: 'energy', label: 'Energie en zin', low: 'leeg', high: 'vol' },
  { key: 'calm', label: 'Hoofd', low: 'druk', high: 'rustig' },
];

export function RecoveryCard() {
  const date = todayFn();
  const events = useBlocks();
  const moves = useMoves();
  const [editing, setEditing] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [answers, setAnswers] = useState<Partial<Record<string, number>>>({});

  const checkin = useLiveQuery(async () => {
    const c = await db.checkins.get(`checkin-${date}`);
    return c && !c.deleted ? c : null;
  }, [date]);
  const workouts = useLiveQuery(async () => (await db.workouts.where('date').above(addDays(date, -200)).toArray()).filter(alive), [date], []);
  const wellness = useLiveQuery(() => getSetting<Record<string, WellnessDay>>('wellness', {}), [], {});

  if (checkin === undefined) return null;

  const series = loadSeries(workouts, addDays(date, -1), addDays(date, 7), date, events, moves);
  const todayRow = series.find(d => d.date === date);
  const yesterday = series.find(d => d.date === addDays(date, -1));
  const future = series.filter(d => d.date > date && d.formPct != null);
  const lowest = future.reduce<typeof future[number] | null>((m, d) => (!m || (d.formPct ?? 0) < (m.formPct ?? 0) ? d : m), null);

  const w: Record<string, WellnessDay> = (wellness ?? {}) as Record<string, WellnessDay>;
  const days = Object.values(w);
  const physio: Physio = {
    restingHR: w[date]?.restingHR,
    restingBase: baseline(days.map(d => ({ date: d.date, v: d.restingHR })), date),
    hrv: w[date]?.hrv,
    hrvBase: baseline(days.map(d => ({ date: d.date, v: d.hrv })), date, 7),
  };

  const rec = recoveryFor({ checkin: checkin ?? undefined, formPct: todayRow?.formPct ?? null, physio, yesterdayLoad: yesterday?.load ?? 0 });
  const todayPlan = planForDay(date, events, moves);
  const hasTraining = todayPlan.items.some(i => ['run', 'strength', 'test'].includes(i.kind) && !i.optional);

  async function submit() {
    if (QUESTIONS.some(q => !answers[q.key])) return;
    await save('checkins', { id: `checkin-${date}`, date, sleep: answers.sleep!, legs: answers.legs!, energy: answers.energy!, calm: answers.calm! });
    setEditing(false);
  }

  async function shiftToday() {
    await save('moves', { id: newId(), week: weekOf(date), op: 'shift', a: (diffDays(date, mondayOf(date)) + 7) % 7, at: Date.now() });
  }

  if (!checkin || editing) {
    return (
      <div className="card">
        <div className="spread"><strong>Hoe voel je je vandaag?</strong><span className="muted small">check-in, 10 sec</span></div>
        {QUESTIONS.map(q => (
          <div key={q.key} style={{ marginTop: 10 }}>
            <div className="spread small"><span>{q.label}</span><span className="muted">{q.low} … {q.high}</span></div>
            <div className="seg" style={{ marginBottom: 0, marginTop: 4 }}>
              {[1, 2, 3, 4, 5].map(n => (
                <button key={n} className={answers[q.key] === n ? 'active' : ''} onClick={() => setAnswers({ ...answers, [q.key]: n })}>{n}</button>
              ))}
            </div>
          </div>
        ))}
        <button className="btn block mt" onClick={submit} disabled={QUESTIONS.some(q => !answers[q.key])}>Opslaan</button>
      </div>
    );
  }

  if (!expanded) {
    return (
      <div className={`rowcard recovery ${rec.level}`} onClick={() => setExpanded(true)} role="button">
        <span className={`dot ${rec.level}`} />
        <div className="grow">
          <div className="lbl">Herstel</div>
          <div className="val"><span className="level">{rec.level}</span> <span className="muted" style={{ fontWeight: 400 }}>· {rec.short}</span></div>
        </div>
        <span className="big">{rec.score}</span>
        <svg className="chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8}><path d="M6 9l6 6 6-6" /></svg>
      </div>
    );
  }

  return (
    <div className={`card recovery ${rec.level}`}>
      <div className="spread">
        <div>
          <div className="muted small">Herstel</div>
          <div className="score">{rec.score} <span className="level">{rec.level}</span></div>
        </div>
        <div className="stack">
          <button className="icon-btn" onClick={() => setExpanded(false)} aria-label="Inklappen" style={{ transform: 'rotate(180deg)' }}>{Icon.down}</button>
          <button className="btn ghost small" onClick={() => { setAnswers({ sleep: checkin.sleep, legs: checkin.legs, energy: checkin.energy, calm: checkin.calm }); setEditing(true); }}>Check-in aanpassen</button>
        </div>
      </div>
      <p style={{ marginTop: 6 }}>{rec.advice}</p>
      {rec.level === 'rood' && hasTraining && !todayPlan.moved && (
        <button className="btn secondary small" onClick={shiftToday}>Schuif vandaag op naar morgen</button>
      )}
      <table className="mt">
        <tbody>
          {rec.parts.map(p => (
            <tr key={p.label}><td className="muted">{p.label}</td><td style={{ textAlign: 'right' }}>{p.value}</td></tr>
          ))}
        </tbody>
      </table>
      {lowest && lowest.formPct != null && lowest.formPct < -20 && (
        <p className="muted small mt">
          Verwachting: je vermoeidheid is het hoogst op {dayName(lowest.date)} (vorm {Math.round(lowest.formPct)}%). Slaap en eet daar goed omheen.
        </p>
      )}
      {!physioAvailable(physio) && (
        <p className="muted small">Rusthartslag en HRV tellen mee als je je horloge ook 's nachts draagt. Zonder dat werkt het ook, op gevoel en belasting.</p>
      )}
      <Why topic="recovery" />
    </div>
  );
}

function physioAvailable(p: Physio) {
  return !!(p.restingHR && p.restingBase) || !!(p.hrv && p.hrvBase);
}
