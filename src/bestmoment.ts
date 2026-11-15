// Beste loopmoment: zoekt in de uurverwachting het blok dat het droogst, lichtst en het prettigst is,
// buiten je werktijd. Puur rekenwerk, zodat het goed te testen is.

export interface HourWeather {
  hour: number; // 0-23
  temp: number; // gevoelstemperatuur °C
  rain: number; // mm in dat uur
  prob: number; // kans op neerslag %
  wind: number; // km/u
}

export interface MomentInput {
  hours: HourWeather[];
  minutes: number; // duur van de training
  nowMin: number; // minuten sinds middernacht
  sunriseMin: number;
  sunsetMin: number;
  busy: [number, number][]; // bezette blokken in minuten, bijv. werk
  earliest?: number; // vroegst redelijke start, standaard 06:00
  latest?: number; // laatst redelijke eind, standaard 22:00
}

export interface Moment {
  start: number;
  end: number;
  score: number;
  rain: number; // verwachte mm in het blok
  prob: number; // hoogste kans in het blok
  dark: boolean;
  temp: number;
}

const at = (hours: HourWeather[], min: number) => hours.find(h => h.hour === Math.floor(min / 60));

/** Score per blok: lager is beter. */
export function scoreWindow(inp: MomentInput, start: number): Moment | null {
  const end = start + inp.minutes;
  let rain = 0;
  let prob = 0;
  let darkMin = 0;
  let temps: number[] = [];
  let windMax = 0;
  for (let t = start; t < end; t += 15) {
    const h = at(inp.hours, t);
    if (!h) return null;
    rain += h.rain / 4;
    prob = Math.max(prob, h.prob);
    temps.push(h.temp);
    windMax = Math.max(windMax, h.wind);
    if (t < inp.sunriseMin || t >= inp.sunsetMin) darkMin += 15;
  }
  const temp = temps.reduce((a, b) => a + b, 0) / temps.length;
  let score = rain * 12 + prob / 12 + (darkMin / inp.minutes) * 3;
  if (temp < 0) score += -temp * 0.4;
  if (temp > 22) score += (temp - 22) * 0.6;
  if (windMax > 30) score += (windMax - 30) / 10;
  return { start, end, score: Math.round(score * 100) / 100, rain: Math.round(rain * 10) / 10, prob, dark: darkMin > inp.minutes / 2, temp: Math.round(temp) };
}

export function bestMoments(inp: MomentInput): Moment[] {
  const earliest = inp.earliest ?? 6 * 60;
  const latest = inp.latest ?? 22 * 60;
  const from = Math.max(earliest, Math.ceil((inp.nowMin + 10) / 15) * 15);
  const list: Moment[] = [];
  for (let s = from; s + inp.minutes <= latest; s += 15) {
    const e = s + inp.minutes;
    if (inp.busy.some(([a, b]) => s < b && e > a)) continue;
    const m = scoreWindow(inp, s);
    if (m) list.push(m);
  }
  return list.sort((a, b) => a.score - b.score || a.start - b.start);
}

/** Beste blok, plus het beste alternatief in een ander deel van de dag (minstens 2 uur ervandaan). */
export function pickMoments(inp: MomentInput): { best?: Moment; alt?: Moment } {
  const all = bestMoments(inp);
  const best = all[0];
  if (!best) return {};
  const alt = all.find(m => Math.abs(m.start - best.start) >= 120);
  return { best, alt };
}

export function describe(m: Moment): string {
  const parts: string[] = [];
  parts.push(m.rain < 0.2 && m.prob < 30 ? 'droog' : m.rain < 1 ? `kans op een bui (${m.prob}%)` : `regen, ongeveer ${String(m.rain).replace('.', ',')} mm`);
  parts.push(m.dark ? 'donker' : 'licht');
  parts.push(`voelt als ${m.temp}°`);
  return parts.join(', ');
}
