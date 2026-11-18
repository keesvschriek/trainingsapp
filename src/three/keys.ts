// Lichte koppeling oefeningnaam -> 3D-beweging, zonder three.js te laden.
export function motionKeyFor(exerciseName: string): string | null {
  const n = exerciseName.toLowerCase();
  const slow = n.includes('3 sec zakken');
  const s = slow ? '-slow' : '';
  if (n.includes('diamant')) return 'pushup-smal';
  if (n.includes('push-up') && n.includes('brede')) return 'pushup-breed';
  if (n.includes('push-up') && n.includes('verhoogd')) return `pushup-verhoogd${s}`;
  if (n.includes('push-up')) return `pushup-normaal${s}`;
  if (n.includes('goblet')) return `squat${s}`;
  if (n.includes('kettlebell squat')) return 'squat-rack';
  if (n.includes('swing')) return 'swing';
  if (n.includes('clean and press')) return 'cleanpress';
  if (n.includes('chin-up')) return `chinup${s}`;
  if (n.includes('pull-up')) return `pullup${s}`;
  if (n.includes('row')) return 'row';
  if (n.includes('curl')) return `curl${s}`;
  if (n.includes('face pull')) return 'facepull';
  if (n.includes('floor press')) return n.includes('pauze') ? 'floorpress-pause' : 'floorpress';
  if (n.includes('strikte press')) return 'press';
  if (n.includes('zijwaarts')) return 'lateral';
  if (n.includes('triceps')) return 'triceps';
  if (n.includes('kuit')) return 'calf';
  return null;
}
