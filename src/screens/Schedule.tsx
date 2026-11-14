import { useEffect, useRef, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, newId, remove, save, type Block, type BlockKind } from '../db';
import { addDays, dayShort, shortDate, today, minutesToText } from '../dates';
import { blockOfWeek, isTestWeek, mondayOfWeek, planForWeek, plannedRunMinutes, weekOf, weekInBlock, type PlanBlock } from '../plan';
import { matchDay } from '../match';
import { Sheet, useBlocks } from '../ui';

const KIND_LABEL: Record<BlockKind, string> = {
  defensie: 'Defensie',
  wedstrijd: 'Wedstrijd of evenement',
  vakantie: 'Vakantie',
  ziek: 'Ziek of geblesseerd',
  anders: 'Anders (geen training)',
};

export function Schedule() {
  const events = useBlocks();
  const current = Math.max(weekOf(today()), 1);
  const [open, setOpen] = useState<number>(current);
  const [form, setForm] = useState<Partial<Block> | null>(null);
  const [extraBlocks, setExtraBlocks] = useState(0);
  const currentRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    currentRef.current?.scrollIntoView({ block: 'start' });
    window.scrollBy(0, -70);
  }, []);

  // Toon het huidige blok, het blok ervoor en de twee erna (plus wat je extra opvraagt)
  const curBlock = blockOfWeek(current).nr;
  const blocks: PlanBlock[] = [];
  for (let w = 1; blocks.length < curBlock + 2 + extraBlocks; ) {
    const b = blockOfWeek(w);
    blocks.push(b);
    w = b.lastWeek + 1;
  }
  const shown = blocks.filter(b => b.nr >= curBlock - 1);

  return (
    <>
      <h2 style={{ marginTop: 4 }}>Defensie, wedstrijden en andere momenten</h2>
      <p className="muted small">Defensie maakt die dagen rustdagen, de dag erna herstel en de rest van die week 30% lichter. Een wedstrijd vervangt de training van die dag.</p>
      <div className="card">
        {events.length === 0 && <div className="muted small">Nog niets toegevoegd. Zet hier je AMO-modules, inzetten en wedstrijden.</div>}
        {events.map(b => (
          <div className="logrow" key={b.id} onClick={() => setForm(b)}>
            <div>{b.label}<span className="tag">{KIND_LABEL[b.kind]}</span></div>
            <div className="stats">{shortDate(b.start)}{b.end !== b.start ? ` t/m ${shortDate(b.end)}` : ''}</div>
          </div>
        ))}
        <button className="btn secondary small mt" onClick={() => setForm({ kind: 'defensie', start: today(), end: today(), label: '' })}>Toevoegen</button>
      </div>

      {shown.map(block => (
        <div key={block.nr}>
          <div className="phase-head">
            <h2 style={{ margin: 0 }}>Blok {block.nr}: {block.name}</h2>
            <div className="muted">Week {weekInBlock(block.firstWeek)} t/m {block.lastWeek - block.firstWeek + 1}, {shortDate(mondayOfWeek(block.firstWeek))} t/m {shortDate(addDays(mondayOfWeek(block.lastWeek), 6))}. {block.focus}</div>
          </div>
          {Array.from({ length: block.lastWeek - block.firstWeek + 1 }, (_, i) => block.firstWeek + i).map(week => (
            <div key={week} ref={week === current ? currentRef : undefined}>
              <WeekCard week={week} events={events} isCurrent={week === current} open={open === week} onToggle={() => setOpen(open === week ? 0 : week)} />
            </div>
          ))}
        </div>
      ))}
      <button className="btn secondary block" onClick={() => setExtraBlocks(extraBlocks + 1)}>Volgend blok tonen</button>

      {form && <EventEditor initial={form} onClose={() => setForm(null)} />}
    </>
  );
}

function WeekCard(props: { week: number; events: Block[]; isCurrent: boolean; open: boolean; onToggle: () => void }) {
  const { week, events } = props;
  const start = mondayOfWeek(week);
  const end = addDays(start, 6);
  const days = planForWeek(week, events);
  const minutes = plannedRunMinutes(week, events);
  const workouts = useLiveQuery(async () => (props.open ? (await db.workouts.where('date').between(start, end, true, true).toArray()).filter(alive) : []), [props.open, start], []);
  const checks = useLiveQuery(async () => (props.open ? (await db.checks.where('date').between(start, end, true, true).toArray()).filter(alive) : []), [props.open, start], []);
  const light = days.some(d => d.lightWeek);
  const test = isTestWeek(week);
  const hasEvent = days.some(d => d.event && d.event.kind !== 'vakantie');

  return (
    <div className={`week${props.isCurrent ? ' current' : ''}`}>
      <button onClick={props.onToggle} aria-expanded={props.open}>
        <div className="spread">
          <strong>Week {weekInBlock(week)}{test ? ': testweek' : ''}</strong>
          <span className="muted small">{shortDate(start)} t/m {shortDate(end)}</span>
        </div>
        <div className="muted small">{minutesToText(minutes)} lopen{light ? ', lichte week' : ''}{hasEvent ? ', met afspraak' : ''}</div>
      </button>
      {props.open && (
        <div className="body">
          <table>
            <tbody>
              {days.map(d => {
                const { statuses } = matchDay(d.items, workouts.filter(w => w.date === d.date), checks.filter(c => c.date === d.date));
                const todo = statuses.filter(s => !['rest', 'free'].includes(s.item.kind) && !s.item.optional);
                return (
                  <tr key={d.date} className={d.date === today() ? 'today' : d.event && d.event.kind !== 'vakantie' ? 'blocked' : ''}>
                    <td style={{ width: 34 }}>{dayShort(d.date)}</td>
                    <td>
                      {statuses.map(s => (
                        <div key={s.item.slotId + s.item.title} style={{ marginBottom: 4 }}>
                          {s.item.title}
                          {s.item.minutes && s.item.kind !== 'rest' ? <span className="muted"> {minutesToText(s.item.minutes)}</span> : null}
                          {s.item.optional ? <span className="muted"> (optioneel)</span> : null}
                          {s.item.exercises && (
                            <div className="exsmall">{s.item.exercises.map(e => `${e.name} ${e.sets}x${e.reps.replace(/,.*$/, '')}`).join(' · ')}</div>
                          )}
                        </div>
                      ))}
                    </td>
                    <td className="done" style={{ width: 22 }}>{todo.length > 0 && todo.every(s => s.done) ? '✓' : ''}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function EventEditor(props: { initial: Partial<Block>; onClose: () => void }) {
  const [kind, setKind] = useState<BlockKind>(props.initial.kind ?? 'defensie');
  const [start, setStart] = useState(props.initial.start ?? today());
  const [end, setEnd] = useState(props.initial.end ?? today());
  const [label, setLabel] = useState(props.initial.label ?? '');
  const existing = props.initial.id;

  async function submit() {
    const e = kind === 'wedstrijd' ? start : end < start ? start : end;
    await save('blocks', { id: existing ?? newId(), kind, start, end: e, label: label.trim() || KIND_LABEL[kind] });
    props.onClose();
  }
  async function del() {
    if (existing && confirm('Verwijderen?')) {
      await remove('blocks', existing);
      props.onClose();
    }
  }

  return (
    <Sheet
      title={existing ? 'Bewerken' : 'Toevoegen'}
      onClose={props.onClose}
      footer={<>{existing && <button className="btn danger" onClick={del}>Verwijderen</button>}<button className="btn" onClick={submit}>Opslaan</button></>}
    >
      <label>Soort</label>
      <select value={kind} onChange={e => setKind(e.target.value as BlockKind)}>
        {(Object.keys(KIND_LABEL) as BlockKind[]).map(k => <option key={k} value={k}>{KIND_LABEL[k]}</option>)}
      </select>
      <label>Omschrijving</label>
      <input value={label} onChange={e => setLabel(e.target.value)} placeholder={kind === 'wedstrijd' ? 'Bijv. 10 km van ...' : 'Bijv. AMO-module, inzet'} />
      <div className="grid2">
        <div><label>{kind === 'wedstrijd' ? 'Datum' : 'Van'}</label><input type="date" value={start} onChange={e => setStart(e.target.value)} /></div>
        {kind !== 'wedstrijd' && <div><label>Tot en met</label><input type="date" value={end} onChange={e => setEnd(e.target.value)} /></div>}
      </div>
      <p className="muted small mt">
        {kind === 'defensie' && 'Deze dagen worden rustdagen, de dag erna herstel, en de rest van de week wordt lichter.'}
        {kind === 'wedstrijd' && 'Vervangt de training van die dag. De dag ervoor wordt een korte rustige loop.'}
        {kind === 'vakantie' && 'Het schema blijft staan. Alleen een herinnering dat je extra ruimte hebt.'}
        {kind === 'ziek' && 'Deze dagen worden rustdagen. Gemiste trainingen niet inhalen.'}
        {kind === 'anders' && 'Deze dagen worden rustdagen.'}
      </p>
    </Sheet>
  );
}
