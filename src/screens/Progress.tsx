import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Bar, CartesianGrid, ComposedChart, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { db, alive, remove, type MetricKind } from '../db';
import { addDays, shortDate, today } from '../dates';
import { GOALS, blockOfWeek, mondayOfWeek, planForWeek, weekOf } from '../plan';
import { METRICS, MetricEditor, formatMetric } from '../editors';
import { useBlocks, useMoves } from '../ui';
import { loadSeries } from '../recovery';
import { cssColor } from '../theme';


export function Progress() {
  const ACCENT = cssColor('--accent');
  const GREY = cssColor('--muted');
  const GRID = cssColor('--line');
  const blocks = useBlocks();
  const moves = useMoves();
  const [add, setAdd] = useState<MetricKind | null>(null);
  const [showAll, setShowAll] = useState<MetricKind | null>(null);

  const curWeek = Math.max(weekOf(today()), 1);
  const lastWeek = curWeek + 1;
  const firstWeek = Math.max(1, lastWeek - 11);

  const runs = useLiveQuery(async () => (await db.workouts.where('kind').equals('run').toArray()).filter(alive), [], []);
  const strength = useLiveQuery(async () => (await db.workouts.where('kind').equals('strength').toArray()).filter(alive), [], []);
  const metrics = useLiveQuery(async () => (await db.metrics.toArray()).filter(alive).filter(m => m.kind !== 'gtg').sort((a, b) => a.date.localeCompare(b.date)), [], []);
  const gtgTotal = useLiveQuery(async () => (await db.metrics.where('kind').equals('gtg').toArray()).filter(alive).reduce((s, m) => s + m.value, 0), [], 0);

  const weekData = [];
  for (let w = firstWeek; w <= lastWeek; w++) {
    const start = mondayOfWeek(w);
    const end = addDays(start, 6);
    const inWeek = runs.filter(r => r.date >= start && r.date <= end);
    const plan = planForWeek(w, blocks, moves).flatMap(d => d.items);
    const plannedMin = plan.filter(i => (i.kind === 'run' || ((i.kind === 'test' || i.kind === 'race') && i.minutes)) && !i.optional).reduce((s, i) => s + (i.minutes ?? 0), 0);
    const plannedLong = Math.max(0, ...plan.filter(i => i.slotId === 'run-long').map(i => i.minutes ?? 0));
    weekData.push({
      week: `w${w}`,
      gelopen: Math.round(inWeek.reduce((s, r) => s + (r.durationMin ?? 0), 0)),
      gepland: plannedMin,
      km: Math.round(inWeek.reduce((s, r) => s + (r.distanceKm ?? 0), 0) * 10) / 10,
      langste: Math.round(Math.max(0, ...inWeek.map(r => r.durationMin ?? 0))),
      langstePlan: plannedLong || null,
      keer: inWeek.length,
      kracht: strength.filter(s => s.date >= start && s.date <= end).length,
    });
  }

  const allWorkouts = [...runs, ...strength];
  const series = loadSeries(allWorkouts, addDays(today(), -42), addDays(today(), 7), today(), blocks, moves);
  const formData = series.map(d => ({
    date: shortDate(d.date),
    fitheid: !d.planned || d.date === addDays(today(), 1) ? Math.round(d.fitness) : null,
    vermoeidheid: !d.planned || d.date === addDays(today(), 1) ? Math.round(d.fatigue) : null,
    fitheidV: d.planned || d.date === today() ? Math.round(d.fitness) : null,
    vermoeidheidV: d.planned || d.date === today() ? Math.round(d.fatigue) : null,
  }));

  const totalKm = runs.filter(r => r.date >= '2026-11-16').reduce((s, r) => s + (r.distanceKm ?? 0), 0);
  const totalHm = runs.filter(r => r.date >= '2026-11-16').reduce((s, r) => s + (r.elevationM ?? 0), 0);
  const latest = (k: MetricKind) => [...metrics].reverse().find(m => m.kind === k);
  const first = (k: MetricKind) => metrics.find(m => m.kind === k);

  // 3 keer lopen per week, laatste 4 afgeronde weken
  const doneWeeks = weekData.filter(d => Number(d.week.slice(1)) < curWeek).slice(-4);
  const freqOk = doneWeeks.filter(d => d.keer >= 3).length;

  return (
    <>
      <div className="stat-grid" style={{ marginTop: 4 }}>
        <div className="stat"><div className="v">{blockOfWeek(curWeek).nr}</div><div className="l">blok ({blockOfWeek(curWeek).name.toLowerCase()})</div></div>
        <div className="stat"><div className="v">{Math.round(totalKm)}</div><div className="l">km sinds de start</div></div>
        <div className="stat"><div className="v">{Math.round(totalHm)}</div><div className="l">hoogtemeters</div></div>
      </div>

      <h2>Looptijd per week</h2>
      <p className="muted small">Balken: gelopen minuten. Lijn: gepland.</p>
      <div className="chart">
        <ResponsiveContainer>
          <ComposedChart data={weekData} margin={{ top: 8, right: 12, left: -18, bottom: 0 }}>
            <CartesianGrid stroke={GRID} vertical={false} />
            <XAxis dataKey="week" tick={{ fontSize: 11 }} tickLine={false} axisLine={{ stroke: GRID }} />
            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip formatter={(v, n) => [`${v} min`, n === 'gelopen' ? 'Gelopen' : 'Gepland']} />
            <Bar isAnimationActive={false} dataKey="gelopen" fill={ACCENT} radius={[3, 3, 0, 0]} maxBarSize={22} />
            <Line isAnimationActive={false} dataKey="gepland" stroke={GREY} strokeWidth={2} dot={{ r: 2 }} />
          </ComposedChart>
        </ResponsiveContainer>
      </div>

      <h2>Langste loop per week</h2>
      <div className="chart">
        <ResponsiveContainer>
          <ComposedChart data={weekData} margin={{ top: 8, right: 12, left: -18, bottom: 0 }}>
            <CartesianGrid stroke={GRID} vertical={false} />
            <XAxis dataKey="week" tick={{ fontSize: 11 }} tickLine={false} axisLine={{ stroke: GRID }} />
            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip formatter={(v, n) => [`${v} min`, n === 'langste' ? 'Gelopen' : 'Gepland']} />
            <Bar isAnimationActive={false} dataKey="langste" fill={ACCENT} radius={[3, 3, 0, 0]} maxBarSize={22} />
            <Line isAnimationActive={false} dataKey="langstePlan" stroke={GREY} strokeWidth={2} dot={{ r: 2 }} connectNulls />
          </ComposedChart>
        </ResponsiveContainer>
      </div>

      <h2>Fitheid en vermoeidheid</h2>
      <p className="muted small">Blauw: fitheid (6 weken). Grijs: vermoeidheid (1 week). Stippellijn: verwachting voor de komende 7 dagen volgens je schema. Ligt grijs ver boven blauw, dan ben je vermoeid.</p>
      <div className="chart">
        <ResponsiveContainer>
          <LineChart data={formData} margin={{ top: 8, right: 12, left: -18, bottom: 0 }}>
            <CartesianGrid stroke={GRID} vertical={false} />
            <XAxis dataKey="date" tick={{ fontSize: 11 }} tickLine={false} axisLine={{ stroke: GRID }} interval={6} />
            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip />
            <Line isAnimationActive={false} dataKey="fitheid" stroke={ACCENT} strokeWidth={2} dot={false} connectNulls />
            <Line isAnimationActive={false} dataKey="vermoeidheid" stroke={GREY} strokeWidth={2} dot={false} connectNulls />
            <Line isAnimationActive={false} dataKey="fitheidV" name="fitheid (verwacht)" stroke={ACCENT} strokeWidth={2} strokeDasharray="4 4" dot={false} connectNulls />
            <Line isAnimationActive={false} dataKey="vermoeidheidV" name="vermoeidheid (verwacht)" stroke={GREY} strokeWidth={2} strokeDasharray="4 4" dot={false} connectNulls />
          </LineChart>
        </ResponsiveContainer>
      </div>

      <h2>Doelen</h2>
      <div className="card">
        {GOALS.map(g => {
          const m = latest(g.metric);
          const f = first(g.metric);
          let status = 'Nog geen meting. Wordt gemeten in de testweek.';
          let pct = 0;
          if (m) {
            status = `Laatste meting: ${formatMetric(g.metric, m.value)} (${shortDate(m.date)})`;
            if (f && f.id !== m.id) {
              const diff = m.value - f.value;
              const better = g.lowerIsBetter ? diff < 0 : diff > 0;
              status += `, ${better ? 'beter' : diff === 0 ? 'gelijk' : 'minder'} dan de eerste (${formatMetric(g.metric, f.value)})`;
            }
            if (g.target) {
              if (g.lowerIsBetter) {
                const from = Math.max(f?.value ?? m.value, g.target + 1);
                pct = m.value <= g.target ? 1 : Math.max(0, (from - m.value) / (from - g.target));
              } else {
                pct = Math.min(1, Math.max(0, (m.value - 2400) / (g.target - 2400)));
              }
            }
          }
          const w = g.id === 'build' ? latest('weight') : undefined;
          return (
            <div key={g.id} style={{ padding: '8px 0' }}>
              <strong>{g.title}</strong>
              <div className="muted small" style={{ margin: '2px 0 6px' }}>
                {status}{w ? `. Gewicht: ${formatMetric('weight', w.value)}` : ''}
              </div>
              {g.target && <div className="progress"><div style={{ width: `${Math.round(pct * 100)}%` }} /></div>}
            </div>
          );
        })}
        <div style={{ padding: '8px 0' }}>
          <strong>Elke week 3 keer lopen</strong>
          <div className="muted small">{doneWeeks.length ? `${freqOk} van de laatste ${doneWeeks.length} weken gehaald` : 'Nog geen volle week'}</div>
        </div>
      </div>

      <h2>Metingen</h2>
      {METRICS.map(mt => {
        const data = metrics.filter(m => m.kind === mt.kind).map(m => ({ date: shortDate(m.date), value: mt.time ? Math.round(m.value / 6) / 10 : m.value, id: m.id }));
        return (
          <div className="card" key={mt.kind}>
            <div className="spread">
              <div>
                <strong>{mt.label}</strong>
                <div className="muted small">{data.length ? formatMetric(mt.kind, metrics.filter(m => m.kind === mt.kind).slice(-1)[0].value) : mt.help}</div>
              </div>
              <button className="btn secondary small" onClick={() => setAdd(mt.kind)}>Meting</button>
            </div>
            {data.length >= 2 && (
              <div className="chart" style={{ height: 150 }}>
                <ResponsiveContainer>
                  <LineChart data={data} margin={{ top: 8, right: 12, left: -18, bottom: 0 }}>
                    <CartesianGrid stroke={GRID} vertical={false} />
                    <XAxis dataKey="date" tick={{ fontSize: 11 }} tickLine={false} axisLine={{ stroke: GRID }} />
                    <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} domain={['auto', 'auto']} />
                    <Tooltip formatter={v => [mt.time ? `${v} min` : `${v} ${mt.unit}`, mt.label]} />
                    <Line isAnimationActive={false} dataKey="value" stroke={ACCENT} strokeWidth={2} dot={{ r: 3 }} />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}
            {data.length > 0 && <button className="btn ghost small" onClick={() => setShowAll(showAll === mt.kind ? null : mt.kind)}>{showAll === mt.kind ? 'Verbergen' : 'Alle metingen'}</button>}
            {showAll === mt.kind && (
              <table>
                <tbody>
                  {[...metrics.filter(m => m.kind === mt.kind)].reverse().map(m => (
                    <tr key={m.id}>
                      <td>{shortDate(m.date)}</td>
                      <td>{formatMetric(mt.kind, m.value)}</td>
                      <td style={{ textAlign: 'right' }}><button className="btn ghost small" onClick={() => confirm('Meting verwijderen?') && remove('metrics', m.id)}>verwijder</button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        );
      })}

      <p className="muted small">Pull-ups tussendoor sinds de start: {gtgTotal}.</p>

      {add && <MetricEditor kind={add} onClose={() => setAdd(null)} />}
    </>
  );
}
