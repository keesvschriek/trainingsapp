import { useEffect, useState } from 'react';
import { db, newId, remove, save, alive, type Workout, type WorkoutKind, type StrengthSet, type Metric, type MetricKind } from './db';
import { planForDay, type Exercise } from './plan';
import { progressionHint, type Hint } from './progression';
import { Icon, Sheet, num } from './ui';
import { longDate, today, type ISODate } from './dates';

const KIND_LABEL: Record<WorkoutKind, string> = { run: 'Lopen', strength: 'Kracht', boxing: 'Boksen', other: 'Overig' };

/** Oefeningen voor een bestaande krachttraining: uit het schema van die dag, anders uit de gelogde sets. */
export async function exercisesFor(w: Workout): Promise<Exercise[]> {
  const moves = (await db.moves.toArray()).filter(alive);
  const planned = planForDay(w.date, [], moves).items.find(i => i.slotId === w.slotId && i.exercises)
    ?? planForDay(w.date).items.find(i => i.slotId === w.slotId && i.exercises);
  if (planned?.exercises) return planned.exercises;
  const sets = (await db.sets.where('workoutId').equals(w.id).toArray()).filter(alive);
  const names = [...new Set(sets.sort((a, b) => a.setNo - b.setNo).map(s => s.exercise))];
  return names.map(name => {
    const first = sets.find(s => s.exercise === name)!;
    return { name, weight: first.weightKg ? `${first.weightKg} kg` : 'lichaamsgewicht', sets: sets.filter(s => s.exercise === name).length, reps: String(first.reps), defaultKg: first.weightKg, defaultReps: first.reps };
  });
}

// ---------------------------------------------------------------------------
// Loop of overige training
// ---------------------------------------------------------------------------

export function WorkoutEditor(props: {
  initial: Partial<Workout> & { date: ISODate; kind: WorkoutKind };
  existing?: Workout;
  allowKind?: boolean;
  onClose: () => void;
}) {
  const w = props.existing ?? props.initial;
  const [kind, setKind] = useState<WorkoutKind>(w.kind);
  const [date, setDate] = useState(w.date);
  const [title, setTitle] = useState(w.title ?? '');
  const [dist, setDist] = useState(w.distanceKm?.toString().replace('.', ',') ?? '');
  const [dur, setDur] = useState(w.durationMin?.toString().replace('.', ',') ?? '');
  const [elev, setElev] = useState(w.elevationM?.toString() ?? '');
  const [hr, setHr] = useState(w.avgHr?.toString() ?? '');
  const [rpe, setRpe] = useState(w.rpe?.toString() ?? '');
  const [rounds, setRounds] = useState(w.rounds?.toString() ?? '');
  const [notes, setNotes] = useState(w.notes ?? '');
  const fromGarmin = props.existing?.source === 'intervals';

  async function submit() {
    const defaultTitle = kind === 'run' ? 'Loop' : kind === 'boxing' ? 'Boksen' : kind === 'strength' ? 'Kracht' : 'Training';
    await save('workouts', {
      ...(props.existing ?? {}),
      id: props.existing?.id ?? newId(),
      date,
      kind,
      slotId: props.existing?.slotId ?? props.initial.slotId,
      title: title.trim() || defaultTitle,
      distanceKm: num(dist),
      durationMin: num(dur),
      elevationM: num(elev),
      avgHr: num(hr),
      rpe: num(rpe),
      rounds: num(rounds),
      notes: notes.trim() || undefined,
      source: props.existing?.source ?? 'manual',
    });
    props.onClose();
  }

  async function del() {
    if (!props.existing) return;
    if (!confirm('Deze training verwijderen?')) return;
    await remove('workouts', props.existing.id);
    props.onClose();
  }

  return (
    <Sheet
      title={props.existing ? 'Training bewerken' : 'Training loggen'}
      onClose={props.onClose}
      action={props.existing && <button className="icon-btn" onClick={del} aria-label="Verwijderen">{Icon.trash}</button>}
      footer={<><button className="btn secondary" onClick={props.onClose}>Annuleren</button><button className="btn" onClick={submit}>Opslaan</button></>}
    >
      {props.allowKind && (
        <div className="seg">
          {(['run', 'other'] as WorkoutKind[]).map(k => (
            <button key={k} className={kind === k ? 'active' : ''} onClick={() => setKind(k)}>{KIND_LABEL[k]}</button>
          ))}
        </div>
      )}
      {fromGarmin && <div className="notice">Opgehaald uit intervals.icu. Je aanvullingen blijven bewaard bij een nieuwe import.</div>}
      <div className="grid2">
        <div><label>Datum</label><input type="date" value={date} onChange={e => setDate(e.target.value)} /></div>
        <div><label>Naam</label><input value={title} onChange={e => setTitle(e.target.value)} placeholder={KIND_LABEL[kind]} /></div>
      </div>
      {kind === 'run' && (
        <>
          <div className="grid2">
            <div><label>Afstand (km)</label><input inputMode="decimal" value={dist} onChange={e => setDist(e.target.value)} /></div>
            <div><label>Duur (min)</label><input inputMode="decimal" value={dur} onChange={e => setDur(e.target.value)} /></div>
          </div>
          <div className="grid3">
            <div><label>Hoogtemeters</label><input inputMode="numeric" value={elev} onChange={e => setElev(e.target.value)} /></div>
            <div><label>Gem. hartslag</label><input inputMode="numeric" value={hr} onChange={e => setHr(e.target.value)} /></div>
            <div><label>Zwaarte (1-10)</label><input inputMode="numeric" value={rpe} onChange={e => setRpe(e.target.value)} /></div>
          </div>
        </>
      )}
      {kind === 'boxing' && (
        <div className="grid2">
          <div><label>Rondes</label><input inputMode="numeric" value={rounds} onChange={e => setRounds(e.target.value)} /></div>
          <div><label>Duur (min)</label><input inputMode="decimal" value={dur} onChange={e => setDur(e.target.value)} /></div>
        </div>
      )}
      {(kind === 'other' || kind === 'strength') && (
        <div className="grid2">
          <div><label>Duur (min)</label><input inputMode="decimal" value={dur} onChange={e => setDur(e.target.value)} /></div>
          <div><label>Afstand (km)</label><input inputMode="decimal" value={dist} onChange={e => setDist(e.target.value)} /></div>
        </div>
      )}
      <label>Notities</label>
      <textarea rows={3} value={notes} onChange={e => setNotes(e.target.value)} placeholder="Hoe voelde het? Pijntjes?" />
      <p className="muted small mt">{longDate(date)}</p>
    </Sheet>
  );
}

// ---------------------------------------------------------------------------
// Krachttraining loggen: per oefening sets met herhalingen en gewicht
// ---------------------------------------------------------------------------

interface SetRow { reps: string; kg: string }

export function StrengthLogger(props: { date: ISODate; title: string; exercises: Exercise[]; slotId?: string; existing?: Workout; onClose: () => void }) {
  const exercises = props.exercises;
  const [rows, setRows] = useState<Record<string, SetRow[]> | null>(null);
  const [notes, setNotes] = useState(props.existing?.notes ?? '');
  const [rpe, setRpe] = useState(props.existing?.rpe?.toString() ?? '');
  const [prevInfo, setPrevInfo] = useState<Record<string, string>>({});
  const [hints, setHints] = useState<Record<string, Hint>>({});

  useEffect(() => {
    (async () => {
      const init: Record<string, SetRow[]> = {};
      const info: Record<string, string> = {};
      const hintMap: Record<string, Hint> = {};
      const existingSets = props.existing
        ? (await db.sets.where('workoutId').equals(props.existing.id).toArray()).filter(alive)
        : [];
      // Vorige keer per oefening, als startpunt en ter vergelijking
      const strengthWorkouts = (await db.workouts.where('kind').equals('strength').toArray())
        .filter(alive)
        .filter(w => w.id !== props.existing?.id && w.date <= props.date)
        .sort((a, b) => b.date.localeCompare(a.date))
        .slice(0, 12);
      const recentSets = strengthWorkouts.length
        ? (await db.sets.where('workoutId').anyOf(strengthWorkouts.map(w => w.id)).toArray()).filter(alive)
        : [];

      for (const ex of exercises) {
        const mine = existingSets.filter(s => s.exercise === ex.name).sort((a, b) => a.setNo - b.setNo);
        let last: StrengthSet[] = [];
        for (const w of strengthWorkouts) {
          last = recentSets.filter(s => s.workoutId === w.id && s.exercise === ex.name).sort((a, b) => a.setNo - b.setNo);
          if (last.length) {
            info[ex.name] = `Vorige keer (${w.date.slice(8, 10)}-${w.date.slice(5, 7)}): ` + last.map(s => (s.weightKg ? `${s.reps}x${s.weightKg}` : `${s.reps}`)).join(', ');
            break;
          }
        }
        const hint = progressionHint(ex, last);
        if (hint) hintMap[ex.name] = hint;
        if (mine.length) {
          init[ex.name] = mine.map(s => ({ reps: String(s.reps), kg: s.weightKg ? String(s.weightKg) : '' }));
        } else {
          const kg = hint?.kg ?? last[0]?.weightKg ?? ex.defaultKg;
          const reps = hint?.reps ?? last[0]?.reps ?? ex.defaultReps;
          init[ex.name] = Array.from({ length: ex.sets }, () => ({ reps: String(reps), kg: kg ? String(kg) : '' }));
        }
      }
      setRows(init);
      setPrevInfo(info);
      setHints(hintMap);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.existing?.id, props.date, props.slotId]);

  function update(name: string, i: number, field: keyof SetRow, v: string) {
    setRows(r => r && { ...r, [name]: r[name].map((s, j) => (j === i ? { ...s, [field]: v } : s)) });
  }
  function addSet(name: string) {
    setRows(r => r && { ...r, [name]: [...r[name], { ...(r[name][r[name].length - 1] ?? { reps: '', kg: '' }) }] });
  }
  function dropSet(name: string, i: number) {
    setRows(r => r && { ...r, [name]: r[name].filter((_, j) => j !== i) });
  }

  async function submit() {
    if (!rows) return;
    const workout = await save('workouts', {
      ...(props.existing ?? {}),
      id: props.existing?.id ?? newId(),
      date: props.date,
      kind: 'strength',
      slotId: props.existing?.slotId ?? props.slotId,
      title: props.title,
      durationMin: props.existing?.durationMin ?? 40,
      rpe: num(rpe),
      notes: notes.trim() || undefined,
      source: 'manual',
    });
    // Oude sets weg, nieuwe erin
    const old = (await db.sets.where('workoutId').equals(workout.id).toArray()).filter(alive);
    for (const s of old) await remove('sets', s.id);
    for (const ex of exercises) {
      const list = rows[ex.name].filter(s => num(s.reps));
      for (let i = 0; i < list.length; i++) {
        await save('sets', { id: newId(), workoutId: workout.id, exercise: ex.name, setNo: i + 1, reps: num(list[i].reps)!, weightKg: num(list[i].kg) ?? 0 });
      }
    }
    props.onClose();
  }

  async function del() {
    if (!props.existing || !confirm('Deze krachttraining verwijderen?')) return;
    const old = (await db.sets.where('workoutId').equals(props.existing.id).toArray()).filter(alive);
    for (const s of old) await remove('sets', s.id);
    await remove('workouts', props.existing.id);
    props.onClose();
  }

  return (
    <Sheet
      title={props.title}
      onClose={props.onClose}
      action={props.existing && <button className="icon-btn" onClick={del} aria-label="Verwijderen">{Icon.trash}</button>}
      footer={<><button className="btn secondary" onClick={props.onClose}>Annuleren</button><button className="btn" onClick={submit} disabled={!rows}>Opslaan</button></>}
    >
      <p className="muted small">{longDate(props.date)}. Stop elke set 1 tot 2 herhalingen voor je niet meer kunt. Vul 0 kg in bij lichaamsgewicht.</p>
      {rows && exercises.map(ex => (
        <div className="ex" key={ex.name}>
          <div className="spread">
            <h3>{ex.name}</h3>
            <span className="muted small">{ex.sets} x {ex.reps}</span>
          </div>
          <div className="muted small">{ex.weight}</div>
          {prevInfo[ex.name] && <div className="small muted">{prevInfo[ex.name]}</div>}
          {hints[ex.name] && <div className="small" style={{ color: 'var(--accent)', fontWeight: 600 }}>{hints[ex.name].text}</div>}
          <div className="sets">
            <span className="n">set</span><span className="n">herh.</span><span className="n">kg</span><span />
            {rows[ex.name].map((s, i) => (
              <Row key={i} i={i} s={s} onChange={(f, v) => update(ex.name, i, f, v)} onDrop={() => dropSet(ex.name, i)} />
            ))}
          </div>
          <button className="btn ghost small" onClick={() => addSet(ex.name)}>+ set</button>
        </div>
      ))}
      <div className="grid2">
        <div><label>Zwaarte (1-10)</label><input inputMode="numeric" value={rpe} onChange={e => setRpe(e.target.value)} /></div>
      </div>
      <label>Notities</label>
      <textarea rows={2} value={notes} onChange={e => setNotes(e.target.value)} />
    </Sheet>
  );
}

function Row(props: { i: number; s: SetRow; onChange: (f: keyof SetRow, v: string) => void; onDrop: () => void }) {
  return (
    <>
      <span className="n">{props.i + 1}</span>
      <input inputMode="numeric" value={props.s.reps} onChange={e => props.onChange('reps', e.target.value)} aria-label="herhalingen" />
      <input inputMode="decimal" value={props.s.kg} onChange={e => props.onChange('kg', e.target.value)} aria-label="kilo" />
      <button className="icon-btn" onClick={props.onDrop} aria-label="Set verwijderen" style={{ padding: 4 }}>{Icon.close}</button>
    </>
  );
}

// ---------------------------------------------------------------------------
// Metingen (testweek en lichaam)
// ---------------------------------------------------------------------------

export const METRICS: { kind: MetricKind; label: string; unit: string; help: string; time?: boolean }[] = [
  { kind: 'cooper', label: 'Cooper-test', unit: 'm', help: 'Zoveel mogelijk meters in 12 minuten. Doel: 3000 m.' },
  { kind: 'tenK', label: '10 km', unit: '', help: 'Tijd als minuten:seconden, bijv. 44:30. Doel: onder 43:00.', time: true },
  { kind: 'waist', label: 'Buikomtrek', unit: 'cm', help: 'Op navelhoogte, na het opstaan, ontspannen uitademen.' },
  { kind: 'weight', label: 'Gewicht', unit: 'kg', help: 'Na het opstaan en voor het ontbijt.' },
  { kind: 'pullupMax', label: 'Strikte pull-ups (max)', unit: 'herh.', help: 'Uitgerust, 1 set zo veel mogelijk.' },
  { kind: 'pressReps', label: 'Press 28 kg (per arm)', unit: 'herh.', help: 'Strikte press, zwakste arm telt.' },
];

export const TEST_METRIC: Record<string, MetricKind[]> = {
  'test-pullups': ['pullupMax'],
  'test-cooper': ['cooper'],
  'test-10k': ['tenK'],
  'test-press': ['pressReps'],
  'test-meten': ['weight', 'waist'],
};

export function formatMetric(kind: MetricKind, value: number): string {
  const def = METRICS.find(m => m.kind === kind);
  if (def?.time) {
    const m = Math.floor(value / 60);
    const s = Math.round(value % 60);
    return `${m}:${String(s).padStart(2, '0')}`;
  }
  return `${value.toLocaleString('nl-NL', { maximumFractionDigits: 1 })} ${def?.unit ?? ''}`.trim();
}

function parseTime(v: string): number | undefined {
  const m = v.trim().match(/^(\d{1,3})[:.,](\d{1,2})$/);
  if (m) return Number(m[1]) * 60 + Number(m[2]);
  const n = num(v);
  return n == null ? undefined : Math.round(n * 60);
}

export function MetricEditor(props: { kind: MetricKind; date?: ISODate; onClose: () => void }) {
  const def = METRICS.find(m => m.kind === props.kind)!;
  const [date, setDate] = useState<ISODate>(props.date ?? today());
  const [value, setValue] = useState('');
  async function submit() {
    const v = def.time ? parseTime(value) : num(value);
    if (v == null) return;
    await save('metrics', { id: newId(), date, kind: props.kind, value: v } as Metric);
    props.onClose();
  }
  return (
    <Sheet title={def.label} onClose={props.onClose} footer={<><button className="btn secondary" onClick={props.onClose}>Annuleren</button><button className="btn" onClick={submit}>Opslaan</button></>}>
      <p className="muted small">{def.help}</p>
      <div className="grid2">
        <div><label>Datum</label><input type="date" value={date} onChange={e => setDate(e.target.value)} /></div>
        <div><label>{def.time ? 'Tijd (mm:ss)' : `Waarde (${def.unit})`}</label><input inputMode={def.time ? 'text' : 'decimal'} autoFocus value={value} onChange={e => setValue(e.target.value)} placeholder={def.time ? '44:30' : ''} /></div>
      </div>
    </Sheet>
  );
}
