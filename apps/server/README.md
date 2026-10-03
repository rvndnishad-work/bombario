# Bombario server

The online room server, plus Daily Dungeon leaderboards and a small
analytics sink. Rooms, quick match and the WebSocket protocol live in
`packages/bombario_net` (the same code a phone runs when it hosts a Wi-Fi
game); this app adds the cloud entry point and the routes in `lib/`.

```sh
dart run bin/server.dart                      # from apps/server
docker build -f apps/server/Dockerfile -t bombario-server .   # from the repo root
docker run -p 8080:8080 -e DATA_DIR=/data -v bombario:/data bombario-server
```

## Deploying to Fly.io

`fly.toml` at the repo root deploys this server as the Fly app
`bombario-server` in Mumbai (`bom`), with a 1 GB volume at `/data` for
leaderboards and analytics. The app's default server address is
`https://bombario-server.fly.dev`; change both if the app name differs.

```sh
fly launch --no-deploy --copy-config   # first time only, from the repo root
fly scale count 1                      # rooms live in memory: one machine
fly deploy
curl https://bombario-server.fly.dev/health
```

Keep it at one machine. A second machine would not know the first one's
room codes, so players would land on "no room with code".

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | 8080 | Port to listen on |
| `MAX_PLAYERS` | 4 | Seats per room |
| `ROOM_TTL_MINUTES` | 10 | How long an empty room keeps its code |
| `QUICK_START_SECONDS` | 20 | Quick-match wait after the first player joins |
| `BOT_SKINS` | every app hat | Comma-separated skins bots pick from (the app validates) |
| `DATA_DIR` | unset | Where leaderboards and events are saved. Unset: leaderboards in memory, last 1000 events in memory |

## HTTP API

Errors are JSON `{"error": "..."}` unless noted.

### Rooms

- `GET /health` → `{"ok": true, "rooms": n}`
- `POST /rooms` → 201 `{"code": "K7QX4M"}`: a private room
- `GET /rooms/<code>` → `{"code", "players", "maxPlayers", "state", "quick"}`, 404 if unknown
- WebSocket `/rooms/<code>`: join (protocol in `packages/bombario_net/lib/src/protocol.dart`)

### Quick match

`POST /quickmatch` with `{"mode": "coop" | "versus"}` → 200 `{"code": "ABC123"}`;
400 for any other body. Then connect to `/rooms/<code>`.

The player gets a seat in an open quick-match room of that mode (not started,
not full, counting seats promised in the last 15 s), or a new one. The room
starts 20 s after its first person joins, or at once with four people, and
fills empty seats with bots: up to 4 players in versus, up to 2 in co-op (a
lone player gets one bot buddy). Co-op quick matches play stage 1-1, where
friendly flames only stun: the gentlest start for strangers. Lobby messages
carry `quick: true` and `startsIn` (seconds) while it counts down. Players
can't change a quick room's mode or stage. After the first match the room
works like a normal room (the host can start a rematch) and the hub sends
nobody new there.

### Leaderboards

Scores are client-reported and can be spoofed until accounts exist.

- `POST /scores` `{"board": "daily-2026-10-03", "name": "Arvind", "timeMs": 83450, "players": 2}`
  → 200 `{"rank": 3}`
  - `board` matches `^[a-z0-9-]{1,40}$`; `name` is 1–16 characters after
    trimming; `timeMs` is 1..3600000; `players` is 1..4. Otherwise 400.
  - Each board keeps one entry per name (case-insensitive) and player count,
    the best time, and at most 500 entries. `rank` is where the submitted
    time places among everyone else (ties go to the earlier run), even when a
    slower run doesn't replace the player's best.
  - 413 for a body over 64 KB; 429 (with `Retry-After: 60`) beyond 30 posts
    a minute from one address.
- `GET /leaderboards/<board>?limit=20` (limit 1..100) →
  `{"board": "...", "entries": [{"rank": 1, "name": "...", "timeMs": 83450, "players": 2}]}`
  fastest first; an unknown board has no entries. 400 for a bad board name
  or limit.

Saved to `$DATA_DIR/leaderboards/<board>.json`.

### Analytics

`POST /events` `{"events": [{"name": "stage_cleared", "ts": 1696300000000, "props": {"stage": "1-4"}}]}`
→ 204.

- 1–50 events per post; `name` matches `^[a-z0-9_]{1,40}$`; `ts` is epoch
  milliseconds; `props` (optional) is a flat object of strings, numbers,
  booleans or nulls, at most 2 KB as JSON. Any bad event refuses the batch
  with 400. 413 over 64 KB, 429 beyond 60 posts a minute from one address.
- Appended as JSON lines `{"name", "ts", "props", "rx"}` (`rx` = receipt
  time) to `$DATA_DIR/events-YYYY-MM-DD.jsonl` (UTC). Nothing else about the
  request (such as the IP address) is stored.

Rate limits key on the first `X-Forwarded-For` address when present (Cloud
Run, Fly.io), else the socket address. Clients can forge that header, so the
limit only slows casual abuse.
