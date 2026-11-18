import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, newId, remove, save, type Note } from '../db';
import { Icon, Sheet } from '../ui';

// Notities: alles wat geen taak is. Gedeeld met de Kobo (tabel notes).

export const FOLDERS = ['Ideeën', 'Citaten', 'Lezen en kijken', 'Werk', 'Thuis', 'Overig'] as const;

export function useNotes(): Note[] {
  return useLiveQuery(async () => (await db.notes.toArray()).filter(alive).sort((a, b) => Number(!!b.pinned) - Number(!!a.pinned) || b.createdAt - a.createdAt), [], []);
}

export async function addNote(text: string, folder: string) {
  await save('notes', { id: newId(), text: text.trim(), folder, createdAt: Date.now(), from: 'telefoon' });
}

function FolderChips({ value, onChange, all }: { value?: string; onChange: (f?: string) => void; all?: boolean }) {
  return (
    <div className="chips">
      {all && <button className={`btn small ${!value ? '' : 'secondary'}`} onClick={() => onChange(undefined)}>Alles</button>}
      {FOLDERS.map(f => (
        <button key={f} className={`btn small ${value === f ? '' : 'secondary'}`} onClick={() => onChange(all && value === f ? undefined : f)}>{f}</button>
      ))}
    </div>
  );
}

export function NoteSheet({ existing, initial, onClose }: { existing?: Note; initial?: string; onClose: () => void }) {
  const [text, setText] = useState(existing?.text ?? initial ?? '');
  const [folder, setFolder] = useState<string>(existing?.folder ?? 'Ideeën');
  async function ok() {
    if (!text.trim()) return;
    if (existing) await save('notes', { ...existing, text: text.trim(), folder });
    else await addNote(text, folder);
    onClose();
  }
  return (
    <Sheet
      title={existing ? 'Notitie' : 'Nieuwe notitie'}
      onClose={onClose}
      footer={
        <>
          {existing && <button className="btn danger" onClick={() => void remove('notes', existing.id).then(onClose)}>Weghalen</button>}
          {existing && <button className="btn secondary" onClick={() => void save('notes', { ...existing, pinned: !existing.pinned }).then(onClose)}>{existing.pinned ? 'Losmaken' : 'Vastzetten'}</button>}
          <button className="btn" onClick={() => void ok()} disabled={!text.trim()}>Bewaren</button>
        </>
      }
    >
      <textarea autoFocus rows={7} value={text} placeholder="Wat wil je onthouden?" onChange={e => setText(e.target.value)} />
      <label>Map</label>
      <FolderChips value={folder} onChange={f => f && setFolder(f)} />
    </Sheet>
  );
}

export function NotesScreen() {
  const all = useNotes();
  const [folder, setFolder] = useState<string | undefined>();
  const [q, setQ] = useState('');
  const [sheet, setSheet] = useState<'new' | Note | null>(null);
  const list = all.filter(n => (!folder || n.folder === folder) && (!q || n.text.toLowerCase().includes(q.toLowerCase())));

  return (
    <>
      <button className="btn" onClick={() => setSheet('new')}>{Icon.plus} Notitie</button>
      <input className="mt" value={q} placeholder="Zoeken" onChange={e => setQ(e.target.value)} />
      <FolderChips value={folder} onChange={setFolder} all />
      {list.length === 0 && <p className="empty">{all.length ? 'Niets gevonden.' : 'Nog geen notities. Ook op de Kobo kun je ze maken en lezen.'}</p>}
      {list.length > 0 && (
        <div className="card">
          {list.map(n => (
            <button key={n.id} className="note-row" onClick={() => setSheet(n)}>
              <span className="note-text">{n.pinned ? '• ' : ''}{n.text}</span>
              <span className="muted small">{n.folder} · {new Date(n.createdAt).toLocaleDateString('nl-NL', { day: 'numeric', month: 'short' })}{n.from === 'kobo' ? ' · Kobo' : ''}</span>
            </button>
          ))}
        </div>
      )}
      {sheet === 'new' && <NoteSheet onClose={() => setSheet(null)} />}
      {sheet && typeof sheet === 'object' && <NoteSheet existing={sheet} onClose={() => setSheet(null)} />}
    </>
  );
}
