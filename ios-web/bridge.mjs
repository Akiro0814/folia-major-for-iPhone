// ios-web/bridge.mjs
// Reject delayed native messages before they can rewind a newer playback session.
export function acceptSnapshot(current, next) {
  if (!next || next.version !== 1 || !Number.isSafeInteger(next.generation)
      || !Number.isSafeInteger(next.sequence) || next.generation < 0 || next.sequence < 0
      || typeof next.trackKey !== 'string' || typeof next.playing !== 'boolean'
      || !Number.isFinite(next.time) || next.time < 0
      || !Number.isFinite(next.duration) || next.duration < 0) return null;
  if (current && (next.generation < current.generation
      || (next.generation === current.generation && next.sequence <= current.sequence))) return null;
  return next;
}

export function interpolateTime(snapshot, receivedAt, now) {
  const elapsed = snapshot.playing ? Math.max(0, now - receivedAt) / 1000 : 0;
  const time = snapshot.time + elapsed;
  return snapshot.duration > 0 ? Math.min(snapshot.duration, time) : time;
}
