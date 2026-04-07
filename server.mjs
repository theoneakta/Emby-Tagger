// Emby Tag Manager — Node.js / Docker server
//
// Serves index.html and exposes /api/config so credentials stay in .env
// and never touch the browser's local filesystem.
//
// In Docker/Node mode the browser calls Emby directly using the serverUrl
// returned by /api/config — no proxy needed as long as your Emby server
// is reachable from the client machine.
//
// Required env vars (copy .env.example → .env):
//   EMBY_SERVER_URL   Full URL to Emby — no trailing slash
//   EMBY_API_KEY      Emby API key
//   EMBY_USER_ID      Emby user ID (hex string)
//   PORT              (optional) defaults to 3000

import express from 'express';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3000;

// ── Validate required env vars on startup ────────────────────────────────────
const REQUIRED = ['EMBY_SERVER_URL', 'EMBY_API_KEY', 'EMBY_USER_ID'];
const missing = REQUIRED.filter(k => !process.env[k]);
if (missing.length) {
  console.error(`[emby-tagger] Missing required env vars: ${missing.join(', ')}`);
  console.error('Copy .env.example → .env and fill in your values.');
  process.exit(1);
}

const config = {
  serverUrl: process.env.EMBY_SERVER_URL.replace(/\/+$/, ''),
  apiKey:    process.env.EMBY_API_KEY,
  userId:    process.env.EMBY_USER_ID,
};

// ── Routes ───────────────────────────────────────────────────────────────────

// Config endpoint — returns credentials to the browser
// The browser uses serverUrl to call Emby directly (no proxy)
app.get('/api/config', (req, res) => {
  res.json(config);
});

// Health check endpoint (used by docker-compose healthcheck)
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', serverUrl: config.serverUrl });
});

// Serve index.html for all other routes (SPA catch-all)
app.use(express.static(__dirname));
app.get('*', (req, res) => {
  res.sendFile(join(__dirname, 'index.html'));
});

// ── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`[emby-tagger] Running on http://localhost:${PORT}`);
  console.log(`[emby-tagger] Emby server: ${config.serverUrl}`);
});
