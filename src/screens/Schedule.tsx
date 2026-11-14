import { useEffect, useRef, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, newId, remove, save, type Block, type BlockKind } from '../db';
import { addDays, dayShort, shortDate, today, minutesToText } from '../dates';
import { PHASES, TOTAL_WEEKS, mondayOfWeek, planForWeek, plannedRunMinutes, weekOf, WEEKS } from '../plan';
import { matchDay } from '../match';
import { Sheet, useBlocks } from '../ui';

const BLOCK_LABEL: Record<BlockKind, string> = { defensie: 'Defensie', vakantie: 'Vakantie', ziek: 'Ziek of geblesseerd', anders: 'Anders (geen training)' };

export function Schedule() {
  const blocks = useBlocks();
  const current = Math.min(Math.max(weekOf(today()), 1), TOTAL_WEEKS);
  const [open, setOpen] = useState<number>(current);
  const [blockForm, setBlockForm] = useState<Partial<Block> | null>(null);
  const currentRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    currentRef.current?.scrollIntoView({ block: 'start' });
    window.scrollBy(0, -70);
  }, []);

  return (
    <>
      <h2 style={{ marginTop: 4 }}>Defensie, vakantie en andere blokken</h2>
      <p className="muted small">Een Defensieblok maakt die dagen rustdagen, de dag erna herstel en de rest van die week 30% lichter.</p>
      <div className="card">
        {blocks.length === 0 && <div className="muted small">Nog geen blokken. Voeg je AMO-modules en inzetten toe.</div>}
        {blocks.map(b => (
          <div className="logrow" key={b.id} onClick={() => setBlockForm(b)}>
            <div>{b.label}<span className="tag">{BLOCK_LABEL[b.kind]}</span></div>
            <div className="stats">{shortDate(b.start)}{b.end !== b.start ? ` t/m ${shortDate(b.end)}` : ''}</div>
          </div>
        ))}
        <button className="btn secondary small mt" onClick={() => setBlockForm({ kind: 'defensie', start: today(), end: today(), label: '' })}>Blok toevoegen</button>
      </div>

      {PHASES.map(phase => (
        <div key={phase.nr}>
          <div className="phase-head">
            <h2 style={{ margin: 0 }}>Fase {phase.nr}: {phase.name}</h2>
            <div className="muted">Week {phase.firstWeek} t/m {phase.lastWeek}. {phase.focus}</div>
          </div>
          {Array.from({ length: phase.lastWeek - phase.firstWeek + 1 }, (_, i) => phase.firstWeek + i).map(week => (
            <div key={week} ref={week === current ? currentRef : undefined}>
              <WeekCard week={week} blocks={blocks} isCurrent={week === current} open={open === week} onToggle={() => setOpen(open === week ? 0 : week)} />
            </div>
          ))}
        </div>
      ))}
      <p className="muted small mt">Fase 2 tot en met 4 zijn voorlopig. Zodra je data voor BVO-KBB en inzetten weet, voeg je ze toe als blok; het schema past zich aan.</p>

      {blockForm && <BlockEditor initial={blockForm} onClose={() => setBlockForm(null)} />}
    </>
  );
}

function WeekCard(props: { week: number; blocks: Block[]; isCurrent: boolean; open: boolean; onToggle: () => void }) {
  const { week, blocks } = props;
  const start = mondayOfWeek(week);
  const end = addDays(start, 6);
  const days = planForWeek(week, blocks);
  const minutes = plannedRunMinutes(week, blocks);
  const spec = WEEKS[week - 1];
  const workouts = useLiveQuery(async () => (props.open ? (await db.workouts.where('date').between(start, end, true, true).toArray()).filter(alive) : []), [props.open, start], []);
  const checks = useLiveQuery(async () => (props.open ? (await db.checks.where('date').between(start, end, true, true).toArray()).filter(alive) : []), [props.open, start], []);
  const light = days.some(d => d.lightWeek);
  const hasBlock = days.some(d => d.block && d.block.kind !== 'vakantie');

  return (
    <div className={`week${props.isCurrent ? ' current' : ''}`}>
      <button onClick={props.onToggle} aria-expanded={props.open}>
        <div className="spread">
          <strong>Week {week}</strong>
          <span className="muted small">{shortDate(start)} t/m {shortDate(end)}</span>
        </div>
        <div className="muted small">
          {minutesToText(minutes)} lopen{light ? ', lichte week' : ''}{hasBlock ? ', met blok' : ''}{spec.note && !spec.light ? `. ${spec.note}` : ''}
        </div>
      </button>
      {props.open && (
        <div className="body">
          <table>
            <tbody>
              {days.map(d => {
                const { statuses } = matchDay(d.items, workouts.filter(w => w.date === d.date), checks.filter(c => c.date === d.date));
                return (
                  <tr key={d.date} className={d.date === today() ? 'today' : d.block && d.block.kind !== 'vakantie' ? 'blocked' : ''}>
                    <td style={{ width: 34 }}>{dayShort(d.date)}</td>
                    <td>
                      {statuses.map(s => (
                        <div key={s.item.slotId + s.item.title}>
                          {s.item.title}
                          {s.item.minutes && s.item.kind !== 'rest' ? <span className="muted"> {minutesToText(s.item.minutes)}</span> : null}
                          {s.item.optional ? <span className="muted"> (optioneel)</span> : null}
                        </div>
                      ))}
                    </td>
                    <td className="done" style={{ width: 22 }}>{statuses.some(s => s.done) && statuses.filter(s => s.item.kind !== 'rest' && s.item.kind !== 'free' && !s.item.optional).every(s => s.done) ? '✓' : ''}</td>
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

function BlockEditor(props: { initial: Partial<Block>; onClose: () => void }) {
  const [kind, setKind] = useState<BlockKind>(props.initial.kind ?? 'defensie');
  const [start, setStart] = useState(props.initial.start ?? today());
  const [end, setEnd] = useState(props.initial.end ?? today());
  const [label, setLabel] = useState(props.initial.label ?? '');
  const existing = props.initial.id;

  async function submit() {
    const e = end < start ? start : end;
    await save('blocks', { id: existing ?? newId(), kind, start, end: e, label: label.trim() || BLOCK_LABEL[kind] });
    props.onClose();
  }
  async function del() {
    if (existing && confirm('Dit blok verwijderen?')) {
      await remove('blocks', existing);
      props.onClose();
    }
  }

  return (
    <Sheet
      title={existing ? 'Blok bewerken' : 'Blok toevoegen'}
      onClose={props.onClose}
      footer={<>{existing && <button className="btn danger" onClick={del}>Verwijderen</button>}<button className="btn" onClick={submit}>Opslaan</button></>}
    >
      <label>Soort</label>
      <select value={kind} onChange={e => setKind(e.target.value as BlockKind)}>
        {(Object.keys(BLOCK_LABEL) as BlockKind[]).map(k => <option key={k} value={k}>{BLOCK_LABEL[k]}</option>)}
      </select>
      <label>Omschrijving</label>
      <input value={label} onChange={e => setLabel(e.target.value)} placeholder="Bijv. AMO-module, inzet, kerstvakantie" />
      <div className="grid2">
        <div><label>Van</label><input type="date" value={start} onChange={e => setStart(e.target.value)} /></div>
        <div><label>Tot en met</label><input type="date" value={end} onChange={e => setEnd(e.target.value)} /></div>
      </div>
      <p className="muted small mt">
        {kind === 'defensie' && 'Deze dagen worden rustdagen, de dag erna herstel, en de rest van de week wordt lichter.'}
        {kind === 'vakantie' && 'Het schema blijft gewoon staan. Alleen een herinnering dat je extra ruimte hebt.'}
        {kind === 'ziek' && 'Deze dagen worden rustdagen. Gemiste trainingen niet inhalen.'}
        {kind === 'anders' && 'Deze dagen worden rustdagen.'}
      </p>
    </Sheet>
  );
}
