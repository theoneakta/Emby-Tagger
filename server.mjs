// Emby Tag Manager — Node.js / Docker server
//
// Serves index.html and exposes:
//   GET  /api/config          → credentials to the browser
//   GET  /api/health          → docker healthcheck
//   GET  /api/cron/status     → cron state (last run, next run, stats, logs)
//   POST /api/cron/csv        → save CSV to server cache (body: { csv: "…" })
//   GET  /api/cron/csv        → retrieve the cached CSV
//   POST /api/cron/run        → trigger an immediate cron run
//   DELETE /api/cron/csv      → clear cached CSV (disables cron)
//
// Required env vars (copy .env.example → .env):
//   EMBY_SERVER_URL      Full URL to Emby — no trailing slash
//   EMBY_API_KEY         Emby API key
//   EMBY_USER_ID         Emby user ID (hex string)
//   PORT                 (optional) defaults to 3000
//   CRON_INTERVAL_HOURS  (optional) hours between auto-tag runs, defaults to 1

import express from 'express';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3000;
const CRON_INTERVAL_HOURS = parseFloat(process.env.CRON_INTERVAL_HOURS || '1');
const CRON_INTERVAL_MS = CRON_INTERVAL_HOURS * 60 * 60 * 1000;

// ── Data directory for persistence ───────────────────────────────────────────
// In Docker the working directory is ephemeral; mount a volume at /data to
// survive restarts. Falls back to a local ./data folder for Node mode.
const DATA_DIR = existsSync('/data') ? '/data' : join(__dirname, 'data');
if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
const CSV_PATH    = join(DATA_DIR, 'auto_tag.csv');
const STATUS_PATH = join(DATA_DIR, 'cron_status.json');

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

// ── Cron state ────────────────────────────────────────────────────────────────
let cronStatus = {
  running:   false,
  lastRun:   null,   // ISO string
  nextRun:   null,   // ISO string
  lastStats: { applied: 0, skipped: 0, errors: 0, newMovies: 0 },
  logs:      [],     // last 200 log lines
};

// Load persisted status (survives restarts when /data is mounted)
try {
  if (existsSync(STATUS_PATH)) {
    const saved = JSON.parse(readFileSync(STATUS_PATH, 'utf8'));
    cronStatus = { ...cronStatus, ...saved, running: false };
  }
} catch (e) { /* ignore corrupt file */ }

function saveStatus() {
  try { writeFileSync(STATUS_PATH, JSON.stringify(cronStatus), 'utf8'); } catch (e) {}
}

function cronLog(msg, type = 'info') {
  const line = { ts: new Date().toISOString(), msg, type };
  cronStatus.logs.unshift(line);
  if (cronStatus.logs.length > 200) cronStatus.logs = cronStatus.logs.slice(0, 200);
  console.log(`[cron] [${type}] ${msg}`);
}

// ── CSV helpers ───────────────────────────────────────────────────────────────
function loadCsv() {
  if (!existsSync(CSV_PATH)) return null;
  try { return readFileSync(CSV_PATH, 'utf8'); } catch (e) { return null; }
}

function saveCsv(raw) {
  writeFileSync(CSV_PATH, raw, 'utf8');
}

// ── Emby API helpers (server-side) ───────────────────────────────────────────
const EMBY_HEADERS = {
  'X-Emby-Token': config.apiKey,
  'Content-Type': 'application/json',
};

async function embyGet(path) {
  const url = config.serverUrl + path;
  const r = await fetch(url, { headers: EMBY_HEADERS });
  if (!r.ok) throw new Error(`Emby GET ${path} → HTTP ${r.status}`);
  return r.json();
}

async function embyPost(path, body) {
  const url = config.serverUrl + path;
  const r = await fetch(url, { method: 'POST', headers: EMBY_HEADERS, body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`Emby POST ${path} → HTTP ${r.status}`);
  return r;
}

async function fetchAllMovies() {
  const data = await embyGet(
    `/emby/Users/${config.userId}/Items` +
    `?IncludeItemTypes=Movie&Recursive=true&Fields=Tags,TagItems,Path,ProductionYear&Limit=9999`
  );
  return (data.Items || []).map(m => ({
    id:       m.Id,
    name:     m.Name,
    year:     m.ProductionYear || '',
    path:     m.Path || '',
    tags:     (m.TagItems || []).map(t => t.Name),
    tagItems: m.TagItems || [],
  }));
}

async function applyTagsToMovie(movieId, tagsToAdd) {
  // Fetch the full item so we can POST it back with extra tags
  const item = await embyGet(`/emby/Users/${config.userId}/Items/${movieId}`);
  const existing = new Set((item.TagItems || []).map(t => t.Name));
  const toAdd = tagsToAdd.filter(t => !existing.has(t));
  if (!toAdd.length) return { added: [], skipped: tagsToAdd };
  const newTagItems = [...(item.TagItems || []), ...toAdd.map(t => ({ Name: t, Id: 0 }))];
  await embyPost(`/emby/Items/${movieId}`, { ...item, TagItems: newTagItems });
  return { added: toAdd, skipped: tagsToAdd.filter(t => existing.has(t)) };
}

// ── Title normalisation (mirrors index.html cleanTitle / normaliseEmby) ───────
function cleanTitle(raw) {
  let s = raw;
  s = s.replace(/\s*\.(mkv|mp4|avi|m4v|mov|wmv|flv|ts)$/i, '');
  s = s.replace(/\s+(mkv|mp4|avi|m4v|mov|wmv|flv|ts)$/i, '');
  s = s.replace(/^\[\s*(?:www\.)?[A-Za-z0-9\-]+\.[a-z]{2,4}\s*\]\s*-?\s*/, '');
  s = s.replace(/^\[.*?\]\s*/, '');
  s = s.replace(/\./g, ' ');
  s = s.replace(/[\[\(]?(19|20)\d{2}[\]\)]?.*/, '');
  s = s.replace(/\b(UNRATED|EXTENDED|THEATRICAL|DIRECTORS?\.?CUT|REMASTERED|REPACK|HC|LIMITED|INTERNAL|UNCENSORED|FRENCH|TRUEFRENCH|DVDRIP|BDRIP|BRRIP|WEBRIP|BLURAY|HDTV|HDRIP|XVID|H264|H265|HEVC|AAC|AC3|DTS|MULTI)\b.*/i, '');
  s = s.replace(/\[.*?\]/g, '').replace(/\{.*?\}/g, '');
  s = s.replace(/\([^)]*\b(Action|Adventure|BluRay|BRRip|WEBRip|HDRip|DVDRip|YTS|x264|x265|AAC|AC3|DTS|HDTV|Dual|Anime)\b[^)]*\)/gi, '');
  s = s.replace(/\s*-\s*[A-Za-z0-9][A-Za-z0-9\.\[\]]{1,25}$/, '');
  s = s.replace(/\.\s+\./g, ' ').replace(/\s+\./g, ' ').replace(/\.\s+/g, ' ');
  s = s.replace(/_+/g, ' ').replace(/\[\s*$/, '').replace(/\(\s*$/, '').replace(/\s*-\s*$/, '').replace(/\s*\.\s*$/, '');
  s = s.replace(/\s{2,}/g, ' ').trim();
  return s.toLowerCase();
}

function normaliseEmby(name) {
  return name.replace(/\s*\(\d{4}\)\s*$/, '').toLowerCase().trim();
}

function bare(s) { return s.replace(/[^a-z0-9]/g, ''); }

function wordOverlap(a, b) {
  const wa = a.split(/\s+/).filter(w => w.length > 1);
  const wb = new Set(b.split(/\s+/).filter(w => w.length > 1));
  if (!wa.length) return 0;
  return wa.filter(w => wb.has(w)).length / wa.length;
}

function buildLookup(movies) {
  const m = new Map();
  movies.forEach(mv => {
    const k = normaliseEmby(mv.name);
    if (!m.has(k)) m.set(k, mv);
  });
  return m;
}

function findMovie(cleaned, lookup) {
  if (lookup.has(cleaned)) return lookup.get(cleaned);
  const noArt = cleaned.replace(/^(the|a|an) /, '');
  for (const [k, v] of lookup) { if (k.replace(/^(the|a|an) /, '') === noArt) return v; }
  const cb = bare(cleaned);
  if (cb.length >= 4) { for (const [k, v] of lookup) { if (bare(k) === cb) return v; } }
  if (cb.length >= 6) { for (const [k, v] of lookup) { const eb = bare(k); if (eb.startsWith(cb) || cb.startsWith(eb)) return v; } }
  const words = cleaned.split(/\s+/).filter(w => w.length > 1);
  if (words.length >= 3) {
    let best = null, bestScore = 0;
    for (const [k, v] of lookup) { const sc = wordOverlap(cleaned, k); if (sc > bestScore) { bestScore = sc; best = v; } }
    if (bestScore >= 0.80) return best;
  }
  return null;
}

// ── Parse CSV (mirrors index.html scanCsv logic) ──────────────────────────────
// Format: MovieFolderName,Tag1,Tag2,...  (header row is skipped)
function parseCsvRows(raw) {
  return raw
    .trim()
    .split('\n')
    .map(l => l.trim())
    .filter(Boolean)
    .filter(l => !/^movie/i.test(l.split(',')[0]) && l.includes(','))
    .map(line => {
      const parts = line.split(',').map(p => p.trim()).filter(Boolean);
      if (parts.length < 2) return null;
      const rawFolder = parts[0];
      const tags = [...new Set(parts.slice(1, 6).filter(Boolean))];
      return { rawFolder, tags };
    })
    .filter(Boolean);
}

// ── Core auto-tag runner ──────────────────────────────────────────────────────
async function runAutoTag() {
  if (cronStatus.running) {
    cronLog('Already running — skipped.', 'info');
    return;
  }
  const csvRaw = loadCsv();
  if (!csvRaw) {
    cronLog('No CSV cached — skipping run. Upload a CSV via the Auto-tag tab.', 'info');
    return;
  }

  cronStatus.running = true;
  cronStatus.lastRun = new Date().toISOString();
  const stats = { applied: 0, skipped: 0, errors: 0, newMovies: 0 };
  cronLog('─── Auto-tag run started ───', 'info');

  try {
    cronLog('Fetching movie library from Emby…', 'info');
    const movies = await fetchAllMovies();
    cronLog(`Library: ${movies.length} movies`, 'info');

    const lookup = buildLookup(movies);
    const csvRows = parseCsvRows(csvRaw);
    cronLog(`CSV rows parsed: ${csvRows.length}`, 'info');

    // Only process movies that are MISSING at least one of the CSV tags
    // (i.e., newly added movies that haven't been tagged yet)
    let toProcess = 0;
    for (const row of csvRows) {
      const cleaned = cleanTitle(row.rawFolder);
      const movie = findMovie(cleaned, lookup);
      if (!movie) continue;

      const missingTags = row.tags.filter(t => !movie.tags.includes(t));
      if (!missingTags.length) {
        stats.skipped += row.tags.length;
        continue;
      }

      toProcess++;
      try {
        const res = await applyTagsToMovie(movie.id, missingTags);
        if (res.added.length) {
          stats.newMovies++;
          stats.applied += res.added.length;
          cronLog(`+ ${movie.name}: added [${res.added.join(', ')}]`, 'ok');
        }
        if (res.skipped.length) {
          stats.skipped += res.skipped.length;
        }
        // Small delay to avoid hammering Emby
        await new Promise(r => setTimeout(r, 80));
      } catch (e) {
        stats.errors++;
        cronLog(`! ${movie.name}: ${e.message}`, 'err');
      }
    }

    cronLog(
      `─── Done — ${stats.applied} tag(s) applied to ${stats.newMovies} movie(s), ` +
      `${stats.skipped} already set, ${stats.errors} error(s) ───`,
      stats.errors ? 'err' : 'ok'
    );
  } catch (e) {
    cronLog(`Fatal error: ${e.message}`, 'err');
    stats.errors++;
  } finally {
    cronStatus.running = false;
    cronStatus.lastStats = stats;
    scheduleNextRun();
    saveStatus();
  }
}

// ── Scheduler ─────────────────────────────────────────────────────────────────
let cronTimer = null;

function scheduleNextRun() {
  if (cronTimer) clearTimeout(cronTimer);
  const next = new Date(Date.now() + CRON_INTERVAL_MS);
  cronStatus.nextRun = next.toISOString();
  cronTimer = setTimeout(() => runAutoTag(), CRON_INTERVAL_MS);
  console.log(`[cron] Next auto-tag run scheduled at ${next.toLocaleString()}`);
}

// ── Express middleware ─────────────────────────────────────────────────────────
app.use(express.json({ limit: '5mb' }));

// ── Routes ────────────────────────────────────────────────────────────────────

// Config endpoint
app.get('/api/config', (req, res) => {
  res.json(config);
});

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', serverUrl: config.serverUrl });
});

// Cron status
app.get('/api/cron/status', (req, res) => {
  const csvExists = existsSync(CSV_PATH);
  let csvRows = 0;
  if (csvExists) {
    try { csvRows = parseCsvRows(readFileSync(CSV_PATH, 'utf8')).length; } catch (e) {}
  }
  res.json({
    ...cronStatus,
    csvCached: csvExists,
    csvRows,
    intervalHours: CRON_INTERVAL_HOURS,
  });
});

// Save CSV to server cache
app.post('/api/cron/csv', (req, res) => {
  const { csv } = req.body || {};
  if (!csv || typeof csv !== 'string' || !csv.trim()) {
    return res.status(400).json({ error: 'Body must contain { csv: "..." }' });
  }
  try {
    saveCsv(csv);
    const rows = parseCsvRows(csv).length;
    // Schedule first run now that we have a CSV
    scheduleNextRun();
    res.json({ ok: true, rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Retrieve cached CSV
app.get('/api/cron/csv', (req, res) => {
  const raw = loadCsv();
  if (!raw) return res.status(404).json({ error: 'No CSV cached' });
  res.type('text/plain').send(raw);
});

// Clear cached CSV
app.delete('/api/cron/csv', (req, res) => {
  try {
    if (existsSync(CSV_PATH)) {
      writeFileSync(CSV_PATH, '', 'utf8'); // truncate instead of unlink for safety
    }
    if (cronTimer) { clearTimeout(cronTimer); cronTimer = null; }
    cronStatus.nextRun = null;
    saveStatus();
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Trigger immediate run
app.post('/api/cron/run', async (req, res) => {
  res.json({ ok: true, message: 'Run started — check /api/cron/status for progress.' });
  // Run asynchronously so the HTTP response returns immediately
  runAutoTag();
});

// Serve index.html for all other routes (SPA catch-all)
app.use(express.static(__dirname));
app.get('*', (req, res) => {
  res.sendFile(join(__dirname, 'index.html'));
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`[emby-tagger] Running on http://localhost:${PORT}`);
  console.log(`[emby-tagger] Emby server: ${config.serverUrl}`);
  console.log(`[cron] Auto-tag interval: every ${CRON_INTERVAL_HOURS}h`);

  // Start the cron loop on boot (first run happens after the interval unless triggered manually)
  scheduleNextRun();
});
