import { useEffect, useRef, useState } from 'react';
import { Haptics, NotificationType } from '@capacitor/haptics';
import { isNative } from '../native';
import { CATEGORY_NAMES } from './questions';
import { getScore, pick, record, useTrivia, type Shown, type TriviaScore } from './trivia';

const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.max(0, s) % 60).padStart(2, '0')}`;

/** Rustpauze met aftellen en een triviavraag. */
export function RestTimer({ onClose }: { onClose: () => void }) {
  const t = useTrivia();
  const [left, setLeft] = useState<number | null>(null);
  const [shown, setShown] = useState<Shown | null>(null);
  const [answer, setAnswer] = useState<number | null>(null);
  const [score, setScore] = useState<TriviaScore | null>(null);
  const ended = useRef(false);

  useEffect(() => {
    void getScore().then(setScore);
  }, []);
  useEffect(() => {
    if (left === null) setLeft(t.restSec);
  }, [t.restSec, left]);
  useEffect(() => {
    if (t.on && !shown && score) setShown(pick(score.asked, t.cats));
  }, [t.on, t.cats, shown, score]);

  useEffect(() => {
    if (left === null) return;
    if (left <= 0) {
      if (!ended.current) {
        ended.current = true;
        if (isNative) void Haptics.notification({ type: NotificationType.Warning }).catch(() => undefined);
      }
      return;
    }
    const id = window.setTimeout(() => setLeft(l => (l ?? 0) - 1), 1000);
    return () => window.clearTimeout(id);
  }, [left]);

  async function choose(i: number) {
    if (!shown || answer !== null) return;
    setAnswer(i);
    setScore(await record(shown.q.id, i === shown.correct, t.cats));
  }
  function next() {
    if (!score) return;
    setShown(pick(score.asked, t.cats));
    setAnswer(null);
  }

  const done = left !== null && left <= 0;
  return (
    <div className="resttimer" role="dialog" aria-label="Rustpauze">
      <div className="resttimer-top">
        <div className={`resttimer-clock${done ? ' done' : ''}`}>{done ? 'Volgende set' : mmss(left ?? t.restSec)}</div>
        <div className="row" style={{ gap: 6 }}>
          {!done && <button className="btn secondary small" onClick={() => setLeft(l => (l ?? 0) + 30)}>+30 s</button>}
          <button className="btn small" onClick={onClose}>{done ? 'Verder' : 'Klaar'}</button>
        </div>
      </div>
      {t.on && shown && (
        <div className="quiz">
          <div className="muted small">{CATEGORY_NAMES[shown.q.cat]}{score && score.total > 0 ? ` · ${score.right} van ${score.total} goed${score.streak > 1 ? `, ${score.streak} op rij` : ''}` : ''}</div>
          <div className="quiz-q">{shown.q.q}</div>
          <div className="quiz-opts">
            {shown.options.map((o, i) => {
              const cls = answer === null ? '' : i === shown.correct ? ' right' : i === answer ? ' wrong' : ' dim';
              return <button key={o} className={`quiz-opt${cls}`} onClick={() => void choose(i)} disabled={answer !== null}>{o}</button>;
            })}
          </div>
          {answer !== null && (
            <>
              <p className="small" style={{ margin: '10px 0 6px' }}><strong>{answer === shown.correct ? 'Goed.' : `Het was: ${shown.options[shown.correct]}.`}</strong> {shown.q.why}</p>
              {!done && <button className="btn secondary small" onClick={next}>Nog een vraag</button>}
            </>
          )}
        </div>
      )}
    </div>
  );
}
