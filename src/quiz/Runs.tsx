import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react';
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';
import { isNative } from '../native';
import { remember } from './engine';
import { sum, sumMatches, type MathKind, type Sum } from './gen';
import { COUNTRIES, byC3, matches, type Region } from './geo/countries';
import { mapPool } from './gen';
import type { ListQuiz } from './lists';
import { catName, shuffle, type MC } from './model';
import { removeQuestion } from './packs';
import { saveResult } from './records';

const MapView = lazy(() => import('./MapView').then(m => ({ default: m.MapView })));
const buzz = (ok: boolean) => {
  if (!isNative) return;
  void (ok ? Haptics.impact({ style: ImpactStyle.Light }) : Haptics.notification({ type: NotificationType.Error })).catch(() => undefined);
};
const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.max(0, s) % 60).padStart(2, '0')}`;

function useCountdown(seconds: number, running: boolean) {
  const [left, setLeft] = useState(seconds);
  useEffect(() => {
    if (!running || left <= 0) return;
    const id = window.setTimeout(() => setLeft(l => l - 1), 1000);
    return () => window.clearTimeout(id);
  }, [left, running]);
  return [left, setLeft] as const;
}

export interface Done { title: string; score: number; unit: string; detail: string; record: boolean; previous?: number }

export function Result({ r, onAgain, onClose }: { r: Done; onAgain: () => void; onClose: () => void }) {
  return (
    <div className="card quiz-result">
      <div className="muted small">{r.title}</div>
      <div className="quiz-score">{r.score}<span className="muted"> {r.unit}</span></div>
      <p style={{ margin: '4px 0 12px' }}>{r.record ? `Nieuw record. Vorige: ${r.previous} ${r.unit}.` : r.previous !== undefined ? `Record: ${Math.max(r.previous, r.score)} ${r.unit}.` : 'Eerste keer: dit is je record.'} {r.detail}</p>
      <div className="row">
        <button className="btn" onClick={onAgain}>Nog een keer</button>
        <button className="btn secondary" onClick={onClose}>Terug</button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Meerkeuze: 100 punten per goed antwoord, tot 50 extra als je snel bent.
// ---------------------------------------------------------------------------

export function MCRun({ title, recKey, questions, onDone, onClose }: { title: string; recKey: string; questions: MC[]; onDone: (d: Done) => void; onClose: () => void }) {
  const [i, setI] = useState(0);
  const [answer, setAnswer] = useState<number | null>(null);
  const [points, setPoints] = useState(0);
  const [right, setRight] = useState(0);
  const [streak, setStreak] = useState(0);
  const [best, setBest] = useState(0);
  const [hidden, setHidden] = useState(false);
  const started = useRef(Date.now());
  const q = questions[i];
  const order = useMemo(() => (q ? shuffle(q.a.map((_, k) => k)) : []), [q]);

  useEffect(() => { started.current = Date.now(); }, [i]);

  if (!q) return <div className="empty">Geen vragen gevonden in deze selectie.</div>;

  function choose(k: number) {
    if (answer !== null) return;
    const ok = order[k] === 0;
    const secs = (Date.now() - started.current) / 1000;
    const bonus = ok ? Math.max(0, Math.round(50 - Math.max(0, secs - 3) * 5)) : 0;
    setAnswer(k);
    buzz(ok);
    setPoints(p => p + (ok ? 100 + bonus : 0));
    if (ok) {
      setRight(r => r + 1);
      setStreak(s => { setBest(b => Math.max(b, s + 1)); return s + 1; });
    } else setStreak(0);
    void remember(q.id, ok);
  }

  async function next() {
    setHidden(false);
    if (i + 1 < questions.length) {
      setI(i + 1);
      setAnswer(null);
      return;
    }
    const xp = right * 10;
    const r = await saveResult(recKey, points, 'punten', questions.length, right, xp);
    onDone({ title, score: points, unit: 'punten', detail: `${right} van ${questions.length} goed${best > 2 ? `, ${best} op rij` : ''}.`, ...r });
  }

  const correctIdx = order.indexOf(0);
  return (
    <div>
      <div className="quiz-bar">
        <span>{i + 1}/{questions.length}</span>
        <span>{points} punten{streak > 1 ? ` · ${streak} op rij` : ''}</span>
        <button className="btn ghost small" onClick={onClose}>Stoppen</button>
      </div>
      <div className="quiz-prog"><div style={{ width: `${(i / questions.length) * 100}%` }} /></div>
      <div className="card">
        <div className="muted small">{catName(q.cat)}{q.asOf ? ` · stand ${q.asOf}` : ''}{q.src === 'ai' ? ' · door AI gemaakt' : q.src === 'pack' ? ' · uit pakket' : ''}</div>
        {q.big && <div className="quiz-big">{q.big}</div>}
        {q.map && (
          <Suspense fallback={<div className="empty">Kaart laden...</div>}>
            <MapView focus={q.map} marks={{ [q.map]: 'target' }} height={210} />
          </Suspense>
        )}
        <div className="quiz-q">{q.q}</div>
        <div className="quiz-opts">
          {order.map((k, j) => {
            const cls = answer === null ? '' : j === correctIdx ? ' right' : j === answer ? ' wrong' : ' dim';
            return <button key={q.a[k]} className={`quiz-opt${cls}`} onClick={() => choose(j)} disabled={answer !== null}>{q.a[k]}</button>;
          })}
        </div>
        {answer !== null && (
          <>
            <p className="small" style={{ margin: '10px 0' }}>
              <strong>{answer === correctIdx ? 'Goed.' : `Het was: ${q.a[0]}.`}</strong> {q.why}
            </p>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <button className="btn" onClick={() => void next()}>{i + 1 < questions.length ? 'Volgende' : 'Uitslag'}</button>
              {!q.id.startsWith('gen-') && !hidden && (
                <button className="btn ghost small" onClick={() => { void removeQuestion(q.id); setHidden(true); }}>Klopt niet, verbergen</button>
              )}
              {hidden && <span className="muted small">Verborgen.</span>}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Rekensprint: 60 seconden, typ het antwoord. Goed is meteen door.
// ---------------------------------------------------------------------------

export const MATH_NAMES: Record<MathKind, string> = { mix: 'Hoofdrekenen gemengd', tafels: 'Tafels tot 15', procent: 'Procenten', tempo: 'Tempo en snelheid', kwadraat: 'Kwadraten en wortels' };

export function MathRun({ kind, onDone, onClose }: { kind: MathKind; onDone: (d: Done) => void; onClose: () => void }) {
  const SECS = kind === 'tempo' ? 90 : 60;
  const [s, setS] = useState<Sum>(() => sum(kind));
  const [val, setVal] = useState('');
  const [right, setRight] = useState(0);
  const [skipped, setSkipped] = useState<Sum[]>([]);
  const [left] = useCountdown(SECS, true);
  const [flash, setFlash] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const done = useRef(false);

  useEffect(() => {
    if (left > 0 || done.current) return;
    done.current = true;
    void saveResult(`math:${kind}`, right, 'goed', right + skipped.length, right, right * 5).then(r =>
      onDone({ title: MATH_NAMES[kind], score: right, unit: 'goed', detail: skipped.length ? `Overgeslagen: ${skipped.slice(-3).map(x => `${x.q} = ${x.answers[0]}`).join(', ')}.` : '', ...r }),
    );
  }, [left, right, skipped, kind, onDone]);

  function change(v: string) {
    setVal(v);
    if (sumMatches(v, s)) {
      setRight(r => r + 1);
      setS(sum(kind));
      setVal('');
      setFlash(true);
      window.setTimeout(() => setFlash(false), 180);
      buzz(true);
    }
  }
  function skip() {
    setSkipped(x => [...x, s]);
    setS(sum(kind));
    setVal('');
    input.current?.focus();
  }

  const needsText = kind === 'tempo';
  return (
    <div>
      <div className="quiz-bar">
        <span className={left <= 10 ? 'bad' : ''}>{mmss(left)}</span>
        <span>{right} goed</span>
        <button className="btn ghost small" onClick={onClose}>Stoppen</button>
      </div>
      <div className={`card math${flash ? ' flash' : ''}`}>
        <div className="math-q">{s.q}</div>
        <input
          ref={input}
          className="math-in"
          inputMode={needsText ? 'text' : 'decimal'}
          autoFocus
          value={val}
          placeholder={s.hint ?? 'antwoord'}
          onChange={e => change(e.target.value)}
          aria-label="Antwoord"
        />
        <button className="btn secondary small" onClick={skip} style={{ marginTop: 10 }}>Overslaan</button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Lijstjes: noem er zo veel mogelijk binnen de tijd.
// ---------------------------------------------------------------------------

export function ListRun({ list, onDone, onClose }: { list: ListQuiz; onDone: (d: Done) => void; onClose: () => void }) {
  const [found, setFound] = useState<Set<number>>(new Set());
  const [val, setVal] = useState('');
  const [over, setOver] = useState(false);
  const [left] = useCountdown(list.seconds, !over);
  const [last, setLast] = useState('');
  const saved = useRef(false);
  const total = list.items.length;

  function change(v: string) {
    setVal(v);
    const hit = list.items.findIndex((it, i) => !found.has(i) && matches(v, it.answers));
    if (hit >= 0) {
      const f = new Set(found);
      f.add(hit);
      setFound(f);
      setVal('');
      setLast(list.items[hit].show);
      buzz(true);
      if (f.size === total) finish(f);
    }
  }

  function finish(f = found) {
    if (saved.current) return;
    saved.current = true;
    setOver(true);
    const pct = Math.round((f.size / total) * 100);
    void saveResult(`list:${list.key}`, f.size, `van ${total}`, total, f.size, f.size * 5).then(r =>
      onDone({
        title: list.title,
        score: f.size,
        unit: `van ${total}`,
        detail: `${pct}%${f.size === total ? `, met ${mmss(left)} over` : ''}.${f.size < total ? ` Gemist: ${list.items.filter((_, i) => !f.has(i)).map(it => (it.hint && it.hint !== it.show ? `${it.hint} (${it.show})` : it.show)).join(', ')}.` : ''}`,
        ...r,
      }),
    );
  }

  useEffect(() => { if (left <= 0 && !over) finish(); });

  return (
    <div>
      <div className="quiz-bar">
        <span className={left <= 15 ? 'bad' : ''}>{mmss(left)}</span>
        <span>{found.size}/{total}</span>
        <button className="btn ghost small" onClick={() => finish()}>Opgeven</button>
      </div>
      <div className="card">
        <div className="quiz-q" style={{ marginTop: 0 }}>{list.title}</div>
        {list.note && <p className="muted small" style={{ marginTop: -4 }}>{list.note}</p>}
        <input className="math-in" value={val} onChange={e => change(e.target.value)} placeholder="Typ een antwoord" autoFocus autoCapitalize="words" autoCorrect="off" spellCheck={false} aria-label="Antwoord" />
        <div className="muted small" style={{ minHeight: 20, marginTop: 6 }}>{last && `Goed: ${last}`}</div>
      </div>
      <div className={`list-grid${list.items.some(i => i.hint) ? ' hinted' : ''}`}>
        {list.items.map((it, i) => (
          <div key={i} className={`list-cell${found.has(i) ? ' got' : over ? ' miss' : ''}`}>
            {it.hint && <span className="muted">{it.hint} </span>}
            <span>{found.has(i) || over ? it.show : ''}</span>
          </div>
        ))}
      </div>
      <button className="btn secondary small" onClick={onClose} style={{ marginTop: 12 }}>Terug</button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Aanwijzen op de kaart: tik het gevraagde land aan.
// ---------------------------------------------------------------------------

export function MapRun({ region, rounds = 15, onDone, onClose }: { region?: Region; rounds?: number; onDone: (d: Done) => void; onClose: () => void }) {
  const pool = useMemo(() => mapPool(region), [region]);
  const targets = useMemo(() => shuffle(pool).slice(0, rounds), [pool, rounds]);
  const clickable = useMemo(() => new Set(pool.map(c => c.c3)), [pool]);
  const [i, setI] = useState(0);
  const [tries, setTries] = useState(0);
  const [marks, setMarks] = useState<Record<string, 'target' | 'right' | 'wrong' | 'dim'>>({});
  const [points, setPoints] = useState(0);
  const [right, setRight] = useState(0);
  const [msg, setMsg] = useState('');
  const t = targets[i];
  const name = region ? region : 'de wereld';

  function pickC(c3: string) {
    if (!t || marks[t.c3] === 'right' || marks[t.c3] === 'target') return;
    if (c3 === t.c3) {
      const p = tries === 0 ? 100 : tries === 1 ? 50 : 20;
      setPoints(x => x + p);
      if (tries === 0) setRight(r => r + 1);
      setMarks(m => ({ ...m, [c3]: 'right' }));
      setMsg(tries === 0 ? 'Goed.' : 'Goed, in de herkansing.');
      buzz(true);
      window.setTimeout(advance, 700);
    } else {
      const nt = tries + 1;
      setTries(nt);
      buzz(false);
      setMarks(m => ({ ...m, [c3]: 'wrong' }));
      setMsg(`Dat is ${byC3.get(c3)?.name}.`);
      if (nt >= 3) {
        setMarks(m => ({ ...m, [t.c3]: 'target' }));
        setMsg(`Hier ligt ${t.name}.`);
        window.setTimeout(advance, 1600);
      }
    }
  }

  function advance() {
    setTries(0);
    setMarks({});
    setMsg('');
    setI(x => x + 1);
  }

  useEffect(() => {
    if (t || !targets.length) return;
    void saveResult(`map:${region ?? 'Wereld'}`, points, 'punten', targets.length, right, right * 10).then(r =>
      onDone({ title: `Aanwijzen: ${region ?? 'Wereld'}`, score: points, unit: 'punten', detail: `${right} van ${targets.length} in een keer goed.`, ...r }),
    );
  }, [t]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!t) return <div className="empty">Uitslag opslaan...</div>;
  return (
    <div>
      <div className="quiz-bar">
        <span>{i + 1}/{targets.length}</span>
        <span>{points} punten</span>
        <button className="btn ghost small" onClick={onClose}>Stoppen</button>
      </div>
      <div className="map-ask">Tik aan: <strong>{t.name}</strong> <span className="muted small">in {name}</span></div>
      <Suspense fallback={<div className="empty">Kaart laden...</div>}>
        <MapView region={region} clickable={clickable} marks={marks} onPick={pickC} height={!region ? 190 : region === 'Europa' ? 400 : 320} />
      </Suspense>
      <div className="small" style={{ minHeight: 22, marginTop: 6 }}>{msg || (tries ? `Nog ${3 - tries} poging${3 - tries === 1 ? '' : 'en'}.` : '')}</div>
    </div>
  );
}

export const COUNTRY_COUNT = COUNTRIES.length;
