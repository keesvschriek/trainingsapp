import { useRef, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Haptics, ImpactStyle } from '@capacitor/haptics';
import { db, alive, newId, remove, save, type Opvolg } from '../db';
import { addDays, today, type ISODate } from '../dates';
import { GROUPS, dueChoices, dueNow, dueText, parseLine, sortOpen } from '../opvolg';
import { Icon, Sheet } from '../ui';
import { isNative } from '../native';

export function useOpvolg(): Opvolg[] {
  return useLiveQuery(async () => (await db.opvolg.toArray()).filter(alive), [], []);
}

async function toggle(o: Opvolg) {
  if (isNative) void Haptics.impact({ style: o.done ? ImpactStyle.Light : ImpactStyle.Medium }).catch(() => undefined);
  await save('opvolg', { ...o, done: !o.done, doneAt: o.done ? undefined : Date.now() });
}

async function add(title: string, due: ISODate, group?: string) {
  await save('opvolg', { id: newId(), title, due, group, done: false, createdAt: Date.now(), from: 'telefoon' });
}

function Row({ o, day, onEdit }: { o: Opvolg; day: ISODate; onEdit?: (o: Opvolg) => void }) {
  const late = !o.done && o.due < day;
  return (
    <div className="ov-row">
      <button className={`check${o.done ? ' done' : ''}`} onClick={() => void toggle(o)} aria-label={o.done ? 'Weer open' : 'Afronden'}>{o.done && Icon.check}</button>
      <button className="ov-text" onClick={() => onEdit?.(o)}>
        <span className={o.done ? 'ov-title done' : 'ov-title'}>{o.title}</span>
        <span className={`small ${late ? '' : 'muted'}`}>{late ? <strong>{dueText(o.due, day)}</strong> : dueText(o.due, day)}{o.group ? ` · ${o.group}` : ''}</span>
      </button>
    </div>
  );
}

function DueChips({ value, onChange }: { value: ISODate; onChange: (d: ISODate) => void }) {
  const day = today();
  return (
    <div className="chips">
      {dueChoices(day).map(c => (
        <button key={c.label} className={`btn small ${value === c.date ? '' : 'secondary'}`} onClick={() => onChange(c.date)}>{c.label}</button>
      ))}
    </div>
  );
}

function GroupChips({ value, onChange }: { value?: string; onChange: (g?: string) => void }) {
  return (
    <div className="chips">
      {GROUPS.map(g => (
        <button key={g} className={`btn small ${value === g ? '' : 'secondary'}`} onClick={() => onChange(value === g ? undefined : g)}>{g}</button>
      ))}
    </div>
  );
}

/** Eén punt toevoegen of aanpassen. */
export function PointSheet({ existing, onClose }: { existing?: Opvolg; onClose: () => void }) {
  const day = today();
  const [text, setText] = useState(existing?.title ?? '');
  const [due, setDue] = useState<ISODate>(existing?.due ?? addDays(day, 1));
  const [group, setGroup] = useState<string | undefined>(existing?.group);

  async function ok() {
    const p = parseLine(text, day, due);
    if (!p.title) return;
    if (existing) await save('opvolg', { ...existing, title: p.title, due: p.due, group });
    else await add(p.title, p.due, group);
    onClose();
  }

  return (
    <Sheet
      title={existing ? 'Punt aanpassen' : 'Nieuw punt'}
      onClose={onClose}
      footer={
        <>
          {existing && <button className="btn danger" onClick={() => void remove('opvolg', existing.id).then(onClose)}>Weghalen</button>}
          <button className="btn" onClick={() => void ok()} disabled={!text.trim()}>Bewaren</button>
        </>
      }
    >
      <label>Wat moet je doen?</label>
      <input autoFocus value={text} placeholder="Bijv. verslag rondsturen vr" onChange={e => setText(e.target.value)} onKeyDown={e => e.key === 'Enter' && void ok()} />
      <p className="muted small">Geen leerlingnamen: initialen of een rol is genoeg. Een dag aan het eind (morgen, vr, volgende week) zet de datum vanzelf.</p>
      <label>Wanneer</label>
      <DueChips value={due} onChange={setDue} />
      <label>Bij</label>
      <GroupChips value={group} onChange={setGroup} />
    </Sheet>
  );
}

/** Overlegmodus: kies de werkgroep en tik actiepunten achter elkaar in. */
export function MeetingSheet({ onClose }: { onClose: () => void }) {
  const day = today();
  const [group, setGroup] = useState<string | undefined>();
  const [due, setDue] = useState<ISODate>(addDays(day, 7));
  const [text, setText] = useState('');
  const [added, setAdded] = useState<{ id: string; title: string; due: ISODate }[]>([]);
  const input = useRef<HTMLInputElement>(null);

  async function push() {
    const p = parseLine(text, day, due);
    if (!p.title) return;
    const id = newId();
    await save('opvolg', { id, title: p.title, due: p.due, group, done: false, createdAt: Date.now(), from: 'telefoon' });
    setAdded(a => [...a, { id, title: p.title, due: p.due }]);
    setText('');
    input.current?.focus();
  }

  return (
    <Sheet title={group ? `Overleg ${group}` : 'Overleg'} onClose={onClose} footer={<button className="btn" onClick={onClose}>Klaar ({added.length})</button>}>
      {!group ? (
        <>
          <p className="muted small">Welk overleg?</p>
          <GroupChips value={group} onChange={setGroup} />
        </>
      ) : (
        <>
          <input ref={input} autoFocus value={text} enterKeyHint="next" placeholder="Actiepunt, Enter voor het volgende" onChange={e => setText(e.target.value)} onKeyDown={e => e.key === 'Enter' && void push()} />
          <button className="btn block mt" onClick={() => void push()} disabled={!text.trim()}>Toevoegen</button>
          <label>Standaard klaar op</label>
          <DueChips value={due} onChange={setDue} />
          {added.length > 0 && (
            <div className="card mt">
              {added.map(a => (
                <div key={a.id} className="spread ov-added">
                  <span>{a.title} <span className="muted small">· {dueText(a.due, day)}</span></span>
                  <button className="icon-btn" aria-label="Weghalen" onClick={() => void remove('opvolg', a.id).then(() => setAdded(x => x.filter(y => y.id !== a.id)))}>{Icon.close}</button>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </Sheet>
  );
}

/** Op Vandaag: wat vandaag aandacht vraagt. */
export function OpvolgCard() {
  const day = today();
  const all = useOpvolg();
  const now = dueNow(all, day);
  const open = sortOpen(all);
  const later = open.length - now.length;
  const [sheet, setSheet] = useState<'add' | 'meeting' | Opvolg | null>(null);

  return (
    <div className="card ov-card">
      <div className="spread">
        <strong>Opvolgen</strong>
        <a className="small muted" href="#/opvolgen">{open.length ? `Alles (${open.length})` : 'Alles'}</a>
      </div>
      {now.length ? (
        now.map(o => <Row key={o.id} o={o} day={day} onEdit={setSheet} />)
      ) : (
        <p className="muted small" style={{ margin: '6px 0' }}>Niets voor vandaag.{later ? ` ${later} ${later === 1 ? 'punt' : 'punten'} later.` : ''}</p>
      )}
      <div className="row mt">
        <button className="btn small" onClick={() => setSheet('add')}>{Icon.plus} Punt</button>
        <button className="btn small secondary" onClick={() => setSheet('meeting')}>Overleg</button>
      </div>
      {sheet === 'add' && <PointSheet onClose={() => setSheet(null)} />}
      {sheet === 'meeting' && <MeetingSheet onClose={() => setSheet(null)} />}
      {sheet && typeof sheet === 'object' && <PointSheet existing={sheet} onClose={() => setSheet(null)} />}
    </div>
  );
}

/** Hele lijst, per periode, met filter op werkgroep. */
export function OpvolgScreen() {
  const day = today();
  const all = useOpvolg();
  const [group, setGroup] = useState<string | undefined>();
  const [sheet, setSheet] = useState<'add' | 'meeting' | Opvolg | null>(null);
  const [showDone, setShowDone] = useState(false);
  const pick = (o: Opvolg) => !group || o.group === group;
  const open = sortOpen(all).filter(pick);
  const weekEnd = addDays(day, 6);
  const parts: [string, Opvolg[]][] = [
    ['Te laat', open.filter(o => o.due < day)],
    ['Vandaag', open.filter(o => o.due === day)],
    ['Komende 7 dagen', open.filter(o => o.due > day && o.due <= weekEnd)],
    ['Later', open.filter(o => o.due > weekEnd)],
  ];
  const done = all.filter(o => o.done && pick(o) && (o.doneAt ?? 0) > Date.now() - 14 * 86400000).sort((a, b) => (b.doneAt ?? 0) - (a.doneAt ?? 0));

  return (
    <>
      <div className="row">
        <button className="btn" onClick={() => setSheet('add')}>{Icon.plus} Punt</button>
        <button className="btn secondary" onClick={() => setSheet('meeting')}>Overleg</button>
      </div>
      <h2>Filter</h2>
      <GroupChips value={group} onChange={setGroup} />
      {open.length === 0 && <p className="empty">Geen open punten{group ? ` bij ${group}` : ''}.</p>}
      {parts.map(([label, list]) =>
        list.length ? (
          <div key={label}>
            <h2>{label}</h2>
            <div className="card">{list.map(o => <Row key={o.id} o={o} day={day} onEdit={setSheet} />)}</div>
          </div>
        ) : null,
      )}
      {done.length > 0 && (
        <>
          <button className="btn ghost mt" onClick={() => setShowDone(!showDone)}>{showDone ? 'Afgerond verbergen' : `Afgerond, laatste 2 weken (${done.length})`}</button>
          {showDone && <div className="card">{done.map(o => <Row key={o.id} o={o} day={day} onEdit={setSheet} />)}</div>}
        </>
      )}
      {sheet === 'add' && <PointSheet onClose={() => setSheet(null)} />}
      {sheet === 'meeting' && <MeetingSheet onClose={() => setSheet(null)} />}
      {sheet && typeof sheet === 'object' && <PointSheet existing={sheet} onClose={() => setSheet(null)} />}
    </>
  );
}
