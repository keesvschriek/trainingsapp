import { db, alive, newId, remove, save, type Block, type Move } from './db';
import { addDays, dayName, fromISO, shortDate, today, type ISODate } from './dates';
import { mondayOfWeek, planForWeek } from './plan';
import { Sheet } from './ui';

/** Scherm om een trainingsdag te verschuiven of te ruilen. */
export function MoveSheet(props: { date: ISODate; week: number; weekday: number; events: Block[]; moves: Move[]; onClose: () => void }) {
  const days = planForWeek(props.week, props.events, props.moves);
  const weekMoved = props.moves.some(m => m.week === props.week && m.op !== 'busy');
  const label = (i: number) => days[i].items.filter(x => x.kind !== 'free').map(x => x.title).join(', ') || 'Vrij';

  async function add(op: Move['op'], b?: number) {
    await save('moves', { id: newId(), week: props.week, op, a: props.weekday, b, at: Date.now() });
    props.onClose();
  }

  async function reset() {
    const list = (await db.moves.where('week').equals(props.week).toArray()).filter(alive).filter(m => m.op !== 'busy');
    for (const m of list) await remove('moves', m.id);
    props.onClose();
  }

  return (
    <Sheet title="Verschuiven" onClose={props.onClose}>
      <p className="muted small">{dayName(props.date)} {shortDate(props.date)}: {label(props.weekday)}</p>

      <button className="btn block" onClick={() => add('shift')}>Naar morgen</button>
      <p className="muted small" style={{ marginTop: 6 }}>
        Vandaag wordt een rustdag. De trainingen erna schuiven een dag op, tot de eerstvolgende rust- of vrije dag. Is die er niet meer, dan schuift de laatste training door naar maandag.
      </p>

      <h2>Ruilen met</h2>
      <div className="card">
        {days.map((d, i) => i === props.weekday ? null : (
          <div className="logrow" key={d.date} onClick={() => add('swap', i)}>
            <div><strong>{dayName(d.date)}</strong> {shortDate(d.date)}<div className="muted small">{label(i)}</div></div>
            <div className="stats">ruilen</div>
          </div>
        ))}
      </div>

      {weekMoved && (
        <>
          <h2>Terugzetten</h2>
          <p className="muted small">Zet deze week ({shortDate(mondayOfWeek(props.week))} t/m {shortDate(addDays(mondayOfWeek(props.week), 6))}) terug naar het oorspronkelijke schema.</p>
          <button className="btn secondary" onClick={reset}>Week terugzetten</button>
        </>
      )}
    </Sheet>
  );
}

/** Drukke week: laat zien wat blijft en wat vervalt, en zet het aan. */
export function BusyWeekSheet(props: { week: number; events: Block[]; moves: Move[]; onClose: () => void }) {
  const now = planForWeek(props.week, props.events, props.moves);
  const t = today();
  const monday = mondayOfWeek(props.week);
  const from = t > monday ? Math.min(6, Math.round((fromISO(t).getTime() - fromISO(monday).getTime()) / 86400000)) : 0;
  const fake: Move = { id: 'preview', week: props.week, op: 'busy', a: from, at: 0, updatedAt: 0 };
  const after = planForWeek(props.week, props.events, [...props.moves, fake]);
  const rows = now.map((d, i) => ({
    date: d.date,
    before: d.items.filter(x => x.kind !== 'rest' && x.kind !== 'free' && !x.optional),
    after: after[i].items,
  })).filter(r => r.before.length && r.date >= t);

  async function confirm() {
    await save('moves', { id: newId(), week: props.week, op: 'busy', a: from, at: Date.now() });
    props.onClose();
  }

  return (
    <Sheet
      title="Drukke week"
      onClose={props.onClose}
      footer={<><button className="btn secondary" onClick={props.onClose}>Annuleren</button><button className="btn" onClick={confirm}>Week inkorten</button></>}
    >
      <p className="muted small">De kern blijft staan: de lange loop (20% korter), één andere loop en één krachttraining. De rest vervalt en telt niet als gemist in je terugblik. Push-ups en pull-ups tussendoor gaan gewoon door.</p>
      <div className="card">
        {rows.map(r => (
          <div key={r.date} className="logrow" style={{ cursor: 'default' }}>
            <div>
              <strong>{dayName(r.date)}</strong> {shortDate(r.date)}
              {r.before.map((b, i) => {
                const a = r.after.find(x => x.slotId === b.slotId);
                return (
                  <div key={i} className="small" style={{ color: a ? 'var(--ink)' : 'var(--muted)', textDecoration: a ? 'none' : 'line-through' }}>
                    {b.title}{a && a.minutes && a.minutes !== b.minutes ? ` (${a.minutes} in plaats van ${b.minutes} min)` : ''}
                  </div>
                );
              })}
            </div>
            <div className="stats">{r.before.some(b => r.after.find(x => x.slotId === b.slotId)) ? 'blijft' : 'vervalt'}</div>
          </div>
        ))}
      </div>
    </Sheet>
  );
}

export async function undoBusy(week: number) {
  const list = (await db.moves.where('week').equals(week).toArray()).filter(alive).filter(m => m.op === 'busy');
  for (const m of list) await remove('moves', m.id);
}
