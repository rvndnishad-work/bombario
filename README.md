# Bombario

A multiplayer rebuild of the classic grid-and-bomb formula for iOS and Android, built in Flutter.
The name comes from the repository; change it in one place later if it does not stick.

The full design is in `docs/game-design-document.md`.

## Layout

```
packages/bombario_core/   pure Dart game rules: grid, movement, bombs, flames, enemies, items, levels
apps/mobile/           Flutter + Flame client: renders the simulation, touch controls, HUD
.github/workflows/     CI: format, analyze and test both packages
```

`bombario_core` has no Flutter dependency on purpose. The same simulation will run on the
online room server, on a phone hosting a local Wi-Fi game, and inside the client for solo
play and client-side prediction, so the rules only ever exist once.

## Phase 0 status

- [x] Grid, lane-constrained movement with cornering assist
- [x] Bombs, fuses, plus-shaped flames, chain reactions, brick destruction
- [x] The eight classic power-ups (Bomb Up, Fire Up, Speed Up, Wall Pass, Remote, Bomb Pass, Flame Pass, Mystery)
- [x] Three enemy behaviours (wander, chase, phase-chase with bomb avoidance) plus time-out hunters
- [x] Solo and co-op exit rules, bombing the exit spawns guards
- [x] Seeded level generator and an ASCII level format
- [x] Flame renderer with placeholder shapes, floating D-pad, bomb button, HUD
- [ ] Sprites and audio
- [ ] Local Wi-Fi and online rooms (Phase 1 and 2)

## Running

```sh
# rules package
cd packages/bombario_core
dart pub get
dart test

# mobile app (needs the Flutter SDK, a device or emulator)
cd apps/mobile
flutter pub get
flutter run
```

The app is landscape only. Left half of the screen is a floating D-pad (touch anywhere and
drag), the big red button places a bomb, the amber button detonates when you hold Remote.
