import { chromium } from 'playwright';
import { readFile, mkdir } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

// ios-web/smoke.mjs
const modes = JSON.parse(await readFile('ios/Folia/Resources/visualizers.json', 'utf8'));
await mkdir('artifacts/ios/web-smoke', { recursive: true });
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 393, height: 620 }, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', error => errors.push(error.message));
await page.addInitScript(() => {
  window.foliaMessages = [];
  window.webkit = { messageHandlers: { folia: { postMessage: message => window.foliaMessages.push(message) } } };
});
try {
  await page.goto(pathToFileURL(resolve('ios/Folia/Resources/Lyrics/index.html')).href);
  await page.waitForFunction(() => typeof window.foliaReceive === 'function');
  for (const [i, entry] of modes.entries()) {
    await page.evaluate(({ mode, i }) => window.foliaReceive({
      version: 1, generation: i + 1, sequence: i + 1, trackKey: `test:${i}`, time: 3, duration: 30,
      playing: false, visible: true, title: 'Folia', artist: 'Renderer validation', album: '', coverUrl: '',
      lyrics: { original: '[00:00.00]辞曲新境\n[00:02.00]让音乐与文字相遇\n[00:06.00]Lyrics reimagined', translation: '', romanization: '', wordTimed: '' },
      settings: { renderer: mode, background: 'common', showTranslation: true, showRomanization: false, lyricOffset: 0, fontSize: 36 },
      daylight: false, reduceMotion: true,
    }), { mode: entry.mode, i });
    await page.waitForTimeout(350);
    const failures = await page.evaluate(() => window.foliaMessages.filter(x => x.type === 'error'));
    assert.equal(failures.length, 0, `${entry.mode}: ${JSON.stringify(failures)}`);
    assert.ok((await page.locator('#root').innerHTML()).length > 100, `${entry.mode}: empty renderer`);
    await page.screenshot({ path: `artifacts/ios/web-smoke/${entry.mode}.png` });
    console.log(`PASS ${entry.mode}`);
  }
  assert.deepEqual(errors, [], 'JavaScript runtime errors');
  await page.setViewportSize({ width: 844, height: 350 });
  await page.screenshot({ path: 'artifacts/ios/web-smoke/landscape.png' });
} finally { await browser.close(); }
