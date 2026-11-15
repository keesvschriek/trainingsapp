import { useEffect, useState } from 'react';
import { allCatKeys, buildQuiz, countsByCat, pickQuestions, THEMES, wrongQuestions, getMemory } from './engine';
import { geoSet, type GeoKind, type MathKind } from './gen';
import { REGIONS, type Region } from './geo/countries';
import { LISTS, type ListQuiz } from './lists';
import { CATS, GROUPS, type MC } from './model';
import { dayStreak, level, useRecords, useStats, xpForLevel } from './records';
import { ListRun, MapRun, MATH_NAMES, MathRun, MCRun, Result, type Done } from './Runs';
import { UpdateSection } from './UpdateSection';

type Play =
  | { kind: 'mc'; title: string; recKey: string; make: () => Promise<MC[]> }
  | { kind: 'math'; mk: MathKind }
  | { kind: 'list'; list: ListQuiz }
  | { kind: 'map'; region?: Region };

const GEO_MODES: { key: string; name: string; kinds: GeoKind[] }[] = [
  { key: 'flag', name: 'Vlaggen', kinds: ['flag'] },
  { key: 'capital', name: 'Hoofdsteden', kinds: ['capital'] },
  { key: 'capital2', name: 'Land bij hoofdstad', kinds: ['countryOfCapital'] },
  { key: 'highlight', name: 'Welk land is dit?', kinds: ['highlight'] },
  { key: 'mixed', name: 'Gemengd', kinds: ['flag', 'capital', 'countryOfCapital', 'highlight', 'borders', 'area', 'landlocked'] },
];

export function QuizHome() {
  const [play, setPlay] = useState<Play | null>(null);
  const [qs, setQs] = useState<MC[] | null>(null);
  const [done, setDone] = useState<Done | null>(null);
  const [run, setRun] = useState(0); // telt op om opnieuw te starten
  const [region, setRegion] = useState<Region | 'Wereld'>('Europa');
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [wrongCount, setWrongCount] = useState(0);
  const [size, setSize] = useState(10);
  const recs = useRecords();
  const stats = useStats();

  useEffect(() => {
    if (play) return;
    void countsByCat().then(setCounts);
    void getMemory().then(m => setWrongCount(m.wrong.length));
  }, [play, run]);

  useEffect(() => {
    if (play?.kind !== 'mc') return;
    setQs(null);
    void play.make().then(setQs);
  }, [play, run]);

  function start(p: Play) {
    setDone(null);
    setPlay(p);
    setRun(r => r + 1);
    window.scrollTo(0, 0);
  }
  const close = () => { setPlay(null); setDone(null); };
  const again = () => { setDone(null); setRun(r => r + 1); };
  const reg = region === 'Wereld' ? undefined : region;
  const rec = (k: string) => recs[k] ? `Record ${recs[k].best} ${recs[k].unit}` : 'Nog niet gespeeld';

  if (play) {
    if (done) return <Result r={done} onAgain={again} onClose={close} />;
    return (
      <div key={run}>
        {play.kind === 'mc' && (qs ? <MCRun title={play.title} recKey={play.recKey} questions={qs} onDone={setDone} onClose={close} /> : <div className="empty">Vragen kiezen...</div>)}
        {play.kind === 'math' && <MathRun kind={play.mk} onDone={setDone} onClose={close} />}
        {play.kind === 'list' && <ListRun list={play.list} onDone={setDone} onClose={close} />}
        {play.kind === 'map' && <MapRun region={play.region} onDone={setDone} onClose={close} />}
      </div>
    );
  }

  const lv = level(stats.xp);
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  const pct = stats.answered ? Math.round((stats.correct / stats.answered) * 100) : 0;
  const listGroups = [...new Set(LISTS.map(l => l.group))];

  return (
    <div>
      <div className="stat-grid">
        <div className="stat"><div className="v">{lv}</div><div className="l">niveau · {stats.xp - xpForLevel(lv)}/{xpForLevel(lv + 1) - xpForLevel(lv)} xp</div></div>
        <div className="stat"><div className="v">{dayStreak(stats.days)}</div><div className="l">dagen op rij</div></div>
        <div className="stat"><div className="v">{pct}%</div><div className="l">goed van {stats.answered}</div></div>
      </div>

      <h2 className="section-title">Snel</h2>
      <div className="quiz-tiles">
        <button className="tile" onClick={() => start({ kind: 'mc', title: 'Snelle mix', recKey: `mix:${size}`, make: () => pickQuestions(allCatKeys(), size) })}>
          <strong>Snelle mix</strong><span>{size} vragen uit alles · {rec(`mix:${size}`)}</span>
        </button>
        <button className="tile" onClick={() => start({ kind: 'math', mk: 'mix' })}>
          <strong>Rekensprint</strong><span>60 seconden · {rec('math:mix')}</span>
        </button>
        {wrongCount > 0 && (
          <button className="tile" onClick={() => start({ kind: 'mc', title: 'Fouten herhalen', recKey: 'wrong', make: () => wrongQuestions(size) })}>
            <strong>Fouten herhalen</strong><span>{wrongCount} vragen die je fout had</span>
          </button>
        )}
      </div>
      <div className="seg" role="group" aria-label="Aantal vragen">
        {[10, 20, 30].map(n => <button key={n} className={size === n ? 'active' : ''} onClick={() => setSize(n)}>{n} vragen</button>)}
      </div>

      <h2 className="section-title">Quiz samenstellen</h2>
      <div className="card">
        {THEMES.map(t => (
          <button key={t.key} className="list-row" onClick={() => start({ kind: 'mc', title: t.name, recKey: `theme:${t.key}:${size}`, make: () => buildQuiz(t.cats, t.geo, size, t.geo ? reg : undefined) })}>
            <span>{t.name}</span><span className="muted small">{rec(`theme:${t.key}:${size}`)}</span>
          </button>
        ))}
      </div>

      <h2 className="section-title">Topografie</h2>
      <div className="seg seg-wrap" role="group" aria-label="Gebied">
        {(['Wereld', ...REGIONS] as const).map(r => <button key={r} className={region === r ? 'active' : ''} onClick={() => setRegion(r)}>{r}</button>)}
      </div>
      <div className="quiz-tiles">
        <button className="tile" onClick={() => start({ kind: 'map', region: reg })}>
          <strong>Aanwijzen op de kaart</strong><span>{rec(`map:${region}`)}</span>
        </button>
        {GEO_MODES.map(m => (
          <button key={m.key} className="tile" onClick={() => start({ kind: 'mc', title: `${m.name}: ${region}`, recKey: `geo:${m.key}:${region}`, make: async () => geoSet(m.kinds, size, reg) })}>
            <strong>{m.name}</strong><span>{rec(`geo:${m.key}:${region}`)}</span>
          </button>
        ))}
      </div>

      <h2 className="section-title">Lijstjes</h2>
      {listGroups.map(g => (
        <div className="card" key={g}>
          <div className="muted small" style={{ marginBottom: 4 }}>{g}</div>
          {LISTS.filter(l => l.group === g).map(l => (
            <button key={l.key} className="list-row" onClick={() => start({ kind: 'list', list: l })}>
              <span>{l.title}</span><span className="muted small">{recs[`list:${l.key}`] ? `${recs[`list:${l.key}`].best}/${l.items.length}` : `${l.items.length} · ${Math.round(l.seconds / 60 * 10) / 10} min`}</span>
            </button>
          ))}
        </div>
      ))}

      <h2 className="section-title">Rekenen</h2>
      <div className="card">
        {(Object.keys(MATH_NAMES) as MathKind[]).map(k => (
          <button key={k} className="list-row" onClick={() => start({ kind: 'math', mk: k })}>
            <span>{MATH_NAMES[k]}</span><span className="muted small">{rec(`math:${k}`)}</span>
          </button>
        ))}
      </div>

      <h2 className="section-title">Per categorie</h2>
      {GROUPS.map(g => (
        <div className="card" key={g}>
          <div className="muted small" style={{ marginBottom: 4 }}>{g}</div>
          {CATS.filter(c => c.group === g && counts[c.key]).map(c => (
            <button key={c.key} className="list-row" onClick={() => start({ kind: 'mc', title: c.name, recKey: `cat:${c.key}:${size}`, make: () => pickQuestions([c.key], size) })}>
              <span>{c.name}</span><span className="muted small">{counts[c.key]} vragen</span>
            </button>
          ))}
        </div>
      ))}
      <p className="muted small">In totaal {total} vaste vragen, plus onbeperkt gegenereerde topografie- en rekenvragen.</p>

      <UpdateSection onChange={() => setRun(r => r + 1)} />
    </div>
  );
}
