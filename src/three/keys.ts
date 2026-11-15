// Lichte koppeling oefeningnaam -> 3D-beweging, zonder three.js te laden.
export function motionKeyFor(exerciseName: string): string | null {
  const n = exerciseName.toLowerCase();
  if (n.includes('diamant')) return 'pushup-smal';
  if (n.includes('push-up') && n.includes('brede')) return 'pushup-breed';
  if (n.includes('push-up')) return 'pushup-normaal';
  return null;
}
