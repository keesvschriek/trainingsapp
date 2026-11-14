import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, type Workout, type WorkoutKind } from '../db';
import { mondayOf, shortDate, dayShort, today } from '../dates';
import { weekOf } from '../plan';
import { importActivities, IntervalsError } from '../intervals';
import { StrengthLogger, WorkoutEditor } from '../editors';
import { summary, strengthKeyOf } from './Today';
import { fmt } from '../ui';

type Filter = 'all' | WorkoutKind;
const FILTERS: [Filter, string][] = [['all', 'Alles'], ['run', 'Lopen'], ['strength', 'Kracht'], ['boxing', 'Boksen'], ['other', 'Overig']];

export function Log() {
  const [filter, setFilter] = useState<Filter>('all');
  const [edit, setEdit] = useState<Workout | 'new' | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; err?: boolean } | null>(null);
  const [limit, setLimit] = useState(60);

  const hasKey = useLiveQuery(async () => !!((await db.kv.get('intervals'))?.value as { key?: string } | undefined)?.key, [], false);
  const list = useLiveQuery(
    async () => (await db.workouts.orderBy('date').reverse().toArray()).filter(alive).filter(w => filter === 'all' || w.kind === filter),
    [filter],
    [],
  );

  async function pull() {
    setBusy(true);
    setMsg(null);
    try {
      const r = await importActivities();
      setMsg({ text: r.added ? `${r.added} nieuwe activiteit${r.added === 1 ? '' : 'en'} opgehaald.` : 'Alles is al binnen.' });
    } catch (e) {
      setMsg({ text: e instanceof IntervalsError ? e.message : 'Ophalen mislukt.', err: true });
    } finally {
      setBusy(false);
    }
  }

  // Groeperen per week
  const groups: { monday: string; items: Workout[] }[] = [];
  for (const w of list.slice(0, limit)) {
    const m = mondayOf(w.date);
    const g = groups[groups.length - 1];
    if (g && g.monday === m) g.items.push(w);
    else groups.push({ monday: m, items: [w] });
  }

  return (
    <>
      <div className="spread">
        <button className="btn" onClick={pull} disabled={busy || !hasKey}>{busy ? 'Bezig...' : 'Ophalen uit Garmin'}</button>
        <button className="btn secondary" onClick={() => setEdit('new')}>Toevoegen</button>
      </div>
      {!hasKey && <div className="notice">Vul bij Instellingen je intervals.icu-sleutel in om je Garmin-activiteiten op te halen.</div>}
      {msg && <div className={`notice${msg.err ? ' err' : ''}`}>{msg.text}</div>}

      <div className="seg mt">
        {FILTERS.map(([f, l]) => <button key={f} className={filter === f ? 'active' : ''} onClick={() => setFilter(f)}>{l}</button>)}
      </div>

      {list.length === 0 && <div className="empty">Nog niets gelogd.</div>}
      {groups.map(g => {
        const runs = g.items.filter(w => w.kind === 'run');
        const km = runs.reduce((s, w) => s + (w.distanceKm ?? 0), 0);
        const wk = weekOf(g.monday);
        return (
          <div key={g.monday}>
            <h2>
              {wk >= 1 && wk <= 34 ? `Week ${wk}` : `Week van ${shortDate(g.monday)}`}
              {km > 0 && <span className="muted small" style={{ fontWeight: 400 }}> · {fmt.km(km)} gelopen</span>}
            </h2>
            <div className="card">
              {g.items.map(w => (
                <div className="logrow" key={w.id} onClick={() => setEdit(w)}>
                  <div>
                    <div>{w.title}{w.source === 'intervals' && <span className="tag">Garmin</span>}</div>
                    <div className="muted small">{dayShort(w.date)} {shortDate(w.date)}{w.date === today() ? ', vandaag' : ''}</div>
                  </div>
                  <div className="stats">{summary(w)}</div>
                </div>
              ))}
            </div>
          </div>
        );
      })}
      {list.length > limit && <button className="btn secondary block" onClick={() => setLimit(limit + 60)}>Meer laden</button>}

      {edit === 'new' && <WorkoutEditor initial={{ date: today(), kind: 'run' }} allowKind onClose={() => setEdit(null)} />}
      {edit && edit !== 'new' && edit.kind === 'strength' && edit.source === 'manual' && (
        <StrengthLogger date={edit.date} strength={strengthKeyOf(edit)} existing={edit} onClose={() => setEdit(null)} />
      )}
      {edit && edit !== 'new' && !(edit.kind === 'strength' && edit.source === 'manual') && (
        <WorkoutEditor initial={edit} existing={edit} onClose={() => setEdit(null)} />
      )}
    </>
  );
}
