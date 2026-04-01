# Emby Tag Manager

A self-hosted, browser-based tool for managing category tags on your Emby movie library — built for the common scenario of migrating from a genre-folder structure to a flat Radarr-managed library.

> **Use case:** You had movies in `/movies/Action/`, `/movies/Sci-Fi/` etc. and Emby used the parent folder name as a tag. After Radarr moved everything into one flat folder, all your tags disappeared. This tool lets you rebuild them — either visually with drag-and-drop, or by re-importing a CSV backup.

---

## Features

| Tab | What it does |
|-----|-------------|
| 🗂 **Visual Sorter** | Create categories, then assign movies by drag-and-drop (grid) or dropdown (list). Saves progress locally between sessions. |
| 📄 **CSV Import** | Upload or paste a `Category,MovieFolder` CSV. Fuzzy-matches titles against your live Emby library before applying. |
| ⬇ **Export CSV** | Download your current Emby tags as a CSV backup, or export Visual Sorter assignments before pushing to Emby. |
| 🎬 **Movies** | Manual movie-by-movie tag editing with autocomplete from tag history. |

---

## Prerequisites

- **Node.js 22+** (for local run) — [nodejs.org](https://nodejs.org)
- **Docker + Docker Compose** (for container run) — [docs.docker.com](https://docs.docker.com/get-docker/)
- An **Emby server** with an API key

### Find your Emby User ID

```bash
curl -s "http://YOUR_SERVER:8096/Users" \
  -H "X-Emby-Token: YOUR_API_KEY" | \
  python3 -c "import sys,json; [print(u['Id'], u['Name']) for u in json.load(sys.stdin)]"
```

---

## Setup

### 1. Clone

```bash
git clone https://github.com/YOUR_USERNAME/emby-tag-manager.git
cd emby-tag-manager
```

### 2. Configure

```bash
cp .env.example .env
```

Edit `.env`:

```env
EMBY_SERVER=http://192.168.1.100:8096
EMBY_API_KEY=your_api_key_here
EMBY_USER_ID=your_user_id_here
```

> ⚠️ `.env` is in `.gitignore` — it will never be committed.

---

## Running locally (Node.js)

Requires Node.js 22 or newer (uses the built-in `--env-file` flag, no extra dependencies).

```bash
npm install
npm run dev
```

Open **http://localhost:3000**

To run on a different port:

```bash
PORT=8765 npm run dev
```

---

## Running with Docker

```bash
docker compose up -d --build
```

Open **http://localhost:8765**

Change the host port by editing the left side of `ports` in `docker-compose.yml`:

```yaml
ports:
  - "8765:3000"   # change 8765 to any free port
```

### Useful Docker commands

```bash
# View logs
docker compose logs -f

# Restart after config change
docker compose restart

# Stop
docker compose down

# Rebuild after updating files
docker compose down && docker compose up -d --build
```

---

## Disaster recovery workflow

The typical full-loss recovery after a Radarr migration:

```
Before migration                After migration
─────────────────               ──────────────────────────────
/movies/Action/                 /movies/Die Hard (1988)/
  Die Hard (1988)/              /movies/The Matrix (1999)/
/movies/Sci-Fi/                 /movies/Inception (2010)/
  The Matrix (1999)/            ...all in one folder, no tags
```

**Step 1 — Export first (do this before migrating)**

Open the **⬇ Export CSV** tab and download your tags CSV. Store it somewhere safe.

**Step 2 — Migrate with Radarr**

Let Radarr move/rename everything into its flat structure. Refresh Emby so it picks up the new paths.

**Step 3 — Restore tags**

Option A — you have the CSV backup:
1. Open **📄 CSV Import**
2. Drop in the CSV
3. Review matches, click **Apply**

Option B — no backup, rebuild manually:
1. Open **🗂 Visual Sorter**
2. Add your categories (or use **Auto-import from Emby paths** if old path data is still cached)
3. Assign movies to categories in grid or list view
4. Click **Apply all to Emby →**

---

## CSV format

Both import and export use the same format:

```csv
Category,Movie,Year
Action,Die Hard,1988
Sci-Fi,The Matrix,1999
Comedy,Bad Moms,2016
```

For import, the second column can also be the raw folder name — dots, quality tags, and years are stripped automatically before title matching:

```csv
Action,Die.Hard.1988.BluRay.x264-YTS
Sci-Fi,The.Matrix.1999.BDRIP
Comedy,Bad.Moms.2016.BRRip.XviD
```

---

## Architecture

```
Browser  ──→  GET /api/config   ──→  Node (reads .env)  ──→  { apiKey, userId }
         ──→  /emby/*           ──→  Node proxy          ──→  Emby HTTP API
         ←──  public/index.html ←──  express.static
```

Credentials are never exposed as query parameters in browser network requests — the API key is injected by the proxy at the server layer.

The Visual Sorter state (categories + assignments) is persisted in **browser localStorage** so you can close the tab and resume later without losing your work.

---

## Project structure

```
emby-tag-manager/
├── public/
│   └── index.html        # Entire frontend (single file, no build step)
├── server.mjs            # Express backend — proxy + config endpoint
├── package.json
├── Dockerfile
├── docker-compose.yml
├── .env.example          # Copy to .env and fill in your values
└── .gitignore
```

---

## Contributing

Pull requests welcome. The frontend is intentionally a single-file vanilla JS app with no build step — keep it that way for simplicity.

---

## License

MIT
