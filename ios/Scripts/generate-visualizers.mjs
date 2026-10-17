import { readdir, readFile, writeFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

// ios/Scripts/generate-visualizers.mjs
const root = new URL('../../', import.meta.url);
const entries = [];
for (const directory of await readdir(new URL('src/components/visualizer/', root), { withFileTypes: true })) {
  if (!directory.isDirectory() || directory.name === 'backgrounds') continue;
  const source = await readFile(new URL(`src/components/visualizer/${directory.name}/entry.tsx`, root), 'utf8').catch(() => '');
  const mode = source.match(/mode:\s*'([^']+)'/)?.[1];
  if (mode) entries.push({ mode, label: source.match(/labelFallback:\s*'([^']+)'/)?.[1] ?? mode });
}
if (!entries.length) throw new Error('No visualizer registry entries found');
await writeFile(new URL('ios/Folia/Resources/visualizers.json', root), JSON.stringify(entries, null, 2) + '\n');
const typeSource = await readFile(new URL('src/types.ts', root), 'utf8');
const constantsSource = stripTypeScriptTypes(typeSource, { mode: 'transform' }).replace(/^import .*;\r?$/gm, '');
const constants = await import(`data:text/javascript;base64,${Buffer.from(constantsSource).toString('base64')}`);
const tunings = Object.fromEntries(Object.entries(constants)
  .filter(([name]) => /^DEFAULT_\w+_TUNING$/.test(name))
  .map(([name, value]) => [name.slice(8, -7).toLowerCase(), value]));
await writeFile(new URL('ios/Folia/Resources/tuning-defaults.json', root), JSON.stringify(tunings, null, 2) + '\n');
console.log(`Generated ${entries.length} visualizer modes`);
