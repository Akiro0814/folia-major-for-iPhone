import { parseLRC, parseYRC, parseQRC, parseKRC, parseTTML, parseAwlrc } from '../src/utils/lyrics/parserCore';
import type { Line } from '../src/types';
import { DOMParser, XMLSerializer } from '@xmldom/xmldom';

// ios-web/lyrics.ts
export interface LyricPayload { original?: string; translation?: string; romanization?: string; wordTimed?: string }
function unwrapQRC(text: string): string {
  if (!text.includes('LyricContent=')) return text;
  const document = new DOMParser().parseFromString(text, 'application/xml');
  const nodes = document.getElementsByTagName('*');
  for (let i = 0; i < nodes.length; i++) {
    if (nodes[i].hasAttribute('LyricContent')) return nodes[i].getAttribute('LyricContent') ?? '';
  }
  return text;
}
// The shared AMLL parser expects Apple line IDs even for otherwise valid standard TTML.
function withLineIdentifiers(text: string): string {
  const document = new DOMParser().parseFromString(text, 'application/xml');
  const ns = 'http://music.apple.com/lyric-ttml-internal';
  document.documentElement?.setAttribute('xmlns:itunes', ns);
  const lines = document.getElementsByTagNameNS('*', 'p');
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].getAttributeNS(ns, 'key')) lines[i].setAttributeNS(ns, 'itunes:key', `native-${i}`);
  }
  return new XMLSerializer().serializeToString(document);
}
export function parseNativeLyrics(payload?: LyricPayload): Line[] {
  if (!payload) return [];
  const original = unwrapQRC(payload.original ?? '');
  const wordTimed = unwrapQRC(payload.wordTimed ?? '');
  const translation = unwrapQRC(payload.translation ?? '');
  const romanization = unwrapQRC(payload.romanization ?? '');
  const text = wordTimed || original;
  if (/<(?:\w+:)?tt(?:\s|>)/i.test(text)) return parseTTML(withLineIdentifiers(text), translation, {}, romanization).lines;
  if (/^\[\d+,\d+\]\(\d+,\d+,\d+\)/m.test(text)) return parseYRC(text, translation, {}, romanization).lines;
  if (/^\[\d+,\d+\].*\(\d+,\d+\)/m.test(text)) return parseQRC(text, translation, {}, romanization).lines;
  if (/^\[\d+,\d+\]<\d+,\d+,\d+>/m.test(text)) return parseKRC(text, translation, {}, romanization).lines;
  if (/<\d+,\d+>/.test(text)) return parseAwlrc(text, translation, {}, romanization).lines;
  return parseLRC(original || wordTimed, translation, {}, romanization).lines;
}
