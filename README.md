# Emby Tag Manager — Self-Hosted

A browser-based tool for managing tags on your Emby movie library.
Runs as a Docker container (Node.js + Express).

---

## Quick start

### 1. Edit `.env`

```env
EMBY_SERVER=http://192.168.3.7:8096
EMBY_API_KEY=your_api_key_here
EMBY_USER_ID=your_user_id_here
```

- **EMBY_SERVER** — local IP and port, no trailing slash
- **EMBY_API_KEY** — Emby Dashboard → Advanced → Security → API Keys
- **EMBY_USER_ID** — find yours with the command below

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

Go to **http://localhost:8765** (or your NAS/server IP).

The app loads your library automatically — no login screen.

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

## How it works

```
Browser  →  /emby/*      →  Node proxy  →  Emby server
         ←  /api/config  (apiKey + userId, read from .env)
```

Credentials never leave the server. The browser receives the API key
and user ID from /api/config at startup and uses them for Emby calls,
all of which are proxied through the Node container.

---

## File reference

| File | Purpose |
|------|---------|
| `.env` | Credentials and server URL (edit this) |
| `server.mjs` | Node.js backend — reads .env, proxies Emby API |
| `public/index.html` | The entire frontend (single file) |
| `Dockerfile` | Builds the Node image |
| `docker-compose.yml` | Wires everything together |
| `package.json` | Node dependencies (express, http-proxy-middleware) |
