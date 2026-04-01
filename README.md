# Emby Tag Manager — Self-Hosted

A browser-based tool for restoring category tags on your Emby movie library after a Radarr migration (or any total library rebuild).

---

## Quick start

### 1. Create `.env`

```env
EMBY_SERVER=http://192.168.3.7:8096
EMBY_API_KEY=your_api_key_here
EMBY_USER_ID=your_user_id_here
```

Find your User ID:
```bash
curl -s "http://192.168.3.7:8096/Users" \
  -H "X-Emby-Token: YOUR_API_KEY" | \
  python3 -c "import sys,json; [print(u['Id'], u['Name']) for u in json.load(sys.stdin)]"
```

### 2. Start

```bash
docker compose up -d --build
```

### 3. Open

**http://localhost:8765**

---

## How to restore tags after a Radarr migration

**Scenario:** You had movies organized in genre folders (`/movies/Action/Die.Hard`, `/movies/Sci-Fi/The.Matrix`) and Emby used the parent folder as a tag. After moving everything to one flat Radarr folder, all the tags are gone.

**Two ways to restore:**

### Option A — Visual Sorter (recommended for rebuilds)

1. Open **🗂 Visual Sorter**
2. Click **Auto-import categories from Emby paths** if Emby still has old path metadata, OR manually add categories (Action, Comedy, Sci-Fi, etc.)
3. Browse your movie library in grid or list mode
4. **Drag** movies into category columns, or click **＋** to assign via dropdown, or use the list-mode dropdown selector
5. Click **Apply all to Emby →** to write tags back

### Option B — CSV Import (great if you have a backup)

1. Export a CSV **before** your migration using **⬇ Export CSV**
2. After migration, open **📄 CSV Import**
3. Drop the CSV file or paste its contents
4. The tool matches movies by title (tolerates dots, quality tags, year differences)
5. Review matches, uncheck anything wrong, click **Apply**

### CSV format

```
Category,MovieFolderName
Action,Die.Hard.1988.BluRay.x264
Sci-Fi,The.Matrix.1999.BDRIP
Comedy,Bad.Moms.2016.BRRip.YTS
```

---

## Tabs

| Tab | Purpose |
|-----|---------|
| 🗂 Visual Sorter | Create categories, drag-and-drop or click-assign movies, apply tags to Emby |
| 📄 CSV Import | Upload/paste a category→movie CSV and apply tags in bulk |
| ⬇ Export CSV | Download your current tags as a CSV backup |
| 🎬 Movies | Manual tag management movie-by-movie |

---

## Updating

```bash
docker compose down
docker compose up -d --build
```

## Logs

```bash
docker compose logs -f
```

---

## Architecture

```
Browser  →  /emby/*      →  Node proxy  →  Emby server
         ←  /api/config  (apiKey + userId from .env)
```

Credentials never leave your server. The sorter state (categories + assignments) is persisted in browser localStorage so you can resume across sessions.

---

## File reference

| File | Purpose |
|------|---------|
| `.env` | Credentials and server URL (edit this) |
| `server.mjs` | Node.js backend — proxies Emby API |
| `public/index.html` | Entire frontend (single file) |
| `Dockerfile` | Builds the Node image |
| `docker-compose.yml` | Wires everything together |
| `package.json` | Node dependencies |
