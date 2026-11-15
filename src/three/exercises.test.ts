import { describe, expect, it } from 'vitest';
import * as THREE from 'three';
import { daysOfWeek } from '../plan';
import { buildRig, worldPos } from './rig';
import { getMotion, MOTION_KEYS, type Props } from './exercises';
import { motionKeyFor } from './keys';

const props = (): Props => ({
  kb: new THREE.Group(), bar: new THREE.Group(), bandL: new THREE.Mesh(), bandR: new THREE.Mesh(),
  step: new THREE.Mesh(), post: new THREE.Group(),
});

describe('3D-oefeningen', () => {
  it('elke krachtoefening uit het schema heeft een beweging', () => {
    const names = new Set<string>();
    for (let w = 1; w <= 26; w++) {
      for (const day of daysOfWeek(w).days) for (const item of day) for (const e of item.exercises ?? []) names.add(e.name);
    }
    expect(names.size).toBeGreaterThan(10);
    for (const n of names) {
      const key = motionKeyFor(n);
      expect(key, n).not.toBeNull();
      expect(MOTION_KEYS, n).toContain(key);
    }
  });

  it('elke beweging geeft geldige houdingen, zonder door de vloer te zakken', () => {
    const rig = buildRig({ body: '#999', muscle: '#999', active: '#f00' });
    for (const key of MOTION_KEYS) {
      const m = getMotion(key)!;
      for (let i = 0; i < 12; i++) {
        const t = (m.cycle * i) / 12;
        const load = m.pose(rig, t, props());
        for (const v of Object.values(load)) expect(Number.isFinite(v), key).toBe(true);
        for (const bone of Object.values(rig.b)) {
          const p = worldPos(bone);
          expect(Number.isFinite(p.x + p.y + p.z), key).toBe(true);
          expect(p.y, `${key} ${bone.name} t=${t.toFixed(2)}`).toBeGreaterThan(-0.02);
        }
      }
    }
  });
});
