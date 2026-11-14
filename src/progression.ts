import type { Exercise } from './plan';

// Automatisch zwaarder: advies per oefening op basis van de vorige keer.
// Kettlebells: 20 en 28 kg. Pas als alle sets de bovenkant van de range halen, gaat het omhoog.

export interface LastSet { reps: number; weightKg: number }

export interface Hint {
  text: string;
  /** Voorstel om alvast in te vullen voor vandaag */
  reps?: number;
  kg?: number;
}

export function repRange(reps: string): { lo: number; hi: number } | null {
  if (/bijna max/i.test(reps)) return null;
  const nums = (reps.match(/\d+/g) ?? []).map(Number);
  if (!nums.length) return null;
  return { lo: nums[0], hi: nums.length > 1 && /tot/.test(reps) ? nums[1] : nums[0] };
}

const KETTLEBELLS = [20, 28];

export function progressionHint(ex: Exercise, last: LastSet[]): Hint | null {
  if (!last.length) return null;
  if (ex.light) {
    const kg = Math.max(...last.map(x => x.weightKg));
    return { text: 'Lichte week: zelfde gewicht, ruim binnen je kunnen. Niet zwaarder.', kg: kg || undefined, reps: Math.min(...last.map(x => x.reps)) };
  }
  const range = repRange(ex.reps);
  const total = last.reduce((s, x) => s + x.reps, 0);

  // Zoveel als je kunt: probeer het totaal te verhogen
  if (!range) {
    const best = Math.max(...last.map(x => x.reps));
    return { text: `Vorige keer ${total} in totaal (beste set ${best}). Doel: ${total + 2} of meer.`, reps: best };
  }

  const kg = Math.max(...last.map(x => x.weightKg));
  const allTop = last.length >= ex.sets && last.every(x => x.reps >= range.hi);
  if (allTop) {
    const next = KETTLEBELLS.find(w => w > kg);
    if (kg > 0 && next && !/band/.test(ex.weight)) {
      return { text: `Alle sets gehaald. Probeer ${next} kg, begin op ${range.lo} herhalingen.`, kg: next, reps: range.lo };
    }
    return { text: `Alle sets gehaald. Doe er per set 2 bij of zak 3 tellen langzaam.`, reps: range.hi + 2, kg: kg || undefined };
  }
  const missed = last.filter(x => x.reps < range.hi).length;
  return { text: `Nog ${missed} ${missed === 1 ? 'set' : 'sets'} onder de ${range.hi}. Zelfde gewicht, probeer per set 1 herhaling meer.`, kg: kg || undefined };
}
