import { useEffect, useRef, useState, type ReactNode } from 'react';
import { App as CapApp } from '@capacitor/app';
import { BiometricAuth } from '@aparajita/capacitor-biometric-auth';
import { isNative } from './native';

// App-slot: pincode (gehasht met PBKDF2) en optioneel vingerafdruk.
// Instellingen staan in localStorage, zodat het slot er direct is bij het openen (geen flits van je gegevens).
// Let op: dit is een slot op de app, geen versleuteling van de gegevens op je telefoon.

export interface LockConfig {
  on: boolean;
  hash: string;
  salt: string;
  bio: boolean;
  afterSec: number; // na hoeveel seconden op de achtergrond opnieuw vergrendelen
  len: number; // lengte van de pincode
}

const KEY = 'trainingsapp.lock';
const OFF: LockConfig = { on: false, hash: '', salt: '', bio: false, afterSec: 60, len: 4 };

export function getLock(): LockConfig {
  try {
    return { ...OFF, ...(JSON.parse(localStorage.getItem(KEY) ?? '{}') as Partial<LockConfig>) };
  } catch {
    return OFF;
  }
}

export function setLock(c: LockConfig) {
  localStorage.setItem(KEY, JSON.stringify(c));
  window.dispatchEvent(new Event('lock-changed'));
}

const hex = (b: ArrayBuffer | Uint8Array) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');

export async function hashPin(pin: string, salt: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(pin), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: new TextEncoder().encode(salt), iterations: 120_000 }, key, 256);
  return hex(bits);
}

export async function makePin(pin: string): Promise<{ hash: string; salt: string }> {
  const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
  return { hash: await hashPin(pin, salt), salt };
}

export async function bioAvailable(): Promise<boolean> {
  if (!isNative) return false;
  try {
    return (await BiometricAuth.checkBiometry()).isAvailable;
  } catch {
    return false;
  }
}

async function bioUnlock(): Promise<boolean> {
  try {
    await BiometricAuth.authenticate({
      reason: 'Ontgrendel je trainingsapp',
      androidTitle: 'Kees Study ontgrendelen',
      androidSubtitle: 'Gebruik je vingerafdruk',
      cancelTitle: 'Pincode',
      allowDeviceCredential: false,
      androidConfirmationRequired: false,
    });
    return true;
  } catch {
    return false;
  }
}

/** Zet de app achter het slot zolang hij vergrendeld is. */
export function LockGate({ children }: { children: ReactNode }) {
  const [cfg, setCfg] = useState(getLock);
  const [locked, setLocked] = useState(() => getLock().on && !!getLock().hash);
  const pausedAt = useRef<number | null>(null);

  useEffect(() => {
    const onChange = () => setCfg(getLock());
    window.addEventListener('lock-changed', onChange);
    return () => window.removeEventListener('lock-changed', onChange);
  }, []);

  useEffect(() => {
    if (!isNative) return;
    const subs = [
      CapApp.addListener('pause', () => {
        pausedAt.current = Date.now();
      }),
      CapApp.addListener('resume', () => {
        const c = getLock();
        if (c.on && c.hash && pausedAt.current && Date.now() - pausedAt.current >= c.afterSec * 1000) setLocked(true);
        pausedAt.current = null;
      }),
    ];
    return () => subs.forEach(s => void s.then(h => h.remove()));
  }, []);

  if (locked && cfg.on && cfg.hash) return <LockScreen cfg={cfg} onUnlock={() => setLocked(false)} />;
  return <>{children}</>;
}

function LockScreen({ cfg, onUnlock }: { cfg: LockConfig; onUnlock: () => void }) {
  const [pin, setPin] = useState('');
  const [wrong, setWrong] = useState(0);
  const [busy, setBusy] = useState(false);

  async function tryBio() {
    if (!cfg.bio || busy) return;
    setBusy(true);
    const ok = await bioUnlock();
    setBusy(false);
    if (ok) onUnlock();
  }

  useEffect(() => {
    void tryBio();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function press(d: string) {
    const next = (pin + d).slice(0, cfg.len);
    setPin(next);
    if (next.length === cfg.len) {
      const h = await hashPin(next, cfg.salt);
      if (h === cfg.hash) return onUnlock();
      setWrong(w => w + 1);
      setPin('');
    }
  }

  const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'bio', '0', 'del'];
  return (
    <div className="lock" role="dialog" aria-label="Vergrendeld">
      <div className="lock-title">Kees Study</div>
      <div className="muted small">Voer je pincode in</div>
      <div className="lock-dots" aria-label={`${pin.length} cijfers ingevoerd`}>
        {Array.from({ length: cfg.len }, (_, i) => <span key={i} className={i < pin.length ? 'on' : ''} />)}
      </div>
      <div className="lock-msg small">{wrong > 0 ? 'Onjuiste pincode' : ' '}</div>
      <div className="lock-pad">
        {keys.map(k =>
          k === 'bio' ? (
            cfg.bio ? <button key={k} className="lock-key small" onClick={() => void tryBio()} aria-label="Vingerafdruk">Vinger&shy;afdruk</button> : <span key={k} />
          ) : k === 'del' ? (
            <button key={k} className="lock-key small" onClick={() => setPin(p => p.slice(0, -1))} aria-label="Wissen">Wis</button>
          ) : (
            <button key={k} className="lock-key" onClick={() => void press(k)}>{k}</button>
          ),
        )}
      </div>
      <p className="muted small lock-help">
        Pincode vergeten? Gebruik je vingerafdruk. Lukt dat niet, wis dan de gegevens van de app in de Android-instellingen. Met synchronisatie aan haal je daarna alles terug.
      </p>
    </div>
  );
}
