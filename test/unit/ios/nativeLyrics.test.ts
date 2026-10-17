import { describe, it, expect } from 'vitest';
import { parseNativeLyrics } from '../../../ios-web/lyrics';

// test/unit/ios/nativeLyrics.test.ts
describe('native lyric payload formats', () => {
  it('preserves LRC translation and romanization', () => {
    const lines = parseNativeLyrics({ original: '[00:01.00]你好', translation: '[00:01.00]Hello', romanization: '[00:01.00]ni hao' });
    const line = lines.find(x => x.fullText === '你好');
    expect(line?.translation).toBe('Hello');
    expect(line?.romanization).toBe('ni hao');
  });
  it('detects TTML with an XML declaration', () => {
    const lines = parseNativeLyrics({ original: '<?xml version="1.0" encoding="UTF-8"?><tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="Word"><body><div><p begin="00:01.000" end="00:03.000"><span begin="00:01.000" end="00:03.000">Hello</span></p></div></body></tt>' });
    expect(lines.some(x => x.fullText.includes('Hello'))).toBe(true);
  });
  it('parses Bodian AWLRC syllables', () => {
    const lines = parseNativeLyrics({ wordTimed: '[00:01.00]<1000,1000>Hel<2000,1000>lo' });
    const line = lines.find(x => x.fullText === 'Hello');
    expect(line?.words).toHaveLength(2);
  });
  it('keeps word timing from YRC rather than falling back to plain LRC', () => {
    const lines = parseNativeLyrics({ original: '[00:01.00]Hello', wordTimed: '[1000,2000](1000,1000,0)Hel(2000,1000,0)lo' });
    const line = lines.find(x => x.fullText === 'Hello');
    expect(line?.words).toHaveLength(2);
    expect(line?.words[1].startTime).toBe(2);
  });
  it('unwraps QQ lyric XML without losing word timing', () => {
    const lines = parseNativeLyrics({ wordTimed: '<?xml version="1.0"?><QrcInfos><Lyric_1 LyricContent="[1000,2000]Hel(1000,1000)lo(2000,1000)" /></QrcInfos>' });
    const line = lines.find(x => x.fullText === 'Hello');
    expect(line?.words).toHaveLength(2);
    expect(line?.startTime).toBe(1);
  });
});
