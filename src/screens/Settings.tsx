import { linkKobo, cleanCode } from '../kobolink';
import { useEffect, useState } from 'react';
import { db, getSetting, setSetting, SYNC_TABLES, type Base } from '../db';
import { getIntervalsSettings, importActivities, IntervalsError, type IntervalsSettings } from '../intervals';
import { currentUser, getSupabase, getSupabaseSettings, hasBuiltIn, sync, type SupabaseSettings } from '../sync';
import { today } from '../dates';
import type { Table } from 'dexie';
import { APK_URL, isNative } from '../native';
import { pushToGarmin } from '../garmin';
import { NotifySection } from './NotifySection';
import { setThemePref, type ThemePref } from '../theme';
import { usePushupSettings } from '../pushups';
import { bioAvailable, getLock, makePin, setLock } from '../lock';
import { saveWork, useWork } from '../work';
import { useCar, type CarSettings } from '../savings';
import { ALL_CATS, useTrivia, type TriviaSettings } from '../trivia/trivia';
import { CATEGORY_NAMES } from '../trivia/questions';
import { getPlace, searchPlace, type Place } from '../weather';

export function Settings() {
  return (
    <>
      <ThemeSection />
      <IntervalsSection />
      <GarminSection />
      <NotifySection />
      <PushupSection />
      <LockSection />
      <WorkSection />
      <CarSection />
      <TriviaSection />
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
      <h2>Garmin via intervals.icu</h2>
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
  const [koboCode, setKoboCode] = useState('');
  const [koboPw, setKoboPw] = useState('');

  async function refresh() {
    const u = await currentUser();
    setUser(u?.email ?? null);
    setLastOk(await getSetting('sync.lastOk', ''));
  }
  useEffect(() => {
    void getSupabaseSettings().then(setCfg);
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

  async function koppelKobo() {
    setBusy(true);
    setMsg(null);
    try {
      if (!cfg || !user) throw new Error('Log eerst in.');
      await linkKobo(koboCode, { url: cfg.url, key: cfg.anonKey, email: user, pw: koboPw });
      setKoboCode('');
      setKoboPw('');
      setMsg({ text: 'Verstuurd. Over een paar seconden staat er Gelukt op de Kobo.' });
    } catch (e) {
      setMsg({ text: e instanceof Error ? e.message : String(e), err: true });
    } finally {
      setBusy(false);
    }
  }

  async function logout() {
    const sb = await getSupabase();
    await sb?.auth.signOut();
    await refresh();
    setMsg({ text: 'Uitgelogd. Je gegevens blijven op dit apparaat staan.' });
  }

  const projectFields = (
    <>
      <label>Project-URL</label>
      <input value={cfg.url} placeholder="https://xxxx.supabase.co" onChange={e => store({ ...cfg, url: e.target.value.trim() })} />
      <label>Anon public key</label>
      <input value={cfg.anonKey} onChange={e => store({ ...cfg, anonKey: e.target.value.trim() })} />
    </>
  );

  return (
    <>
      <h2>Synchroniseren</h2>
      <p className="muted small">Log in, dan staan je gegevens ook in de cloud en lopen je laptop en de Kobo gelijk.</p>
      {hasBuiltIn() ? (
        <details className="muted small">
          <summary>Ander Supabase-project</summary>
          {projectFields}
        </details>
      ) : projectFields}

      {user ? (
        <>
        <div className="card soft mt">
          <div>Ingelogd als <strong>{user}</strong></div>
          {lastOk && <div className="muted small">Laatste synchronisatie: {new Date(lastOk).toLocaleString('nl-NL')}</div>}
          <div className="row mt">
            <button className="btn" onClick={syncNow} disabled={busy}>{busy ? 'Bezig...' : 'Nu synchroniseren'}</button>
            <button className="btn secondary" onClick={logout}>Uitloggen</button>
          </div>
        </div>
        <h2>Kobo koppelen</h2>
        <p className="muted small">Kies op de Kobo Instellingen, Telefoon-app, Koppelen. Typ de code van de Kobo hier over, met je wachtwoord. De Kobo logt daarmee één keer in en bewaart je wachtwoord niet.</p>
        <div className="grid2">
          <div><label>Code op de Kobo</label><input value={koboCode} autoCapitalize="characters" autoComplete="off" spellCheck={false} maxLength={9} placeholder="ABCD 2345" onChange={e => setKoboCode(e.target.value.toUpperCase())} /></div>
          <div><label>Wachtwoord</label><input type="password" autoComplete="current-password" value={koboPw} onChange={e => setKoboPw(e.target.value)} /></div>
        </div>
        <button className="btn block mt" onClick={koppelKobo} disabled={busy || cleanCode(koboCode).length !== 8 || !koboPw}>{busy ? 'Bezig...' : 'Koppel de Kobo'}</button>
        </>
      ) : (
        <>
          <div className="grid2">
            <div><label>E-mail</label><input type="email" autoComplete="username" value={email} onChange={e => setEmail(e.target.value)} /></div>
            <div><label>Wachtwoord</label><input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} /></div>
          </div>
          <div className="row mt">
            <button className="btn" onClick={() => login(false)} disabled={busy || !email || !password}>Inloggen</button>
            {!hasBuiltIn() && <button className="btn secondary" onClick={() => login(true)} disabled={busy || !email || password.length < 6}>Account aanmaken</button>}
          </div>
          <h2>Kobo koppelen</h2>
          <p className="muted small">Log eerst hierboven in. Daarna staat hier het vak voor de code van de Kobo.</p>
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

function GarminSection() {
  const [on, setOn] = useState<boolean | null>(null);
  const [last, setLast] = useState(0);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; err?: boolean } | null>(null);

  useEffect(() => {
    void getSetting('garmin.on', false).then(setOn);
    void getSetting('garmin.last', 0).then(setLast);
  }, []);
  if (on === null) return null;

  async function toggle(v: boolean) {
    setOn(v);
    await setSetting('garmin.on', v);
    if (v) await send();
  }

  async function send() {
    setBusy(true);
    setMsg(null);
    try {
      const r = await pushToGarmin();
      setMsg({ text: `${r.sent} trainingen in je intervals.icu-agenda gezet${r.removed ? `, ${r.removed} verschoven weggehaald` : ''}.` });
      setLast(Date.now());
    } catch (e) {
      setMsg({ text: e instanceof IntervalsError ? e.message : String(e), err: true });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <h2>Trainingen naar je Garmin</h2>
      <p className="muted small">
        De app zet je schema van de komende 14 dagen in je intervals.icu-agenda. Lopen gaan erin als training met hartslagdoelen: intervals.icu stuurt de komende 7 dagen door naar Garmin Connect, en na een sync staan ze op je Fenix. Kracht, tests en wedstrijden gaan erin als notitie: die zie je in intervals.icu en op je Kobo, niet op je horloge. Verschuif je iets, dan gaat dat automatisch mee.
      </p>
      <p className="muted small">
        Eenmalig in intervals.icu: Settings, bij Garmin het vinkje <strong>Upload planned workouts</strong> aan. Controleer ook dat je lactaatdrempel-hartslag (LTHR) bij Hardlopen goed staat.
      </p>
      <label className="row" style={{ color: 'var(--ink)', fontSize: '1rem' }}>
        <input type="checkbox" checked={on} onChange={e => toggle(e.target.checked)} style={{ width: 'auto' }} /> Automatisch versturen
      </label>
      <div className="row mt">
        <button className="btn secondary" onClick={send} disabled={busy}>{busy ? 'Bezig...' : 'Nu versturen'}</button>
        {last > 0 && <span className="muted small">Laatst: {new Date(last).toLocaleString('nl-NL')}</span>}
      </div>
      {msg && <div className={`notice${msg.err ? ' err' : ''}`}>{msg.text}</div>}
    </>
  );
}

function ThemeSection() {
  const [pref, setPref] = useState<ThemePref | null>(null);
  useEffect(() => { void getSetting<ThemePref>('theme', 'system').then(setPref); }, []);
  if (!pref) return null;
  const opts: [ThemePref, string][] = [['system', 'Zoals telefoon'], ['light', 'Licht'], ['dark', 'Donker']];
  return (
    <>
      <h2 style={{ marginTop: 4 }}>Weergave</h2>
      <div className="seg">
        {opts.map(([v, l]) => (
          <button key={v} className={pref === v ? 'active' : ''} onClick={() => { setPref(v); void setThemePref(v); }}>{l}</button>
        ))}
      </div>
    </>
  );
}

function PushupSection() {
  const { goal, setSize, manualSet, auto, lastMax, show } = usePushupSettings();
  const num = (v: string, min: number, max: number) => Math.max(min, Math.min(max, Math.round(Number(v) || 0)));
  return (
    <>
      <h2>Push-ups tussendoor</h2>
      <div className="card">
        <label className="row" style={{ justifyContent: 'space-between' }}>
          <span>Kaart tonen op Vandaag</span>
          <input type="checkbox" checked={show} onChange={e => void setSetting('pushupShow', e.target.checked)} />
        </label>
        <label className="row mt" style={{ justifyContent: 'space-between' }}>
          <span>Dagdoel</span>
          <input type="number" inputMode="numeric" min={10} max={1000} style={{ width: 90 }} defaultValue={goal} key={`g${goal}`}
            onBlur={e => void setSetting('pushupGoal', num(e.target.value, 10, 1000))} aria-label="Dagdoel push-ups" />
        </label>
        <label className="row mt" style={{ justifyContent: 'space-between' }}>
          <span>Grote knop: helft van je laatste maxtest</span>
          <input type="checkbox" checked={auto} onChange={e => void setSetting('pushupSetAuto', e.target.checked)} />
        </label>
        {auto ? (
          <p className="muted small">{lastMax ? `Laatste maxtest: ${lastMax}. De grote knop telt nu ${setSize}.` : `Nog geen maxtest gedaan. Tot die tijd telt de grote knop ${setSize}. De eerste test staat in je eerste testweek.`}</p>
        ) : (
          <label className="row mt" style={{ justifyContent: 'space-between' }}>
            <span>Grote knop telt</span>
            <input type="number" inputMode="numeric" min={1} max={200} style={{ width: 90 }} defaultValue={manualSet} key={`s${manualSet}`}
              onBlur={e => void setSetting('pushupSet', num(e.target.value, 1, 200))} aria-label="Aantal per set" />
          </label>
        )}
        <p className="muted small" style={{ marginBottom: 0 }}>Houd elke set ruim onder je maximum, ongeveer de helft. Dan herstel je snel genoeg om het elke dag te doen. Op je borst-dag en op de testdag sla je ze over.</p>
      </div>
    </>
  );
}

function LockSection() {
  const [cfg, setCfg] = useState(getLock);
  const [bio, setBio] = useState(false);
  const [step, setStep] = useState<null | { first?: string }>(null);
  const [pin, setPin] = useState('');
  const [msg, setMsg] = useState('');
  useEffect(() => {
    void bioAvailable().then(setBio);
  }, []);
  const store = (c: typeof cfg) => {
    setLock(c);
    setCfg(c);
  };

  async function submitPin() {
    if (!/^\d{4,8}$/.test(pin)) return setMsg('Kies 4 tot 8 cijfers.');
    if (!step?.first) {
      setStep({ first: pin });
      setPin('');
      return setMsg('Voer dezelfde pincode nog een keer in.');
    }
    if (step.first !== pin) {
      setStep({});
      setPin('');
      return setMsg('Niet hetzelfde. Begin opnieuw.');
    }
    const { hash, salt } = await makePin(pin);
    store({ ...cfg, on: true, hash, salt, len: pin.length, bio: cfg.bio || bio });
    setStep(null);
    setPin('');
    setMsg('Pincode ingesteld. De app is vanaf nu vergrendeld.');
  }

  return (
    <>
      <h2>Beveiliging</h2>
      <div className="card">
        {cfg.on && cfg.hash ? (
          <>
            <p className="small" style={{ marginTop: 0 }}>De app vraagt om je pincode{cfg.bio ? ' of vingerafdruk' : ''} bij het openen.</p>
            {bio && (
              <label className="row" style={{ justifyContent: 'space-between' }}>
                <span>Vingerafdruk gebruiken</span>
                <input type="checkbox" checked={cfg.bio} onChange={e => store({ ...cfg, bio: e.target.checked })} />
              </label>
            )}
            <label className="row mt" style={{ justifyContent: 'space-between' }}>
              <span>Opnieuw vergrendelen na</span>
              <select value={cfg.afterSec} onChange={e => store({ ...cfg, afterSec: Number(e.target.value) })} style={{ width: 'auto' }}>
                <option value={0}>direct</option>
                <option value={60}>1 minuut</option>
                <option value={300}>5 minuten</option>
                <option value={1800}>30 minuten</option>
              </select>
            </label>
            <div className="row mt">
              <button className="btn secondary small" onClick={() => { setStep({}); setMsg(''); }}>Pincode wijzigen</button>
              <button className="btn secondary small" onClick={() => { if (confirm('Slot uitzetten?')) store({ ...cfg, on: false, hash: '', salt: '' }); }}>Slot uitzetten</button>
            </div>
          </>
        ) : (
          <>
            <p className="small" style={{ marginTop: 0 }}>Zet een pincode op de app{bio ? ', met je vingerafdruk als snelle manier om te openen' : ''}.</p>
            {!step && <button className="btn small" onClick={() => { setStep({}); setMsg(''); }}>Pincode instellen</button>}
          </>
        )}
        {step && (
          <div className="row mt" style={{ flexWrap: 'nowrap' }}>
            <input type="password" inputMode="numeric" autoComplete="off" maxLength={8} value={pin} onChange={e => setPin(e.target.value.replace(/\D/g, ''))}
              onKeyDown={e => e.key === 'Enter' && void submitPin()} placeholder={step.first ? 'Nog een keer' : '4 tot 8 cijfers'} aria-label="Pincode" />
            <button className="btn small" onClick={() => void submitPin()}>{step.first ? 'Bevestig' : 'Verder'}</button>
          </div>
        )}
        {msg && <p className="small" style={{ marginBottom: 0 }}>{msg}</p>}
        <p className="muted small" style={{ marginBottom: 0 }}>Het slot houdt anderen uit de app. Je gegevens op je telefoon zelf worden er niet door versleuteld. De widget blijft werken.</p>
      </div>
    </>
  );
}

const DAY_NAMES = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

function WorkSection() {
  const work = useWork();
  const [place, setPlace] = useState<Place | null>(null);
  const [q, setQ] = useState('');
  const [hits, setHits] = useState<Place[]>([]);
  useEffect(() => {
    void getPlace().then(setPlace);
  }, []);
  const toggleDay = (d: number) => void saveWork({ ...work, days: work.days.includes(d) ? work.days.filter(x => x !== d) : [...work.days, d].sort() });
  async function find() {
    setHits(q.trim() ? await searchPlace(q.trim()) : []);
  }
  async function choose(p: Place) {
    await setSetting('place', p);
    setPlace(p);
    setHits([]);
    setQ('');
  }
  return (
    <>
      <h2>Werk en weer</h2>
      <div className="card">
        <p className="small" style={{ marginTop: 0 }}>Op werkdagen zoekt de app je beste loopmoment buiten je werktijd. Op Vandaag zet je een dag snel om naar vrij of werk. Vakantie, ziek en Defensie tellen vanzelf als vrij.</p>
        <div className="row" style={{ gap: 6 }}>
          {DAY_NAMES.map((n, i) => (
            <button key={n} className={`btn small ${work.days.includes(i + 1) ? '' : 'secondary'}`} onClick={() => toggleDay(i + 1)} aria-pressed={work.days.includes(i + 1)}>{n}</button>
          ))}
        </div>
        <div className="grid2 mt">
          <div><label>Weg vanaf</label><input type="time" value={work.start} onChange={e => void saveWork({ ...work, start: e.target.value })} /></div>
          <div><label>Thuis om</label><input type="time" value={work.end} onChange={e => void saveWork({ ...work, end: e.target.value })} /></div>
        </div>
        <label>Plaats voor het weer</label>
        <div className="row" style={{ flexWrap: 'nowrap' }}>
          <input value={q} onChange={e => setQ(e.target.value)} onKeyDown={e => e.key === 'Enter' && void find()} placeholder={place?.name ?? 'Nijmegen'} aria-label="Plaats zoeken" />
          <button className="btn secondary small" onClick={() => void find()}>Zoek</button>
        </div>
        {hits.map(h => (
          <div key={`${h.lat},${h.lon}`} className="logrow" onClick={() => void choose(h)}><div>{h.name}</div><div className="stats">kies</div></div>
        ))}
        <p className="muted small" style={{ marginBottom: 0 }}>Nu: {place?.name ?? 'Nijmegen'}. Weer van Open-Meteo, gratis en zonder account.</p>
      </div>
    </>
  );
}

function CarSection() {
  const car = useCar();
  const field = (k: keyof CarSettings, label: string, step: string) => (
    <div>
      <label>{label}</label>
      <input inputMode="decimal" defaultValue={String(car[k]).replace('.', ',')} key={`${k}${car[k]}`} step={step}
        onBlur={e => { const v = Number(e.target.value.replace(',', '.')); if (Number.isFinite(v) && v >= 0) void setSetting('car', { ...car, [k]: v }); }} />
    </div>
  );
  return (
    <>
      <h2>Auto (voor wat je bespaart)</h2>
      <div className="card">
        <p className="small" style={{ marginTop: 0 }}>Vink bij een loop of fietsrit "de auto bleef staan" aan. Rijdt de auto toch, bijvoorbeeld met iemand anders, dan bespaar je niets en vink je het niet aan.</p>
        <div className="grid2">
          {field('km', 'Enkele reis (km)', '1')}
          {field('usage', 'Verbruik (l/100 km)', '0.1')}
          {field('price', 'Prijs per liter (€)', '0.01')}
          {field('extraPerKm', 'Onderhoud per km (€)', '0.01')}
        </div>
        <p className="muted small" style={{ marginBottom: 0 }}>Vul de prijs in die je echt betaalt. Onderhoud en slijtage mag op 0 blijven als je alleen brandstof wilt tellen.</p>
      </div>
    </>
  );
}

function TriviaSection() {
  const t = useTrivia();
  const store = (x: TriviaSettings) => void setSetting('trivia', x);
  const toggle = (c: (typeof ALL_CATS)[number]) => {
    const cats = t.cats.includes(c) ? t.cats.filter(x => x !== c) : [...t.cats, c];
    if (cats.length) store({ ...t, cats });
  };
  return (
    <>
      <h2>Rustpauze en trivia</h2>
      <div className="card">
        <label className="row" style={{ justifyContent: 'space-between' }}>
          <span>Triviavraag tijdens de rustpauze</span>
          <input type="checkbox" checked={t.on} onChange={e => store({ ...t, on: e.target.checked })} />
        </label>
        <label className="row mt" style={{ justifyContent: 'space-between' }}>
          <span>Rustpauze</span>
          <select value={t.restSec} onChange={e => store({ ...t, restSec: Number(e.target.value) })} style={{ width: 'auto' }}>
            {[60, 90, 120, 150, 180].map(s => <option key={s} value={s}>{Math.floor(s / 60)}:{String(s % 60).padStart(2, '0')}</option>)}
          </select>
        </label>
        {t.on && (
          <>
            <p className="small" style={{ marginBottom: 6 }}>Onderwerpen</p>
            <div className="row" style={{ gap: 6 }}>
              {ALL_CATS.map(c => (
                <button key={c} className={`btn small ${t.cats.includes(c) ? '' : 'secondary'}`} onClick={() => toggle(c)} aria-pressed={t.cats.includes(c)}>{CATEGORY_NAMES[c]}</button>
              ))}
            </div>
          </>
        )}
        <p className="muted small" style={{ marginTop: 12, marginBottom: 0 }}>Start de rustpauze in het logscherm van je krachttraining. Je telefoon trilt als de pauze voorbij is.</p>
      </div>
    </>
  );
}
