import { useEffect, useState } from 'react';
import { setSetting } from '../db';
import { getNotifySettings, requestNotifyPermission, scheduleMorning, type NotifySettings } from '../notify';
import { isNative } from '../native';

export function NotifySection() {
  const [s, setS] = useState<NotifySettings | null>(null);
  const [msg, setMsg] = useState<{ text: string; err?: boolean } | null>(null);

  useEffect(() => { void getNotifySettings().then(setS); }, []);
  if (!s) return null;

  async function store(next: NotifySettings) {
    setS(next);
    await setSetting('notify', next);
    if (next.on || next.evening || next.week) {
      const ok = await requestNotifyPermission();
      if (!ok) {
        setMsg({ text: 'Geen toestemming voor meldingen. Zet die aan bij Android-instellingen > Apps > Training > Meldingen.', err: true });
        return;
      }
    }
    const n = await scheduleMorning();
    setMsg(next.on || next.evening || next.week ? { text: `${n} meldingen ingepland.` } : { text: 'Meldingen uit.' });
  }

  return (
    <>
      <h2>Meldingen</h2>
      {!isNative ? (
        <p className="muted small">Alleen in de Android-app.</p>
      ) : (
        <>
          <label className="row" style={{ color: 'var(--ink)', fontSize: '1rem' }}>
            <input type="checkbox" checked={!!s.evening} onChange={e => store({ ...s, evening: e.target.checked })} style={{ width: 'auto' }} /> Seintje na school
          </label>
          <p className="muted small">Alleen als je training of een opvolgpunt van die dag nog open staat. Geen melding als alles klaar is.</p>
          <div className="grid2">
            <div>
              <label>Tijd</label>
              <input type="time" value={s.eveningTime ?? '18:00'} onChange={e => e.target.value && store({ ...s, eveningTime: e.target.value })} />
            </div>
          </div>
          <label className="row" style={{ color: 'var(--ink)', fontSize: '1rem' }}>
            <input type="checkbox" checked={!!s.week} onChange={e => store({ ...s, week: e.target.checked })} style={{ width: 'auto' }} /> Zondag: je week bekijken
          </label>
          <div className="grid2">
            <div>
              <label>Tijd</label>
              <input type="time" value={s.weekTime ?? '16:00'} onChange={e => e.target.value && store({ ...s, weekTime: e.target.value })} />
            </div>
          </div>
          <p className="muted small">Elke ochtend een melding met je training van die dag. Tik erop voor je check-in. Op zondag om 19:00 krijg je ook een melding voor je weekterugblik.</p>
          <label className="row" style={{ color: 'var(--ink)', fontSize: '1rem' }}>
            <input type="checkbox" checked={s.on} onChange={e => store({ ...s, on: e.target.checked })} style={{ width: 'auto' }} /> Ochtendmelding aan
          </label>
          <div className="grid2">
            <div>
              <label>Tijd</label>
              <input type="time" value={s.time} onChange={e => e.target.value && store({ ...s, time: e.target.value })} />
            </div>
          </div>
          {msg && <div className={`notice${msg.err ? ' err' : ''}`}>{msg.text}</div>}
        </>
      )}
    </>
  );
}
