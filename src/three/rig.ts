import * as THREE from 'three';

// ---------------------------------------------------------------------------
// Gestileerde 3D-pop (tekenpop) met losse spiergroepen.
// Eenheden in meters, Y omhoog, de pop kijkt naar +Z.
// Ledematen hangen langs de lokale -Y-as van hun gewricht.
// ---------------------------------------------------------------------------

export type MuscleId =
  | 'borst' | 'schouders' | 'biceps' | 'triceps' | 'onderarmen' | 'rug' | 'trapezius'
  | 'buik' | 'billen' | 'bovenbenen' | 'hamstrings' | 'kuiten';

export const MUSCLE_NAMES: Record<MuscleId, string> = {
  borst: 'borst', schouders: 'schouders', biceps: 'biceps', triceps: 'triceps', onderarmen: 'onderarmen',
  rug: 'brede rugspieren', trapezius: 'bovenrug', buik: 'buik en romp', billen: 'billen',
  bovenbenen: 'bovenbenen', hamstrings: 'achterkant bovenbenen', kuiten: 'kuiten',
};

export const LIMB = { upperArm: 0.30, forearm: 0.27, thigh: 0.44, shin: 0.43 };

export interface Rig {
  root: THREE.Group;
  b: Record<string, THREE.Group>; // gewrichten
  muscles: Record<MuscleId, THREE.MeshStandardMaterial[]>;
  toeL: THREE.Object3D;
  toeR: THREE.Object3D;
  palmL: THREE.Object3D;
  palmR: THREE.Object3D;
  setColors: (body: string, muscle: string, active: string) => void;
}

export function buildRig(colors: { body: string; muscle: string; active: string }): Rig {
  const bodyMat = new THREE.MeshStandardMaterial({ color: colors.body, roughness: 0.75, metalness: 0 });
  const muscleMats: Partial<Record<MuscleId, THREE.MeshStandardMaterial[]>> = {};
  let muscleBase = new THREE.Color(colors.muscle);
  let activeColor = new THREE.Color(colors.active);

  const group = (name: string, parent: THREE.Object3D, x = 0, y = 0, z = 0) => {
    const g = new THREE.Group();
    g.name = name;
    g.position.set(x, y, z);
    parent.add(g);
    return g;
  };
  const mesh = (geo: THREE.BufferGeometry, parent: THREE.Object3D, pos: [number, number, number], scale?: [number, number, number], mat: THREE.Material = bodyMat) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(...pos);
    if (scale) m.scale.set(...scale);
    m.castShadow = true;
    m.receiveShadow = true;
    parent.add(m);
    return m;
  };
  const sphere = new THREE.SphereGeometry(1, 24, 16);
  const capsule = (r: number, len: number) => new THREE.CapsuleGeometry(r, len, 6, 14);
  const muscle = (id: MuscleId, parent: THREE.Object3D, pos: [number, number, number], scale: [number, number, number]) => {
    const mat = new THREE.MeshStandardMaterial({ color: muscleBase.clone(), roughness: 0.6, metalness: 0, emissive: new THREE.Color(0x000000) });
    (muscleMats[id] ??= []).push(mat);
    mesh(sphere, parent, pos, scale, mat);
  };

  const root = new THREE.Group();
  root.name = 'root';
  const b: Record<string, THREE.Group> = {};

  // Romp
  b.pelvis = group('pelvis', root);
  mesh(sphere, b.pelvis, [0, 0.02, 0], [0.165, 0.1, 0.105]);
  b.spine = group('spine', b.pelvis, 0, 0.06, 0);
  mesh(capsule(0.105, 0.12), b.spine, [0, 0.1, 0], [1.25, 1, 0.95]);
  b.chest = group('chest', b.spine, 0, 0.22, 0);
  mesh(sphere, b.chest, [0, 0.13, 0], [0.175, 0.17, 0.11]);
  b.neck = group('neck', b.chest, 0, 0.3, 0);
  mesh(capsule(0.045, 0.05), b.neck, [0, 0.03, 0]);
  b.head = group('head', b.neck, 0, 0.08, 0);
  mesh(sphere, b.head, [0, 0.1, 0.01], [0.095, 0.115, 0.105]);

  muscle('borst', b.chest, [-0.075, 0.16, 0.085], [0.075, 0.06, 0.035]);
  muscle('borst', b.chest, [0.075, 0.16, 0.085], [0.075, 0.06, 0.035]);
  muscle('buik', b.spine, [0, 0.11, 0.075], [0.075, 0.12, 0.035]);
  muscle('rug', b.chest, [-0.11, 0.08, -0.045], [0.055, 0.13, 0.045]);
  muscle('rug', b.chest, [0.11, 0.08, -0.045], [0.055, 0.13, 0.045]);
  muscle('trapezius', b.chest, [0, 0.22, -0.065], [0.12, 0.075, 0.035]);

  // Armen
  for (const [side, sx] of [['L', 1], ['R', -1]] as const) {
    const sh = (b[`shoulder${side}`] = group(`shoulder${side}`, b.chest, 0.195 * sx, 0.24, 0));
    mesh(capsule(0.045, 0.22), sh, [0, -0.15, 0]);
    muscle('schouders', sh, [0.012 * sx, -0.01, 0], [0.065, 0.07, 0.065]);
    muscle('biceps', sh, [0, -0.15, 0.02], [0.036, 0.09, 0.032]);
    muscle('triceps', sh, [0, -0.15, -0.02], [0.038, 0.1, 0.034]);
    const el = (b[`elbow${side}`] = group(`elbow${side}`, sh, 0, -LIMB.upperArm, 0));
    mesh(sphere, el, [0, 0, 0], [0.04, 0.04, 0.04]);
    mesh(capsule(0.037, 0.2), el, [0, -0.135, 0]);
    muscle('onderarmen', el, [0, -0.09, 0.008], [0.042, 0.085, 0.036]);
    const wr = (b[`wrist${side}`] = group(`wrist${side}`, el, 0, -LIMB.forearm, 0));
    mesh(sphere, wr, [0, -0.05, 0], [0.036, 0.058, 0.02]);
    const palm = new THREE.Object3D();
    palm.position.set(0, -0.05, 0);
    wr.add(palm);
    if (side === 'L') (b as Record<string, unknown>).__palmL = palm; else (b as Record<string, unknown>).__palmR = palm;
  }

  // Benen
  const toes: THREE.Object3D[] = [];
  for (const [side, sx] of [['L', 1], ['R', -1]] as const) {
    muscle('billen', b.pelvis, [0.07 * sx, -0.01, -0.055], [0.075, 0.075, 0.06]);
    const hip = (b[`hip${side}`] = group(`hip${side}`, b.pelvis, 0.095 * sx, -0.02, 0));
    mesh(capsule(0.068, 0.3), hip, [0, -0.22, 0]);
    muscle('bovenbenen', hip, [0, -0.22, 0.026], [0.062, 0.17, 0.048]);
    muscle('hamstrings', hip, [0, -0.22, -0.026], [0.058, 0.16, 0.046]);
    const kn = (b[`knee${side}`] = group(`knee${side}`, hip, 0, -LIMB.thigh, 0));
    mesh(sphere, kn, [0, 0, 0], [0.055, 0.055, 0.055]);
    mesh(capsule(0.05, 0.32), kn, [0, -0.21, 0]);
    muscle('kuiten', kn, [0, -0.12, -0.02], [0.046, 0.1, 0.042]);
    const an = (b[`ankle${side}`] = group(`ankle${side}`, kn, 0, -LIMB.shin, 0));
    mesh(sphere, an, [0, -0.03, 0.06], [0.045, 0.035, 0.11]);
    const toe = new THREE.Object3D();
    toe.position.set(0, -0.06, 0.16);
    an.add(toe);
    toes.push(toe);
  }

  const muscles = muscleMats as Record<MuscleId, THREE.MeshStandardMaterial[]>;
  return {
    root,
    b,
    muscles,
    toeL: toes[0],
    toeR: toes[1],
    palmL: (b as Record<string, unknown>).__palmL as THREE.Object3D,
    palmR: (b as Record<string, unknown>).__palmR as THREE.Object3D,
    setColors(body, m, active) {
      bodyMat.color.set(body);
      muscleBase = new THREE.Color(m);
      activeColor = new THREE.Color(active);
    },
    // kleur per spier zetten gebeurt in applyIntensity
    ...{ _get: () => ({ muscleBase, activeColor }) },
  } as Rig & { _get: () => { muscleBase: THREE.Color; activeColor: THREE.Color } };
}

/** Kleurt spieren: 0 = rust, 1 = maximaal belast (rood). */
export function applyIntensity(rig: Rig, intensity: Partial<Record<MuscleId, number>>) {
  const { muscleBase, activeColor } = (rig as Rig & { _get: () => { muscleBase: THREE.Color; activeColor: THREE.Color } })._get();
  for (const id of Object.keys(rig.muscles) as MuscleId[]) {
    const v = Math.max(0, Math.min(1, intensity[id] ?? 0));
    for (const mat of rig.muscles[id]) {
      mat.color.copy(muscleBase).lerp(activeColor, v);
      mat.emissive.copy(activeColor).multiplyScalar(v * 0.18);
    }
  }
}

/** Zet alle gewrichten terug in rechtopstaande houding. */
export function resetPose(rig: Rig) {
  for (const g of Object.values(rig.b)) if (g instanceof THREE.Group) g.quaternion.identity();
  rig.root.position.set(0, 0, 0);
  rig.root.quaternion.identity();
}

// ---------------------------------------------------------------------------
// Hulpfuncties voor houdingen
// ---------------------------------------------------------------------------

const tmpQ = new THREE.Quaternion();
const tmpM = new THREE.Matrix4();

/** Richt een gewricht zo dat het ledemaat (lokale -Y) in wereldrichting `dir` wijst, met de voorkant (lokale +Z) richting `front`. */
export function aim(bone: THREE.Object3D, dir: THREE.Vector3, front: THREE.Vector3) {
  const y = dir.clone().normalize().negate();
  let z = front.clone().sub(y.clone().multiplyScalar(front.dot(y)));
  if (z.lengthSq() < 1e-6) z = new THREE.Vector3(0, 0, 1).sub(y.clone().multiplyScalar(y.z));
  z.normalize();
  const x = new THREE.Vector3().crossVectors(y, z).normalize();
  z = new THREE.Vector3().crossVectors(x, y).normalize();
  tmpM.makeBasis(x, y, z);
  const qWorld = new THREE.Quaternion().setFromRotationMatrix(tmpM);
  bone.parent!.updateMatrixWorld(true);
  bone.parent!.getWorldQuaternion(tmpQ);
  bone.quaternion.copy(tmpQ.invert().multiply(qWorld));
  bone.updateMatrixWorld(true);
}

export function worldPos(o: THREE.Object3D): THREE.Vector3 {
  o.updateWorldMatrix(true, false);
  return o.getWorldPosition(new THREE.Vector3());
}

/**
 * Twee-delige IK (bovenarm + onderarm of bovenbeen + onderbeen).
 * `pole` geeft de richting waarin het middelste gewricht (elleboog/knie) uitwijkt.
 */
export function solveTwoBone(upper: THREE.Group, lower: THREE.Group, a: number, b: number, target: THREE.Vector3, pole: THREE.Vector3, frontHint?: THREE.Vector3) {
  const S = worldPos(upper);
  const toT = target.clone().sub(S);
  const d = Math.min(Math.max(toT.length(), Math.abs(a - b) + 0.01), a + b - 0.002);
  const u = toT.normalize();
  const w = pole.clone().sub(u.clone().multiplyScalar(pole.dot(u))).normalize();
  const cosA = (a * a + d * d - b * b) / (2 * a * d);
  const sinA = Math.sqrt(Math.max(0, 1 - cosA * cosA));
  const dir1 = u.clone().multiplyScalar(cosA).add(w.clone().multiplyScalar(sinA)).normalize();
  const E = S.clone().add(dir1.clone().multiplyScalar(a));
  const dir2 = S.clone().add(u.clone().multiplyScalar(d)).sub(E).normalize();
  // Voorkant: de kant waar het ledemaat naartoe buigt (biceps, voorkant onderarm)
  let anterior = dir2.clone().sub(dir1.clone().multiplyScalar(dir2.dot(dir1)));
  if (anterior.lengthSq() < 1e-5) anterior = frontHint?.clone() ?? w.clone().negate();
  anterior.normalize();
  aim(upper, dir1, anterior);
  aim(lower, dir2, anterior);
}
