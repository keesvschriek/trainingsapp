import { useEffect, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive, newId, remove, save, type Inbox } from '../db';
import { addDays, today } from '../dates';
import { parseLine } from '../opvolg';
import { Icon, Sheet } from '../ui';
import { sync } from '../sync';
import { splitShared } from '../share';
import { addNote } from './Notes';

// Van telefoon naar Kobo: link of tekst. De Kobo haalt het op bij de volgende synchronisatie
// en zet het bij Lezen, Te lezen. Ook te gebruiken vanuit Delen in elke app (Delen > K).

export async function sendToKobo(v: { url?: string; text?: string; title?: string }) {
  await save('inbox', { id: newId(), url: v.url, text: v.text, title: v.title, createdAt: Date.now(), done: false });
  void sync();
}

function useInbox(): Inbox[] {
  return useLiveQuery(async () => (await db.inbox.toArray()).filter(alive).sort((a, b) => b.createdAt - a.createdAt).slice(0, 20), [], []);
}

export function InboxScreen() {
  const items = useInbox();
  const [text, setText] = useState('');
  const [title, setTitle] = useState('');
  const [msg, setMsg] = useState('');

  async function send() {
    const v = splitShared(text, title);
    if (!v.url && !v.text) return;
    await sendToKobo(v);
    setText('');
    setTitle('');
    setMsg('Verstuurd. De Kobo zet het bij Te lezen zodra hij synchroniseert.');
  }

  return (
    <>
      <p className="muted small">Plak een link of tekst. Op de Kobo staat het daarna bij Lezen, Te lezen. Sneller: tik in Chrome of een andere app op Delen en kies K.</p>
      <p className="muted small">Leerstof? Zet per regel <code>vraag :: antwoord</code> (of plak twee kolommen uit Excel). Dan wordt het een stap in de leerlijn Eigen stof, met de titel als naam.</p>
      <label>Link of tekst</label>
      <textarea rows={6} value={text} placeholder={'https://...\n\nof leerstof:\nWaar staat CBRN voor? :: Chemisch, biologisch, radiologisch, nucleair'} onChange={e => setText(e.target.value)} />
      <label>Titel (mag leeg)</label>
      <input value={title} onChange={e => setTitle(e.target.value)} />
      <button className="btn block mt" onClick={() => void send()} disabled={!text.trim()}>Naar de Kobo</button>
      {msg && <div className="notice">{msg}</div>}
      {items.length > 0 && (
        <>
          <h2>Laatst verstuurd</h2>
          <div className="card">
            {items.map(i => (
              <div key={i.id} className="spread ov-added">
                <span>
                  {i.title || i.url || (i.text ?? '').slice(0, 60)}
                  <br />
                  <span className="muted small">{i.done ? (i.note ? i.note : 'Staat op de Kobo') : 'Wacht op de Kobo'}</span>
                </span>
                <button className="icon-btn" aria-label="Weghalen" onClick={() => void remove('inbox', i.id)}>{Icon.close}</button>
              </div>
            ))}
          </div>
        </>
      )}
    </>
  );
}

/** Verschijnt als je iets naar K deelt: kies Kobo of opvolgpunt. */
export function ShareSheet({ shared, onClose }: { shared: { text: string; subject: string }; onClose: () => void }) {
  const v = splitShared(shared.text, shared.subject);
  const [done, setDone] = useState('');
  useEffect(() => {
    if (!done) return;
    const t = window.setTimeout(onClose, 1200);
    return () => window.clearTimeout(t);
  }, [done, onClose]);

  async function asPoint() {
    const day = today();
    const p = parseLine(v.title ?? v.text ?? v.url ?? '', day, addDays(day, 1));
    await save('opvolg', { id: newId(), title: v.url ? `${p.title} (${v.url})` : p.title, due: p.due, done: false, createdAt: Date.now(), from: 'telefoon' });
    setDone('Staat bij Opvolgen, voor morgen.');
  }

  return (
    <Sheet title="Gedeeld met K" onClose={onClose}>
      <div className="card soft">
        <strong>{v.title || (v.url ? 'Link' : 'Tekst')}</strong>
        <div className="muted small" style={{ wordBreak: 'break-all' }}>{v.url ?? (v.text ?? '').slice(0, 200)}</div>
      </div>
      {done ? (
        <div className="notice">{done}</div>
      ) : (
        <>
          <button className="btn block mt" onClick={() => void sendToKobo(v).then(() => setDone('Onderweg naar de Kobo, bij Te lezen.'))}>Lezen op de Kobo</button>
          <button className="btn secondary block mt" onClick={() => void asPoint()}>Opvolgpunt voor morgen</button>
          <button className="btn secondary block mt" onClick={() => void addNote([v.title, v.url ?? v.text].filter(Boolean).join('\n'), v.url ? 'Lezen en kijken' : 'Ideeën').then(() => setDone('Staat bij Notities.'))}>Als notitie</button>
        </>
      )}
    </Sheet>
  );
}
