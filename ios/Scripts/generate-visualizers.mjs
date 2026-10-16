import { readdir, readFile, writeFile } from 'node:fs/promises';

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
console.log(`Generated ${entries.length} visualizer modes`);
