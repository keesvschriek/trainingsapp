import { SystemBars, SystemBarsStyle } from '@capacitor/core';
import { getSetting, setSetting } from './db';
import { isNative } from './native';

export type ThemePref = 'system' | 'light' | 'dark';

const media = window.matchMedia('(prefers-color-scheme: dark)');

function isDark(pref: ThemePref) {
  return pref === 'dark' || (pref === 'system' && media.matches);
}

export function applyTheme(pref: ThemePref) {
  const root = document.documentElement;
  if (pref === 'system') delete root.dataset.theme;
  else root.dataset.theme = pref;
  const dark = isDark(pref);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#0d1116' : '#f5f3ee');
  if (isNative) {
    void SystemBars.setStyle({ style: dark ? SystemBarsStyle.Dark : SystemBarsStyle.Light }).catch(() => undefined);
  }
  window.dispatchEvent(new Event('theme-changed'));
}

export async function initTheme() {
  const pref = await getSetting<ThemePref>('theme', 'system');
  applyTheme(pref);
  media.addEventListener('change', async () => applyTheme(await getSetting<ThemePref>('theme', 'system')));
}

export async function setThemePref(pref: ThemePref) {
  await setSetting('theme', pref);
  applyTheme(pref);
}

/** Kleuren uit de CSS, voor grafieken. */
export function cssColor(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || '#1f4e79';
}
