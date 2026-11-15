import * as THREE from 'three';
import { aim, resetPose, solveTwoBone, worldPos, LIMB, type Intensity, type Rig } from './rig';

// ---------------------------------------------------------------------------
// Bewegingen per oefening. Elke beweging is een lus van `cycle` seconden.
// pose() zet de pop (en de spullen) neer en geeft terug hoe zwaar elke spier werkt.
// Links = +X, rechts = -X. De pop kijkt naar +Z.
// ---------------------------------------------------------------------------

export interface Cue { from: number; to: number; text: string }

export type PropName = 'kb' | 'bar' | 'band' | 'step' | 'post';

export interface Props {
  kb: THREE.Group;
  bar: THREE.Group;
  bandL: THREE.Mesh;
  bandR: THREE.Mesh;
  step: THREE.Mesh;
  post: THREE.Group;
}

export interface Motion {
  key: string;
  title: string;
  cycle: number;
  cues: Cue[];
  focus: [number, number, number];
  camera: [number, number, number];
  props: PropName[];
  /** Mat onder de pop: lengte langs Z en midden. */
  mat?: { length: number; z: number } | null;
  pose: (rig: Rig, t: number, p: Props) => Intensity;
}

const V = (x: number, y: number, z: number) => new THREE.Vector3(x, y, z);
const ease = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x * x * (3 - 2 * x));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const lerpV = (a: THREE.Vector3, b: THREE.Vector3, t: number) => a.clone().lerp(b, t);

/** 0 = beginstand, 1 = eindstand: heen, vasthouden, terug, rust. */
function phase(t: number, go: number, hold: number, back: number, rest: number) {
  const total = go + hold + back + rest;
  const x = ((t % total) + total) % total;
  if (x < go) return ease(x / go);
  if (x < go + hold) return 1;
  if (x < go + hold + back) return 1 - ease((x - go - hold) / back);
  return 0;
}

const SIDES = [['L', 1], ['R', -1]] as const;
const STAND_Y = 0.95;
const ANKLE_Y = 0.075;

function arm(rig: Rig, side: 'L' | 'R', target: THREE.Vector3, pole: THREE.Vector3, front = V(0, 0, 1)) {
  solveTwoBone(rig.b[`shoulder${side}`], rig.b[`elbow${side}`], LIMB.upperArm, LIMB.forearm, target, pole, front);
}

function leg(rig: Rig, side: 'L' | 'R', ankle: THREE.Vector3, pole: THREE.Vector3) {
  solveTwoBone(rig.b[`hip${side}`], rig.b[`knee${side}`], LIMB.thigh, LIMB.shin, ankle, pole, V(0, 0, 1), true);
}

function footFlat(rig: Rig, side: 'L' | 'R', forward = V(0, 0, 1)) {
  aim(rig.b[`ankle${side}`], V(0, -1, 0), forward);
}

/** Staan of hurken: bekken op hoogte y, voeten plat op heupbreedte. */
function stand(rig: Rig, opts: { y?: number; z?: number; hinge?: number; lean?: number; stance?: number; feetZ?: [number, number]; knees?: number } = {}) {
  resetPose(rig);
  rig.root.position.set(0, opts.y ?? STAND_Y, opts.z ?? 0);
  rig.b.pelvis.rotation.x = opts.hinge ?? 0;
  rig.b.spine.rotation.x = opts.lean ?? 0;
  rig.root.updateMatrixWorld(true);
  const w = opts.stance ?? 0.11;
  const fz = opts.feetZ ?? [0, 0];
  const kx = opts.knees ?? 0.25;
  SIDES.forEach(([side, sx], i) => {
    leg(rig, side, V(sx * w, ANKLE_Y, fz[i]), V(sx * kx, 0, 1));
    footFlat(rig, side, V(sx * 0.12, 0, 1));
  });
}

function local(o: THREE.Object3D, v: THREE.Vector3) {
  o.updateWorldMatrix(true, false);
  return o.localToWorld(v.clone());
}

function mid(a: THREE.Object3D, b: THREE.Object3D) {
  return worldPos(a).add(worldPos(b)).multiplyScalar(0.5);
}

/** Kettlebell: de oorsprong is het midden van de handgreep, de bol hangt eronder (lokale -Y). */
function placeKb(p: Props, grip: THREE.Vector3, down: THREE.Vector3 = V(0, -1, 0), side: THREE.Vector3 = V(1, 0, 0)) {
  p.kb.position.copy(grip);
  const y = down.clone().normalize().negate();
  const x = side.clone().sub(y.clone().multiplyScalar(side.dot(y))).normalize();
  const z = new THREE.Vector3().crossVectors(x, y);
  p.kb.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(x, y, z));
}

/** Band als dun staafje tussen twee punten. */
function segment(mesh: THREE.Mesh, a: THREE.Vector3, b: THREE.Vector3) {
  const d = b.clone().sub(a);
  mesh.position.copy(a).add(b).multiplyScalar(0.5);
  mesh.scale.set(1, Math.max(0.001, d.length()), 1);
  mesh.quaternion.setFromUnitVectors(V(0, 1, 0), d.normalize());
}

// ---------------------------------------------------------------------------
// Push-up (normaal, smal/diamant, breed, voeten verhoogd)
// ---------------------------------------------------------------------------

const STEP_H = 0.2;

function plankRoot(rig: Rig, tilt: number, toeY: number) {
  rig.root.position.set(0, 0, 0);
  rig.root.rotation.set(Math.PI / 2 - tilt, 0, 0);
  rig.root.updateMatrixWorld(true);
  const toe = mid(rig.toeL, rig.toeR);
  rig.root.position.sub(toe).add(V(0, toeY, 0));
  rig.root.updateMatrixWorld(true);
}
const shoulderY = (rig: Rig) => (worldPos(rig.b.shoulderL).y + worldPos(rig.b.shoulderR).y) / 2;

function solvePlank(rig: Rig, target: number, toeY: number) {
  let lo = -0.4, hi = 0.75;
  for (let i = 0; i < 24; i++) {
    const m = (lo + hi) / 2;
    plankRoot(rig, m, toeY);
    if (shoulderY(rig) > target) hi = m; else lo = m;
  }
  plankRoot(rig, (lo + hi) / 2, toeY);
}

function pushup(variant: 'normaal' | 'smal' | 'breed' | 'verhoogd', slow: boolean): Motion {
  const handWidth = variant === 'smal' ? 0.07 : variant === 'breed' ? 0.34 : 0.22;
  const toeY = variant === 'verhoogd' ? STEP_H + 0.015 : 0.015;
  const top = LIMB.upperArm + LIMB.forearm + 0.02;
  const bottom = 0.17;
  const down = slow ? 3 : 1.8;
  let handZ: number | null = null;
  return {
    key: `pushup-${variant}${slow ? '-slow' : ''}`,
    title: variant === 'smal' ? 'Diamant push-up' : variant === 'breed' ? 'Push-up, brede greep' : variant === 'verhoogd' ? 'Push-up, voeten verhoogd' : 'Push-up',
    cycle: down + 0.4 + 1.0 + 1.8,
    props: variant === 'verhoogd' ? ['step'] : [],
    focus: variant === 'verhoogd' ? [0, 0.3, 0.8] : [0, 0.24, 0.92],
    camera: variant === 'verhoogd' ? [3.1, 1.3, 1.1] : [2.5, 0.95, 1.45],
    cues: [
      { from: 0, to: down, text: slow ? '3 tellen zakken. Ellebogen schuin naar achteren, niet wijd.' : variant === 'smal' ? 'Zakken met je handen dicht bij elkaar. Ellebogen langs je lichaam.' : 'Zakken, gecontroleerd. Ellebogen schuin naar achteren, niet wijd.' },
      { from: down, to: down + 0.4, text: 'Borst net boven de vloer. Romp blijft een rechte plank.' },
      { from: down + 0.4, to: down + 1.4, text: 'Omhoog duwen en uitademen. Billen niet laten zakken.' },
      { from: down + 1.4, to: down + 3.2, text: variant === 'verhoogd' ? 'Voeten op de verhoging: meer werk voor je schouders en bovenkant borst.' : 'Bovenin: armen gestrekt, schouders weg van je oren.' },
    ],
    pose(rig, t, p) {
      resetPose(rig);
      if (handZ === null) {
        solvePlank(rig, top, toeY);
        handZ = (worldPos(rig.b.shoulderL).z + worldPos(rig.b.shoulderR).z) / 2;
      }
      const d = phase(t, down, 0.4, 1.0, 1.8);
      solvePlank(rig, lerp(top, bottom, d), toeY);
      for (const [side, sx] of SIDES) {
        const pole = V(sx * (variant === 'breed' ? 0.9 : variant === 'smal' ? 0.2 : 0.45), 0.4, -1);
        arm(rig, side, V(sx * handWidth, 0.05, handZ - 0.02), pole);
        aim(rig.b[`wrist${side}`], V(0, 0, 1), V(0, -1, 0));
      }
      rig.b.neck.rotation.x = -0.15;
      if (variant === 'verhoogd') {
        const toe = mid(rig.toeL, rig.toeR);
        p.step.position.set(0, STEP_H / 2, toe.z - 0.05);
      }
      return {
        borst: variant === 'smal' ? 0.25 + 0.5 * d : 0.35 + 0.65 * d,
        schouders: variant === 'verhoogd' ? 0.4 + 0.6 * d : 0.25 + 0.55 * d,
        triceps: variant === 'smal' ? 0.5 + 0.5 * d : 0.3 + 0.6 * d,
        buik: 0.55, billen: 0.3, bovenbenen: 0.25, onderarmen: 0.15,
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Goblet squat
// ---------------------------------------------------------------------------

function gobletSquat(slow: boolean): Motion {
  const down = slow ? 3 : 1.8;
  return {
    key: slow ? 'squat-slow' : 'squat',
    title: 'Goblet squat',
    cycle: down + 0.5 + 1.2 + 1.3,
    props: ['kb'],
    mat: null,
    focus: [0, 0.75, 0],
    camera: [2.3, 1.3, 2.2],
    cues: [
      { from: 0, to: down, text: slow ? '3 tellen zakken. Heupen naar achteren en omlaag, borst omhoog.' : 'Zakken: heupen naar achteren en omlaag, borst omhoog.' },
      { from: down, to: down + 0.5, text: 'Onderin: knieën in de richting van je tenen, hielen op de grond.' },
      { from: down + 0.5, to: down + 1.7, text: 'Omhoog duwen vanuit je hielen. Billen aanspannen.' },
      { from: down + 1.7, to: down + 3, text: 'Bovenin: rechtop, kettlebell tegen je borst.' },
    ],
    pose(rig, t, p) {
      const d = phase(t, down, 0.5, 1.2, 1.3);
      stand(rig, { y: lerp(STAND_Y - 0.01, 0.52, d), z: lerp(0, -0.2, d), hinge: 0.6 * d, lean: -0.2 * d, stance: 0.16, knees: 0.4 });
      for (const [side, sx] of SIDES) {
        arm(rig, side, local(rig.b.chest, V(sx * 0.055, 0.05, 0.24)), V(sx * 0.6, -1, -0.1));
        aim(rig.b[`wrist${side}`], V(0, 1, 0), V(-sx, 0, 0));
      }
      const grip = mid(rig.palmL, rig.palmR);
      placeKb(p, grip, V(0, -1, 0));
      return { bovenbenen: 0.35 + 0.65 * d, billen: 0.3 + 0.65 * d, hamstrings: 0.15 + 0.3 * d, buik: 0.45, rug: 0.25, onderarmen: 0.3, schouders: 0.2, biceps: 0.25, kuiten: 0.2 };
    },
  };
}

// ---------------------------------------------------------------------------
// Pull-up en chin-up
// ---------------------------------------------------------------------------

export const BAR_Y = 2.2;

function pullup(chin: boolean, slow: boolean): Motion {
  const grip = chin ? 0.16 : 0.34;
  const down = slow ? 3 : 1.6;
  return {
    key: `${chin ? 'chinup' : 'pullup'}${slow ? '-slow' : ''}`,
    title: chin ? 'Chin-up' : 'Pull-up',
    cycle: 1.4 + 0.5 + down + 0.8,
    props: ['bar'],
    mat: null,
    focus: [0, 1.4, 0],
    camera: [2.3, 1.75, 2.6],
    cues: [
      { from: 0, to: 1.4, text: chin ? 'Optrekken met je handpalmen naar je toe. Ellebogen naar je heupen.' : 'Optrekken: schouderbladen eerst omlaag, dan ellebogen naar je zij.' },
      { from: 1.4, to: 1.9, text: 'Kin boven de stang. Niet zwaaien met je benen.' },
      { from: 1.9, to: 1.9 + down, text: slow ? '3 tellen zakken, gecontroleerd tot gestrekte armen.' : 'Gecontroleerd zakken tot je armen bijna gestrekt zijn.' },
      { from: 1.9 + down, to: 2.7 + down, text: 'Onderin: even hangen, schouders actief.' },
    ],
    pose(rig, t) {
      const up = phase(t, 1.4, 0.5, down, 0.8);
      resetPose(rig);
      const reach = LIMB.upperArm + LIMB.forearm + 0.02;
      const shoulderOffset = 0.52; // schouder boven root (bekken)
      const handY = BAR_Y - 0.02;
      const sBottom = handY - Math.sqrt(reach * reach - (grip - 0.195) ** 2);
      const sTop = BAR_Y - 0.2;
      const sy = lerp(sBottom, sTop, up);
      rig.root.position.set(0, sy - shoulderOffset, lerp(-0.02, -0.07, up));
      rig.b.spine.rotation.x = -0.1 * up;
      for (const [side] of SIDES) {
        rig.b[`hip${side}`].rotation.set(-0.2, 0, 0);
        rig.b[`knee${side}`].rotation.set(0.7, 0, 0);
        rig.b[`ankle${side}`].rotation.set(0.45, 0, 0);
      }
      rig.root.updateMatrixWorld(true);
      for (const [side, sx] of SIDES) {
        const pole = chin ? V(sx * 0.3, -0.5, 1) : V(sx * 1, -0.4, 0.1);
        arm(rig, side, V(sx * grip, handY, 0), pole, V(0, 0, chin ? -1 : 1));
        aim(rig.b[`wrist${side}`], V(0, 1, 0), V(0, 0, chin ? -1 : 1));
      }
      rig.b.neck.rotation.x = -0.15 * up;
      return {
        rug: 0.45 + 0.55 * up, trapezius: 0.3 + 0.4 * up, biceps: chin ? 0.45 + 0.55 * up : 0.3 + 0.45 * up,
        onderarmen: 0.65, schouders: 0.2 + 0.25 * up, buik: 0.35,
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Eenarmige row (rechterarm)
// ---------------------------------------------------------------------------

function row(): Motion {
  return {
    key: 'row',
    title: 'Eenarmige row',
    cycle: 1.0 + 0.5 + 1.6 + 0.6,
    props: ['kb'],
    mat: null,
    focus: [0, 0.7, 0.1],
    camera: [-2.5, 1.3, 1.4],
    cues: [
      { from: 0, to: 1.0, text: 'Trek de kettlebell naar je heup. Elleboog langs je lichaam naar achteren.' },
      { from: 1.0, to: 1.5, text: 'Bovenin: schouderblad naar achteren, rug blijft plat.' },
      { from: 1.5, to: 3.1, text: 'Rustig laten zakken tot je arm gestrekt is.' },
      { from: 3.1, to: 3.7, text: 'Heupen naar achteren, rug plat, andere hand op je knie.' },
    ],
    pose(rig, t, p) {
      const up = phase(t, 1.0, 0.5, 1.6, 0.6);
      stand(rig, { y: 0.84, z: -0.14, hinge: 1.0, lean: 0.0, stance: 0.15, feetZ: [0.2, -0.12], knees: 0.2 });
      rig.b.neck.rotation.x = -0.35;
      rig.root.updateMatrixWorld(true);
      const S = worldPos(rig.b.shoulderR);
      const bottom = S.clone().add(V(0.0, -0.55, 0.04));
      const top = S.clone().add(V(-0.03, -0.27, -0.3));
      arm(rig, 'R', lerpV(bottom, top, up), V(-0.2, 1, -0.7));
      aim(rig.b.wristR, worldPos(rig.b.wristR).sub(worldPos(rig.b.elbowR)), V(1, 0, 0));
      const knee = worldPos(rig.b.kneeL);
      arm(rig, 'L', knee.add(V(0.0, 0.06, 0.03)), V(0.9, 0.3, -0.5));
      placeKb(p, worldPos(rig.palmR), V(0, -1, 0), V(0, 0, 1));
      return {
        'rug:R': 0.45 + 0.55 * up, 'rug:L': 0.2, trapezius: 0.3 + 0.45 * up, 'biceps:R': 0.25 + 0.45 * up,
        'onderarmen:R': 0.55, 'schouders:R': 0.2 + 0.35 * up, buik: 0.4, hamstrings: 0.3, billen: 0.25,
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Kettlebell curl (twee handen aan de handgreep, bol omlaag)
// ---------------------------------------------------------------------------

function curl(slow: boolean): Motion {
  const down = slow ? 3 : 1.6;
  return {
    key: slow ? 'curl-slow' : 'curl',
    title: 'Kettlebell curl',
    cycle: 1.2 + 0.4 + down + 0.5,
    props: ['kb'],
    mat: null,
    focus: [0, 1.0, 0],
    camera: [2.1, 1.35, 2.3],
    cues: [
      { from: 0, to: 1.2, text: 'Omhoog krullen. Ellebogen blijven tegen je zij.' },
      { from: 1.2, to: 1.6, text: 'Bovenin even aanspannen. Niet naar achteren leunen.' },
      { from: 1.6, to: 1.6 + down, text: slow ? '3 tellen zakken.' : 'Rustig laten zakken.' },
      { from: 1.6 + down, to: 2.1 + down, text: 'Onderin: armen bijna gestrekt.' },
    ],
    pose(rig, t, p) {
      const up = phase(t, 1.2, 0.4, down, 0.5);
      stand(rig);
      const phi = lerp(0.25, 2.2, up);
      for (const [side, sx] of SIDES) {
        const S = worldPos(rig.b[`shoulder${side}`]);
        const E = S.clone().add(V(-sx * 0.035, -LIMB.upperArm + 0.01, 0.02));
        const l = Math.max(-0.6, Math.min(0.6, (sx * 0.065 - E.x) / LIMB.forearm));
        const k = Math.sqrt(1 - l * l);
        const dir = V(l, -Math.cos(phi) * k, Math.sin(phi) * k);
        arm(rig, side, E.clone().add(dir.multiplyScalar(LIMB.forearm)), V(sx * 0.15, -0.3, -1));
        const fore = worldPos(rig.b[`wrist${side}`]).sub(worldPos(rig.b[`elbow${side}`]));
        aim(rig.b[`wrist${side}`], fore, V(0, 1, 0.2));
      }
      const grip = mid(rig.palmL, rig.palmR);
      placeKb(p, grip, V(0, -1, 0));
      return { biceps: 0.35 + 0.65 * Math.sin(Math.min(Math.PI / 2, phi * 0.85)), onderarmen: 0.55, schouders: 0.2, buik: 0.3 };
    },
  };
}

// ---------------------------------------------------------------------------
// Face pulls met band
// ---------------------------------------------------------------------------

function facePull(): Motion {
  const anchor = V(0, 1.55, 1.3);
  return {
    key: 'facepull',
    title: 'Face pulls met band',
    cycle: 1.0 + 0.6 + 1.4 + 0.5,
    props: ['band', 'post'],
    mat: null,
    focus: [0, 1.25, 0.5],
    camera: [2.4, 1.7, 1.9],
    cues: [
      { from: 0, to: 1.0, text: 'Trek de band naar je gezicht. Ellebogen hoog en naar buiten.' },
      { from: 1.0, to: 1.6, text: 'Handen naast je oren, schouderbladen samen.' },
      { from: 1.6, to: 3.0, text: 'Rustig terug tot je armen gestrekt zijn.' },
      { from: 3.0, to: 3.5, text: 'Band vast op ooghoogte. Rechtop staan.' },
    ],
    pose(rig, t, p) {
      const pull = phase(t, 1.0, 0.6, 1.4, 0.5);
      stand(rig);
      p.post.position.set(anchor.x, 0, anchor.z + 0.03);
      for (const [side, sx] of SIDES) {
        const start = V(sx * 0.1, 1.46, 0.6);
        const end = V(sx * 0.26, 1.6, 0.1);
        arm(rig, side, lerpV(start, end, pull), V(sx * 1, 0.5, -0.3));
        aim(rig.b[`wrist${side}`], anchor.clone().sub(worldPos(rig.b[`wrist${side}`])), V(0, 1, 0));
      }
      segment(p.bandL, anchor, worldPos(rig.palmL));
      segment(p.bandR, anchor, worldPos(rig.palmR));
      return { schouders: 0.35 + 0.6 * pull, trapezius: 0.35 + 0.6 * pull, rug: 0.3, biceps: 0.2, onderarmen: 0.3, buik: 0.2 };
    },
  };
}

// ---------------------------------------------------------------------------
// Floor press (rechterarm, liggend op de rug)
// ---------------------------------------------------------------------------

function floorPress(pause: boolean): Motion {
  const hold = pause ? 2 : 0.4;
  return {
    key: pause ? 'floorpress-pause' : 'floorpress',
    title: 'Floor press',
    cycle: 1.6 + hold + 1.0 + 0.8,
    props: ['kb'],
    mat: { length: 1.85, z: 0 },
    focus: [0, 0.22, 0.3],
    camera: [-2.2, 1.55, 1.2],
    cues: [
      { from: 0, to: 1.6, text: 'Laten zakken tot je bovenarm de vloer raakt. Elleboog schuin langs je lichaam.' },
      { from: 1.6, to: 1.6 + hold, text: pause ? 'Onderin 2 tellen stil, niet ontspannen.' : 'Bovenarm raakt de vloer.' },
      { from: 1.6 + hold, to: 2.6 + hold, text: 'Recht omhoog duwen boven je schouder. Pols recht.' },
      { from: 2.6 + hold, to: 3.4 + hold, text: 'Bovenin: arm gestrekt, schouder blijft op de vloer.' },
    ],
    pose(rig, t, p) {
      const d = phase(t, 1.6, hold, 1.0, 0.8); // 1 = onder
      resetPose(rig);
      rig.root.rotation.set(-Math.PI / 2, 0, 0); // op de rug, hoofd naar -Z, voorkant omhoog
      rig.root.position.set(0, 0.1, 0.2);
      rig.root.updateMatrixWorld(true);
      for (const [side, sx] of SIDES) {
        leg(rig, side, V(sx * 0.17, ANKLE_Y, 0.85), V(sx * 0.2, 1, 0));
        footFlat(rig, side);
      }
      const S = worldPos(rig.b.shoulderR);
      const top = S.clone().add(V(0.02, LIMB.upperArm + LIMB.forearm - 0.02, 0));
      const bottom = S.clone().add(V(-0.17, 0.25, 0.18));
      arm(rig, 'R', lerpV(top, bottom, d), V(-1, -0.35, 0.6));
      aim(rig.b.wristR, V(0, 1, 0), V(1, 0, 0));
      // Linkerarm ontspannen naast het lichaam
      const SL = worldPos(rig.b.shoulderL);
      arm(rig, 'L', SL.clone().add(V(0.22, -0.03, 0.5)), V(1, 0.4, 0));
      placeKb(p, worldPos(rig.palmR), V(0, 0, 1).add(V(0, -0.35, 0)), V(1, 0, 0));
      return { 'borst:R': 0.35 + 0.6 * d, 'borst:L': 0.15, 'triceps:R': 0.5 + 0.4 * (1 - d), 'schouders:R': 0.3 + 0.4 * d, 'onderarmen:R': 0.3, buik: 0.3 };
    },
  };
}

// ---------------------------------------------------------------------------
// Strikte press (rechterarm, staand)
// ---------------------------------------------------------------------------

function press(): Motion {
  return {
    key: 'press',
    title: 'Strikte press',
    cycle: 1.2 + 0.5 + 1.6 + 0.7,
    props: ['kb'],
    mat: null,
    focus: [0, 1.2, 0],
    camera: [-2.1, 1.5, 2.4],
    cues: [
      { from: 0, to: 1.2, text: 'Recht omhoog drukken. Billen en buik aanspannen, niet achterover leunen.' },
      { from: 1.2, to: 1.7, text: 'Bovenin: arm gestrekt naast je oor.' },
      { from: 1.7, to: 3.3, text: 'Gecontroleerd terug naar je schouder.' },
      { from: 3.3, to: 4.0, text: 'Startpositie: kettlebell tegen je onderarm, pols recht.' },
    ],
    pose(rig, t, p) {
      const up = phase(t, 1.2, 0.5, 1.6, 0.7);
      stand(rig);
      const S = worldPos(rig.b.shoulderR);
      const rack = S.clone().add(V(0.07, -0.04, 0.15));
      const top = S.clone().add(V(0.01, LIMB.upperArm + LIMB.forearm - 0.03, 0.02));
      arm(rig, 'R', lerpV(rack, top, up), V(-0.3, -1, 0.6));
      aim(rig.b.wristR, worldPos(rig.b.wristR).sub(worldPos(rig.b.elbowR)), V(0, 0, 1));
      rig.b.shoulderL.rotation.set(0, 0, 0.12);
      rig.b.elbowL.rotation.set(-0.15, 0, 0);
      const fore = worldPos(rig.b.wristR).sub(worldPos(rig.b.elbowR)).normalize();
      // Bol ligt achter de onderarm
      const down = fore.clone().negate().multiplyScalar(0.3).add(V(0, 0, -1)).normalize();
      placeKb(p, worldPos(rig.palmR), down, V(1, 0, 0));
      const s = Math.sin(Math.PI * up);
      return { 'schouders:R': 0.45 + 0.4 * s + 0.15 * up, 'schouders:L': 0.15, 'triceps:R': 0.25 + 0.7 * up, trapezius: 0.3, buik: 0.5, billen: 0.35, 'onderarmen:R': 0.35 };
    },
  };
}

// ---------------------------------------------------------------------------
// Zijwaarts heffen met band
// ---------------------------------------------------------------------------

function lateralRaise(): Motion {
  return {
    key: 'lateral',
    title: 'Zijwaarts heffen met band',
    cycle: 1.1 + 0.4 + 1.6 + 0.5,
    props: ['band'],
    mat: null,
    focus: [0, 1.05, 0],
    camera: [0.9, 1.4, 3.0],
    cues: [
      { from: 0, to: 1.1, text: 'Armen zijwaarts omhoog tot schouderhoogte. Ellebogen licht gebogen.' },
      { from: 1.1, to: 1.5, text: 'Bovenin: schouders laag houden, niet optrekken.' },
      { from: 1.5, to: 3.1, text: 'Langzaam laten zakken tegen de band in.' },
      { from: 3.1, to: 3.6, text: 'Sta met beide voeten op het midden van de band.' },
    ],
    pose(rig, t, p) {
      const u = phase(t, 1.1, 0.4, 1.6, 0.5);
      stand(rig);
      const th = lerp(0.12, 1.45, u);
      for (const [side, sx] of SIDES) {
        rig.b[`shoulder${side}`].rotation.set(-0.08, 0, sx * th);
        rig.b[`elbow${side}`].rotation.set(-0.3, 0, 0);
      }
      rig.root.updateMatrixWorld(true);
      segment(p.bandL, V(0.07, 0.02, 0.04), worldPos(rig.palmL));
      segment(p.bandR, V(-0.07, 0.02, 0.04), worldPos(rig.palmR));
      return { schouders: 0.3 + 0.7 * u, trapezius: 0.2 + 0.3 * u, buik: 0.25, onderarmen: 0.2 };
    },
  };
}

// ---------------------------------------------------------------------------
// Triceps extensie boven het hoofd
// ---------------------------------------------------------------------------

function tricepsExt(): Motion {
  return {
    key: 'triceps',
    title: 'Triceps extensie',
    cycle: 1.6 + 0.4 + 1.1 + 0.5,
    props: ['kb'],
    mat: null,
    focus: [0, 1.4, 0],
    camera: [2.1, 1.7, 2.3],
    cues: [
      { from: 0, to: 1.6, text: 'Kettlebell achter je hoofd laten zakken. Ellebogen blijven naar voren wijzen.' },
      { from: 1.6, to: 2.0, text: 'Onderin: voel de rek achter in je bovenarm.' },
      { from: 2.0, to: 3.1, text: 'Strekken tot boven je hoofd. Alleen je onderarmen bewegen.' },
      { from: 3.1, to: 3.6, text: 'Buik aan, niet in je onderrug hangen.' },
    ],
    pose(rig, t, p) {
      const d = phase(t, 1.6, 0.4, 1.1, 0.5); // 1 = gebogen
      stand(rig);
      const phi = lerp(0.1, 2.35, d);
      for (const [side, sx] of SIDES) {
        const S = worldPos(rig.b[`shoulder${side}`]);
        const E = S.clone().add(V(-sx * 0.08, LIMB.upperArm - 0.02, 0.07));
        const l = Math.max(-0.6, Math.min(0.6, (sx * 0.06 - E.x) / LIMB.forearm));
        const k = Math.sqrt(1 - l * l);
        const dir = V(l, Math.cos(phi) * k, -Math.sin(phi) * k);
        arm(rig, side, E.clone().add(dir.multiplyScalar(LIMB.forearm)), V(sx * 0.3, 1, 0.8));
        const fore = worldPos(rig.b[`wrist${side}`]).sub(worldPos(rig.b[`elbow${side}`]));
        aim(rig.b[`wrist${side}`], fore, V(0, 0, 1));
      }
      const grip = mid(rig.palmL, rig.palmR);
      placeKb(p, grip, V(0, -1, 0), V(1, 0, 0));
      return { triceps: 0.4 + 0.55 * d, schouders: 0.3, buik: 0.4, onderarmen: 0.3 };
    },
  };
}

// ---------------------------------------------------------------------------
// Kuitheffen op 1 been (rechts), bal van de voet op een verhoging
// ---------------------------------------------------------------------------

function calfRaise(): Motion {
  return {
    key: 'calf',
    title: 'Kuitheffen op 1 been',
    cycle: 1.0 + 0.6 + 1.8 + 0.4,
    props: ['step'],
    mat: null,
    focus: [0, 0.95, 0.05],
    camera: [2.5, 1.35, 1.7],
    cues: [
      { from: 0, to: 1.0, text: 'Omhoog op je tenen, zo hoog als je kunt.' },
      { from: 1.0, to: 1.6, text: 'Bovenin even vasthouden.' },
      { from: 1.6, to: 3.4, text: 'Langzaam zakken tot je hiel onder de rand hangt.' },
      { from: 3.4, to: 3.8, text: 'Onderin: rek in je kuit, knie bijna gestrekt. Hand tegen de muur mag.' },
    ],
    pose(rig, t, p) {
      const u = phase(t, 1.0, 0.6, 1.8, 0.4);
      resetPose(rig);
      rig.root.position.set(0, STAND_Y + STEP_H, 0);
      rig.b.hipL.rotation.set(-0.15, 0, 0);
      rig.b.kneeL.rotation.set(1.4, 0, 0);
      rig.b.ankleL.rotation.set(0.5, 0, 0);
      rig.b.kneeR.rotation.set(0.05, 0, 0);
      rig.b.ankleR.rotation.set(lerp(-0.3, 0.65, u), 0, 0);
      rig.b.shoulderL.rotation.set(-0.15, 0, 0.12);
      rig.b.shoulderR.rotation.set(-0.15, 0, -0.12);
      rig.root.updateMatrixWorld(true);
      // Bal van de voet blijft op de rand van de verhoging
      const toe = worldPos(rig.toeR);
      rig.root.position.y += STEP_H + 0.02 - toe.y;
      rig.root.position.z += 0.24 - toe.z; // voorvoet op de tree, hiel hangt erachter
      rig.root.updateMatrixWorld(true);
      p.step.position.set(-0.02, STEP_H / 2, 0.22);
      return { 'kuiten:R': 0.35 + 0.65 * u, 'kuiten:L': 0.05, buik: 0.25, 'billen:R': 0.25, 'bovenbenen:R': 0.2 };
    },
  };
}

// ---------------------------------------------------------------------------
// Register
// ---------------------------------------------------------------------------

const MOTIONS: Record<string, () => Motion> = {
  'pushup-normaal': () => pushup('normaal', false),
  'pushup-normaal-slow': () => pushup('normaal', true),
  'pushup-smal': () => pushup('smal', false),
  'pushup-breed': () => pushup('breed', false),
  'pushup-verhoogd': () => pushup('verhoogd', false),
  'pushup-verhoogd-slow': () => pushup('verhoogd', true),
  squat: () => gobletSquat(false),
  'squat-slow': () => gobletSquat(true),
  pullup: () => pullup(false, false),
  'pullup-slow': () => pullup(false, true),
  chinup: () => pullup(true, false),
  'chinup-slow': () => pullup(true, true),
  row: () => row(),
  curl: () => curl(false),
  'curl-slow': () => curl(true),
  facepull: () => facePull(),
  floorpress: () => floorPress(false),
  'floorpress-pause': () => floorPress(true),
  press: () => press(),
  lateral: () => lateralRaise(),
  triceps: () => tricepsExt(),
  calf: () => calfRaise(),
};

export const MOTION_KEYS = Object.keys(MOTIONS);

export function getMotion(key: string): Motion | null {
  return MOTIONS[key]?.() ?? null;
}
