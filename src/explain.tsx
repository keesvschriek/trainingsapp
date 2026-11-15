import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, alive } from './db';
import { addDays, today } from './dates';
import { planForDay, type PlannedItem } from './plan';
import { autoSetSize } from './pushups';

// Uitleglaag: per onderwerp kort waarom, met een bron en waar het kan met je eigen cijfers.
// Teksten zijn eigen samenvattingen; de bron staat erbij om het na te lezen.

export type Topic =
  | 'easy' | 'long' | 'quality' | 'strength' | 'nearFailure' | 'pushups'
  | 'light' | 'test' | 'busy' | 'drift' | 'load' | 'recovery';

interface Explainer {
  title: string;
  text: string;
  source: { label: string; url: string };
}

export const EXPLAIN: Record<Topic, Explainer> = {
  easy: {
    title: 'Waarom zo rustig?',
    text: 'Goede duursporters doen het grootste deel van hun training op lage intensiteit, ongeveer 80%, en maar een klein deel echt hard. Rustig lopen bouwt je hart, bloedvaten en vetverbranding op zonder dat je herstel eronder lijdt. Daardoor kun je de harde trainingen wel echt hard doen. Te snel lopen op rustige dagen is de meest gemaakte fout.',
    source: { label: 'Seiler (2010), Int J Sports Physiol Perform', url: 'https://pubmed.ncbi.nlm.nih.gov/20861519/' },
  },
  long: {
    title: 'Waarom een lange loop?',
    text: 'De lange loop is het langste rustige blok van je week. Langer achter elkaar lopen op lage intensiteit traint je uithoudingsvermogen en leert je lichaam zuinig met energie om te gaan. Voor een snelle 10 km en een goede Cooper is dit de basis waar de snellere trainingen op bouwen. Houd het tempo rustig: je moet kunnen praten.',
    source: { label: 'Seiler (2010), Int J Sports Physiol Perform', url: 'https://pubmed.ncbi.nlm.nih.gov/20861519/' },
  },
  quality: {
    title: 'Waarom tempo en intervallen?',
    text: 'Naast veel rustig werk heb je een klein deel echt hard werk nodig, rond je drempel of daarboven. Dat verhoogt het tempo dat je lang kunt volhouden, en dat is precies wat je nodig hebt voor 10 km en de Cooper. Eén zo’n training per week is genoeg. Meer hard werk levert bij goed getrainde lopers niet aantoonbaar meer op.',
    source: { label: 'Seiler (2010), Int J Sports Physiol Perform', url: 'https://pubmed.ncbi.nlm.nih.gov/20861519/' },
  },
  strength: {
    title: 'Waarom kracht naast het lopen?',
    text: 'Krachttraining maakt lopers zuiniger: je gebruikt minder energie bij hetzelfde tempo. In onderzoek verbetert ook de tijd op 1,5 tot 10 km. Je wordt er niet zwaarder of trager van. Twee tot drie keer per week, met verschillende soorten oefeningen, lijkt het beste te werken.',
    source: { label: 'Blagrove e.a. (2018), Sports Medicine', url: 'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5889786/' },
  },
  nearFailure: {
    title: 'Waarom 1 tot 2 herhalingen over?',
    text: 'Voor spiergroei hoef je niet tot je echt niet meer kunt. Sets die net voor dat punt stoppen geven vrijwel dezelfde groei, met minder vermoeidheid. Dat is belangrijk omdat je ook nog moet lopen. Stop dus als je nog 1 of 2 herhalingen zou kunnen, maar wel echt zwaar.',
    source: { label: 'Refalo e.a. (2023), Sports Medicine', url: 'https://pubmed.ncbi.nlm.nih.gov/36334240/' },
  },
  pushups: {
    title: 'Waarom vaak een halve set?',
    text: 'Dit heet grease the groove: een beweging vaak per dag oefenen, ruim onder je maximum en nooit tot falen. Je zenuwstelsel leert de beweging efficiënter aan te sturen, zonder dat je moe wordt. Daarom de helft van je maximum en tussen de sets minstens een kwartier.',
    source: { label: 'Art of Manliness over Pavel Tsatsouline', url: 'https://www.artofmanliness.com/strength/fitness/get-stronger-by-greasing-the-groove/' },
  },
  light: {
    title: 'Waarom een lichte week?',
    text: 'Na een paar weken opbouwen stapelt vermoeidheid zich op. In een lichte week train je bewust minder, zodat je lichaam herstelt en de aanpassingen van de vorige weken vastlegt. Coaches doen dit meestal elke 4 tot 6 weken. Je bent na zo’n week vaak sterker dan ervoor.',
    source: { label: 'Bell e.a. (2023), Sports Medicine Open', url: 'https://doi.org/10.1186/s40798-023-00633-0' },
  },
  test: {
    title: 'Waarom een testweek?',
    text: 'Zonder meten weet je niet of het schema werkt. Elke paar weken test je onder dezelfde omstandigheden je Cooper of 10 km, je pull-ups, push-ups en press. Daarop past de app je setgroottes aan. De rest van de week is licht, zodat je uitgerust test en de cijfers eerlijk zijn.',
    source: { label: 'Bell e.a. (2023), Sports Medicine Open', url: 'https://doi.org/10.1186/s40798-023-00633-0' },
  },
  busy: {
    title: 'Waarom alleen de kern?',
    text: 'In drukke periodes hoef je niet alles te doen om je niveau te houden. Uithouding blijft weken op peil met twee trainingen per week, en kracht met één, zolang de intensiteit hetzelfde blijft. Daarom houdt de drukke week de lange loop, één andere loop en één krachttraining, op het normale tempo en gewicht.',
    source: { label: 'Spiering e.a. (2021), J Strength Cond Res', url: 'https://pubmed.ncbi.nlm.nih.gov/33629972/' },
  },
  drift: {
    title: 'Wat zegt hartslagdrift?',
    text: 'Bij een rustige loop loopt je hartslag langzaam op terwijl je tempo gelijk blijft. Hoe minder dat gebeurt, hoe beter je basis. Onder 5% geldt als een goede aerobe basis voor die duur, 5 tot 10% groeit nog, boven 10% was de loop te zwaar of te lang. Warmte en te weinig drinken verhogen de drift ook.',
    source: { label: 'Friel, TrainingPeaks', url: 'https://www.trainingpeaks.com/learn/articles/aerobic-endurance-and-decoupling/' },
  },
  load: {
    title: 'Hoe werkt fitheid en vermoeidheid?',
    text: 'Elke training geeft fitheid, die langzaam opbouwt en wegzakt (gemiddelde over 6 weken), en vermoeidheid, die snel komt en snel weer gaat (gemiddelde over 1 week). Het verschil is je vorm. Een lichte week laat de vermoeidheid zakken terwijl je fitheid blijft. Daarom voel je je daarna fris.',
    source: { label: 'TrainingPeaks: de Performance Management Chart', url: 'https://www.trainingpeaks.com/learn/articles/what-is-the-performance-management-chart/' },
  },
  recovery: {
    title: 'Hoe rekent de herstelvoorspeller?',
    text: 'Elke training krijgt een belasting: hoe zwaar het voelde (1 tot 10) keer hoeveel minuten. Die methode werkt voor lopen, kracht en ook Defensie, en past goed bij hartslagmetingen. Samen met je check-in in de ochtend schat de app hoe hersteld je bent.',
    source: { label: 'Haddad e.a. (2017), overzicht van de sRPE-methode', url: 'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5673663/' },
  },
};

export function topicFor(item: PlannedItem): Topic | null {
  if (item.slotId === 'run-long') return 'long';
  if (item.slotId === 'run-quality') return 'quality';
  if (item.kind === 'run') return 'easy';
  if (item.kind === 'strength') return 'strength';
  if (item.kind === 'test') return 'test';
  return null;
}

/** Eigen cijfers bij een onderwerp, over de laatste 4 weken. */
function useMine(topic: Topic): string | null {
  return useLiveQuery(async () => {
    const from = addDays(today(), -28);
    const ws = (await db.workouts.where('date').aboveOrEqual(from).toArray()).filter(alive);
    const runs = ws.filter(w => w.kind === 'run');
    if (topic === 'easy' || topic === 'quality') {
      const isHard = (d: string) => planForDay(d).items.some(i => i.slotId === 'run-quality');
      const total = runs.reduce((s, w) => s + (w.durationMin ?? 0), 0);
      if (total < 30) return null;
      const easy = runs.filter(w => w.slotId ? w.slotId !== 'run-quality' : !isHard(w.date)).reduce((s, w) => s + (w.durationMin ?? 0), 0);
      return `Jij: de laatste 4 weken was ${Math.round((easy / total) * 100)}% van je looptijd rustig.`;
    }
    if (topic === 'long') {
      const max = Math.max(0, ...runs.map(w => w.durationMin ?? 0));
      return max ? `Jij: je langste loop de laatste 4 weken was ${Math.round(max)} minuten.` : null;
    }
    if (topic === 'strength' || topic === 'nearFailure') {
      const n = ws.filter(w => w.kind === 'strength').length;
      return n ? `Jij: ${n} krachttrainingen in de laatste 4 weken, gemiddeld ${String(Math.round((n / 4) * 10) / 10).replace('.', ',')} per week.` : null;
    }
    if (topic === 'pushups') {
      const maxes = (await db.metrics.where('kind').equals('pushupMax').toArray()).filter(alive).sort((a, b) => a.date.localeCompare(b.date));
      const last = maxes[maxes.length - 1]?.value;
      return last ? `Jij: je laatste maxtest was ${last}, dus sets van ${autoSetSize(last, 20)}.` : null;
    }
    return null;
  }, [topic], null);
}

/** Kleine "Waarom?"-knop die de uitleg openklapt. */
export function Why({ topic, extra }: { topic: Topic; extra?: string }) {
  const [open, setOpen] = useState(false);
  const e = EXPLAIN[topic];
  const mine = useMine(topic);
  return (
    <div className="why">
      <button className="why-btn" onClick={ev => { ev.stopPropagation(); setOpen(o => !o); }} aria-expanded={open}>
        {open ? 'Sluiten' : e.title}
      </button>
      {open && (
        <div className="why-body" onClick={ev => ev.stopPropagation()}>
          <p>{e.text}</p>
          {(extra || mine) && <p className="why-mine">{extra ?? mine}</p>}
          <p className="muted small">Bron: <a href={e.source.url} target="_blank" rel="noreferrer">{e.source.label}</a></p>
        </div>
      )}
    </div>
  );
}
