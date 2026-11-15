import { getSetting, setSetting } from './db';
import type { ISODate } from './dates';
import type { HourWeather } from './bestmoment';
import { toMin } from './work';

// Weer van Open-Meteo: gratis, zonder account of sleutel. Eén keer per uur ophalen.

export interface Place { name: string; lat: number; lon: number }
export const DEFAULT_PLACE: Place = { name: 'Nijmegen', lat: 51.8426, lon: 5.8528 };

interface Forecast {
  fetchedAt: number;
  place: Place;
  hourly: { time: string[]; apparent_temperature: number[]; precipitation: number[]; precipitation_probability: (number | null)[]; wind_speed_10m: number[] };
  daily: { time: string[]; sunrise: string[]; sunset: string[] };
}

export async function getPlace(): Promise<Place> {
  return getSetting<Place>('place', DEFAULT_PLACE);
}

export async function searchPlace(q: string): Promise<Place[]> {
  const res = await fetch(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(q)}&count=5&language=nl&countryCode=NL`);
  if (!res.ok) return [];
  const data = (await res.json()) as { results?: { name: string; latitude: number; longitude: number; admin1?: string }[] };
  return (data.results ?? []).map(r => ({ name: r.admin1 ? `${r.name} (${r.admin1})` : r.name, lat: r.latitude, lon: r.longitude }));
}

export async function getForecast(force = false): Promise<Forecast | null> {
  const place = await getPlace();
  const cached = await getSetting<Forecast | null>('forecast', null);
  const fresh = cached && cached.place.lat === place.lat && cached.place.lon === place.lon && Date.now() - cached.fetchedAt < 60 * 60 * 1000;
  if (fresh && !force) return cached;
  if (typeof navigator !== 'undefined' && !navigator.onLine) return cached;
  try {
    const url =
      `https://api.open-meteo.com/v1/forecast?latitude=${place.lat}&longitude=${place.lon}` +
      '&hourly=apparent_temperature,precipitation,precipitation_probability,wind_speed_10m' +
      '&daily=sunrise,sunset&timezone=Europe%2FAmsterdam&forecast_days=2';
    const res = await fetch(url);
    if (!res.ok) return cached;
    const data = (await res.json()) as Omit<Forecast, 'fetchedAt' | 'place'>;
    const f: Forecast = { fetchedAt: Date.now(), place, hourly: data.hourly, daily: data.daily };
    await setSetting('forecast', f);
    return f;
  } catch {
    return cached;
  }
}

/** Uurverwachting en zon op/onder voor één dag. */
export function dayWeather(f: Forecast, date: ISODate): { hours: HourWeather[]; sunriseMin: number; sunsetMin: number } | null {
  const hours: HourWeather[] = [];
  f.hourly.time.forEach((t, i) => {
    if (!t.startsWith(date)) return;
    hours.push({
      hour: Number(t.slice(11, 13)),
      temp: f.hourly.apparent_temperature[i],
      rain: f.hourly.precipitation[i] ?? 0,
      prob: f.hourly.precipitation_probability[i] ?? 0,
      wind: f.hourly.wind_speed_10m[i] ?? 0,
    });
  });
  const di = f.daily.time.indexOf(date);
  if (!hours.length || di < 0) return null;
  return { hours, sunriseMin: toMin(f.daily.sunrise[di].slice(11, 16)), sunsetMin: toMin(f.daily.sunset[di].slice(11, 16)) };
}
