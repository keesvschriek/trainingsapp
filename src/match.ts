import type { Check, Workout } from './db';
import type { ItemKind, PlannedItem } from './plan';

// Koppelt geplande items van een dag aan gelogde trainingen.
// Eerst expliciete koppelingen (slotId), daarna ongekoppelde trainingen van hetzelfde soort op volgorde.

const KIND_MAP: Partial<Record<ItemKind, Workout['kind']>> = { run: 'run', race: 'run', strength: 'strength', boxing: 'boxing' };

export interface ItemStatus {
  item: PlannedItem;
  workout?: Workout;
  checked: boolean;
  done: boolean;
}

export function matchDay(items: PlannedItem[], workouts: Workout[], checks: Check[]): { statuses: ItemStatus[]; extra: Workout[] } {
  const used = new Set<string>();
  const statuses: ItemStatus[] = items.map(item => {
    const w = workouts.find(w => w.slotId === item.slotId && !used.has(w.id));
    if (w) used.add(w.id);
    const checked = checks.some(c => c.slotId === item.slotId && c.done);
    return { item, workout: w, checked, done: !!w || checked };
  });

  for (const st of statuses) {
    if (st.workout) continue;
    const kind = KIND_MAP[st.item.kind];
    if (!kind) continue;
    const w = workouts.find(w => w.kind === kind && !w.slotId && !used.has(w.id));
    if (w) {
      used.add(w.id);
      st.workout = w;
      st.done = true;
    }
  }

  const extra = workouts.filter(w => !used.has(w.id));
  return { statuses, extra };
}
