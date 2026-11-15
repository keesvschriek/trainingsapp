import { describe, expect, it } from 'vitest';
import * as THREE from 'three';
import { daysOfWeek } from '../plan';
import { buildRig, worldPos } from './rig';
import { BAR_Y, getMotion, MOTION_KEYS, type Props } from './exercises';
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

// ---------------------------------------------------------------------------
// Techniek: meetbare punten uit erkende beschrijvingen (NASM, StrongFirst e.a.).
// ---------------------------------------------------------------------------

describe('3D-techniek klopt met de maatstaven', () => {
  const rig = buildRig({ body: '#999', muscle: '#999', active: '#f00' });
  const P = (o: THREE.Object3D) => worldPos(o);
  const deg = (a: THREE.Vector3, b: THREE.Vector3) => (a.angleTo(b) * 180) / Math.PI;
  const elbowAngle = (s: 'L' | 'R') => 180 - deg(P(rig.b[`elbow${s}`]).sub(P(rig.b[`shoulder${s}`])), P(rig.b[`wrist${s}`]).sub(P(rig.b[`elbow${s}`])));
  const kneeAngle = (s: 'L' | 'R') => 180 - deg(P(rig.b[`knee${s}`]).sub(P(rig.b[`hip${s}`])), P(rig.b[`ankle${s}`]).sub(P(rig.b[`knee${s}`])));
  const upperArmVsTorso = (s: 'L' | 'R') => deg(P(rig.b[`elbow${s}`]).sub(P(rig.b[`shoulder${s}`])), P(rig.b.pelvis).sub(P(rig.b.chest)));
  const pose = (key: string, t: number) => { const p = props(); getMotion(key)!.pose(rig, t, p); rig.root.updateMatrixWorld(true); return p; };

  it('push-up: bovenin armen gestrekt, onderin ellebogen 35-55 graden van de romp', () => {
    pose('pushup-normaal', 0);
    expect(elbowAngle('R')).toBeGreaterThan(160);
    pose('pushup-normaal', 2.0);
    expect(upperArmVsTorso('R')).toBeGreaterThan(35);
    expect(upperArmVsTorso('R')).toBeLessThan(55);
  });

  it('goblet squat: onderin heup op of onder kniehoogte, ellebogen binnen de knieën; bovenin benen gestrekt', () => {
    pose('squat', 2.2);
    expect(P(rig.b.hipR).y).toBeLessThanOrEqual(P(rig.b.kneeR).y);
    expect(Math.abs(P(rig.b.elbowR).x)).toBeLessThan(Math.abs(P(rig.b.kneeR).x));
    pose('squat', 0);
    expect(kneeAngle('R')).toBeGreaterThan(160);
  });

  it('pull-up en chin-up: start uit dead hang, kin boven de stang, greep op of iets buiten schouderbreedte', () => {
    for (const key of ['pullup', 'chinup']) {
      pose(key, 0);
      expect(elbowAngle('R'), key).toBeGreaterThan(160);
      const shoulderWidth = P(rig.b.shoulderL).x - P(rig.b.shoulderR).x;
      const grip = P(rig.b.wristL).x - P(rig.b.wristR).x;
      expect(grip / shoulderWidth, key).toBeGreaterThanOrEqual(0.95);
      expect(grip / shoulderWidth, key).toBeLessThan(1.5);
      pose(key, 1.6);
      expect(P(rig.b.head).y, key).toBeGreaterThan(BAR_Y); // onderkant hoofd (kin) boven de stang
    }
  });

  it('row: rug bijna horizontaal, bovenin elleboog naast de romp', () => {
    pose('row', 1.2);
    const torso = P(rig.b.neck).sub(P(rig.b.pelvis));
    const fromHorizontal = 90 - deg(torso, new THREE.Vector3(0, 1, 0));
    expect(fromHorizontal).toBeLessThan(30);
    expect(Math.abs(P(rig.b.elbowR).x - P(rig.b.shoulderR).x)).toBeLessThan(0.06);
    expect(P(rig.b.elbowR).y).toBeGreaterThan(P(rig.b.shoulderR).y - 0.05);
  });

  it('face pull: band op ooghoogte, eindstand ellebogen boven schouderhoogte en handen naast het hoofd', () => {
    pose('facepull', 1.3);
    expect(P(rig.b.elbowR).y).toBeGreaterThan(P(rig.b.shoulderR).y);
    expect(P(rig.b.wristR).y).toBeGreaterThan(P(rig.b.head).y);
    expect(Math.abs(P(rig.b.wristR).z)).toBeLessThan(0.1);
  });

  it('floor press: onderin bovenarm op de vloer op 35-55 graden, onderarm loodrecht', () => {
    pose('floorpress', 1.8);
    expect(upperArmVsTorso('R')).toBeGreaterThan(35);
    expect(upperArmVsTorso('R')).toBeLessThan(55);
    expect(P(rig.b.elbowR).y).toBeLessThan(0.12);
    const fo = P(rig.b.wristR).sub(P(rig.b.elbowR));
    expect(deg(fo, new THREE.Vector3(0, 1, 0))).toBeLessThan(12);
  });

  it('strikte press: rack met onderarm bijna loodrecht en elleboog binnen de schouder; bovenin gestrekt boven de schouder', () => {
    pose('press', 0);
    const fo = P(rig.b.wristR).sub(P(rig.b.elbowR));
    expect(deg(fo, new THREE.Vector3(0, 1, 0))).toBeLessThan(20);
    expect(Math.abs(P(rig.b.elbowR).x)).toBeLessThan(Math.abs(P(rig.b.shoulderR).x));
    pose('press', 1.5);
    expect(elbowAngle('R')).toBeGreaterThan(155);
    expect(Math.abs(P(rig.b.wristR).z - P(rig.b.shoulderR).z)).toBeLessThan(0.06);
  });

  it('zijwaarts heffen: tot schouderhoogte, in het schouderbladvlak (15-35 graden naar voren)', () => {
    pose('lateral', 1.3);
    const up = P(rig.b.elbowR).sub(P(rig.b.shoulderR));
    expect(Math.abs(up.y)).toBeLessThan(0.06);
    const forward = (Math.atan2(up.z, Math.abs(up.x)) * 180) / Math.PI;
    expect(forward).toBeGreaterThan(15);
    expect(forward).toBeLessThan(35);
  });

  it('triceps extensie: bovenarm blijft stil en dicht bij het hoofd', () => {
    pose('triceps', 0);
    const e0 = P(rig.b.elbowR);
    pose('triceps', 1.8);
    expect(P(rig.b.elbowR).distanceTo(e0)).toBeLessThan(0.03);
    expect(Math.abs(P(rig.b.elbowR).x)).toBeLessThan(0.17);
  });

  it('kuitheffen: knie gestrekt, onderin hiel onder de tree', () => {
    const p = pose('calf', 0);
    expect(kneeAngle('R')).toBeGreaterThan(165);
    const stepTop = p.step.position.y + 0.1;
    expect(P(rig.b.ankleR).y - 0.065).toBeLessThan(stepTop);
  });
});
