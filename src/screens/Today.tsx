import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, save, type Workout, type Metric } from '../db';
import { addDays, diffDays, longDate, mondayOf, today, minutesToText, type ISODate } from '../dates';
import { planForDay, planForWeek, gtgDay, TOTAL_WEEKS, RACE_DATE, type PlannedItem } from '../plan';
import { matchDay } from '../match';
import { Icon, useBlocks, fmt } from '../ui';
import { StrengthLogger, WorkoutEditor } from '../editors';

type Editor =
  | { type: 'workout'; initial: Partial<Workout> & { date: ISODate; kind: Workout['kind'] }; existing?: Workout; allowKind?: boolean }
  | { type: 'strength'; item: PlannedItem; existing?: Workout };

export function Today() {
  const [date, setDate] = useState<ISODate>(today());
  const [editor, setEditor] = useState<Editor | null>(null);
  const blocks = useBlocks();
  const plan = planForDay(date, blocks);

  const workouts = useLiveQuery(async () => (await db.workouts.where('date').equals(date).toArray()).filter(alive), [date], []);
  const checks = useLiveQuery(async () => (await db.checks.where('date').equals(date).toArray()).filter(alive), [date], []);
  const gtg = useLiveQuery(() => db.metrics.get(`gtg-${date}`), [date]);

  // Weekoverzicht
  const monday = mondayOf(date);
  const weekWorkouts = useLiveQuery(
    async () => (await db.workouts.where('date').between(monday, addDays(monday, 6), true, true).toArray()).filter(alive),
    [monday],
    [],
  );

  const { statuses, extra } = matchDay(plan.items, workouts, checks);

  async function toggleCheck(item: PlannedItem, on: boolean) {
    await save('checks', { id: `${date}:${item.slotId}`, date, slotId: item.slotId, done: on });
  }

  async function bumpGtg(delta: number) {
    const value = Math.max(0, (gtg && !gtg.deleted ? gtg.value : 0) + delta);
    await save('metrics', { id: `gtg-${date}`, date, kind: 'gtg', value } as Metric);
  }

  function open(item: PlannedItem, w?: Workout) {
    if (item.kind === 'strength' && item.strength) return setEditor({ type: 'strength', item, existing: w });
    if (w) return setEditor({ type: 'workout', initial: w, existing: w });
    const kind = item.kind === 'boxing' ? 'boxing' : 'run';
    const rounds = item.kind === 'boxing' ? Number(item.title.match(/\d+/)?.[0] ?? 3) : undefined;
    setEditor({ type: 'workout', initial: { date, kind, slotId: item.slotId, title: item.title, rounds, durationMin: item.kind === 'boxing' ? item.minutes : undefined } });
  }

  // Weekcijfers
  const weekPlan = plan.week >= 1 && plan.week <= TOTAL_WEEKS ? planForWeek(plan.week, blocks) : [];
  const plannedRuns = weekPlan.flatMap(d => d.items).filter(i => (i.kind === 'run' || i.kind === 'race') && !i.optional);
  const plannedStrength = weekPlan.flatMap(d => d.items).filter(i => i.kind === 'strength' && !i.optional);
  const runs = weekWorkouts.filter(w => w.kind === 'run');
  const runMin = runs.reduce((s, w) => s + (w.durationMin ?? 0), 0);
  const runKm = runs.reduce((s, w) => s + (w.distanceKm ?? 0), 0);
  const plannedMin = plannedRuns.reduce((s, i) => s + (i.minutes ?? 0), 0);
  const isToday = date === today();
  const daysToRace = diffDays(RACE_DATE, date);

  return (
    <>
      <div className="datenav">
        <button className="icon-btn" onClick={() => setDate(addDays(date, -1))} aria-label="Vorige dag">{Icon.left}</button>
        <div className="date">{longDate(date)}</div>
        <button className="icon-btn" onClick={() => setDate(addDays(date, 1))} aria-label="Volgende dag">{Icon.right}</button>
      </div>
      <div className="context">
        {plan.status === 'actief' && plan.phase
          ? <>Week {plan.week} van {TOTAL_WEEKS}, fase {plan.phase.nr} {plan.phase.name}{plan.lightWeek ? ', lichte week' : ''}</>
          : plan.status === 'voor' ? 'Voor de start van het schema' : 'Schema afgerond'}
        {!isToday && <> · <button className="btn ghost small" onClick={() => setDate(today())}>naar vandaag</button></>}
      </div>

      {plan.weekNote && <div className="notice">{plan.weekNote}</div>}
      {plan.block && plan.block.kind === 'vakantie' && <div className="notice">{plan.block.label}: extra ruimte voor een trailloop.</div>}

      <div className={`card${plan.block && plan.block.kind !== 'vakantie' ? ' warn' : ''}`}>
        {statuses.map(({ item, workout, checked, done }) => (
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
              {item.detail && <div className="meta">{item.detail}</div>}
              {workout && <div className="logged">{summary(workout)}</div>}
            </div>
            <div>
              {(item.kind === 'run' || item.kind === 'race' || item.kind === 'strength' || item.kind === 'boxing') && (
                <button className="btn secondary small" onClick={() => open(item, workout)}>{workout ? 'Bekijk' : 'Loggen'}</button>
              )}
            </div>
          </div>
        ))}
      </div>

      {gtgDay(date) && !(plan.block && plan.block.kind !== 'vakantie') && (
        <div className="card">
          <div className="counter">
            <div>
              <div style={{ fontWeight: 600 }}>Pull-ups tussendoor</div>
              <div className="muted small">4 tot 5 keer 3, steeds ruim voor je moe bent</div>
            </div>
            <div className="row" style={{ flexWrap: 'nowrap' }}>
              <button className="btn secondary small" onClick={() => bumpGtg(-1)} aria-label="Min 1">−1</button>
              <span className="num">{gtg && !gtg.deleted ? gtg.value : 0}</span>
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
              <div className="logrow" key={w.id} onClick={() => w.kind === 'strength' ? setEditor({ type: 'strength', item: { slotId: w.slotId ?? 'kracht-A', kind: 'strength', title: w.title, strength: strengthKeyOf(w) }, existing: w }) : setEditor({ type: 'workout', initial: w, existing: w })}>
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
        </>
      )}
      {daysToRace > 0 && plan.status === 'actief' && <p className="muted small">Nog {daysToRace} dagen tot de 50 km.</p>}

      {editor?.type === 'workout' && <WorkoutEditor initial={editor.initial} existing={editor.existing} allowKind={editor.allowKind} onClose={() => setEditor(null)} />}
      {editor?.type === 'strength' && editor.item.strength && (
        <StrengthLogger date={date} strength={editor.item.strength} slotId={editor.item.slotId} existing={editor.existing} onClose={() => setEditor(null)} />
      )}
    </>
  );
}

export function strengthKeyOf(w: Workout): 'A' | 'B' | 'kort' {
  if (/kort/i.test(w.title) || w.slotId === 'kracht-kort') return 'kort';
  if (/B$/.test(w.title) || w.slotId === 'kracht-B') return 'B';
  return 'A';
}

export function summary(w: Workout): string {
  const parts: string[] = [];
  if (w.distanceKm) parts.push(fmt.km(w.distanceKm));
  if (w.durationMin) parts.push(minutesToText(w.durationMin));
  if (w.elevationM) parts.push(`${w.elevationM} hm`);
  if (w.avgHr) parts.push(`${w.avgHr} bpm`);
  if (w.rounds) parts.push(`${w.rounds} rondes`);
  if (w.kind === 'strength' && !parts.length) parts.push('gelogd');
  return parts.join(' · ') || 'gedaan';
}
