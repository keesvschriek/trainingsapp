import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { applyIntensity, buildRig, MUSCLE_NAMES, type MuscleId } from './rig';
import { BAR_Y, getMotion, type Motion, type Props } from './exercises';
import { cssColor } from '../theme';
import { Sheet } from '../ui';

/** Scherm met de 3D-pop die de oefening voordoet. */
export default function ExerciseViewer(props: { motionKey: string; name: string; onClose: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [speed, setSpeed] = useState(1);
  const [paused, setPaused] = useState(false);
  const [cue, setCue] = useState('');
  const [active, setActive] = useState<string[]>([]);
  const state = useRef({ speed: 1, paused: false });
  state.current.speed = speed;
  state.current.paused = paused;
  const motion: Motion | null = getMotion(props.motionKey);

  useEffect(() => {
    if (!motion || !canvasRef.current) return;
    const canvas = canvasRef.current;
    const dark = document.documentElement.dataset.theme === 'dark' || (!document.documentElement.dataset.theme && window.matchMedia('(prefers-color-scheme: dark)').matches);

    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap;
    renderer.outputColorSpace = THREE.SRGBColorSpace;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(cssColor('--bg'));

    const camera = new THREE.PerspectiveCamera(42, 1, 0.05, 30);
    camera.position.set(...motion.camera);
    const controls = new OrbitControls(camera, canvas);
    controls.target.set(...motion.focus);
    controls.enablePan = false;
    controls.minDistance = 1.2;
    controls.maxDistance = 5;
    controls.maxPolarAngle = Math.PI / 2 - 0.05;
    controls.update();

    scene.add(new THREE.HemisphereLight(dark ? 0xb8c6d6 : 0xffffff, dark ? 0x1c232c : 0xd8d2c6, dark ? 1.2 : 1.5));
    const sun = new THREE.DirectionalLight(0xffffff, dark ? 1.6 : 1.9);
    sun.position.set(2.5, 4, 2);
    sun.castShadow = true;
    sun.shadow.mapSize.set(1024, 1024);
    sun.shadow.camera.left = -2;
    sun.shadow.camera.right = 2;
    sun.shadow.camera.top = 2;
    sun.shadow.camera.bottom = -2;
    sun.shadow.radius = 4;
    scene.add(sun);

    // Vloer met een dunne cirkel, zoals een trainingsmat
    const floor = new THREE.Mesh(
      new THREE.CircleGeometry(2.2, 64),
      new THREE.MeshStandardMaterial({ color: new THREE.Color(cssColor('--surface-2')), roughness: 1 }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.receiveShadow = true;
    scene.add(floor);
    const mat = new THREE.Mesh(
      new THREE.PlaneGeometry(0.62, 1.85),
      new THREE.MeshStandardMaterial({ color: new THREE.Color(cssColor('--line')), roughness: 1 }),
    );
    mat.rotation.x = -Math.PI / 2;
    mat.position.set(0, 0.002, 0.75);
    mat.receiveShadow = true;
    scene.add(mat);
    if (motion.mat === null) mat.visible = false;
    else if (motion.mat) { mat.scale.y = motion.mat.length / 1.85; mat.position.z = motion.mat.z; }

    const props = buildProps(dark);
    for (const [name, objs] of Object.entries({ kb: [props.kb], bar: [props.bar], band: [props.bandL, props.bandR], step: [props.step], post: [props.post] })) {
      for (const o of objs) { o.visible = motion.props.includes(name as Motion['props'][number]); scene.add(o); }
    }

    const rig = buildRig({
      body: dark ? '#8c97a3' : '#a7b0ba',
      muscle: dark ? '#8c97a3' : '#a7b0ba',
      active: dark ? '#ff5a45' : '#d8321f',
    });
    scene.add(rig.root);

    const resize = () => {
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    let t = 0;
    let last = performance.now();
    let raf = 0;
    let lastCue = '';
    let lastActive = '';
    const loop = (now: number) => {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      if (!state.current.paused) t += dt * state.current.speed;
      const intensity = motion.pose(rig, t, props);
      applyIntensity(rig, intensity);
      controls.update();
      renderer.render(scene, camera);

      const x = t % motion.cycle;
      const c = motion.cues.find(q => x >= q.from && x < q.to)?.text ?? '';
      if (c !== lastCue) { lastCue = c; setCue(c); }
      const act = [...new Set((Object.entries(intensity) as [string, number][])
        .filter(([, v]) => v >= 0.5)
        .sort((a, b) => b[1] - a[1])
        .map(([k]) => MUSCLE_NAMES[k.split(':')[0] as MuscleId]))];
      const key = act.join(',');
      if (key !== lastActive) { lastActive = key; setActive(act); }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      controls.dispose();
      renderer.dispose();
      scene.traverse(o => {
        const m = o as THREE.Mesh;
        m.geometry?.dispose?.();
        const material = m.material as THREE.Material | THREE.Material[] | undefined;
        if (Array.isArray(material)) material.forEach(x => x.dispose());
        else material?.dispose?.();
      });
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.motionKey]);

  return (
    <Sheet title={props.name} onClose={props.onClose}>
      {!motion ? (
        <p className="muted">Voor deze oefening is nog geen 3D-uitleg.</p>
      ) : (
        <>
          <canvas ref={canvasRef} className="viewer3d" aria-label={`3D-uitleg ${props.name}`} />
          <p className="muted small" style={{ textAlign: 'center', marginTop: 6 }}>Sleep om te draaien, knijp om te zoomen.</p>
          <div className="cue">{cue}</div>
          <div className="muted small" style={{ minHeight: 20 }}>
            {active.length > 0 && <>Werkt nu vooral: <span className="active-muscles">{active.join(', ')}</span></>}
          </div>
          <div className="row mt" style={{ justifyContent: 'space-between' }}>
            <div className="seg" style={{ marginBottom: 0, flex: 1 }}>
              {[0.5, 1].map(s => (
                <button key={s} className={speed === s ? 'active' : ''} onClick={() => setSpeed(s)}>{s === 1 ? 'Normaal' : 'Langzaam'}</button>
              ))}
            </div>
            <button className="btn secondary" onClick={() => setPaused(!paused)}>{paused ? 'Verder' : 'Pauze'}</button>
          </div>
        </>
      )}
    </Sheet>
  );
}

/** Spullen: kettlebell, optrekstang, weerstandsband en verhoging. */
export function buildProps(dark: boolean): Props {
  const iron = new THREE.MeshStandardMaterial({ color: dark ? '#3a4048' : '#2b2f33', roughness: 0.55, metalness: 0.35 });
  const steel = new THREE.MeshStandardMaterial({ color: dark ? '#9aa4ae' : '#7d8790', roughness: 0.35, metalness: 0.6 });
  const rubber = new THREE.MeshStandardMaterial({ color: '#2f8f5b', roughness: 0.7 });
  const wood = new THREE.MeshStandardMaterial({ color: dark ? '#6b5a48' : '#b79a77', roughness: 0.9 });
  const shadow = (m: THREE.Object3D) => { m.traverse(o => { o.castShadow = true; o.receiveShadow = true; }); return m; };

  // Kettlebell: oorsprong in het midden van de handgreep, bol eronder
  const kb = new THREE.Group();
  const bell = new THREE.Mesh(new THREE.SphereGeometry(0.085, 28, 20), iron);
  bell.scale.set(1, 0.95, 1);
  bell.position.y = -0.13;
  const handle = new THREE.Mesh(new THREE.TorusGeometry(0.06, 0.013, 12, 32, Math.PI), iron);
  handle.position.y = -0.065;
  const horns = new THREE.Mesh(new THREE.CylinderGeometry(0.013, 0.013, 0.07, 10), iron);
  for (const sx of [1, -1]) { const h = horns.clone(); h.position.set(sx * 0.06, -0.09, 0); kb.add(h); }
  kb.add(bell, handle);
  shadow(kb);

  // Optrekstang met twee steunen
  const bar = new THREE.Group();
  const rod = new THREE.Mesh(new THREE.CylinderGeometry(0.016, 0.016, 1.1, 16), steel);
  rod.rotation.z = Math.PI / 2;
  rod.position.set(0, BAR_Y, 0);
  bar.add(rod);
  for (const sx of [1, -1]) {
    const post = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.12, 0.12), steel);
    post.position.set(sx * 0.55, BAR_Y, -0.05);
    bar.add(post);
  }
  shadow(bar);

  const bandGeo = new THREE.CylinderGeometry(0.008, 0.008, 1, 8);
  const bandL = new THREE.Mesh(bandGeo, rubber);
  const bandR = new THREE.Mesh(bandGeo, rubber);
  shadow(bandL); shadow(bandR);

  const step = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.2, 0.32), wood);
  shadow(step);

  // Paal waar de band aan vastzit (zoals een deurpost of rek)
  const post = new THREE.Group();
  const pole = new THREE.Mesh(new THREE.BoxGeometry(0.07, 1.9, 0.07), wood);
  pole.position.y = 0.95;
  const knot = new THREE.Mesh(new THREE.SphereGeometry(0.022, 12, 8), rubber);
  knot.position.set(0, 1.55, -0.04);
  post.add(pole, knot);
  shadow(post);
  return { kb, bar, bandL, bandR, step, post };
}
