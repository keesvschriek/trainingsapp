import { useState, type ReactNode } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Haptics, ImpactStyle } from '@capacitor/haptics';
import { db, alive, save, type Workout, type Metric, type MetricKind } from '../db';
import { addDays, dayShort, diffDays, fromISO, mondayOf, today, minutesToText, shortDate, type ISODate } from '../dates';
import { planForDay, planForWeek, gtgDay, nextTestWeek, weekInBlock, type PlannedItem, type Exercise } from '../plan';
import { matchDay, type ItemStatus } from '../match';
import { Contour, Icon, Show3D, useBlocks, useMoves, fmt } from '../ui';
import { MetricEditor, StrengthLogger, TEST_METRIC, WorkoutEditor, METRICS, exercisesFor, formatMetric } from '../editors';
import { MoveSheet } from '../moves';
import { RecoveryCard } from './RecoveryCard';
import { isNative } from '../native';

type Editor =
  | { type: 'workout'; initial: Partial<Workout> & { date: ISODate; kind: Workout['kind'] }; existing?: Workout; allowKind?: boolean }
  | { type: 'strength'; title: string; exercises: Exercise[]; slotId?: string; existing?: Workout }
  | { type: 'metric'; kind: MetricKind }
  | { type: 'move' };

const MONTHS = ['januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli', 'augustus', 'september', 'oktober', 'november', 'december'];
const DAYS = ['Maandag', 'Dinsdag', 'Woensdag', 'Donderdag', 'Vrijdag', 'Zaterdag', 'Zondag'];

const isTraining = (i: PlannedItem) => i.kind !== 'rest' && i.kind !== 'free';
const isRunLike = (i: PlannedItem) => i.kind === 'run' || i.kind === 'race' || i.slotId === 'test-cooper' || i.slotId === 'test-10k';

function kindInfo(i: PlannedItem): { label: string; icon: ReactNode } {
  if (i.kind === 'strength') return { label: 'Kracht', icon: Icon.kettlebell };
  if (i.kind === 'test') return { label: 'Testweek', icon: Icon.flag };
  if (i.kind === 'race') return { label: 'Wedstrijd', icon: Icon.flag };
  if (i.kind === 'run') return { label: 'Lopen', icon: Icon.run };
  return { label: i.kind === 'free' ? 'Vrij' : 'Rust', icon: Icon.moon };
}

function figures(i: PlannedItem): { num: string; unit: string }[] {
  const out: { num: string; unit: string }[] = [];
  if (i.minutes && i.kind !== 'rest') out.push({ num: String(i.minutes), unit: 'minuten' });
  if (i.kind === 'run') {
    const tempo = i.slotId === 'run-quality' && i.title.startsWith('Tempo');
    out.push(tempo ? { num: '90-96', unit: '% LTHR tempo' } : { num: '80-88', unit: '% LTHR rustig' });
  }
  if (i.kind === 'strength' && i.exercises) {
    out.push({ num: String(i.exercises.length), unit: 'oefeningen' });
    out.push({ num: String(i.exercises.reduce((s, e) => s + e.sets, 0)), unit: 'sets' });
  }
  if (i.slotId === 'test-cooper') out.push({ num: '3000', unit: 'meter doel' });
  if (i.slotId === 'test-10k') out.push({ num: '43:00', unit: 'doel' });
  return out;
}

export function Today() {
  const [date, setDate] = useState<ISODate>(today());
  const [editor, setEditor] = useState<Editor | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const events = useBlocks();
  const moves = useMoves();
  const plan = planForDay(date, events, moves);

  const workouts = useLiveQuery(async () => (await db.workouts.where('date').equals(date).toArray()).filter(alive), [date], []);
  const checks = useLiveQuery(async () => (await db.checks.where('date').equals(date).toArray()).filter(alive), [date], []);
  const metrics = useLiveQuery(async () => (await db.metrics.where('date').equals(date).toArray()).filter(alive), [date], []);
  const gtg = metrics.find(m => m.id === `gtg-${date}`);

  const monday = mondayOf(date);
  const sunday = addDays(monday, 6);
  const weekWorkouts = useLiveQuery(async () => (await db.workouts.where('date').between(monday, sunday, true, true).toArray()).filter(alive), [monday], []);
  const weekChecks = useLiveQuery(async () => (await db.checks.where('date').between(monday, sunday, true, true).toArray()).filter(alive), [monday], []);

  const { statuses, extra } = matchDay(plan.items, workouts, checks);
  for (const st of statuses) {
    const kinds = TEST_METRIC[st.item.slotId];
    if (kinds && kinds.every(k => metrics.some(m => m.kind === k))) st.done = true;
  }

  async function toggleCheck(item: PlannedItem, on: boolean) {
    if (isNative) void Haptics.impact({ style: on ? ImpactStyle.Medium : ImpactStyle.Light }).catch(() => undefined);
    await save('checks', { id: `${date}:${item.slotId}`, date, slotId: item.slotId, done: on });
  }

  async function bumpGtg(delta: number) {
    if (isNative) void Haptics.impact({ style: ImpactStyle.Light }).catch(() => undefined);
    const value = Math.max(0, (gtg?.value ?? 0) + delta);
    await save('metrics', { id: `gtg-${date}`, date, kind: 'gtg', value } as Metric);
  }

  function openItem(item: PlannedItem, w?: Workout) {
    if (item.kind === 'strength' && item.exercises) {
      return setEditor({ type: 'strength', title: item.title, exercises: item.exercises, slotId: item.slotId, existing: w });
    }
    if (w) return setEditor({ type: 'workout', initial: w, existing: w });
    setEditor({ type: 'workout', initial: { date, kind: 'run', slotId: item.slotId, title: item.title } });
  }

  async function openExtra(w: Workout) {
    if (w.kind === 'strength') setEditor({ type: 'strength', title: w.title, exercises: await exercisesFor(w), slotId: w.slotId, existing: w });
    else setEditor({ type: 'workout', initial: w, existing: w });
  }

  // Weekstrook
  const weekPlan = plan.status === 'actief' ? planForWeek(plan.week, events, moves) : [];
  const strip = Array.from({ length: 7 }, (_, i) => {
    const d = addDays(monday, i);
    const p = weekPlan[i];
    const items = p ? p.items.filter(x => isTraining(x) && !x.optional) : [];
    const { statuses: st } = matchDay(items, weekWorkouts.filter(w => w.date === d), weekChecks.filter(c => c.date === d));
    const done = items.length > 0 && st.every(s => s.done);
    const first = items[0];
    return { d, done, rest: !first, icon: first ? kindInfo(first).icon : Icon.dash };
  });

  // Weekcijfers
  const plannedItems = weekPlan.flatMap(d => d.items);
  const plannedRuns = plannedItems.filter(i => isRunLike(i) && !i.optional);
  const plannedStrength = plannedItems.filter(i => i.kind === 'strength');
  const runs = weekWorkouts.filter(w => w.kind === 'run');
  const runMin = runs.reduce((s, w) => s + (w.durationMin ?? 0), 0);
  const runKm = runs.reduce((s, w) => s + (w.distanceKm ?? 0), 0);
  const plannedMin = plannedRuns.reduce((s, i) => s + (i.minutes ?? 0), 0);
  const isToday = date === today();
  const testMonday = nextTestWeek(date);
  const daysToTest = diffDays(testMonday, date);
  const blocking = plan.event && ['defensie', 'ziek', 'anders'].includes(plan.event.kind);

  const main = statuses.find(s => isTraining(s.item) && !s.item.optional) ?? statuses[0];
  const others = statuses.filter(s => s !== main && s.item.kind !== 'free');
  const d = fromISO(date);

  return (
    <>
      <div className="dayhead">
        <button className="icon-btn" onClick={() => setDate(addDays(date, -1))} aria-label="Vorige dag">{Icon.left}</button>
        <div className="when" style={{ textAlign: 'center' }}>
          <strong>{DAYS[(d.getDay() + 6) % 7]} {d.getDate()} {MONTHS[d.getMonth()]}</strong>
          <div>
            {plan.status === 'actief' && plan.block ? `Blok ${plan.block.nr} (${plan.block.name.toLowerCase()}), week ${weekInBlock(plan.week)} van ${plan.block.lastWeek - plan.block.firstWeek + 1}` : 'Voor de start'}
            {!isToday && <> · <button className="btn ghost small" style={{ padding: 0 }} onClick={() => setDate(today())}>vandaag</button></>}
          </div>
        </div>
        <button className="icon-btn" onClick={() => setDate(addDays(date, 1))} aria-label="Volgende dag">{Icon.right}</button>
      </div>

      {plan.status === 'actief' && (
        <div className="weekstrip">
          {strip.map(s => (
            <button key={s.d} className={`ws-day${s.d === date ? ' sel' : ''}${s.d === today() ? ' today' : ''}${s.done ? ' done' : ''}${s.rest ? ' rest' : ''}`} onClick={() => setDate(s.d)}>
              <span className="d">{dayShort(s.d)}</span>
              <span className="n">{fromISO(s.d).getDate()}</span>
              <span className="mark">{s.done ? Icon.check : s.icon}</span>
            </button>
          ))}
        </div>
      )}

      {plan.weekNote && <div className="notice">{plan.weekNote}</div>}
      {plan.moved && <div className="notice">Deze week is aangepast. Terugzetten kan via Verschuiven.</div>}
      {plan.event?.kind === 'vakantie' && <div className="notice">{plan.event.label}: extra ruimte voor een trailloop.</div>}

      {main && (
        <Hero
          st={main}
          others={others}
          warn={!!blocking}
          metrics={metrics}
          openKey={open}
          setOpen={setOpen}
          onOpen={openItem}
          onToggle={toggleCheck}
          onMetric={k => setEditor({ type: 'metric', kind: k })}
          onMove={plan.status === 'actief' && !blocking ? () => setEditor({ type: 'move' }) : undefined}
        />
      )}

      {isToday && plan.status === 'actief' && <RecoveryCard />}

      {gtgDay(date) && !blocking && (
        <div className="rowcard" style={{ cursor: 'default' }}>
          <div className="grow">
            <div className="val">Pull-ups tussendoor</div>
            <div className="lbl">4 tot 5 keer 3, ruim voor je moe bent</div>
          </div>
          <button className="btn secondary small" onClick={() => bumpGtg(-1)} aria-label="Min 1">−1</button>
          <span className="big" style={{ minWidth: 34, textAlign: 'center' }}>{gtg?.value ?? 0}</span>
          <button className="btn small" onClick={() => bumpGtg(3)}>+3</button>
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

      {weekPlan.length > 0 && (
        <>
          <h2>Deze week</h2>
          <div className="mini-stats">
            <div className="s"><div className="v">{runs.length}<span> / {plannedRuns.length}</span></div><div className="l">keer gelopen</div></div>
            <div className="s"><div className="v">{Math.round(runMin)}<span> / {plannedMin}</span></div><div className="l">minuten lopen</div></div>
            <div className="s"><div className="v">{weekWorkouts.filter(w => w.kind === 'strength').length}<span> / {plannedStrength.length}</span></div><div className="l">keer kracht</div></div>
          </div>
          <p className="muted small">
            {runKm > 0 ? `${fmt.km(runKm)} gelopen. ` : ''}
            {!plan.testWeek && daysToTest > 0 ? `Volgende testweek: ${shortDate(testMonday)}, over ${daysToTest} dagen.` : ''}
          </p>
        </>
      )}

      <button className="btn ghost block" onClick={() => setEditor({ type: 'workout', initial: { date, kind: 'run' }, allowKind: true })}>
        + Extra training toevoegen
      </button>

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

function Hero(props: {
  st: ItemStatus;
  others: ItemStatus[];
  warn: boolean;
  metrics: Metric[];
  openKey: string | null;
  setOpen: (k: string | null) => void;
  onOpen: (i: PlannedItem, w?: Workout) => void;
  onToggle: (i: PlannedItem, on: boolean) => void;
  onMetric: (k: MetricKind) => void;
  onMove?: () => void;
}) {
  const { item, workout, checked, done } = props.st;
  const k = kindInfo(item);
  const training = isTraining(item);
  const metricKinds = TEST_METRIC[item.slotId];
  const figs = figures(item);
  const key = item.slotId + item.title;
  const isOpen = props.openKey === key;
  const hasDetails = !!item.detail || !!item.exercises;

  let primary: ReactNode = null;
  if (metricKinds) {
    primary = metricKinds.map(mk => (
      <button key={mk} className="btn big" onClick={() => props.onMetric(mk)}>
        {metricKinds.length > 1 ? METRICS.find(m => m.kind === mk)?.label : 'Resultaat invullen'}
      </button>
    ));
  } else if (item.kind === 'strength' || isRunLike(item)) {
    primary = <button className={`btn big${workout ? ' secondary' : ''}`} onClick={() => props.onOpen(item, workout)}>{workout ? 'Bekijk' : 'Loggen'}</button>;
  }

  const doneText = workout
    ? summary(workout)
    : metricKinds
      ? metricKinds.map(mk => {
          const m = props.metrics.find(x => x.kind === mk);
          return m ? formatMetric(mk, m.value) : '';
        }).filter(Boolean).join(' · ')
      : '';

  return (
    <div className={`hero${props.warn ? ' warn' : ''}`}>
      <Contour className="contour" />
      <div className="hero-kind">{k.icon}<span>{k.label}{item.optional ? ', optioneel' : ''}</span></div>
      <div className="hero-title">{item.kind === 'strength' ? item.title.replace(/^Kracht: /, '').replace(/^./, c => c.toUpperCase()) : item.title}</div>
      {!training && <div className="hero-sub">{item.detail ?? 'Herstel hoort bij het schema.'}</div>}
      {item.exercises && !isOpen && <div className="exchips">{item.exercises.map(e => e.name).join(' · ')}</div>}

      {figs.length > 0 && (
        <div className="hero-figs">
          {figs.map(f => <div className="fig" key={f.unit}><div className="num">{f.num}</div><div className="unit">{f.unit}</div></div>)}
        </div>
      )}

      {done && doneText && <div className="done-badge" style={{ marginBottom: 10 }}>{Icon.check}{doneText}</div>}

      {training && (
        <div className="hero-actions">
          {primary}
          <button
            className={`check${done ? ' done' : ''}`}
            style={{ width: 46, height: 46 }}
            onClick={() => (workout ? props.onOpen(item, workout) : props.onToggle(item, !checked))}
            aria-label={done ? 'Gedaan' : 'Afvinken'}
          >{done && Icon.check}</button>
        </div>
      )}

      <div className="spread">
        {hasDetails && training ? (
          <button className="details-toggle" onClick={() => props.setOpen(isOpen ? null : key)}>
            {isOpen ? 'Minder' : 'Uitleg en oefeningen'}
            <span style={{ display: 'inline-flex', transform: isOpen ? 'rotate(180deg)' : undefined }}>{Icon.down}</span>
          </button>
        ) : <span />}
        {props.onMove && <button className="details-toggle" onClick={props.onMove}>Verschuiven</button>}
      </div>

      {isOpen && (
        <div className="details">
          {item.exercises && (
            <ul className="exlist">
              {item.exercises.map(e => <li key={e.name} className="spread"><span><strong>{e.name}</strong> {e.sets} x {e.reps}{!['lichaamsgewicht', 'band'].includes(e.weight) ? `, ${e.weight}` : ''}</span><Show3D name={e.name} /></li>)}
            </ul>
          )}
          {item.detail && <p className="muted" style={{ marginTop: 6 }}>{item.detail}</p>}
        </div>
      )}

      {props.others.length > 0 && (
        <div className="sub-items">
          {props.others.map(o => <SubItem key={o.item.slotId + o.item.title} st={o} onOpen={props.onOpen} onToggle={props.onToggle} onMetric={props.onMetric} />)}
        </div>
      )}
    </div>
  );
}

function SubItem(props: { st: ItemStatus; onOpen: (i: PlannedItem, w?: Workout) => void; onToggle: (i: PlannedItem, on: boolean) => void; onMetric: (k: MetricKind) => void }) {
  const { item, workout, checked, done } = props.st;
  const metricKinds = TEST_METRIC[item.slotId];
  return (
    <div className="sub-item">
      <button className={`check${done ? ' done' : ''}`} onClick={() => (workout ? props.onOpen(item, workout) : props.onToggle(item, !checked))} aria-label={done ? 'Gedaan' : 'Afvinken'}>{done && Icon.check}</button>
      <div>
        <div className="t">{item.title}{item.optional ? <span className="muted" style={{ fontWeight: 400 }}> (optioneel)</span> : null}</div>
        <div className="m">{item.minutes ? minutesToText(item.minutes) : ''}{workout ? ` · ${summary(workout)}` : ''}</div>
      </div>
      {metricKinds
        ? <button className="btn secondary small" onClick={() => props.onMetric(metricKinds[0])}>Resultaat</button>
        : (item.kind === 'strength' || isRunLike(item)) && <button className="btn secondary small" onClick={() => props.onOpen(item, workout)}>{workout ? 'Bekijk' : 'Loggen'}</button>}
    </div>
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
