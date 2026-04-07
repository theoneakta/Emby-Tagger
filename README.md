# Emby Tag Manager

A browser-based tool for managing category tags on your Emby movie library — built for migrating from a genre-folder structure to a flat Radarr-managed library.

> **Use case:** You had movies in `/movies/Action/`, `/movies/Sci-Fi/` etc. and Emby used the parent folder name as a tag. After Radarr moved everything into one flat folder, all your tags disappeared. This tool lets you rebuild them — visually with drag-and-drop, or by re-importing a CSV backup.

---

## Features

| Tab | What it does |
|-----|-------------|
| 🗂 **Visual Sorter** | Create categories, assign movies by drag-and-drop or dropdown. Saves progress in browser localStorage. |
| 📄 **CSV Import** | Upload or paste a CSV. Movie name first, then up to 5 tags per row. Fuzzy-matches titles against your live Emby library before applying. |
| ⬇ **Export CSV** | Download your current Emby tags as a CSV backup. |
| 🎬 **Movies** | Manual movie-by-movie tag editing — add tags with autocomplete, remove individual tags with ×, or delete all tags from all movies at once. |

---

## Running modes

| Mode | Requirements | Steps |
|------|-------------|-------|
| **Standalone** | Nothing | Copy `config.example.js` → `config.js`, fill in values, open `index.html` |
| **Docker** | Docker + Compose | Copy `.env.example` → `.env`, fill in values, `docker compose up -d` |
| **Node.js** | Node.js 22+ | Copy `.env.example` → `.env`, `npm install`, `npm run dev` |

---

## Standalone mode (recommended for local use)

No server, no Node, no Docker — just a browser.

**1. Copy the config template:**
```bash
cp config.example.js config.js
```

**2. Edit `config.js`** and fill in your Emby server URL, API key, and user ID.

**3. Open `index.html`** in your browser:
```bash
open index.html      # macOS
start index.html     # Windows
xdg-open index.html  # Linux
```

> ⚠️ `config.js` contains your API key in plain text. It is listed in `.gitignore` and will never be committed.

> **CORS note:** your browser calls Emby directly in this mode. This works on a local network with no extra configuration. If Emby is behind a reverse proxy (Cloudflare, nginx, etc.) you may get CORS errors — use Docker mode instead.

### Finding your Emby credentials

**API key:** Emby Dashboard → Advanced → Security → API Keys → + New Key

**User ID:**
```bash
curl -s "http://YOUR_SERVER:8096/Users" \
  -H "X-Emby-Token: YOUR_API_KEY" | \
  python3 -c "import sys,json; [print(u['Id'], u['Name']) for u in json.load(sys.stdin)]"
```

---

## Docker mode

Credentials stay server-side. All Emby API calls are proxied — no CORS issues.

**1. Copy and fill in `.env`:**
```bash
cp .env.example .env
# edit .env
```

**2. Start:**
```bash
docker compose up -d --build
```

**3. Open** http://localhost:8765

Change the port in `docker-compose.yml`:
```yaml
ports:
  - "8765:3000"   # change 8765 to any free port
```

```bash
docker compose logs -f           # view logs
docker compose down              # stop
docker compose up -d --build     # rebuild after changes
```

---

## Node.js mode

```bash
npm install
cp .env.example .env
# edit .env
npm run dev
```

Open http://localhost:3000

---

## CSV Import format

Movie name first, then up to 5 tags per row:

```csv
MovieFolderName,Tag1,Tag2,Tag3,Tag4,Tag5
Die.Hard.1988.BluRay.x264,Action,Thriller,Christmas
The.Matrix.1999.BDRIP,Sci-Fi,Action
Bad.Moms.2016.BRRip,Comedy
```

- Extra tag columns are optional — use as many as you need (up to 5)
- Dots, quality tags, and years in the folder name are stripped automatically before matching
- All tags for a movie are applied in a single API call per movie

---

## Movies tab

The Movies tab lets you manage tags movie by movie:

- **Add tags** — type in the tag input with autocomplete from your tag history
- **Remove a tag** — click the **×** on any existing tag chip to remove just that tag
- **Apply all pending** — batch-applies all queued tag additions at once
- **🗑 Delete all tags** — removes every tag from every movie in your library (shows a confirmation dialog first)

---

## Disaster recovery

```
Before migration          After migration
────────────────          ───────────────────────────
/movies/Action/           /movies/Die Hard (1988)/
  Die Hard (1988)/        /movies/The Matrix (1999)/
/movies/Sci-Fi/           ...flat folder, tags gone
```

1. **Before migrating** — Export CSV (⬇ Export CSV tab)
2. Let Radarr migrate, refresh Emby
3. **Import CSV** (📄 CSV Import tab) — titles fuzzy-matched automatically

---

## How it works

```
Standalone mode:
  config.js ──→ index.html ──→ calls Emby API directly

Docker/Node mode:
  .env ──→ server.mjs ──→ /api/config ──→ index.html
                       ──→ /emby/*    ──→ proxies to Emby
```

In standalone mode `config.js` sets `window.__EMBY_CONFIG__` which `index.html` reads on startup. In Docker/Node mode `config.js` is absent and credentials come from `/api/config` instead.

---

## Project structure

```
emby-tagger/
├── index.html          # The entire app — open directly or served by Node
├── config.example.js   # Template — copy to config.js for standalone mode
├── config.js           # Your credentials — gitignored, never committed
├── server.mjs          # Node.js proxy server for Docker/Node mode
├── package.json
├── Dockerfile
├── docker-compose.yml
├── .env.example        # Template — copy to .env for Docker/Node mode
└── .gitignore
```

---

## License

MIT