import { useState } from 'react';
import { generate, getKey, MODEL, setKey } from './ai';
import { allQuestions } from './engine';
import { CATS } from './model';
import { addAi, clearAi, updatePacks, useExtra } from './packs';

/** Nieuwe vragen: pakketten ophalen uit de repo, of laten maken met je eigen API-sleutel. */
export function UpdateSection({ onChange }: { onChange: () => void }) {
  const extra = useExtra();
  const [busy, setBusy] = useState('');
  const [msg, setMsg] = useState('');
  const [key, setK] = useState(getKey());
  const [showKey, setShowKey] = useState(false);
  const [cat, setCat] = useState('wereldgeschiedenis');
  const [topic, setTopic] = useState('');

  async function fetchPacks() {
    setBusy('packs');
    setMsg('');
    try {
      const r = await updatePacks();
      setMsg(r.added ? `${r.added} nieuwe vragen binnen.` : 'Geen nieuwe vragen: je bent bij.');
      onChange();
    } catch (e) {
      setMsg(`Ophalen mislukt: ${(e as Error).message}`);
    }
    setBusy('');
  }

  async function makeAi() {
    setBusy('ai');
    setMsg('');
    try {
      const avoid = (await allQuestions()).filter(q => q.cat === cat).map(q => q.q);
      const list = await generate(key, cat, topic.trim(), 10, avoid);
      await addAi(list);
      setMsg(list.length ? `${list.length} vragen gemaakt. Ze zitten nu in de categorie en in de snelle mix.` : 'Er kwamen geen bruikbare vragen terug.');
      onChange();
    } catch (e) {
      setMsg(`Mislukt: ${(e as Error).message}`);
    }
    setBusy('');
  }

  const packCount = extra.packs.reduce((a, p) => a + p.questions.length, 0);
  return (
    <>
      <h2 className="section-title">Nieuwe vragen</h2>
      <div className="card">
        <p className="small" style={{ marginTop: 0 }}>
          Vragenpakketten staan in de repo (map <code>quiz-packs</code>). Ophalen kan zonder nieuwe app-versie.
          {extra.checkedAt ? ` Laatst opgehaald ${new Date(extra.checkedAt).toLocaleDateString('nl-NL')}, ${packCount} vragen uit ${extra.packs.length} pakket${extra.packs.length === 1 ? '' : 'ten'}.` : ''}
        </p>
        <button className="btn" onClick={() => void fetchPacks()} disabled={!!busy}>{busy === 'packs' ? 'Ophalen...' : 'Nieuwe vragen ophalen'}</button>
        {extra.removed.length > 0 && <p className="muted small">{extra.removed.length} vragen verborgen omdat je ze als fout markeerde.</p>}
      </div>

      <div className="card">
        <div className="muted small" style={{ marginBottom: 6 }}>Zelf vragen laten maken met AI</div>
        <p className="small" style={{ marginTop: 0 }}>
          Met je eigen Anthropic API-sleutel ({MODEL}). Tien vragen kosten naar schatting rond een cent; het precieze verbruik zie je in de Anthropic Console.
          AI-vragen kunnen fouten bevatten. Ze krijgen een label en je kunt ze met "Klopt niet" verbergen.
        </p>
        <label className="field">
          <span>Categorie</span>
          <select value={cat} onChange={e => setCat(e.target.value)}>
            {CATS.map(c => <option key={c.key} value={c.key}>{c.name}</option>)}
          </select>
        </label>
        <label className="field">
          <span>Onderwerp (mag leeg)</span>
          <input value={topic} onChange={e => setTopic(e.target.value)} placeholder="bijv. Koude Oorlog in Azië" />
        </label>
        {showKey || !key ? (
          <label className="field">
            <span>API-sleutel (blijft op deze telefoon)</span>
            <input type="password" value={key} autoComplete="off" onChange={e => { setK(e.target.value); setKey(e.target.value); }} placeholder="sk-ant-..." />
          </label>
        ) : (
          <button className="btn ghost small" onClick={() => setShowKey(true)}>Sleutel wijzigen</button>
        )}
        <div className="row" style={{ marginTop: 8 }}>
          <button className="btn" onClick={() => void makeAi()} disabled={!!busy || !key}>{busy === 'ai' ? 'Bezig...' : 'Maak 10 vragen'}</button>
          {extra.ai.length > 0 && <button className="btn secondary small" onClick={() => void clearAi().then(onChange)}>Alle {extra.ai.length} AI-vragen wissen</button>}
        </div>
      </div>
      {msg && <p className="small" role="status">{msg}</p>}
    </>
  );
}
