import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// Always served from a domain root (Railway), never a sub-path.
const base = '/';

export default defineConfig({
  base,
  define: {
    __BUILD_ID__: JSON.stringify(process.env.GITHUB_SHA?.slice(0, 7) ?? new Date().toISOString()),
  },
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'favicon-32.png', 'favicon-16.png', 'apple-touch-icon.png'],
      manifest: {
        name: 'Bullet Life',
        short_name: 'Bullet Life',
        description: 'A calm notebook for rapid logging, one day at a time.',
        lang: 'en',
        start_url: base,
        scope: base,
        display: 'standalone',
        background_color: '#FAF8F4',
        theme_color: '#FAF8F4',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'icons/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,woff2}'],
        navigateFallback: `${base}index.html`,
        // Dexie Cloud lives on another origin; never intercept it.
        navigateFallbackDenylist: [/^\/__/],
      },
    }),
  ],
});
