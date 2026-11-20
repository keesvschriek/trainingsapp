// Hartslag en tempo voor rustig lopen, uit je lactaatdrempel (Garmin Fenix, november 2026).
// Rustig = 80 tot 88% van je drempelhartslag, tempo ongeveer 23 tot 36% langzamer dan je drempeltempo.
// Verandert je drempel, pas dan alleen deze twee getallen aan.

export const LTHR = 184; // drempelhartslag
export const THRESHOLD_PACE = 4 * 60 + 53; // drempeltempo in sec per km (4:53)

const fmt = (sec: number) => {
  const r = Math.round(sec / 5) * 5; // op 5 sec afgerond
  return `${Math.floor(r / 60)}:${String(r % 60).padStart(2, '0')}`;
};

export const easyHr = (): [number, number] => [Math.round(LTHR * 0.8), Math.round(LTHR * 0.88)];
export const easyPace = (): [string, string] => [fmt(THRESHOLD_PACE * 1.23), fmt(THRESHOLD_PACE * 1.36)];

/** Bijvoorbeeld "147-162 slagen, rond 6:00-6:40 /km". */
export function easyText(): string {
  const [lo, hi] = easyHr();
  const [p1, p2] = easyPace();
  return `${lo}-${hi} slagen, rond ${p1}-${p2} /km`;
}
