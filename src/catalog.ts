import type { Exercise } from './plan';

// Alle oefeningen om zelf een krachttraining mee samen te stellen.
// De standaardwaarden zijn een startpunt; de app onthoudt wat je de vorige keer deed.

const ex = (name: string, weight: string, sets: number, reps: string, defaultKg: number, defaultReps: number): Exercise => ({ name, weight, sets, reps, defaultKg, defaultReps });

export const CATALOG: { group: string; items: Exercise[] }[] = [
  {
    group: 'Benen',
    items: [
      ex('Goblet squat', '28 kg', 3, '10', 28, 10),
      ex('Goblet squat, 3 sec zakken', '28 kg', 3, '10', 28, 10),
      ex('Split squat', '20 kg', 3, '10 per been', 20, 10),
      ex('Kettlebell swing', '28 kg', 5, '15', 28, 15),
      ex('Kuitheffen op 1 been', 'lichaamsgewicht', 2, '20 per been', 0, 20),
    ],
  },
  {
    group: 'Duwen',
    items: [
      ex('Push-ups', 'lichaamsgewicht', 4, 'bijna max', 0, 25),
      ex('Push-ups, brede greep', 'lichaamsgewicht', 3, 'bijna max', 0, 20),
      ex('Push-ups, voeten verhoogd', 'lichaamsgewicht', 4, 'bijna max', 0, 20),
      ex('Diamant push-ups', 'lichaamsgewicht', 3, 'bijna max', 0, 15),
      ex('Floor press', '28 kg', 3, '8 tot 10 per arm', 28, 8),
      ex('Strikte press', '20 kg', 3, '6 tot 8 per arm', 20, 6),
      ex('Zijwaarts heffen met band', 'band', 3, '15 tot 20', 0, 15),
      ex('Triceps extensie boven het hoofd', '20 kg', 3, '10 tot 12', 20, 10),
    ],
  },
  {
    group: 'Trekken',
    items: [
      ex('Pull-ups', 'lichaamsgewicht', 4, 'bijna max', 0, 5),
      ex('Chin-ups (onderhands)', 'lichaamsgewicht', 3, 'bijna max', 0, 6),
      ex('Eenarmige row', '28 kg', 3, '10 per arm', 28, 10),
      ex('Kettlebell curl', '20 kg', 3, '8 tot 10', 20, 8),
      ex('Face pulls met band', 'band', 2, '15 tot 20', 0, 15),
    ],
  },
  {
    group: 'Romp en overig',
    items: [
      ex('Kettlebell clean', '20 kg', 4, '5 per arm', 20, 5),
      ex('Knieheffen aan de stang', 'lichaamsgewicht', 3, '8 tot 12', 0, 10),
      ex('Plank (seconden)', 'lichaamsgewicht', 3, '45 sec', 0, 45),
    ],
  },
];

export const ALL_EXERCISES: Exercise[] = CATALOG.flatMap(g => g.items);

/** Eigen oefening met een naam die niet in de lijst staat. */
export function customExercise(name: string): Exercise {
  return ex(name.trim(), '', 3, '10', 0, 10);
}
