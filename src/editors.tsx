import { useEffect, useState } from 'react';
import { db, newId, remove, save, alive, type Workout, type WorkoutKind, type StrengthSet } from './db';
import { STRENGTH, type StrengthKey } from './plan';
import { Icon, Sheet, num } from './ui';
import { longDate, type ISODate } from './dates';

const KIND_LABEL: Record<WorkoutKind, string> = { run: 'Lopen', strength: 'Kracht', boxing: 'Boksen', other: 'Overig' };

// ---------------------------------------------------------------------------
// Loop, boksen of overige training
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
          {(['run', 'boxing', 'other'] as WorkoutKind[]).map(k => (
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

export function StrengthLogger(props: { date: ISODate; strength: StrengthKey; slotId?: string; existing?: Workout; onClose: () => void }) {
  const exercises = STRENGTH[props.strength];
  const [rows, setRows] = useState<Record<string, SetRow[]> | null>(null);
  const [notes, setNotes] = useState(props.existing?.notes ?? '');
  const [rpe, setRpe] = useState(props.existing?.rpe?.toString() ?? '');
  const [prevInfo, setPrevInfo] = useState<Record<string, string>>({});

  useEffect(() => {
    (async () => {
      const init: Record<string, SetRow[]> = {};
      const info: Record<string, string> = {};
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
        if (mine.length) {
          init[ex.name] = mine.map(s => ({ reps: String(s.reps), kg: s.weightKg ? String(s.weightKg) : '' }));
        } else {
          const kg = last[0]?.weightKg ?? ex.defaultKg;
          const reps = last[0]?.reps ?? ex.defaultReps;
          init[ex.name] = Array.from({ length: ex.sets }, () => ({ reps: String(reps), kg: kg ? String(kg) : '' }));
        }
      }
      setRows(init);
      setPrevInfo(info);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.existing?.id, props.date, props.strength]);

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
    const title = props.strength === 'kort' ? 'Kracht kort' : `Kracht ${props.strength}`;
    const workout = await save('workouts', {
      ...(props.existing ?? {}),
      id: props.existing?.id ?? newId(),
      date: props.date,
      kind: 'strength',
      slotId: props.existing?.slotId ?? props.slotId,
      title,
      durationMin: props.existing?.durationMin ?? (props.strength === 'kort' ? 30 : 40),
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

  const title = props.strength === 'kort' ? 'Kracht kort' : `Kracht ${props.strength}`;
  return (
    <Sheet
      title={title}
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
          <div className="muted small">{ex.weight}, {ex.why}</div>
          {prevInfo[ex.name] && <div className="small" style={{ color: 'var(--accent)' }}>{prevInfo[ex.name]}</div>}
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
