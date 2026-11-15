import * as THREE from 'three';
import { aim, resetPose, solveTwoBone, worldPos, LIMB, type MuscleId, type Rig } from './rig';

// ---------------------------------------------------------------------------
// Bewegingen per oefening. Elke beweging is een lus van `cycle` seconden.
// pose(t) zet de pop neer en geeft terug hoe zwaar elke spier op dat moment werkt.
// ---------------------------------------------------------------------------

export interface Cue {
  from: number;
  to: number;
  text: string;
}

export interface Motion {
  key: string;
  title: string;
  cycle: number;
  cues: Cue[];
  /** Waar de camera naar kijkt */
  focus: [number, number, number];
  camera: [number, number, number];
  pose: (rig: Rig, t: number) => Partial<Record<MuscleId, number>>;
}

const ease = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x * x * (3 - 2 * x));

/** Verloop van 0 (boven) naar 1 (onder) en terug, met pauzes. */
function depthCurve(t: number, down: number, holdLow: number, up: number, holdHigh: number) {
  const total = down + holdLow + up + holdHigh;
  const x = ((t % total) + total) % total;
  if (x < down) return ease(x / down);
  if (x < down + holdLow) return 1;
  if (x < down + holdLow + up) return 1 - ease((x - down - holdLow) / up);
  return 0;
}

// ---------------------------------------------------------------------------
// Push-up
// ---------------------------------------------------------------------------

function plankRoot(rig: Rig, tilt: number) {
  // Lichaam voorover gekanteld (voorkant naar de vloer, hoofd naar +Z), tenen vast op de vloer.
  rig.root.position.set(0, 0, 0);
  rig.root.rotation.set(Math.PI / 2 - tilt, 0, 0);
  rig.root.updateMatrixWorld(true);
  const toe = worldPos(rig.toeL).add(worldPos(rig.toeR)).multiplyScalar(0.5);
  rig.root.position.sub(toe);
  rig.root.updateMatrixWorld(true);
}

function shoulderHeight(rig: Rig) {
  return (worldPos(rig.b.shoulderL).y + worldPos(rig.b.shoulderR).y) / 2;
}

function pushupFactory(variant: 'normaal' | 'smal' | 'breed'): Motion {
  const handWidth = variant === 'smal' ? 0.07 : variant === 'breed' ? 0.34 : 0.22;
  const top = LIMB.upperArm + LIMB.forearm + 0.02;
  const bottom = 0.17;
  let handZ: number | null = null;

  return {
    key: `pushup-${variant}`,
    title: variant === 'smal' ? 'Diamant push-up' : variant === 'breed' ? 'Push-up, brede greep' : 'Push-up',
    cycle: 5,
    focus: [0, 0.24, 0.92],
    camera: [2.5, 0.95, 1.45],
    cues: [
      { from: 0, to: 1.8, text: 'Zakken, gecontroleerd. Ellebogen schuin naar achteren, niet wijd.' },
      { from: 1.8, to: 2.2, text: 'Borst net boven de vloer. Romp blijft een rechte plank.' },
      { from: 2.2, to: 3.2, text: 'Omhoog duwen en uitademen. Billen niet laten zakken.' },
      { from: 3.2, to: 5, text: 'Bovenin: armen gestrekt, schouders weg van je oren.' },
    ],
    pose(rig, t) {
      resetPose(rig);
      const depth = depthCurve(t, 1.8, 0.4, 1.0, 1.8);
      const target = top + (bottom - top) * depth;

      // Zoek de kanteling waarbij de schouders op de juiste hoogte staan
      let lo = 0.02;
      let hi = 0.75;
      for (let i = 0; i < 22; i++) {
        const mid = (lo + hi) / 2;
        plankRoot(rig, mid);
        if (shoulderHeight(rig) > target) hi = mid; else lo = mid;
      }
      plankRoot(rig, (lo + hi) / 2);

      // Handen staan vast op de vloer, onder de schouders in de hoogste stand
      if (handZ === null) {
        const save = rig.root.rotation.x;
        let l = 0.02, h = 0.75;
        for (let i = 0; i < 22; i++) {
          const m = (l + h) / 2;
          plankRoot(rig, m);
          if (shoulderHeight(rig) > top) h = m; else l = m;
        }
        plankRoot(rig, (l + h) / 2);
        handZ = (worldPos(rig.b.shoulderL).z + worldPos(rig.b.shoulderR).z) / 2;
        rig.root.rotation.x = save;
        plankRoot(rig, (lo + hi) / 2);
      }

      for (const [side, sx] of [['L', 1], ['R', -1]] as const) {
        const shoulder = rig.b[`shoulder${side}`];
        const S = worldPos(shoulder);
        const wristTarget = new THREE.Vector3(sx * handWidth, 0.05, handZ - 0.02);
        // Ellebogen schuin naar achteren en iets naar buiten
        const pole = new THREE.Vector3(sx * (variant === 'breed' ? 0.9 : 0.45), 0.4, -1);
        solveTwoBone(shoulder, rig.b[`elbow${side}`], LIMB.upperArm, LIMB.forearm, wristTarget, pole, new THREE.Vector3(0, 0, 1));
        // Hand plat op de vloer, vingers naar voren
        aim(rig.b[`wrist${side}`], new THREE.Vector3(0, 0, 1), new THREE.Vector3(0, -1, 0));
        void S;
      }
      // Hoofd in het verlengde van de romp, blik iets naar voren
      rig.b.neck.rotation.x = -0.15;

      const load = 0.35 + 0.65 * depth;
      return {
        borst: load,
        schouders: 0.25 + 0.55 * depth,
        triceps: variant === 'smal' ? 0.45 + 0.55 * depth : 0.3 + 0.6 * depth,
        buik: 0.55,
        billen: 0.3,
        bovenbenen: 0.25,
        onderarmen: 0.15,
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Register: oefeningnaam uit het schema -> beweging
// ---------------------------------------------------------------------------

const MOTIONS: Record<string, () => Motion> = {
  'pushup-normaal': () => pushupFactory('normaal'),
  'pushup-smal': () => pushupFactory('smal'),
  'pushup-breed': () => pushupFactory('breed'),
};

export function getMotion(key: string): Motion | null {
  return MOTIONS[key]?.() ?? null;
}
