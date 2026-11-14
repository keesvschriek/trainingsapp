import { db, alive, newId, remove, save, type Block, type Move } from './db';
import { addDays, dayName, shortDate, type ISODate } from './dates';
import { mondayOfWeek, planForWeek } from './plan';
import { Sheet } from './ui';

/** Scherm om een trainingsdag te verschuiven of te ruilen. */
export function MoveSheet(props: { date: ISODate; week: number; weekday: number; events: Block[]; moves: Move[]; onClose: () => void }) {
  const days = planForWeek(props.week, props.events, props.moves);
  const weekMoved = props.moves.some(m => m.week === props.week);
  const label = (i: number) => days[i].items.filter(x => x.kind !== 'free').map(x => x.title).join(', ') || 'Vrij';

  async function add(op: Move['op'], b?: number) {
    await save('moves', { id: newId(), week: props.week, op, a: props.weekday, b, at: Date.now() });
    props.onClose();
  }

  async function reset() {
    const list = (await db.moves.where('week').equals(props.week).toArray()).filter(alive);
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
