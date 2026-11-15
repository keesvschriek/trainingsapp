import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive } from '../db';
import { addDays, fromISO, shortDate, type ISODate } from '../dates';
import { weekOf } from '../plan';
import { weekReview } from '../review';
import { usePushupSettings } from '../pushups';
import { useBlocks, useMoves } from '../ui';

const pct = (x: number) => `${x.toString().replace('.', ',')}%`;

/** Op zondag: terugblik op deze week. Op maandag: terugblik op vorige week. */
export function WeekReviewCard({ date }: { date: ISODate }) {
  const dow = fromISO(date).getDay(); // 0 = zondag
  const week = dow === 0 ? weekOf(date) : dow === 1 ? weekOf(date) - 1 : 0;
  const [open, setOpen] = useState(dow === 0);
  const events = useBlocks();
  const moves = useMoves();
  const { goal } = usePushupSettings();
  const data = useLiveQuery(async () => {
    if (week < 1) return null;
    const from = addDays(date, dow === 0 ? -13 : -14);
    const to = date;
    const [workouts, checks, metrics] = await Promise.all([
      db.workouts.where('date').between(from, to, true, true).toArray(),
      db.checks.where('date').between(from, to, true, true).toArray(),
      db.metrics.where('date').between(from, to, true, true).toArray(),
    ]);
    return { workouts: workouts.filter(alive), checks: checks.filter(alive), metrics: metrics.filter(alive) };
  }, [date, week]);
  if (week < 1 || !data) return null;

  const reviewDay = dow === 0 ? date : addDays(date, -1);
  const r = weekReview(week, reviewDay, { ...data, events, moves, pushupGoal: goal });

  return (
    <div className="card review" aria-label={`Terugblik week ${week}`}>
      <button className="review-head" onClick={() => setOpen(o => !o)} aria-expanded={open}>
        <div>
          <div className="pu-title">Terugblik week {r.week}</div>
          <div className="muted small">{shortDate(r.monday)} t/m {shortDate(r.sunday)} · {r.done} van {r.planned} trainingen</div>
        </div>
        <span className="muted">{open ? 'Minder' : 'Bekijk'}</span>
      </button>
      {open && (
        <>
          <p className="small" style={{ margin: '10px 0' }}>{r.verdict}</p>
          <div className="stat-row">
            <div><div className="num">{r.runMin}<span className="muted small"> / {r.runMinPlanned}</span></div><div className="muted small">min gelopen{r.runKm ? `, ${r.runKm.toString().replace('.', ',')} km` : ''}</div></div>
            <div><div className="num">{r.strength}<span className="muted small"> / {r.strengthPlanned}</span></div><div className="muted small">kracht{r.strengthRpe ? `, zwaarte ${r.strengthRpe.toString().replace('.', ',')}` : ''}</div></div>
            <div><div className="num">{r.pushups}</div><div className="muted small">push-ups, {r.pushupDays} van {r.pushupDaysPossible} dagen doel</div></div>
          </div>
          <div className="stat-row mt">
            <div><div className="num">{r.pullups}</div><div className="muted small">pull-ups tussendoor</div></div>
            <div>
              <div className="num">{r.drift !== undefined ? pct(r.drift) : '-'}</div>
              <div className="muted small">hartslagdrift{r.drift !== undefined && r.driftPrev !== undefined ? ` (vorige week ${pct(r.driftPrev)})` : ''}</div>
            </div>
            <div><div className="num">{r.extra.length}</div><div className="muted small">extra {r.extra.length === 1 ? 'training' : 'trainingen'}</div></div>
          </div>
          {r.missed.length > 0 && (
            <>
              <h3 className="pick-h">Gemist</h3>
              <ul className="review-list">{r.missed.map(m => <li key={m.date + m.title}>{shortDate(m.date)}: {m.title}</li>)}</ul>
            </>
          )}
          {r.openToday.length > 0 && (
            <>
              <h3 className="pick-h">Nog te doen vandaag</h3>
              <ul className="review-list">{r.openToday.map(t => <li key={t}>{t}</li>)}</ul>
            </>
          )}
          {r.next.length > 0 && (
            <>
              <h3 className="pick-h">Volgende week</h3>
              <ul className="review-list">{r.next.map(t => <li key={t}>{t}</li>)}</ul>
            </>
          )}
        </>
      )}
    </div>
  );
}
