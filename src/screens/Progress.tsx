import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Bar, CartesianGrid, ComposedChart, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { db, alive, newId, remove, save, type Metric, type MetricKind } from '../db';
import { addDays, diffDays, shortDate, today, type ISODate } from '../dates';
import { GOALS, RACE_DATE, TOTAL_WEEKS, mondayOfWeek, planForWeek, weekOf } from '../plan';
import { Sheet, useBlocks, num, fmt } from '../ui';

const ACCENT = '#1f4e79';
const GREY = '#9aa5b1';

const METRICS: { kind: MetricKind; label: string; unit: string; help: string }[] = [
  { kind: 'pullupMax', label: 'Strikte pull-ups (max)', unit: 'herh.', help: 'Elke eerste maandag van de maand, uitgerust.' },
  { kind: 'cooper', label: 'Cooper-test', unit: 'm', help: 'Zoveel mogelijk meters in 12 minuten.' },
  { kind: 'pressReps', label: 'Press 28 kg (per arm)', unit: 'herh.', help: 'Strikte press met 28 kg, zwakste arm telt.' },
  { kind: 'weight', label: 'Gewicht', unit: 'kg', help: 'Zelfde moment van de dag, bijv. zaterdag na het opstaan.' },
];

export function Progress() {
  const blocks = useBlocks();
  const [add, setAdd] = useState<MetricKind | null>(null);
  const [showAll, setShowAll] = useState<MetricKind | null>(null);

  const curWeek = Math.min(Math.max(weekOf(today()), 1), TOTAL_WEEKS);
  const lastWeek = Math.min(curWeek + 1, TOTAL_WEEKS);
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
    const plan = planForWeek(w, blocks).flatMap(d => d.items);
    const plannedMin = plan.filter(i => (i.kind === 'run' || i.kind === 'race') && !i.optional).reduce((s, i) => s + (i.minutes ?? 0), 0);
    const plannedLong = Math.max(0, ...plan.filter(i => i.slotId === 'run-long' || i.kind === 'race').map(i => i.minutes ?? 0));
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

  const totalKm = runs.filter(r => r.date >= '2026-11-16').reduce((s, r) => s + (r.distanceKm ?? 0), 0);
  const totalHm = runs.filter(r => r.date >= '2026-11-16').reduce((s, r) => s + (r.elevationM ?? 0), 0);
  const daysToRace = diffDays(RACE_DATE, today());
  const latest = (k: MetricKind) => [...metrics].reverse().find(m => m.kind === k);

  // Week-doel: 3 keer lopen, laatste 4 afgeronde weken
  const doneWeeks = weekData.filter(d => Number(d.week.slice(1)) < curWeek).slice(-4);
  const freqOk = doneWeeks.filter(d => d.keer >= 3).length;

  return (
    <>
      <div className="stat-grid" style={{ marginTop: 4 }}>
        <div className="stat"><div className="v">{daysToRace > 0 ? daysToRace : 0}</div><div className="l">dagen tot de 50 km</div></div>
        <div className="stat"><div className="v">{Math.round(totalKm)}</div><div className="l">km sinds de start</div></div>
        <div className="stat"><div className="v">{Math.round(totalHm)}</div><div className="l">hoogtemeters</div></div>
      </div>

      <h2>Looptijd per week</h2>
      <p className="muted small">Balken: gelopen minuten. Lijn: gepland.</p>
      <div className="chart">
        <ResponsiveContainer>
          <ComposedChart data={weekData} margin={{ top: 8, right: 12, left: -18, bottom: 0 }}>
            <CartesianGrid stroke="#eef1f4" vertical={false} />
            <XAxis dataKey="week" tick={{ fontSize: 11 }} tickLine={false} axisLine={{ stroke: '#d8dee6' }} />
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
            <CartesianGrid stroke="#eef1f4" vertical={false} />
            <XAxis dataKey="week" tick={{ fontSize: 11 }} tickLine={false} axisLine={{ stroke: '#d8dee6' }} />
            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip formatter={(v, n) => [`${v} min`, n === 'langste' ? 'Gelopen' : 'Gepland']} />
            <Bar isAnimationActive={false} dataKey="langste" fill={ACCENT} radius={[3, 3, 0, 0]} maxBarSize={22} />
            <Line isAnimationActive={false} dataKey="langstePlan" stroke={GREY} strokeWidth={2} dot={{ r: 2 }} connectNulls />
          </ComposedChart>
        </ResponsiveContainer>
      </div>

      <h2>Doelen</h2>
      <div className="card">
        {GOALS.map(g => {
          const m = g.metric ? latest(g.metric) : undefined;
          let status = '';
          let pct = 0;
          if (g.id === 'freq') {
            status = doneWeeks.length ? `${freqOk} van de laatste ${doneWeeks.length} weken 3 keer gelopen` : 'Nog geen volle week';
            pct = doneWeeks.length ? freqOk / doneWeeks.length : 0;
          } else if (g.id === 'race') {
            status = `${shortDate(g.deadline)} 2027`;
            pct = Math.min(1, Math.max(0, diffDays(today(), '2026-11-16') / diffDays(RACE_DATE, '2026-11-16')));
          } else if (g.metric && g.target) {
            status = m ? `Laatste meting: ${fmt.n1(m.value)} ${g.unit} (${shortDate(m.date)})` : 'Nog geen meting';
            pct = m ? Math.min(1, m.value / g.target) : 0;
            if (g.metric === 'cooper' && m) pct = Math.min(1, Math.max(0, (m.value - 2400) / (g.target - 2400)));
          }
          return (
            <div key={g.id} style={{ padding: '8px 0' }}>
              <div className="spread"><strong>{g.title}</strong><span className="muted small">voor {shortDate(g.deadline)}</span></div>
              <div className="muted small" style={{ margin: '2px 0 6px' }}>{status}</div>
              <div className="progress"><div style={{ width: `${Math.round(pct * 100)}%` }} /></div>
            </div>
          );
        })}
      </div>

      <h2>Metingen</h2>
      {METRICS.map(mt => {
        const data = metrics.filter(m => m.kind === mt.kind).map(m => ({ date: shortDate(m.date), value: m.value, id: m.id }));
        return (
          <div className="card" key={mt.kind}>
            <div className="spread">
              <div>
                <strong>{mt.label}</strong>
                <div className="muted small">{data.length ? `${fmt.n1(data[data.length - 1].value)} ${mt.unit}` : mt.help}</div>
              </div>
              <button className="btn secondary small" onClick={() => setAdd(mt.kind)}>Meting</button>
            </div>
            {data.length >= 2 && (
              <div className="chart" style={{ height: 150 }}>
                <ResponsiveContainer>
                  <LineChart data={data} margin={{ top: 8, right: 12, left: -18, bottom: 0 }}>
                    <CartesianGrid stroke="#eef1f4" vertical={false} />
                    <XAxis dataKey="date" tick={{ fontSize: 11 }} tickLine={false} axisLine={{ stroke: '#d8dee6' }} />
                    <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} domain={['auto', 'auto']} />
                    <Tooltip formatter={v => [`${v} ${mt.unit}`, mt.label]} />
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
                      <td>{fmt.n1(m.value)} {mt.unit}</td>
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

function MetricEditor(props: { kind: MetricKind; onClose: () => void }) {
  const def = METRICS.find(m => m.kind === props.kind)!;
  const [date, setDate] = useState<ISODate>(today());
  const [value, setValue] = useState('');
  async function submit() {
    const v = num(value);
    if (v == null) return;
    await save('metrics', { id: newId(), date, kind: props.kind, value: v } as Metric);
    props.onClose();
  }
  return (
    <Sheet title={def.label} onClose={props.onClose} footer={<><button className="btn secondary" onClick={props.onClose}>Annuleren</button><button className="btn" onClick={submit}>Opslaan</button></>}>
      <p className="muted small">{def.help}</p>
      <div className="grid2">
        <div><label>Datum</label><input type="date" value={date} onChange={e => setDate(e.target.value)} /></div>
        <div><label>Waarde ({def.unit})</label><input inputMode="decimal" autoFocus value={value} onChange={e => setValue(e.target.value)} /></div>
      </div>
    </Sheet>
  );
}
