# Bombario

A multiplayer rebuild of the classic grid-and-bomb formula for iOS and Android, built in Flutter.
The name comes from the repository; change it in one place later if it does not stick.

The full design is in `docs/game-design-document.md`.

## Layout

```
packages/bombario_core/   pure Dart game rules: grid, movement, bombs, flames, enemies, items, levels, snapshots
packages/bombario_net/    pure Dart room server (lobby, 30 Hz match loop, WebSocket), client and prediction
apps/server/              cloud entry point for online rooms, plus a Dockerfile
apps/mobile/              Flutter + Flame client: renders snapshots, touch controls, HUD, online/host/join/lobby screens
.github/workflows/        CI: format, analyze and test every package
```

`bombario_core` has no Flutter dependency on purpose. The same simulation will run on the
online room server, on a phone hosting a local Wi-Fi game, and inside the client for solo
play and client-side prediction, so the rules only ever exist once.

## Status

Phase 3 (co-op campaign v1):
- [x] Worlds 1 and 2: 20 stages from the design doc's stage table, including a bonus stage and a boss in each world
- [x] Hand-made 1-1 "First Spark" from the design doc; the other stages are generated from per-stage enemy mixes, items, brick density and timers
- [x] New enemies: Pebble (patrol), Hopper (telegraphed jump), Barrelhop, Grinface, Splitter and Splitlings, Shellback (front armour), Wisp
- [x] Bosses: King Puffball (bounces, splits at half HP) and Rockjaw Worm (burrows, rumbles, surfaces); boss HP scales +60% per extra player
- [x] Co-op ghosts: the fallen float through walls, ping and haunt; teammates revive them by standing on the tombstone for 2 s, paid from a shared lives pool (3 + 1 per player)
- [x] Lose the newest half of your power-ups on death; they scatter for teammates
- [x] New power-ups: Kick, Heart, Sonar Ping, Team Boost, Tether, Frost Bomb; one active item at a time
- [x] Quick-chat pings (Exit here, Power-up, Help, Run)
- [x] World 2 hazards: cracked floor that collapses, telegraphed falling rocks; tutorial stages stun instead of kill on friendly fire
- [x] Host picks the co-op stage in the lobby, and a cleared stage moves the room to the next one
- [x] Solo now plays the same campaign
- [ ] Glove/throw (World 2 in the design doc) is deferred; Kick covers bomb movement for now
- [ ] Deep-link invites and Firebase guest sign-in (left over from Phase 2; need a Firebase project)

Phase 2 (online rooms):
- [x] `RoomHub`: many rooms per server, each with a 6-character code (no O/0/I/1); empty rooms expire after 10 minutes
- [x] HTTP API: `POST /rooms` creates a room, `GET /rooms/<code>` looks one up, `GET /health`; WebSocket at `/rooms/<code>`
- [x] `apps/server`: runs on any container host that sets `PORT` (Cloud Run, Fly.io, Render), compiled to a native binary
- [x] Client-side prediction: inputs carry sequence numbers, the server consumes one per tick and echoes the last one, and the client replays unacknowledged inputs on top of each snapshot
- [x] Interpolation: other players and enemies slide between snapshots instead of stepping at 15 Hz
- [x] Reconnect: a dropped player's seat is held for 20 seconds mid-match and the app resumes it on its own
- [x] App: **Online** screen to create a room and share its code, or join by code
- [ ] Deploy a public server and bake its address into release builds
- [ ] Accounts, friends and matchmaking (Firebase, later phase)

Phase 1 (local Wi-Fi multiplayer):
- [x] Versus mode in the rules: last player standing wins, draws when the last two die together
- [x] `WorldSnapshot`: serialisable world state; the renderer draws snapshots, so solo and networked play share it
- [x] `RoomServer`: 6-character room codes, lobby with ready flags, host-controlled mode and start, authoritative 30 Hz loop, 15 Hz snapshots
- [x] `GameClient` and the app's `RoomSession`: host a room on the phone, join by Bonjour/mDNS discovery or typed `host:port`
- [x] Lobby, join and network game screens
- [x] Client-side prediction and interpolation (done in Phase 2)
- [ ] Sudden death, revenge carts, co-op ghosts

Phase 0 (solo prototype):

- [x] Grid, lane-constrained movement with cornering assist
- [x] Bombs, fuses, plus-shaped flames, chain reactions, brick destruction
- [x] The eight classic power-ups (Bomb Up, Fire Up, Speed Up, Wall Pass, Remote, Bomb Pass, Flame Pass, Mystery)
- [x] Three enemy behaviours (wander, chase, phase-chase with bomb avoidance) plus time-out hunters
- [x] Solo and co-op exit rules, bombing the exit spawns guards
- [x] Seeded level generator and an ASCII level format
- [x] Flame renderer with placeholder shapes, floating D-pad, bomb button, HUD
- [ ] Sprites and audio
- [x] Local Wi-Fi and online rooms (Phase 1 and 2)

## Running

```sh
# rules package
cd packages/bombario_core
dart pub get
dart test

# room server and client
cd packages/bombario_net
dart pub get
dart test

# online room server, listening on :8080
cd apps/server
dart pub get
dart run bin/server.dart

# mobile app (needs the Flutter SDK, a device or emulator)
cd apps/mobile
flutter pub get
flutter run --dart-define=BOMBARIO_SERVER=http://<your-laptop-ip>:8080
```

To play online: one player opens **Online**, taps **Create room** and shares the 6-character
code; friends type it under **Join**. The server address defaults to the `BOMBARIO_SERVER`
build setting and can be changed on the Online screen under **Server**.

To deploy the server, build the image from the repository root:

```sh
docker build -f apps/server/Dockerfile -t bombario-server .
docker run -p 8080:8080 bombario-server
```

Behind HTTPS (as on Cloud Run), point the app at `https://...` and it will use `wss://` for
the game connection.

To play on Wi-Fi: one phone taps **Host Wi-Fi room** and reads out the room's address (or friends
pick it from the list under **Join Wi-Fi room**, which uses Bonjour/mDNS); everyone taps Ready; the
host picks Versus or Co-op and taps Start. A phone hotspot works too.

The app is landscape only. Left half of the screen is a floating D-pad (touch anywhere and
drag), the big red button places a bomb, the amber button detonates when you hold Remote.
