import assert from 'node:assert/strict';
import test from 'node:test';
import { acceptSnapshot, interpolateTime } from './bridge.mjs';

// ios-web/bridge.test.mjs
const snapshot = (patch = {}) => ({ version: 1, generation: 2, sequence: 8, trackKey: 'netease:1', time: 12, duration: 180, playing: true, ...patch });

test('accepts a current playback snapshot', () => {
  assert.equal(acceptSnapshot(null, snapshot())?.trackKey, 'netease:1');
});
test('rejects an older song generation and out of order updates', () => {
  const current = snapshot();
  assert.equal(acceptSnapshot(current, snapshot({ generation: 1, sequence: 99 })), null);
  assert.equal(acceptSnapshot(current, snapshot({ sequence: 7 })), null);
});
test('rejects malformed payloads and unknown versions', () => {
  for (const bad of [null, {}, snapshot({ version: 2 }), snapshot({ time: NaN }), snapshot({ time: -1 }), snapshot({ playing: 'yes' })]) {
    assert.equal(acceptSnapshot(null, bad), null);
  }
});
test('does not merge equal numeric media IDs from different platforms', () => {
  const next = acceptSnapshot(snapshot(), snapshot({ generation: 3, trackKey: 'qq:1' }));
  assert.equal(next?.trackKey, 'qq:1');
});
test('extrapolates monotonic playback but clamps duration and freezes paused', () => {
  assert.equal(interpolateTime(snapshot(), 1000, 1500), 12.5);
  assert.equal(interpolateTime(snapshot({ playing: false }), 1000, 1500), 12);
  assert.equal(interpolateTime(snapshot({ time: 179.9 }), 1000, 1500), 180);
  assert.equal(interpolateTime(snapshot(), 1500, 1000), 12);
});
