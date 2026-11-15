import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { applyIntensity, buildRig, MUSCLE_NAMES, type MuscleId } from './rig';
import { getMotion, type Motion } from './exercises';
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
      const intensity = motion.pose(rig, t);
      applyIntensity(rig, intensity);
      controls.update();
      renderer.render(scene, camera);

      const x = t % motion.cycle;
      const c = motion.cues.find(q => x >= q.from && x < q.to)?.text ?? '';
      if (c !== lastCue) { lastCue = c; setCue(c); }
      const act = (Object.entries(intensity) as [MuscleId, number][])
        .filter(([, v]) => v >= 0.5)
        .sort((a, b) => b[1] - a[1])
        .map(([k]) => MUSCLE_NAMES[k]);
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
