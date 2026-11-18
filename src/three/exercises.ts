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
const ANKLE_Y = 0.075;
const LEG = LIMB.thigh + LIMB.shin;
/** Hoogte van het bekken waarbij de benen bijna gestrekt zijn (knie ~170 graden). */
function standY(stance = 0.11, dz = 0) {
  const d = LEG - 0.006;
  return ANKLE_Y + Math.sqrt(d * d - (stance - 0.095) ** 2 - dz * dz) + 0.02;
}
const STAND_Y = standY();

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
  rig.root.position.set(0, opts.y ?? standY(opts.stance ?? 0.11), opts.z ?? 0);
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
  const top = 0.05 + LIMB.upperArm + LIMB.forearm - 0.006; // armen gestrekt
  const bottom = 0.17; // borst ongeveer 6 cm boven de vloer
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
      { from: 0, to: down, text: (slow ? '3 tellen zakken. ' : 'Zakken. ') + (variant === 'smal' ? 'Handen dicht bij elkaar, ellebogen langs je lichaam.' : 'Ellebogen schuin naar achteren, zo’n 45 graden van je romp. Van bovenaf een pijl, geen T.') },
      { from: down, to: down + 0.4, text: 'Borst net boven de vloer. Romp blijft een rechte plank.' },
      { from: down + 0.4, to: down + 1.4, text: 'Omhoog duwen en uitademen. Billen niet laten zakken.' },
      { from: down + 1.4, to: down + 3.2, text: variant === 'verhoogd' ? 'Voeten op de verhoging: meer werk voor je schouders en bovenkant borst.' : 'Bovenin: armen gestrekt, handen onder je schouders, schouders weg van je oren.' },
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
        const pole = V(sx * (variant === 'breed' ? 1.4 : variant === 'smal' ? 0.25 : 0.85), 0.4, -1);
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
      { from: down, to: down + 0.5, text: 'Onderin: heupen tot kniehoogte of lager, ellebogen binnen je knieën, hielen op de grond.' },
      { from: down + 0.5, to: down + 1.7, text: 'Omhoog duwen vanuit je hielen. Billen aanspannen.' },
      { from: down + 1.7, to: down + 3, text: 'Bovenin: rechtop, kettlebell aan de hoorns tegen je borst, ellebogen omlaag.' },
    ],
    pose(rig, t, p) {
      const d = phase(t, down, 0.5, 1.2, 1.3);
      stand(rig, { y: lerp(standY(0.17), 0.39, d), z: lerp(0, -0.17, d), hinge: 0.7 * d, lean: -0.32 * d, stance: 0.17, knees: lerp(0.4, 0.75, d) });
      for (const [side, sx] of SIDES) {
        arm(rig, side, local(rig.b.chest, V(sx * 0.055, 0.04, 0.23)), V(sx * 0.15, -1, 0.1));
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
  const grip = chin ? 0.2 : 0.26; // chin-up op schouderbreedte, pull-up iets breder
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
      { from: 1.4, to: 1.9, text: 'Kin boven de stang zonder je nek te strekken. Niet zwaaien.' },
      { from: 1.9, to: 1.9 + down, text: slow ? '3 tellen zakken, gecontroleerd tot gestrekte armen.' : 'Gecontroleerd zakken tot je armen gestrekt zijn.' },
      { from: 1.9 + down, to: 2.7 + down, text: 'Onderin: armen helemaal gestrekt. Elke herhaling begint vanuit hangen.' },
    ],
    pose(rig, t) {
      const up = phase(t, 1.4, 0.5, down, 0.8);
      resetPose(rig);
      const reach = LIMB.upperArm + LIMB.forearm - 0.004; // dead hang: armen gestrekt
      const shoulderOffset = 0.52; // schouder boven root (bekken)
      const handY = BAR_Y - 0.02;
      const sBottom = handY - Math.sqrt(reach * reach - (grip - 0.195) ** 2);
      const sTop = BAR_Y - 0.1; // kin net boven de stang
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
        const pole = chin ? V(sx * 0.3, -0.6, 1) : V(sx * 0.75, -0.6, 0.5);
        arm(rig, side, V(sx * grip, handY, 0), pole, V(0, 0, chin ? -1 : 1));
        aim(rig.b[`wrist${side}`], V(0, 1, 0), V(0, 0, chin ? -1 : 1));
      }
      rig.b.neck.rotation.x = 0; // hoofd neutraal, niet met je kin naar de stang reiken
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
      { from: 0, to: 1.0, text: 'Trek de kettlebell naar je heup, niet naar je borst. Elleboog dicht langs je lichaam.' },
      { from: 1.0, to: 1.5, text: 'Bovenin: schouderblad naar achteren, niet draaien met je romp of schouder optrekken.' },
      { from: 1.5, to: 3.1, text: 'Rustig laten zakken tot je arm gestrekt is.' },
      { from: 3.1, to: 3.7, text: 'Rug plat en bijna horizontaal, hand steunt op je bovenbeen, kijk naar de vloer.' },
    ],
    pose(rig, t, p) {
      const up = phase(t, 1.0, 0.5, 1.6, 0.6);
      // Spreidstand, linkervoet voor. Romp bijna horizontaal (ca. 15-20 graden), rug plat.
      stand(rig, { y: 0.8, z: -0.12, hinge: 1.15, lean: 0.12, stance: 0.15, feetZ: [0.3, -0.55], knees: 0.15 });
      rig.b.neck.rotation.x = 0; // nek in het verlengde van de rug, blik naar de vloer
      rig.root.updateMatrixWorld(true);
      const S = worldPos(rig.b.shoulderR);
      const hipR = worldPos(rig.b.hipR);
      const bottom = S.clone().add(V(0.0, -(LIMB.upperArm + LIMB.forearm - 0.01), 0.02));
      // Bovenin: elleboog naast de romp, iets boven de rug, onderarm loodrecht
      const E = S.clone().lerp(hipR, 0.5).add(V(-0.05, 0.07, 0));
      const topW = E.clone().add(V(0, -LIMB.forearm + 0.01, 0));
      const w = lerpV(bottom, topW, up);
      const pole = lerpV(V(-0.2, 0.3, -1), E.clone().sub(S).normalize(), up);
      arm(rig, 'R', w, pole);
      aim(rig.b.wristR, worldPos(rig.b.wristR).sub(worldPos(rig.b.elbowR)), V(1, 0, 0));
      // Linkerhand steunt op het bovenbeen, net boven de knie
      const support = worldPos(rig.b.kneeL).lerp(worldPos(rig.b.hipL), 0.15).add(V(0.0, 0.07, 0));
      arm(rig, 'L', support, V(0.9, 0.4, -0.4));
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
  const anchor = V(0, 1.7, 1.3); // op ooghoogte
  return {
    key: 'facepull',
    title: 'Face pulls met band',
    cycle: 1.0 + 0.6 + 1.4 + 0.5,
    props: ['band', 'post'],
    mat: null,
    focus: [0, 1.25, 0.5],
    camera: [2.4, 1.7, 1.9],
    cues: [
      { from: 0, to: 1.0, text: 'Trek naar je voorhoofd, handen uit elkaar. Ellebogen op of boven schouderhoogte.' },
      { from: 1.0, to: 1.6, text: 'Handen naast je oren, knokkels omhoog, schouderbladen samen. Even vasthouden.' },
      { from: 1.6, to: 3.0, text: 'Rustig terug tot je armen gestrekt zijn.' },
      { from: 3.0, to: 3.5, text: 'Band vast op ooghoogte, armen gestrekt. Schouders laag.' },
    ],
    pose(rig, t, p) {
      const pull = phase(t, 1.0, 0.6, 1.4, 0.5);
      stand(rig);
      p.post.position.set(anchor.x, 0, anchor.z + 0.03);
      for (const [side, sx] of SIDES) {
        const S = worldPos(rig.b[`shoulder${side}`]);
        const start = S.clone().add(anchor.clone().add(V(sx * 0.08, 0, 0)).sub(S).normalize().multiplyScalar(LIMB.upperArm + LIMB.forearm - 0.02));
        const end = V(sx * 0.2, 1.7, 0.03); // handen naast je oren
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
      { from: 0, to: 1.6, text: 'Laten zakken tot je bovenarm de vloer raakt. Elleboog op 45 graden van je romp.' },
      { from: 1.6, to: 1.6 + hold, text: pause ? 'Onderin 2 tellen stil, niet ontspannen.' : 'Bovenarm raakt de vloer.' },
      { from: 1.6 + hold, to: 2.6 + hold, text: 'Recht omhoog duwen boven je schouder. Pols recht, onderarm loodrecht. Niet stuiteren.' },
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
      const top = S.clone().add(V(0.0, LIMB.upperArm + LIMB.forearm - 0.006, 0));
      // Onderin: bovenarm op de vloer, 45 graden van je romp, onderarm loodrecht
      const bottom = S.clone().add(V(-0.21, LIMB.forearm - 0.01, 0.21));
      arm(rig, 'R', lerpV(top, bottom, d), V(-1, -0.6, 1));
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
      { from: 0, to: 1.2, text: 'Recht omhoog drukken, onderarm blijft loodrecht. Billen en buik aan, niet achterover leunen.' },
      { from: 1.2, to: 1.7, text: 'Bovenin: arm gestrekt, kettlebell boven je schouder, niet ervoor.' },
      { from: 1.7, to: 3.3, text: 'Gecontroleerd terug naar je schouder.' },
      { from: 3.3, to: 4.0, text: 'Rack: kettlebell op de buitenkant van je onderarm, pols recht, elleboog tegen je ribben.' },
    ],
    pose(rig, t, p) {
      const up = phase(t, 1.2, 0.5, 1.6, 0.7);
      stand(rig);
      const S = worldPos(rig.b.shoulderR);
      // Rack: onderarm loodrecht, elleboog tegen je ribben en iets voor je lichaam
      const rack = S.clone().add(V(0.06, -0.03, 0.14));
      // Bovenin: arm gestrekt, kettlebell boven je schouder, bovenarm naast je oor
      const top = S.clone().add(V(0.05, LIMB.upperArm + LIMB.forearm - 0.008, -0.01));
      arm(rig, 'R', lerpV(rack, top, up), lerpV(V(0.25, -1, 0.5), V(-0.6, 0.2, 0.6), up));
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
      { from: 0, to: 1.1, text: 'Armen omhoog tot schouderhoogte, iets voor je lichaam (schuin, niet recht opzij). Ellebogen licht gebogen.' },
      { from: 1.1, to: 1.5, text: 'Bovenin: schouders laag houden, niet optrekken.' },
      { from: 1.5, to: 3.1, text: 'Langzaam laten zakken tegen de band in.' },
      { from: 3.1, to: 3.6, text: 'Sta met beide voeten op het midden van de band.' },
    ],
    pose(rig, t, p) {
      const u = phase(t, 1.1, 0.4, 1.6, 0.5);
      stand(rig);
      // Schouderblad-vlak: armen 25 graden voor je zij, tot schouderhoogte
      const elev = lerp(0.12, Math.PI / 2 - 0.04, u);
      const plane = (25 * Math.PI) / 180;
      for (const [side, sx] of SIDES) {
        const dir = V(sx * Math.sin(elev) * Math.cos(plane), -Math.cos(elev), Math.sin(elev) * Math.sin(plane));
        aim(rig.b[`shoulder${side}`], dir, V(0, 1, 0).add(V(0, 0, 1).multiplyScalar(Math.cos(elev))));
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
      const phi = lerp(0.04, 2.3, d);
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
// Kettlebell swing (twee handen): heupen naar achteren, dan explosief strekken
// ---------------------------------------------------------------------------

function swing(): Motion {
  const reach = LIMB.upperArm + LIMB.forearm - 0.01;
  return {
    key: 'swing',
    title: 'Kettlebell swing',
    cycle: 0.8 + 0.15 + 0.6 + 0.45,
    props: ['kb'],
    mat: null,
    focus: [0, 0.85, 0.2],
    camera: [2.6, 1.25, 1.6],
    cues: [
      { from: 0, to: 0.8, text: 'Heupen naar achteren, kettlebell tussen je benen door. Rug plat, knieën licht gebogen.' },
      { from: 0.8, to: 0.95, text: 'Onderin: onderarmen tegen je liezen, gewicht op je hielen.' },
      { from: 0.95, to: 1.55, text: 'Explosief heupen naar voren en billen aanspannen. De heupen doen het werk, niet je armen.' },
      { from: 1.55, to: 2.0, text: 'Bovenin: rechtop als een plank, kettlebell zweeft op borsthoogte.' },
    ],
    pose(rig, t, p) {
      const d = phase(t, 0.8, 0.15, 0.6, 0.45); // 0 = bovenin, 1 = onderin
      const st = 0.2;
      stand(rig, { y: lerp(standY(st), standY(st) - 0.07, d), z: lerp(0, -0.1, d), hinge: 1.0 * d, lean: 0.05 * d, stance: st, knees: lerp(0.35, 0.55, d) });
      rig.b.neck.rotation.x = -0.25 * d;
      rig.root.updateMatrixWorld(true);
      // Armen gestrekt, van horizontaal naar voren tot schuin naar achteren tussen de benen
      const dir = lerpV(V(0, -0.15, 1), V(0, -1, -0.45), d).normalize();
      for (const [side, sx] of SIDES) {
        const S = worldPos(rig.b[`shoulder${side}`]);
        const target = S.clone().add(dir.clone().multiplyScalar(reach));
        target.x = sx * 0.04;
        arm(rig, side, target, V(sx * 0.4, -0.3, -1));
        aim(rig.b[`wrist${side}`], dir, V(0, 0, 1));
      }
      placeKb(p, mid(rig.palmL, rig.palmR), dir);
      return { billen: 0.4 + 0.55 * (1 - d), hamstrings: 0.35 + 0.55 * d, rug: 0.45, buik: 0.4, bovenbenen: 0.3, onderarmen: 0.5, schouders: 0.25 + 0.2 * (1 - d) };
    },
  };
}

// ---------------------------------------------------------------------------
// Clean and press (rechterarm): van tussen je benen naar de rack, dan omhoog
// ---------------------------------------------------------------------------

function cleanPress(): Motion {
  // tijdlijn: clean 0.8, rack 0.3, press 1.0, boven 0.4, terug naar rack 1.0, terug omlaag 0.9, rust 0.4
  const T = [0.8, 0.3, 1.0, 0.4, 1.0, 0.9, 0.4];
  const total = T.reduce((a, b) => a + b, 0);
  return {
    key: 'cleanpress',
    title: 'Clean and press',
    cycle: total,
    props: ['kb'],
    mat: null,
    focus: [0, 1.1, 0.1],
    camera: [-2.3, 1.45, 2.4],
    cues: [
      { from: 0, to: 0.8, text: 'Clean: vanuit de heupen omhoog, kettlebell dicht langs je lichaam. Hand draait om de bol heen.' },
      { from: 0.8, to: 1.1, text: 'Rack: kettlebell op je onderarm, pols recht, elleboog tegen je ribben.' },
      { from: 1.1, to: 2.5, text: 'Press: recht omhoog, billen en buik aan. Niet achterover leunen.' },
      { from: 2.5, to: total, text: 'Gecontroleerd terug naar de rack en tussen je benen. Elke herhaling opnieuw cleanen.' },
    ],
    pose(rig, t, p) {
      const x = ((t % total) + total) % total;
      const at = (i: number) => T.slice(0, i).reduce((a, b) => a + b, 0);
      // c: 0 = hangt tussen de benen, 1 = rack. u: 0 = rack, 1 = boven
      let c = 1, u = 0;
      if (x < at(1)) c = ease(x / T[0]);
      else if (x < at(2)) c = 1;
      else if (x < at(3)) u = ease((x - at(2)) / T[2]);
      else if (x < at(4)) u = 1;
      else if (x < at(5)) u = 1 - ease((x - at(4)) / T[4]);
      else if (x < at(6)) c = 1 - ease((x - at(5)) / T[5]);
      else c = 0;
      stand(rig, { y: lerp(standY(0.16) - 0.06, standY(0.16), c), z: lerp(-0.08, 0, c), hinge: 0.65 * (1 - c), lean: 0.05 * (1 - c), stance: 0.16, knees: lerp(0.5, 0.3, c) });
      rig.root.updateMatrixWorld(true);
      const S = worldPos(rig.b.shoulderR);
      const reach = LIMB.upperArm + LIMB.forearm;
      const hang = S.clone().add(V(0.06, -reach + 0.02, 0.06));
      const rack = S.clone().add(V(0.06, -0.03, 0.14));
      const top = S.clone().add(V(0.05, reach - 0.008, -0.01));
      const target = u > 0 ? lerpV(rack, top, u) : lerpV(hang, rack, c);
      const pole = u > 0 ? lerpV(V(0.25, -1, 0.5), V(-0.6, 0.2, 0.6), u) : lerpV(V(-0.2, 0.3, -1), V(0.25, -1, 0.5), c);
      arm(rig, 'R', target, pole);
      aim(rig.b.wristR, worldPos(rig.b.wristR).sub(worldPos(rig.b.elbowR)), V(0, 0, 1));
      rig.b.shoulderL.rotation.set(0, 0, 0.15);
      rig.b.elbowL.rotation.set(-0.15, 0, 0);
      const fore = worldPos(rig.b.wristR).sub(worldPos(rig.b.elbowR)).normalize();
      const racked = Math.max(c, u > 0 ? 1 : 0);
      const down = lerpV(V(0, -1, 0), fore.clone().negate().multiplyScalar(0.3).add(V(0, 0, -1)), racked).normalize();
      placeKb(p, worldPos(rig.palmR), down, V(1, 0, 0));
      return {
        'schouders:R': 0.3 + 0.6 * u, 'triceps:R': 0.2 + 0.7 * u, billen: 0.3 + 0.5 * (1 - c) * (u > 0 ? 0 : 1), hamstrings: 0.2 + 0.4 * (1 - c),
        rug: 0.35, trapezius: 0.3 + 0.3 * c, buik: 0.5, 'onderarmen:R': 0.45,
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Kettlebell squat in de rack (rechterkant)
// ---------------------------------------------------------------------------

function rackSquat(): Motion {
  const down = 1.8;
  return {
    key: 'squat-rack',
    title: 'Kettlebell squat in de rack',
    cycle: down + 0.5 + 1.2 + 1.3,
    props: ['kb'],
    mat: null,
    focus: [0, 0.8, 0],
    camera: [2.3, 1.3, 2.2],
    cues: [
      { from: 0, to: down, text: 'Zakken met de kettlebell in de rack aan één kant. Romp recht houden, niet naar de bel toe leunen.' },
      { from: down, to: down + 0.5, text: 'Onderin: heupen tot kniehoogte of lager, hielen op de grond.' },
      { from: down + 0.5, to: down + 1.7, text: 'Omhoog duwen vanuit je hielen. Buik aan, dan blijf je recht.' },
      { from: down + 1.7, to: down + 3, text: 'Halverwege de sets van kant wisselen.' },
    ],
    pose(rig, t, p) {
      const d = phase(t, down, 0.5, 1.2, 1.3);
      stand(rig, { y: lerp(standY(0.17), 0.4, d), z: lerp(0, -0.16, d), hinge: 0.65 * d, lean: -0.3 * d, stance: 0.17, knees: lerp(0.4, 0.75, d) });
      rig.root.updateMatrixWorld(true);
      arm(rig, 'R', local(rig.b.chest, V(-0.12, 0.05, 0.2)), V(0.25, -1, 0.5));
      aim(rig.b.wristR, worldPos(rig.b.wristR).sub(worldPos(rig.b.elbowR)), V(0, 0, 1));
      rig.b.shoulderL.rotation.set(-0.5 * d, 0, 0.35);
      rig.b.elbowL.rotation.set(-0.2, 0, 0);
      const fore = worldPos(rig.b.wristR).sub(worldPos(rig.b.elbowR)).normalize();
      placeKb(p, worldPos(rig.palmR), fore.clone().negate().multiplyScalar(0.3).add(V(0, 0, -1)).normalize(), V(1, 0, 0));
      return { bovenbenen: 0.35 + 0.65 * d, billen: 0.3 + 0.65 * d, hamstrings: 0.15 + 0.3 * d, buik: 0.55, 'rug:L': 0.35, 'rug:R': 0.25, 'onderarmen:R': 0.3, 'schouders:R': 0.25, kuiten: 0.2 };
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
  swing: () => swing(),
  cleanpress: () => cleanPress(),
  'squat-rack': () => rackSquat(),
};

export const MOTION_KEYS = Object.keys(MOTIONS);

export function getMotion(key: string): Motion | null {
  return MOTIONS[key]?.() ?? null;
}
