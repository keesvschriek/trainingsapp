import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { db, getSetting, setSetting, SYNC_TABLES, type Base, type SyncTable } from './db';
import type { Table } from 'dexie';

// Synchronisatie via Supabase. Alles staat eerst lokaal (werkt offline);
// deze module duwt wijzigingen omhoog en haalt wijzigingen van andere apparaten op.
// Bij een conflict wint de laatste wijziging (updatedAt).

export interface SupabaseSettings {
  url: string;
  anonKey: string;
}

let client: SupabaseClient | null = null;
let clientFor = '';

export async function getSupabase(): Promise<SupabaseClient | null> {
  const s = await getSetting<SupabaseSettings>('supabase', { url: '', anonKey: '' });
  if (!s.url || !s.anonKey) return null;
  const sig = s.url + s.anonKey;
  if (!client || clientFor !== sig) {
    client = createClient(s.url.trim(), s.anonKey.trim(), { auth: { persistSession: true, autoRefreshToken: true } });
    clientFor = sig;
  }
  return client;
}

export async function currentUser() {
  const sb = await getSupabase();
  if (!sb) return null;
  const { data } = await sb.auth.getSession();
  return data.session?.user ?? null;
}

interface RemoteRow {
  tbl: string;
  id: string;
  data: Base;
  updated_at: number;
  deleted: boolean;
  server_ts: string;
}

let running: Promise<SyncResult> | null = null;

export interface SyncResult {
  pushed: number;
  pulled: number;
  error?: string;
}

export function sync(): Promise<SyncResult> {
  if (!running) running = doSync().finally(() => (running = null));
  return running;
}

async function doSync(): Promise<SyncResult> {
  const sb = await getSupabase();
  if (!sb) return { pushed: 0, pulled: 0, error: 'Supabase is niet ingesteld.' };
  const user = await currentUser();
  if (!user) return { pushed: 0, pulled: 0, error: 'Niet ingelogd.' };
  if (!navigator.onLine) return { pushed: 0, pulled: 0, error: 'Offline.' };

  const lastPush = await getSetting<number>(`sync.lastPush.${user.id}`, 0);
  const lastPull = await getSetting<string>(`sync.lastPull.${user.id}`, '1970-01-01T00:00:00Z');
  const startedAt = Date.now();
  let pushed = 0;
  let pulled = 0;

  // 1. Omhoog: alles wat lokaal sinds de vorige push is veranderd
  for (const tbl of SYNC_TABLES) {
    const t = db[tbl] as unknown as Table<Base, string>;
    const changed = await t.where('updatedAt').above(lastPush).toArray();
    for (let i = 0; i < changed.length; i += 200) {
      const chunk = changed.slice(i, i + 200).map(r => ({
        user_id: user.id,
        tbl,
        id: r.id,
        data: r,
        updated_at: r.updatedAt,
        deleted: !!r.deleted,
      }));
      const { error } = await sb.from('records').upsert(chunk, { onConflict: 'user_id,tbl,id' });
      if (error) return { pushed, pulled, error: `Uploaden mislukt: ${error.message}` };
      pushed += chunk.length;
    }
  }

  // 2. Omlaag: alles wat op de server sinds de vorige pull is veranderd
  let newestServer = lastPull;
  for (;;) {
    const { data, error } = await sb
      .from('records')
      .select('tbl,id,data,updated_at,deleted,server_ts')
      .gt('server_ts', newestServer)
      .order('server_ts', { ascending: true })
      .limit(500);
    if (error) return { pushed, pulled, error: `Downloaden mislukt: ${error.message}` };
    const rows = (data ?? []) as RemoteRow[];
    for (const row of rows) {
      if (!(SYNC_TABLES as readonly string[]).includes(row.tbl)) continue;
      const t = db[row.tbl as SyncTable] as unknown as Table<Base, string>;
      const local = await t.get(row.id);
      if (!local || local.updatedAt < row.updated_at) {
        await t.put({ ...row.data, updatedAt: row.updated_at, deleted: row.deleted });
        pulled++;
      }
      newestServer = row.server_ts;
    }
    if (rows.length < 500) break;
  }

  // Wat net is binnengehaald heeft een oud updatedAt en wordt dus niet opnieuw gepusht.
  await setSetting(`sync.lastPush.${user.id}`, startedAt);
  await setSetting(`sync.lastPull.${user.id}`, newestServer);
  await setSetting('sync.lastOk', new Date().toISOString());
  if (pulled) window.dispatchEvent(new Event('data-changed'));
  return { pushed, pulled };
}

let timer: number | undefined;
/** Synchroniseer een paar seconden na de laatste wijziging. */
export function scheduleSync(delay = 4000) {
  window.clearTimeout(timer);
  timer = window.setTimeout(() => void sync(), delay);
}
