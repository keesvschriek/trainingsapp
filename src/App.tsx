import { lazy, Suspense, useEffect, useState, type ReactNode } from 'react';
import { Today } from './screens/Today';
import { Schedule } from './screens/Schedule';
import { Log } from './screens/Log';
import { Settings } from './screens/Settings';
import { OpvolgScreen } from './screens/Opvolg';
import { Icon } from './ui';
import { currentUser, scheduleSync, sync } from './sync';
import { getIntervalsSettings, importActivities } from './intervals';
import { db, getSetting } from './db';
import { today } from './dates';
import { APK_URL, checkForUpdate } from './native';
import { autoPushToGarmin } from './garmin';
import { scheduleMorning } from './notify';

const QuizHome = lazy(() => import('./quiz/QuizHome').then(m => ({ default: m.QuizHome })));
const Progress = lazy(() => import('./screens/Progress').then(m => ({ default: m.Progress })));

type Route = 'vandaag' | 'schema' | 'logboek' | 'voortgang' | 'quiz' | 'instellingen' | 'opvolgen' | 'meer';
// Vandaag is het hoofdscherm. De rest staat onder Meer.
const TABS: { id: Route; label: string; icon: ReactNode }[] = [
  { id: 'vandaag', label: 'Vandaag', icon: Icon.today },
  { id: 'opvolgen', label: 'Opvolgen', icon: Icon.check },
  { id: 'meer', label: 'Meer', icon: Icon.plan },
];
const MORE: { id: Route; label: string; sub: string; icon: ReactNode }[] = [
  { id: 'schema', label: 'Schema', sub: 'Je trainingsweken en blokken', icon: Icon.plan },
  { id: 'logboek', label: 'Logboek', sub: 'Wat je hebt gedaan', icon: Icon.log },
  { id: 'voortgang', label: 'Voortgang', sub: 'Testen, records en grafieken', icon: Icon.chart },
  { id: 'quiz', label: 'Quiz', sub: 'Leren op je telefoon', icon: Icon.quiz },
  { id: 'instellingen', label: 'Instellingen', sub: 'Sync, Kobo, meldingen, Garmin', icon: Icon.gear },
];
const tabOf = (r: Route): Route => (r === 'vandaag' || r === 'opvolgen' ? r : 'meer');

function More({ go }: { go: (r: Route) => void }) {
  return (
    <div className="card">
      {MORE.map(m => (
        <button key={m.id} className="list-row more-row" onClick={() => go(m.id)}>
          <span className="more-ic">{m.icon}</span>
          <span className="grow"><span>{m.label}</span><br /><span className="muted small">{m.sub}</span></span>
          <span className="muted">{Icon.right}</span>
        </button>
      ))}
    </div>
  );
}

const TITLES: Record<Route, string> = { vandaag: 'Vandaag', schema: 'Schema', logboek: 'Logboek', voortgang: 'Voortgang', quiz: 'Quiz', instellingen: 'Instellingen', opvolgen: 'Opvolgen', meer: 'Meer' };

function readRoute(): Route {
  const r = location.hash.replace('#/', '') as Route;
  return r in TITLES ? r : 'vandaag';
}

export function App() {
  const [route, setRoute] = useState<Route>(readRoute());
  const [syncState, setSyncState] = useState<'off' | 'ok' | 'err'>('off');
  const [update, setUpdate] = useState<number | null>(null);

  useEffect(() => {
    void checkForUpdate().then(setUpdate);
  }, []);

  useEffect(() => {
    const onHash = () => setRoute(readRoute());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  // Synchroniseren bij start, na wijzigingen en als je weer online komt
  useEffect(() => {
    const run = async () => {
      if (!(await currentUser())) return setSyncState('off');
      const r = await sync();
      setSyncState(r.error ? (r.error === 'Offline.' ? 'off' : 'err') : 'ok');
    };
    void run();
    let garminTimer: number | undefined;
    const onChange = () => {
      scheduleSync();
      // Verschuivingen en blokken ook naar Garmin, en meldingen bijwerken
      window.clearTimeout(garminTimer);
      garminTimer = window.setTimeout(() => {
        void autoPushToGarmin();
        void scheduleMorning();
      }, 8000);
    };
    const onOnline = () => void run();
    window.addEventListener('data-changed', onChange);
    window.addEventListener('online', onOnline);
    const iv = window.setInterval(run, 5 * 60 * 1000);
    return () => {
      window.removeEventListener('data-changed', onChange);
      window.removeEventListener('online', onOnline);
      window.clearInterval(iv);
    };
  }, []);

  // Garmin-activiteiten ophalen bij openen, hooguit eens per uur
  useEffect(() => {
    void scheduleMorning();
    void autoPushToGarmin();
    (async () => {
      const s = await getIntervalsSettings();
      if (!s.key || !navigator.onLine) return;
      const last = await getSetting<number>('intervalsLastAuto', 0);
      if (Date.now() - last < 60 * 60 * 1000) return;
      try {
        await importActivities();
        await db.kv.put({ key: 'intervalsLastAuto', value: Date.now() });
      } catch {
        /* stil: de knop in Logboek laat de fout zien */
      }
    })();
  }, []);

  function go(r: Route) {
    location.hash = `#/${r}`;
    window.scrollTo(0, 0);
  }

  return (
    <div className="app">
      <div className="topbar">
        <div className="row" style={{ gap: 4, alignItems: 'center' }}>
          {tabOf(route) === 'meer' && route !== 'meer' && route !== 'instellingen' && (
            <button className="icon-btn" onClick={() => go('meer')} aria-label="Terug">{Icon.left}</button>
          )}
          <h1>{TITLES[route]}</h1>
        </div>
        <div className="right">
          <span className={`sync-dot ${syncState}`} title={syncState === 'ok' ? 'Gesynchroniseerd' : syncState === 'err' ? 'Synchronisatie mislukt' : 'Niet gesynchroniseerd'} />
          <button className="icon-btn" onClick={() => go(route === 'instellingen' ? 'vandaag' : 'instellingen')} aria-label="Instellingen">
            {route === 'instellingen' ? Icon.close : Icon.gear}
          </button>
        </div>
      </div>
      {update && (
        <a className="update-bar" href={APK_URL} target="_blank" rel="noreferrer">
          Nieuwe versie (build {update}) beschikbaar. Tik om te downloaden en installeren.
        </a>
      )}
      <main key={route === 'vandaag' ? `vandaag-${today()}` : route}>
        {route === 'vandaag' && <Today />}
        {route === 'schema' && <Schedule />}
        {route === 'logboek' && <Log />}
        {route === 'voortgang' && <Suspense fallback={<div className="empty">Laden...</div>}><Progress /></Suspense>}
        {route === 'quiz' && <Suspense fallback={<div className="empty">Laden...</div>}><QuizHome /></Suspense>}
        {route === 'instellingen' && <Settings />}
        {route === 'opvolgen' && <OpvolgScreen />}
        {route === 'meer' && <More go={go} />}
      </main>
      <div className="tabbar">
        <nav>
          {TABS.map(t => (
            <button key={t.id} className={tabOf(route) === t.id ? 'active' : ''} onClick={() => go(t.id)}>
              {t.icon}
              <span>{t.label}</span>
            </button>
          ))}
        </nav>
      </div>
    </div>
  );
}
