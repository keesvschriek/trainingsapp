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
    if (next.on) {
      const ok = await requestNotifyPermission();
      if (!ok) {
        setMsg({ text: 'Geen toestemming voor meldingen. Zet die aan bij Android-instellingen > Apps > Training > Meldingen.', err: true });
        return;
      }
    }
    const n = await scheduleMorning();
    setMsg(next.on ? { text: `${n} ochtendmeldingen ingepland.` } : { text: 'Meldingen uit.' });
  }

  return (
    <>
      <h2>Ochtendmelding</h2>
      {!isNative ? (
        <p className="muted small">Alleen in de Android-app.</p>
      ) : (
        <>
          <p className="muted small">Elke ochtend een melding met je training van die dag. Tik erop voor je check-in.</p>
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
