import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

// ios-web/paused-render.test.mjs
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 393, height: 620 } });
  await page.goto(pathToFileURL(resolve('ios/Folia/Resources/Lyrics/index.html')).href);
  await page.waitForFunction(() => typeof window.foliaReceive === 'function');
  await page.evaluate(() => window.foliaReceive({
    version: 1, generation: 1, sequence: 1, trackKey: 'validation:paused', time: 3, duration: 30,
    playing: false, visible: true, title: 'Validation', artist: '', lyrics: { original: '[00:00.00]Hello\n[00:02.00]Music\n[00:06.00]Next' },
    settings: { renderer: 'classic', background: 'common', fontSize: 36 }, daylight: false,
  }));
  await page.waitForTimeout(1500);
  const opacity = await page.locator('.will-change-transform.whitespace-nowrap').filter({ hasText: 'Music' })
    .first().evaluate(element => Number(getComputedStyle(element).opacity));
  assert.ok(opacity > 0.4, `Paused first frame must reveal current word; opacity=${opacity}`);
  console.log('PASS paused initial lyric is visible');
} finally { await browser.close(); }
