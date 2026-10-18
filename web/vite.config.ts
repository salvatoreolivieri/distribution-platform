import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// Locally the APIs run in docker-compose; the dev server proxies them so the browser sees one origin.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/auth': { target: 'http://localhost:8080', rewrite: (p) => p.replace(/^\/auth/, '') },
      '/api': { target: 'http://localhost:8090', rewrite: (p) => p.replace(/^\/api/, '') },
    },
  },
});
