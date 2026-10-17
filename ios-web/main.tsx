import React, { useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { useMotionValue } from 'framer-motion';
import { Buffer } from 'buffer';
import VisualizerRenderer from '../src/components/visualizer/VisualizerRenderer';
import { DEFAULT_THEME, DAYLIGHT_THEME } from '../src/services/baseThemes';
import { installGlobalVisualizerFrameRateLimiter, setGlobalVisualizerFrameRate } from '../src/utils/frameRateLimiter';
import { hasVisualizerMode } from '../src/components/visualizer/registry';
import type { Line } from '../src/types';
import type { VisualizerTuningBundle } from '../src/components/visualizer/tuningRegistry';
import type { VisualizerBackgroundConfig } from '../src/components/visualizer/backgrounds/definition';
import { acceptSnapshot, interpolateTime } from './bridge.mjs';
import { parseNativeLyrics } from './lyrics';
import '../src/i18n/config';
import '../src/index.css';
import './surface.css';

// ios-web/main.tsx
(globalThis as any).Buffer = Buffer;
installGlobalVisualizerFrameRateLimiter();
setGlobalVisualizerFrameRate(60);
const native = () => (window as any).webkit?.messageHandlers?.folia;
type Snapshot = {
  version: number; generation: number; sequence: number; trackKey: string;
  time: number; duration: number; playing: boolean; visible: boolean;
  title: string; artist: string; album: string; coverUrl?: string;
  lyrics?: { original: string; translation: string; romanization: string; wordTimed: string };
  settings: { renderer: string; background: string; showTranslation: boolean; showRomanization: boolean; lyricOffset: number; fontSize: number; themeColors?: string[]; visualizerTunings?: Record<string, Record<string, unknown>> };
  daylight: boolean; reduceMotion: boolean;
};

function LyricsSurface() {
  const [state, setState] = useState<Snapshot | null>(null);
  const clock = useRef<{ snapshot: Snapshot; receivedAt: number } | null>(null);
  const [lineIndex, setLineIndex] = useState(-1);
  const currentTime = useMotionValue(0);
  const zero = useMotionValue(0);
  const audioBands = useMemo(() => ({ bass: zero, lowMid: zero, mid: zero, vocal: zero, treble: zero }), [zero]);
  const lines = useMemo(() => {
    try { return parseNativeLyrics(state?.lyrics); }
    catch { native()?.postMessage({ type: 'error', message: 'Lyrics parsing failed' }); return []; }
  }, [state?.lyrics]);
  const latestLines = useRef(lines);
  latestLines.current = lines;
  useEffect(() => {
    if (!state) return;
    const frame = requestAnimationFrame(() => native()?.postMessage({ type: 'rendered', version: 1 }));
    return () => cancelAnimationFrame(frame);
  }, [state?.generation, state?.settings.renderer]);

  useEffect(() => {
    (window as any).foliaReceive = (next: Snapshot) => {
      const accepted = acceptSnapshot(clock.current?.snapshot, next) as Snapshot | null;
      if (!accepted) return;
      clock.current = { snapshot: accepted, receivedAt: performance.now() };
      const time = Math.max(0, accepted.time + (accepted.settings.lyricOffset || 0));
      currentTime.set(time);
      let index = -1;
      for (let i = 0; i < latestLines.current.length; i++) {
        if (latestLines.current[i].startTime > time) break;
        index = i;
      }
      setLineIndex(previous => previous === index ? previous : index);
      // Time-only snapshots do not rerender React; renderer time travels through MotionValue.
      setState(previous => {
        const { time: _t, sequence: _s, ...content } = accepted;
        const { time: _pt, sequence: _ps, ...oldContent } = previous ?? {} as Snapshot;
        return JSON.stringify(content) === JSON.stringify(oldContent) ? previous : accepted;
      });
    };
    native()?.postMessage({ type: 'ready', version: 1 });
    return () => { delete (window as any).foliaReceive; };
  }, [currentTime]);

  useEffect(() => {
    if (!state?.visible || document.hidden) return;
    let frame = 0;
    let previousIndex = -2;
    const tick = () => {
      const value = clock.current;
      if (!value) return;
      const time = Math.max(0, interpolateTime(value.snapshot, value.receivedAt, performance.now()) + (value.snapshot.settings.lyricOffset || 0));
      currentTime.set(time);
      let low = 0, high = lines.length - 1, index = -1;
      while (low <= high) {
        const mid = (low + high) >>> 1;
        if (lines[mid].startTime <= time) { index = mid; low = mid + 1; } else high = mid - 1;
      }
      if (index !== previousIndex) { previousIndex = index; setLineIndex(index); }
      if (value.snapshot.playing && !document.hidden) frame = requestAnimationFrame(tick);
    };
    tick();
    return () => cancelAnimationFrame(frame);
  }, [state?.visible, state?.playing, state?.generation, state?.settings.lyricOffset, lines, currentTime]);

  if (!state) return <div className="empty">Folia</div>;
  const baseTheme = state.daylight ? DAYLIGHT_THEME : DEFAULT_THEME;
  const colors = state.settings.themeColors;
  const theme = colors?.length === 4 && colors.every(c => /^#[0-9a-f]{6}$/i.test(c))
    ? { ...baseTheme, backgroundColor: colors[0], primaryColor: colors[1], accentColor: colors[2], secondaryColor: colors[3] } : baseTheme;
  return <VisualizerRenderer
    mode={hasVisualizerMode(state.settings.renderer) ? state.settings.renderer : 'classic'}
    currentTime={currentTime} currentLineIndex={lineIndex} lines={lines}
    visualizerTunings={state.settings.visualizerTunings as VisualizerTuningBundle}
    theme={theme}
    isDaylight={state.daylight} audioPower={zero} audioBands={audioBands}
    songTitle={state.title} songArtist={state.artist} songAlbum={state.album} coverUrl={state.coverUrl}
    background={{ mode: state.settings.background,
      monet: { tuning: state.settings.visualizerTunings?.monet_background },
      nomand: { tuning: state.settings.visualizerTunings?.nomand_background },
      latent: { tuning: state.settings.visualizerTunings?.latent_background },
      sora: { tuning: state.settings.visualizerTunings?.sora_background },
    } as VisualizerBackgroundConfig}
    staticMode={state.reduceMotion || !state.visible} backgroundStaticMode={state.reduceMotion || !state.visible}
    paused={!state.playing || !state.visible} isPlayerChromeHidden
    lyricsFontScale={state.settings.fontSize / 36}
    hideTranslationSubtitle={!state.settings.showTranslation}
    subtitleContentMode={state.settings.showRomanization ? (state.settings.showTranslation ? 'both' : 'romanization') : (state.settings.showTranslation ? 'translation' : 'none')}
    onLyricLineSeek={time => native()?.postMessage({ type: 'seek', time })}
  />;
}

class SurfaceBoundary extends React.Component<React.PropsWithChildren, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  componentDidCatch() { native()?.postMessage({ type: 'error', message: 'Visualizer unavailable' }); }
  render() { return this.state.failed ? <div className="empty">歌词画面无法加载，请切换歌词模式</div> : this.props.children; }
}
window.addEventListener('error', () => native()?.postMessage({ type: 'error', message: 'Lyrics resource error' }));
createRoot(document.getElementById('root')!).render(<SurfaceBoundary><LyricsSurface /></SurfaceBoundary>);
