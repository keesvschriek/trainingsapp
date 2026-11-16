import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, newId, remove, save, type Block, type PackItem } from '../db';
import { diffDays, dayShort, shortDate, today } from '../dates';
import { Icon, Sheet, useBlocks } from '../ui';

// Aftellen naar de volgende Defensie-module, met een paklijst die je elke keer opnieuw gebruikt.
// Modules zijn blokken van het soort Defensie (Schema > Blokken). Ook zichtbaar op de Kobo.

export const PACK_START = ['Defensiepas', 'Uniform en kistjes', 'Sportkleding en loopschoenen', 'Toiletspullen en handdoek', 'Oplader en powerbank', 'Notitieboek en pen', 'Medicijnen', 'Snacks en drinkfles'];

export function nextModule(blocks: Block[], day = today()): Block | undefined {
  return blocks
    .filter(b => !b.deleted && b.kind === 'defensie' && b.end >= day)
    .sort((a, b) => (a.start < b.start ? -1 : 1))[0];
}

export function usePack(): PackItem[] {
  return useLiveQuery(async () => (await db.pack.toArray()).filter(alive).sort((a, b) => a.order - b.order), [], []);
}

export async function ensurePack() {
  if ((await db.pack.count()) > 0) return;
  // vaste ids, zodat de Kobo dezelfde startlijst kan maken zonder dubbelingen
  for (let i = 0; i < PACK_START.length; i++) await save('pack', { id: `pack-${i + 1}`, text: PACK_START[i], order: i });
}

function PackEdit({ items, onClose }: { items: PackItem[]; onClose: () => void }) {
  const [text, setText] = useState('');
  async function add() {
    if (!text.trim()) return;
    await save('pack', { id: newId(), text: text.trim(), order: (items[items.length - 1]?.order ?? 0) + 1 });
    setText('');
  }
  return (
    <Sheet title="Paklijst aanpassen" onClose={onClose} footer={<button className="btn" onClick={onClose}>Klaar</button>}>
      <div className="card">
        {items.map(i => (
          <div key={i.id} className="spread ov-added">
            <span>{i.text}</span>
            <button className="icon-btn" aria-label="Weghalen" onClick={() => void remove('pack', i.id)}>{Icon.close}</button>
          </div>
        ))}
      </div>
      <label>Toevoegen</label>
      <input value={text} placeholder="Bijv. instructiekaart" onChange={e => setText(e.target.value)} onKeyDown={e => e.key === 'Enter' && void add()} />
      <button className="btn block mt" onClick={() => void add()} disabled={!text.trim()}>Toevoegen</button>
    </Sheet>
  );
}

export function ModuleCard() {
  const blocks = useBlocks();
  const pack = usePack();
  const [open, setOpen] = useState(false);
  const [edit, setEdit] = useState(false);
  const day = today();
  const m = nextModule(blocks, day);
  if (!m) return null;
  const days = diffDays(m.start, day);
  if (days > 28) return null;
  const packed = new Set(m.packed ?? []);
  const got = pack.filter(p => packed.has(p.id)).length;
  const when = days <= 0 ? 'nu bezig' : days === 1 ? 'morgen' : `over ${days} dagen`;

  async function toggle(id: string) {
    const next = new Set(packed);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    await save('blocks', { ...m!, packed: [...next] });
  }

  return (
    <div className="card">
      <div className="spread">
        <div>
          <div className="muted small">Volgende module</div>
          <strong>{m.label || 'Defensie'}</strong>
          <div className="small">{dayShort(m.start)} {shortDate(m.start)} t/m {dayShort(m.end)} {shortDate(m.end)} · {when}</div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div className="big-num">{days > 0 ? days : '·'}</div>
          <div className="muted small">{days > 0 ? (days === 1 ? 'dag' : 'dagen') : ''}</div>
        </div>
      </div>
      <button className="btn ghost small" style={{ paddingLeft: 0 }} onClick={() => { void ensurePack(); setOpen(!open); }}>
        Paklijst {pack.length ? `${got} van ${pack.length}` : ''} {open ? 'verbergen' : ''}
      </button>
      {open && (
        <>
          {pack.map(p => (
            <div key={p.id} className="ov-row">
              <button className={`check${packed.has(p.id) ? ' done' : ''}`} onClick={() => void toggle(p.id)} aria-label={p.text}>{packed.has(p.id) && Icon.check}</button>
              <span className={packed.has(p.id) ? 'ov-title done' : 'ov-title'}>{p.text}</span>
            </div>
          ))}
          <button className="btn ghost small" style={{ paddingLeft: 0 }} onClick={() => setEdit(true)}>Lijst aanpassen</button>
        </>
      )}
      {edit && <PackEdit items={pack} onClose={() => setEdit(false)} />}
    </div>
  );
}
