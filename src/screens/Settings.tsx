import { useEffect, useState } from 'react';
import { db, getSetting, setSetting, SYNC_TABLES, type Base } from '../db';
import { getIntervalsSettings, importActivities, IntervalsError, type IntervalsSettings } from '../intervals';
import { currentUser, getSupabase, sync, type SupabaseSettings } from '../sync';
import { today } from '../dates';
import type { Table } from 'dexie';
import { APK_URL, isNative } from '../native';

export function Settings() {
  return (
    <>
      <IntervalsSection />
      <SyncSection />
      <BackupSection />
      <h2>Over</h2>
      <p className="muted small">
        Trainingsapp {__APP_BUILD__ ? `build ${__APP_BUILD__}` : ''} ({__APP_VERSION__}). Je gegevens staan op dit apparaat en, als je inlogt, in je eigen Supabase-project.
        De app werkt ook zonder internet.
      </p>
      <p className="small">
        <a href={APK_URL} target="_blank" rel="noreferrer">{isNative ? 'Nieuwste versie downloaden' : 'Android-app downloaden (APK)'}</a>
      </p>
    </>
  );
}

function IntervalsSection() {
  const [s, setS] = useState<IntervalsSettings | null>(null);
  const [msg, setMsg] = useState<{ text: string; err?: boolean } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => { void getIntervalsSettings().then(setS); }, []);
  if (!s) return null;

  async function store(next: IntervalsSettings) {
    setS(next);
    await setSetting('intervals', next);
  }
  async function test() {
    setBusy(true);
    setMsg(null);
    try {
      const r = await importActivities(56);
      setMsg({ text: `Gelukt. ${r.added} nieuwe activiteiten opgehaald.` });
    } catch (e) {
      setMsg({ text: e instanceof IntervalsError ? e.message : String(e), err: true });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <h2 style={{ marginTop: 4 }}>Garmin via intervals.icu</h2>
      <p className="muted small">Koppel in intervals.icu je Garmin Connect. Je API-sleutel staat bij Settings, onderaan bij Developer Settings. De sleutel blijft op dit apparaat en wordt niet gesynchroniseerd.</p>
      <label>API-sleutel</label>
      <input type="password" autoComplete="off" value={s.key} onChange={e => store({ ...s, key: e.target.value.trim() })} />
      <div className="grid2">
        <div>
          <label>Athlete-ID</label>
          <input value={s.athlete} onChange={e => store({ ...s, athlete: e.target.value.trim() || '0' })} />
        </div>
        <div>
          <label>Proxy-URL (alleen webversie)</label>
          <input value={s.proxy} placeholder="leeg laten" onChange={e => store({ ...s, proxy: e.target.value.trim() })} />
        </div>
      </div>
      <p className="muted small">Athlete-ID 0 betekent: jijzelf.</p>
      <button className="btn mt" onClick={test} disabled={busy || !s.key}>{busy ? 'Bezig...' : 'Testen en ophalen'}</button>
      {msg && <div className={`notice${msg.err ? ' err' : ''}`}>{msg.text}</div>}
    </>
  );
}

function SyncSection() {
  const [cfg, setCfg] = useState<SupabaseSettings | null>(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [user, setUser] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ text: string; err?: boolean } | null>(null);
  const [busy, setBusy] = useState(false);
  const [lastOk, setLastOk] = useState('');

  async function refresh() {
    const u = await currentUser();
    setUser(u?.email ?? null);
    setLastOk(await getSetting('sync.lastOk', ''));
  }
  useEffect(() => {
    void getSetting<SupabaseSettings>('supabase', { url: '', anonKey: '' }).then(setCfg);
    void refresh();
  }, []);
  if (!cfg) return null;

  async function store(next: SupabaseSettings) {
    setCfg(next);
    await setSetting('supabase', next);
  }

  async function login(signup: boolean) {
    setBusy(true);
    setMsg(null);
    try {
      const sb = await getSupabase();
      if (!sb) throw new Error('Vul eerst de project-URL en de anon key in.');
      const res = signup
        ? await sb.auth.signUp({ email, password })
        : await sb.auth.signInWithPassword({ email, password });
      if (res.error) throw new Error(res.error.message);
      if (signup && !res.data.session) {
        setMsg({ text: 'Account aangemaakt. Bevestig de link in je mail en log daarna hier in.' });
      } else {
        const r = await sync();
        setMsg(r.error ? { text: r.error, err: true } : { text: `Ingelogd en gesynchroniseerd (${r.pushed} omhoog, ${r.pulled} omlaag).` });
      }
      await refresh();
    } catch (e) {
      setMsg({ text: e instanceof Error ? e.message : String(e), err: true });
    } finally {
      setBusy(false);
    }
  }

  async function syncNow() {
    setBusy(true);
    const r = await sync();
    setMsg(r.error ? { text: r.error, err: true } : { text: `Klaar: ${r.pushed} omhoog, ${r.pulled} omlaag.` });
    await refresh();
    setBusy(false);
  }

  async function logout() {
    const sb = await getSupabase();
    await sb?.auth.signOut();
    await refresh();
    setMsg({ text: 'Uitgelogd. Je gegevens blijven op dit apparaat staan.' });
  }

  return (
    <>
      <h2>Synchroniseren (Supabase)</h2>
      <p className="muted small">Optioneel. Zo staan je gegevens ook op je laptop en heb je een back-up in de cloud. Stappenplan staat in de README op GitHub.</p>
      <label>Project-URL</label>
      <input value={cfg.url} placeholder="https://xxxx.supabase.co" onChange={e => store({ ...cfg, url: e.target.value.trim() })} />
      <label>Anon public key</label>
      <input value={cfg.anonKey} onChange={e => store({ ...cfg, anonKey: e.target.value.trim() })} />

      {user ? (
        <div className="card soft mt">
          <div>Ingelogd als <strong>{user}</strong></div>
          {lastOk && <div className="muted small">Laatste synchronisatie: {new Date(lastOk).toLocaleString('nl-NL')}</div>}
          <div className="row mt">
            <button className="btn" onClick={syncNow} disabled={busy}>{busy ? 'Bezig...' : 'Nu synchroniseren'}</button>
            <button className="btn secondary" onClick={logout}>Uitloggen</button>
          </div>
        </div>
      ) : (
        <>
          <div className="grid2">
            <div><label>E-mail</label><input type="email" autoComplete="username" value={email} onChange={e => setEmail(e.target.value)} /></div>
            <div><label>Wachtwoord</label><input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} /></div>
          </div>
          <div className="row mt">
            <button className="btn" onClick={() => login(false)} disabled={busy || !email || !password}>Inloggen</button>
            <button className="btn secondary" onClick={() => login(true)} disabled={busy || !email || password.length < 6}>Account aanmaken</button>
          </div>
        </>
      )}
      {msg && <div className={`notice${msg.err ? ' err' : ''}`}>{msg.text}</div>}
    </>
  );
}

function BackupSection() {
  const [msg, setMsg] = useState<{ text: string; err?: boolean } | null>(null);

  async function exportJson() {
    const out: Record<string, unknown[]> = {};
    for (const t of SYNC_TABLES) out[t] = await (db[t] as unknown as Table<Base, string>).toArray();
    const blob = new Blob([JSON.stringify({ app: 'trainingsapp', version: 1, exported: new Date().toISOString(), data: out }, null, 1)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `trainingsapp-backup-${today()}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  async function importJson(file: File) {
    try {
      const parsed = JSON.parse(await file.text());
      if (parsed.app !== 'trainingsapp') throw new Error('Dit is geen back-up van de trainingsapp.');
      let n = 0;
      for (const t of SYNC_TABLES) {
        const table = db[t] as unknown as Table<Base, string>;
        for (const rec of (parsed.data?.[t] ?? []) as Base[]) {
          const local = await table.get(rec.id);
          if (!local || local.updatedAt < rec.updatedAt) {
            // nieuw updatedAt zodat het ook naar Supabase gaat
            await table.put({ ...rec, updatedAt: Math.max(rec.updatedAt, Date.now()) });
            n++;
          }
        }
      }
      window.dispatchEvent(new Event('data-changed'));
      setMsg({ text: `${n} records teruggezet.` });
    } catch (e) {
      setMsg({ text: e instanceof Error ? e.message : String(e), err: true });
    }
  }

  return (
    <>
      <h2>Back-up</h2>
      <p className="muted small">Een JSON-bestand met al je trainingen, metingen en blokken. Handig voor je eigen archief.</p>
      <div className="row">
        <button className="btn secondary" onClick={exportJson}>Exporteren</button>
        <label className="btn secondary" style={{ margin: 0, color: 'var(--accent)' }}>
          Importeren
          <input type="file" accept="application/json" style={{ display: 'none' }} onChange={e => e.target.files?.[0] && importJson(e.target.files[0])} />
        </label>
      </div>
      {msg && <div className={`notice${msg.err ? ' err' : ''}`}>{msg.text}</div>}
    </>
  );
}
