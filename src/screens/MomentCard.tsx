import { useEffect, useState } from 'react';
import type { ISODate } from '../dates';
import type { PlannedItem } from '../plan';
import { describe, pickMoments, type Moment } from '../bestmoment';
import { dayWeather, getForecast } from '../weather';
import { fmtMin, isWorkDay, saveWork, toMin, useWork } from '../work';
import { useBlocks } from '../ui';

/** Op Vandaag: werkdag aan/uit en het beste moment voor je loop. */
export function MomentCard({ date, run, done }: { date: ISODate; run?: PlannedItem; done: boolean }) {
  const work = useWork();
  const events = useBlocks();
  const working = isWorkDay(date, work, events);
  const [m, setM] = useState<{ best?: Moment; alt?: Moment } | null>(null);
  const [offline, setOffline] = useState(false);
  const minutes = run?.minutes ?? 45;
  const wantMoment = !!run && !done && run.slotId !== 'run-commute';

  useEffect(() => {
    if (!wantMoment) return;
    let stop = false;
    (async () => {
      const f = await getForecast();
      if (stop) return;
      if (!f) return setOffline(true);
      const w = dayWeather(f, date);
      if (!w) return setOffline(true);
      const now = new Date();
      // Werk plus tijd om te douchen en om te kleden ervoor (30 min) en om thuis te komen erna (15 min)
      const busy: [number, number][] = working ? [[toMin(work.start) - 30, toMin(work.end) + 15]] : [];
      setM(pickMoments({ ...w, minutes, nowMin: now.getHours() * 60 + now.getMinutes(), busy }));
    })();
    return () => {
      stop = true;
    };
  }, [date, minutes, working, work.start, work.end, wantMoment]);

  async function toggle() {
    await saveWork({ ...work, overrides: { ...work.overrides, [date]: !working } });
  }

  return (
    <div className="card moment">
      <div className="spread">
        <div className="small">
          {working ? <>Werkdag, weg van {work.start} tot {work.end}</> : <>Geen werk vandaag</>}
        </div>
        <button className="btn ghost small" onClick={() => void toggle()}>{working ? 'Toch vrij' : 'Toch werk'}</button>
      </div>
      {wantMoment && (
        <div className="moment-body">
          {m?.best ? (
            <>
              <div className="moment-time">Beste moment voor je loop: <strong>{fmtMin(m.best.start)} tot {fmtMin(m.best.end)}</strong></div>
              <div className="muted small">{describe(m.best)}</div>
              {m.alt && <div className="muted small">Anders: {fmtMin(m.alt.start)} tot {fmtMin(m.alt.end)}, {describe(m.alt)}</div>}
            </>
          ) : offline ? (
            <div className="muted small">Geen weerbericht. Geen internet of de weerdienst is even niet bereikbaar.</div>
          ) : m ? (
            <div className="muted small">Vandaag is er geen blok van {minutes} minuten meer vrij voor 22:00.</div>
          ) : (
            <div className="muted small">Weer ophalen...</div>
          )}
        </div>
      )}
    </div>
  );
}
