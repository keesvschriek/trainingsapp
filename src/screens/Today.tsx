import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, save, type Workout, type Metric, type MetricKind } from '../db';
import { addDays, diffDays, longDate, mondayOf, today, minutesToText, shortDate, type ISODate } from '../dates';
import { planForDay, planForWeek, gtgDay, nextTestWeek, weekInBlock, type PlannedItem, type Exercise } from '../plan';
import { matchDay } from '../match';
import { Icon, useBlocks, useMoves, fmt } from '../ui';
import { MoveSheet } from '../moves';
import { RecoveryCard } from './RecoveryCard';
import { MetricEditor, StrengthLogger, TEST_METRIC, WorkoutEditor, METRICS, exercisesFor, formatMetric } from '../editors';

type Editor =
  | { type: 'workout'; initial: Partial<Workout> & { date: ISODate; kind: Workout['kind'] }; existing?: Workout; allowKind?: boolean }
  | { type: 'strength'; title: string; exercises: Exercise[]; slotId?: string; existing?: Workout }
  | { type: 'metric'; kind: MetricKind }
  | { type: 'move' };

export function Today() {
  const [date, setDate] = useState<ISODate>(today());
  const [editor, setEditor] = useState<Editor | null>(null);
  const events = useBlocks();
  const moves = useMoves();
  const plan = planForDay(date, events, moves);

  const workouts = useLiveQuery(async () => (await db.workouts.where('date').equals(date).toArray()).filter(alive), [date], []);
  const checks = useLiveQuery(async () => (await db.checks.where('date').equals(date).toArray()).filter(alive), [date], []);
  const metrics = useLiveQuery(async () => (await db.metrics.where('date').equals(date).toArray()).filter(alive), [date], []);
  const gtg = metrics.find(m => m.id === `gtg-${date}`);

  const monday = mondayOf(date);
  const weekWorkouts = useLiveQuery(
    async () => (await db.workouts.where('date').between(monday, addDays(monday, 6), true, true).toArray()).filter(alive),
    [monday],
    [],
  );

  const { statuses, extra } = matchDay(plan.items, workouts, checks);
  // Testonderdelen zijn klaar zodra de meting is ingevuld
  for (const st of statuses) {
    const kinds = TEST_METRIC[st.item.slotId];
    if (kinds && kinds.every(k => metrics.some(m => m.kind === k))) st.done = true;
  }

  async function toggleCheck(item: PlannedItem, on: boolean) {
    await save('checks', { id: `${date}:${item.slotId}`, date, slotId: item.slotId, done: on });
  }

  async function bumpGtg(delta: number) {
    const value = Math.max(0, (gtg?.value ?? 0) + delta);
    await save('metrics', { id: `gtg-${date}`, date, kind: 'gtg', value } as Metric);
  }

  function open(item: PlannedItem, w?: Workout) {
    if (item.kind === 'strength' && item.exercises) {
      return setEditor({ type: 'strength', title: item.title, exercises: item.exercises, slotId: item.slotId, existing: w });
    }
    if (w) return setEditor({ type: 'workout', initial: w, existing: w });
    setEditor({ type: 'workout', initial: { date, kind: 'run', slotId: item.slotId, title: item.title } });
  }

  async function openExtra(w: Workout) {
    if (w.kind === 'strength') {
      setEditor({ type: 'strength', title: w.title, exercises: await exercisesFor(w), slotId: w.slotId, existing: w });
    } else setEditor({ type: 'workout', initial: w, existing: w });
  }

  // Weekcijfers
  const weekPlan = plan.status === 'actief' ? planForWeek(plan.week, events, moves) : [];
  const plannedItems = weekPlan.flatMap(d => d.items);
  const plannedRuns = plannedItems.filter(i => (i.kind === 'run' || i.slotId === 'test-cooper' || i.slotId === 'test-10k' || i.kind === 'race') && !i.optional);
  const plannedStrength = plannedItems.filter(i => i.kind === 'strength');
  const runs = weekWorkouts.filter(w => w.kind === 'run');
  const runMin = runs.reduce((s, w) => s + (w.durationMin ?? 0), 0);
  const runKm = runs.reduce((s, w) => s + (w.distanceKm ?? 0), 0);
  const plannedMin = plannedRuns.reduce((s, i) => s + (i.minutes ?? 0), 0);
  const isToday = date === today();
  const testMonday = nextTestWeek(date);
  const daysToTest = diffDays(testMonday, date);
  const blocking = plan.event && ['defensie', 'ziek', 'anders'].includes(plan.event.kind);

  return (
    <>
      <div className="datenav">
        <button className="icon-btn" onClick={() => setDate(addDays(date, -1))} aria-label="Vorige dag">{Icon.left}</button>
        <div className="date">{longDate(date)}</div>
        <button className="icon-btn" onClick={() => setDate(addDays(date, 1))} aria-label="Volgende dag">{Icon.right}</button>
      </div>
      <div className="context">
        {plan.status === 'actief' && plan.block
          ? <>Blok {plan.block.nr} ({plan.block.name}), week {weekInBlock(plan.week)} van {plan.block.lastWeek - plan.block.firstWeek + 1}</>
          : 'Voor de start van het schema'}
        {!isToday && <> · <button className="btn ghost small" onClick={() => setDate(today())}>naar vandaag</button></>}
      </div>

      {isToday && plan.status === 'actief' && <RecoveryCard />}
      {plan.weekNote && <div className="notice">{plan.weekNote}</div>}
      {plan.moved && <div className="notice">Deze week is aangepast. Terugzetten kan via Verschuiven.</div>}
      {plan.event?.kind === 'vakantie' && <div className="notice">{plan.event.label}: extra ruimte voor een trailloop.</div>}

      <div className={`card${blocking ? ' warn' : ''}`}>
        {statuses.map(({ item, workout, checked, done }) => {
          const metricKinds = TEST_METRIC[item.slotId];
          const isRunLike = item.kind === 'run' || item.kind === 'race' || item.slotId === 'test-cooper' || item.slotId === 'test-10k';
          return (
            <div className={`item${item.optional ? ' optional' : ''}`} key={item.slotId + item.title}>
              {item.kind === 'rest' || item.kind === 'free'
                ? <span />
                : (
                  <button
                    className={`check${done ? ' done' : ''}`}
                    onClick={() => (workout ? open(item, workout) : toggleCheck(item, !checked))}
                    aria-label={done ? 'Gedaan' : 'Afvinken'}
                  >{done && Icon.check}</button>
                )}
              <div>
                <div className="title">{item.title}{item.minutes && item.kind !== 'rest' ? <span className="muted"> · {minutesToText(item.minutes)}</span> : null}</div>
                {item.exercises && (
                  <ul className="exlist">
                    {item.exercises.map(e => <li key={e.name}><strong>{e.name}</strong> {e.sets} x {e.reps}{!['lichaamsgewicht', 'band'].includes(e.weight) ? `, ${e.weight}` : ''}</li>)}
                  </ul>
                )}
                {item.detail && <div className="meta">{item.detail}</div>}
                {workout && <div className="logged">{summary(workout)}</div>}
                {metricKinds && metricKinds.map(k => {
                  const m = metrics.find(x => x.kind === k);
                  return m ? <div className="logged" key={k}>{METRICS.find(d => d.kind === k)?.label}: {formatMetric(k, m.value)}</div> : null;
                })}
              </div>
              <div className="stack">
                {item.kind === 'strength' && <button className="btn secondary small" onClick={() => open(item, workout)}>{workout ? 'Bekijk' : 'Loggen'}</button>}
                {isRunLike && !metricKinds && <button className="btn secondary small" onClick={() => open(item, workout)}>{workout ? 'Bekijk' : 'Loggen'}</button>}
                {metricKinds && metricKinds.map(k => (
                  <button key={k} className="btn secondary small" onClick={() => setEditor({ type: 'metric', kind: k })}>
                    {metricKinds.length > 1 ? METRICS.find(d => d.kind === k)?.label : 'Resultaat'}
                  </button>
                ))}
              </div>
            </div>
          );
        })}
        {plan.status === 'actief' && !blocking && (
          <div className="row" style={{ justifyContent: 'flex-end', paddingTop: 6 }}>
            <button className="btn ghost small" onClick={() => setEditor({ type: 'move' })}>Verschuiven</button>
          </div>
        )}
      </div>

      {gtgDay(date) && !blocking && (
        <div className="card">
          <div className="counter">
            <div>
              <div style={{ fontWeight: 600 }}>Pull-ups tussendoor</div>
              <div className="muted small">4 tot 5 keer 3, steeds ruim voor je moe bent</div>
            </div>
            <div className="row" style={{ flexWrap: 'nowrap' }}>
              <button className="btn secondary small" onClick={() => bumpGtg(-1)} aria-label="Min 1">−1</button>
              <span className="num">{gtg?.value ?? 0}</span>
              <button className="btn small" onClick={() => bumpGtg(3)}>+3</button>
            </div>
          </div>
        </div>
      )}

      {extra.length > 0 && (
        <>
          <h2>Ook gedaan</h2>
          <div className="card">
            {extra.map(w => (
              <div className="logrow" key={w.id} onClick={() => openExtra(w)}>
                <div>{w.title}{w.source === 'intervals' && <span className="tag">Garmin</span>}</div>
                <div className="stats">{summary(w)}</div>
              </div>
            ))}
          </div>
        </>
      )}

      <button className="btn secondary block mt" onClick={() => setEditor({ type: 'workout', initial: { date, kind: 'run' }, allowKind: true })}>
        Extra training toevoegen
      </button>

      {weekPlan.length > 0 && (
        <>
          <h2>Deze week</h2>
          <div className="stat-grid">
            <div className="stat"><div className="v">{runs.length} / {plannedRuns.length}</div><div className="l">keer gelopen</div></div>
            <div className="stat"><div className="v">{Math.round(runMin)} / {plannedMin}</div><div className="l">minuten lopen</div></div>
            <div className="stat"><div className="v">{weekWorkouts.filter(w => w.kind === 'strength').length} / {plannedStrength.length}</div><div className="l">keer kracht</div></div>
          </div>
          {runKm > 0 && <p className="muted small">{fmt.km(runKm)} gelopen deze week.</p>}
          {!plan.testWeek && daysToTest > 0 && <p className="muted small">Volgende testweek: {shortDate(testMonday)} (over {daysToTest} dagen).</p>}
        </>
      )}

      {editor?.type === 'workout' && <WorkoutEditor initial={editor.initial} existing={editor.existing} allowKind={editor.allowKind} onClose={() => setEditor(null)} />}
      {editor?.type === 'strength' && (
        <StrengthLogger date={date} title={editor.title} exercises={editor.exercises} slotId={editor.slotId} existing={editor.existing} onClose={() => setEditor(null)} />
      )}
      {editor?.type === 'metric' && <MetricEditor kind={editor.kind} date={date} onClose={() => setEditor(null)} />}
      {editor?.type === 'move' && (
        <MoveSheet date={date} week={plan.week} weekday={(diffDays(date, mondayOf(date)) + 7) % 7} events={events} moves={moves} onClose={() => setEditor(null)} />
      )}
    </>
  );
}

export function summary(w: Workout): string {
  const parts: string[] = [];
  if (w.distanceKm) parts.push(fmt.km(w.distanceKm));
  if (w.durationMin) parts.push(minutesToText(w.durationMin));
  if (w.distanceKm && w.durationMin && w.kind === 'run') {
    const sec = Math.round((w.durationMin * 60) / w.distanceKm);
    parts.push(`${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}/km`);
  }
  if (w.elevationM) parts.push(`${w.elevationM} hm`);
  if (w.avgHr) parts.push(`${w.avgHr} bpm`);
  if (w.kind === 'strength' && !parts.length) parts.push('gelogd');
  return parts.join(' · ') || 'gedaan';
}
