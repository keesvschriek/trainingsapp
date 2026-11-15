// Gemeenschappelijke typen voor de quiz.

export interface MC {
  id: string;
  cat: string; // categorie-sleutel
  q: string;
  a: string[]; // eerste = goed, meestal 4
  why?: string;
  big?: string; // grote weergave boven de vraag, bijv. een vlag
  src?: 'bank' | 'gen' | 'pack' | 'ai';
  asOf?: string; // stand van zaken, bij actualiteit
  map?: string; // c3-code van een land om op een kaartje te markeren
}

export interface CatInfo { key: string; name: string; group: string }

export const GROUPS = ['Wereld en geschiedenis', 'Maatschappij', 'Wetenschap en techniek', 'Cultuur en vrije tijd', 'Defensie'] as const;

export const CATS: CatInfo[] = [
  { key: 'geschiedenis', name: 'Vaderlandse en Europese geschiedenis', group: 'Wereld en geschiedenis' },
  { key: 'wereldgeschiedenis', name: 'Wereldgeschiedenis', group: 'Wereld en geschiedenis' },
  { key: 'wereldleiders', name: 'Wereldleiders', group: 'Wereld en geschiedenis' },
  { key: 'aardrijkskunde', name: 'Aardrijkskunde', group: 'Wereld en geschiedenis' },
  { key: 'geopolitiek', name: 'Geopolitiek', group: 'Maatschappij' },
  { key: 'politiek', name: 'Politiek en maatschappij', group: 'Maatschappij' },
  { key: 'nederland', name: 'Nederland', group: 'Maatschappij' },
  { key: 'economie', name: 'Economie en geld', group: 'Maatschappij' },
  { key: 'religie', name: 'Religie en filosofie', group: 'Maatschappij' },
  { key: 'wetenschap', name: 'Wetenschap en lichaam', group: 'Wetenschap en techniek' },
  { key: 'natuur', name: 'Natuur en ruimte', group: 'Wetenschap en techniek' },
  { key: 'ict', name: 'Techniek en ICT', group: 'Wetenschap en techniek' },
  { key: 'uitvindingen', name: 'Uitvindingen', group: 'Wetenschap en techniek' },
  { key: 'cultuur', name: 'Taal en cultuur', group: 'Cultuur en vrije tijd' },
  { key: 'muziekfilm', name: 'Muziek en film', group: 'Cultuur en vrije tijd' },
  { key: 'eten', name: 'Eten en drinken', group: 'Cultuur en vrije tijd' },
  { key: 'sport', name: 'Sport', group: 'Cultuur en vrije tijd' },
  { key: 'defensie', name: 'Defensie en veiligheid', group: 'Defensie' },
  { key: 'zhkh', name: 'ZHKH en MARCH', group: 'Defensie' },
  { key: 'wapenleer', name: 'Wapenleer', group: 'Defensie' },
  { key: 'aaw', name: 'Ammunition Awareness (AAW)', group: 'Defensie' },
  { key: 'search', name: 'Search', group: 'Defensie' },
  { key: 'actueel', name: 'Actualiteit', group: 'Maatschappij' },
];
export const catName = (k: string) => CATS.find(c => c.key === k)?.name ?? k;

export function shuffle<T>(arr: T[], rnd: () => number = Math.random): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export function sample<T>(arr: T[], n: number, rnd: () => number = Math.random): T[] {
  return shuffle(arr, rnd).slice(0, n);
}
