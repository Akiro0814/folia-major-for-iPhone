import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'node:path';
import { icuFoliaDataPlugin } from '../dev/icuFolia/icuFoliaDataPlugin.mjs';

// ios-web/vite.config.ts
export default defineConfig({
  root: resolve(import.meta.dirname),
  base: './',
  publicDir: resolve(import.meta.dirname, '../public'),
  plugins: [react(), icuFoliaDataPlugin(), {
    name: 'ios-file-script',
    enforce: 'post',
    generateBundle(_options, bundle) {
      for (const asset of Object.values(bundle)) {
        if (asset.type === 'asset' && asset.fileName.endsWith('.html')) {
          asset.source = String(asset.source).replace(/type="module"/g, 'defer').replace(/ crossorigin/g, '');
        }
      }
    },
  }],
  resolve: { alias: { '@': resolve(import.meta.dirname, '../src') } },
  define: {
    __APP_VERSION__: JSON.stringify('0.1.0'), __APP_VERSION_LABEL__: JSON.stringify('iOS'),
    __COMMIT_HASH__: JSON.stringify('ios'), __GIT_BRANCH__: JSON.stringify('main'),
    __BUILD_REPO__: JSON.stringify('Akiro0814/folia-major-for-iPhone'),
    __BUILD_COMMIT__: JSON.stringify('ios'), __BUILD_KIND__: JSON.stringify('ios'),
    __BUILD_HOST__: JSON.stringify(''), __APP_RELEASE_CHANNEL__: JSON.stringify('release'),
    __DOCKER_STACK_VERSION__: JSON.stringify(''),
  },
  build: {
    outDir: '../ios/Folia/Resources/Lyrics', emptyOutDir: true, target: 'safari26',
    chunkSizeWarningLimit: 18000, cssCodeSplit: false,
    rolldownOptions: { output: { format: 'iife', inlineDynamicImports: true } },
  },
});
