import { useLiveQuery } from 'dexie-react-hooks';
import { getSetting, type Workout } from './db';
import type { ISODate } from './dates';

// Wat het scheelt als de auto blijft staan omdat je loopt of fietst.
// Alleen ritten die je zelf aanvinkt tellen mee: rijdt de auto toch (bijvoorbeeld met iemand anders), dan bespaar je niets.
// CO2: benzine E10, 2,821 kg per liter inclusief winning en productie (co2emissiefactoren.nl, well-to-wheel).

export interface CarSettings {
  km: number; // enkele reis woon-werk
  usage: number; // liter per 100 km
  price: number; // euro per liter
  extraPerKm: number; // onderhoud en slijtage per km (optioneel)
}

export const DEFAULT_CAR: CarSettings = { km: 15, usage: 6.5, price: 2.3, extraPerKm: 0 };
export const CO2_PER_LITER = 2.821;

export async function getCar(): Promise<CarSettings> {
  return { ...DEFAULT_CAR, ...(await getSetting<Partial<CarSettings>>('car', {})) };
}
export function useCar(): CarSettings {
  return useLiveQuery(getCar, [], DEFAULT_CAR);
}

export interface Saved { trips: number; km: number; liters: number; euro: number; co2: number }

export function savedFor(workouts: Workout[], car: CarSettings, from?: ISODate, to?: ISODate): Saved {
  const trips = workouts.filter(w => !w.deleted && w.carFree && (!from || w.date >= from) && (!to || w.date <= to)).length;
  const km = trips * car.km;
  const liters = (km * car.usage) / 100;
  return {
    trips,
    km,
    liters: Math.round(liters * 10) / 10,
    euro: Math.round((liters * car.price + km * car.extraPerKm) * 100) / 100,
    co2: Math.round(liters * CO2_PER_LITER * 10) / 10,
  };
}

export const euro = (x: number) => `€ ${x.toFixed(2).replace('.', ',')}`;
