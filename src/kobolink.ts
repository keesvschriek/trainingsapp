// Kobo koppelen vanuit de app: de app kent het Supabase-adres, de sleutel en je e-mail al.
// Met de code van het Kobo-scherm en je wachtwoord gaat alles versleuteld (via ntfy.sh) naar de Kobo.
// Dezelfde versleuteling als kobo/web/stuur.html en ks_relay.lua op de Kobo.

const NTFY = 'https://ntfy.sh/';
const enc = new TextEncoder();

async function sha256(s: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(s)));
}
const hex = (b: Uint8Array) => Array.from(b, x => x.toString(16).padStart(2, '0')).join('');

export async function koboTopic(code: string) {
  return 'ks-' + hex(await sha256('kees-topic:' + code)).slice(0, 24);
}

export async function koboEncrypt(code: string, text: string) {
  const data = enc.encode(text);
  const ks = new Uint8Array(data.length);
  for (let i = 0, n = 0; n < data.length; i++) {
    const block = await sha256('kees-key:' + code + ':' + i);
    for (let j = 0; j < 32 && n < data.length; j++, n++) ks[n] = block[j];
  }
  let bin = '';
  data.forEach((x, i) => (bin += String.fromCharCode(x ^ ks[i])));
  const mac = hex(await sha256('kees-mac:' + code + text)).slice(0, 16);
  return 'v1.' + btoa(bin) + '.' + mac;
}

export const cleanCode = (c: string) => c.toUpperCase().replace(/[^A-Z0-9]/g, '');

/** Stuur de koppelgegevens naar de Kobo die deze code toont. */
export async function linkKobo(code: string, cfg: { url: string; key: string; email: string; pw: string }) {
  const c = cleanCode(code);
  if (c.length !== 8) throw new Error('De code op de Kobo heeft 8 tekens.');
  const body = await koboEncrypt(c, JSON.stringify({ t: 'koppel', url: cfg.url, key: cfg.key, email: cfg.email, pw: cfg.pw }));
  const r = await fetch(NTFY + (await koboTopic(c)), { method: 'POST', body });
  if (!r.ok) throw new Error(`Versturen lukte niet (${r.status}).`);
}
