import { useState } from 'react';
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';
import { remove, save, type Metric } from '../db';
import type { ISODate } from '../dates';
import { today } from '../dates';
import { dayTotal, goalStreak, newSetId, setsByDay, usePushupRecords, usePushupSettings } from '../pushups';
import { isNative } from '../native';

/** Kaart op Vandaag: push-ups tussendoor bijhouden met knoppen. */
export function PushupCard({ date }: { date: ISODate }) {
  const { goal, setSize, show } = usePushupSettings();
  const records = usePushupRecords();
  const [custom, setCustom] = useState<string | null>(null);
  if (!show) return null;

  const byDay = setsByDay(records);
  const sets = byDay.get(date) ?? [];
  const total = dayTotal(sets);
  const pct = Math.min(100, Math.round((total / Math.max(1, goal)) * 100));
  const streak = date === today() ? goalStreak(byDay, goal, date) : 0;

  async function add(n: number) {
    if (!Number.isFinite(n) || n <= 0) return;
    const reached = total < goal && total + n >= goal;
    if (isNative) {
      void (reached ? Haptics.notification({ type: NotificationType.Success }) : Haptics.impact({ style: ImpactStyle.Light })).catch(() => undefined);
    }
    await save('metrics', { id: newSetId(date), date, kind: 'pushups', value: Math.round(n) } as Metric);
  }

  async function undo() {
    const last = sets[sets.length - 1];
    if (last) await remove('metrics', last.id);
  }

  const status = total >= goal ? 'Doel gehaald' : `Nog ${goal - total} tot je doel`;

  return (
    <div className="card pushups" aria-label="Push-ups tussendoor">
      <div className="pu-head">
        <div>
          <div className="pu-title">Push-ups tussendoor</div>
          <div className="muted small">
            {status}
            {streak > 1 && <> · {streak} dagen op rij</>}
          </div>
        </div>
        <div className="pu-count" aria-live="polite">
          <span className="num">{total}</span>
          <span className="muted"> / {goal}</span>
        </div>
      </div>
      <div className="progress" role="progressbar" aria-valuenow={total} aria-valuemax={goal}><div style={{ width: `${pct}%` }} /></div>
      {sets.length > 0 && (
        <div className="pu-sets small muted">
          {sets.length} {sets.length === 1 ? 'set' : 'sets'}: {sets.map(s => s.value).join(' · ')}
        </div>
      )}

      {custom === null ? (
        <div className="pu-actions">
          <button className="btn secondary small" onClick={undo} disabled={sets.length === 0}>Ongedaan</button>
          <button className="btn secondary small" onClick={() => setCustom('')}>Ander aantal</button>
          <button className="btn pu-main" onClick={() => add(setSize)}>+{setSize}</button>
        </div>
      ) : (
        <form
          className="pu-actions"
          onSubmit={e => {
            e.preventDefault();
            const n = Number(custom);
            if (n > 0) void add(n);
            setCustom(null);
          }}
        >
          <input
            type="number"
            inputMode="numeric"
            min={1}
            max={500}
            autoFocus
            placeholder="Aantal"
            aria-label="Aantal push-ups"
            value={custom}
            onChange={e => setCustom(e.target.value)}
            style={{ flex: 1, minWidth: 0 }}
          />
          <button type="button" className="btn secondary small" onClick={() => setCustom(null)}>Annuleer</button>
          <button type="submit" className="btn small" disabled={!(Number(custom) > 0)}>Opslaan</button>
        </form>
      )}
    </div>
  );
}
