import { Capacitor } from '@capacitor/core';
import { App as CapApp } from '@capacitor/app';

export const isNative = Capacitor.isNativePlatform();

const REPO = 'keesvschriek/trainingsapp';
export const APK_URL = `https://github.com/${REPO}/releases/latest/download/trainingsapp.apk`;

/** Terugknop van Android: eerst een open scherm sluiten, dan naar Vandaag, dan de app uit. */
export function setupBackButton() {
  if (!isNative) return;
  void CapApp.addListener('backButton', () => {
    const close = document.querySelector<HTMLButtonElement>('.sheet button[aria-label="Sluiten"]');
    if (close) return close.click();
    if (location.hash && location.hash !== '#/vandaag') {
      location.hash = '#/vandaag';
      return;
    }
    void CapApp.exitApp();
  });
}

/** Kijkt op GitHub of er een nieuwere APK is. Geeft het nieuwe buildnummer terug, of null. */
export async function checkForUpdate(): Promise<number | null> {
  if (!isNative || !__APP_BUILD__) return null;
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: 'application/vnd.github+json' } });
    if (!res.ok) return null;
    const data = (await res.json()) as { tag_name?: string };
    const latest = Number((data.tag_name ?? '').replace(/\D/g, ''));
    return latest > __APP_BUILD__ ? latest : null;
  } catch {
    return null;
  }
}
