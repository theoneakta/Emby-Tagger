import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Credentials come from environment variables
// Docker injects these via env_file in docker-compose.yml
const { EMBY_SERVER, EMBY_API_KEY, EMBY_USER_ID } = process.env;

if (!EMBY_SERVER || !EMBY_API_KEY || !EMBY_USER_ID) {
  console.error('ERROR: EMBY_SERVER, EMBY_API_KEY, and EMBY_USER_ID must be set in .env');
  process.exit(1);
}

console.log(`[emby-tag-manager] Emby server: ${EMBY_SERVER}`);
console.log(`[emby-tag-manager] User ID: ${EMBY_USER_ID}`);

const app = express();

// /api/config — sends credentials to the frontend at startup
app.get('/api/config', (req, res) => {
  res.json({ apiKey: EMBY_API_KEY, userId: EMBY_USER_ID });
});

// /emby/* — proxies all Emby API calls server-side
app.use('/emby', createProxyMiddleware({
  target: EMBY_SERVER,
  changeOrigin: true,
  pathRewrite: { '^/emby': '' },
  on: {
    error: (err, req, res) => {
      console.error('[proxy error]', err.message);
      res.status(502).json({ error: 'Could not reach Emby server', detail: err.message });
    },
  },
}));

// Static frontend
app.use(express.static(join(__dirname, 'public')));
app.get('*', (req, res) => {
  res.sendFile(join(__dirname, 'public', 'index.html'));
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`[emby-tag-manager] Running on http://0.0.0.0:${PORT}`);
});
