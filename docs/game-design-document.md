# Bombario: Game Design Document
*A multiplayer rebuild of the NES Bomberman formula for iOS and Android, built in Flutter.*

Version 0.1 · 2 Oct 2026 · Working title "Bombario" (placeholder, see §13 on naming)

---

## Contents
1. Vision and pillars
2. What the 1985 original does (reference)
3. Core gameplay mechanics
4. Game modes (co-op and versus)
5. Power-ups: the classic eight, later-series staples, and new designs
6. Enemies (NPCs) from easy to hard, with behaviour
7. Bosses
8. Worlds and level design, easy to hard
9. Mobile UI/UX
10. Multiplayer architecture (room codes, online, local Wi-Fi)
11. Flutter tech stack and project structure
12. Progression, economy, and retention
13. Legal and IP
14. Production roadmap (MVP to launch)
15. Open questions

---

## 1. Vision and pillars

**One line:** Classic grid-and-bomb gameplay, rebuilt for 1 to 4 friends on phones, where you either clear the maze together and find the exit, or blow each other up.

**Pillars**
- **Readable in one second.** A grid, a timer, a bomb. Anyone who has seen the NES version understands it instantly.
- **Friends first.** Every mode is built for 2 to 4 players. Single player still exists but is the tutorial, not the product.
- **Chaos you caused.** Chain reactions, friendly fire, and power-up steals should create stories ("you trapped me with your own kick bomb").
- **Fair on touch.** Grid movement with generous cornering assist, so touch controls never feel like the reason you died.
- **Short sessions.** A co-op stage is 2 to 4 minutes; a versus round is 2 minutes. Matches fit in a bus ride.

---

## 2. What the 1985 original does (reference)

The screenshot is NES *Bomberman* (Hudson Soft, 1985). Its key systems, which we keep as the baseline:

| System | Original behaviour |
|---|---|
| Field | 31 × 13 tile maze, scrolls horizontally. Indestructible pillars on every even row/column, soft bricks placed randomly. |
| HUD | `TIME` (200 s countdown), score, `LEFT` (lives). |
| Goal | Kill every enemy, then walk onto the exit door hidden under a brick. |
| Hidden items | Each stage hides exactly one exit and one power-up under bricks. |
| Bombing the exit | Bombing the revealed exit (or a revealed power-up) spawns a wave of tougher enemies. A good risk/reward hook we keep. |
| Timeout | When the timer hits 0, Pontans (the hardest enemy) flood the stage. |
| Stages | 50 stages, plus a bonus stage every 5 stages (unlimited enemies, rack up points). |
| Death | Touching an enemy or a flame. Most power-ups are lost on death. |
| Continue | Password system. |

The core loop is: **explore by bombing → reveal power-up and exit → kill all enemies → exit**. Our co-op mode keeps exactly this loop and makes it social.

---

## 3. Core gameplay mechanics

### 3.1 Grid and movement
- Logical grid of tiles. Positions are stored as continuous floats, but movement is constrained to lanes (rows/columns between pillars).
- **Cornering assist (critical for touch):** if a player pushes Up while slightly off-centre in a column, they slide automatically towards the nearest open lane rather than getting stuck on the pillar edge. Assist window: up to 40% of a tile. Original Bomberman had a subtle version of this; ours should be generous.
- Base speed: 3.0 tiles/s. Each Speed pickup: +0.5 tiles/s, cap 6.0.
- Collision box: 0.8 tiles, slightly smaller than the sprite so near-misses feel fair.

### 3.2 Bombs
- Placed on the tile the player's centre occupies. Max one bomb per tile.
- **Fuse:** 2.5 s default. Bombs flash faster in the last 0.75 s.
- **Explosion:** plus-shaped flame, range 1 tile at start (grows with Fire pickups, cap 8). Flame lingers 0.5 s.
- Flames stop at pillars; they destroy the first soft brick they hit and stop there (unless Pierce).
- **Chain reaction:** a flame touching another bomb detonates it immediately.
- Bombs are solid to the player who placed them **only after they step off** (prevents instant self-trap).
- Flames destroy items lying on the floor (except the exit, which instead spawns enemies when hit, as in the original).

### 3.3 Soft bricks and hidden things
- Soft bricks density by difficulty: 35% (easy) to 65% (hard) of free tiles.
- Under bricks: the exit, power-ups, and, in later worlds, traps and enemy nests (§8).
- Keep a 3-tile L-shaped safe zone at every spawn point so nobody dies in the first second.

### 3.4 Death and lives
- Single player / co-op: lives as in the original. Versus: one life per round.
- On death in co-op the player becomes a **Ghost** (see §4.1) instead of just respawning, which keeps them engaged.
- Power-up loss on death: lose the most recent 50% (rounded up). Full loss like the NES feels harsh with 4 players. Lost items scatter onto nearby free tiles so teammates can pick them back up.

### 3.5 Timer
- Co-op stage timer: 180 to 240 s depending on stage. At 0, "Overtime": Pontan-style hunters spawn every 10 s.
- Versus round timer: 120 s, then **Sudden Death**: the arena shrinks from the edges with falling blocks (classic Super Bomberman rule).

### 3.6 Scoring
Points for enemies (with multiplier for multi-kills in one blast: ×2, ×4, ×8...), bricks (10), power-ups (100), time bonus at exit. Co-op shows both team score and individual MVP stats at the results screen.

---

## 4. Game modes

### 4.1 Co-op Expedition (the main mode, from your "find powers and the exit together" idea)
2 to 4 players share one maze.

- **Bigger maze:** 31 × 13 for 2 players; 41 × 17 for 3–4 players. Each device's camera follows its own player, so a scrolling maze works fine online (unlike a shared TV).
- **Goal:** kill all enemies, then **all living players** stand on the exit together (or within 2 tiles of it) for 3 seconds. A big team-moment.
- **Hidden items scale with players:** one power-up per player plus one shared, so nobody fights over a single item.
- **Shared lives pool** (default 3 + 1 per player). Optional "Hardcore" uses no pool.
- **Ghost mode:** a dead player floats through walls, can't be hurt, can **ping** tiles (shows a marker to teammates) and, once per life, drop a "haunt" that slows one enemy for 3 s. Revive: a living teammate walks onto the ghost's tombstone for 2 s, costing one life from the pool. This turns death from "wait and watch" into support play.
- **Friendly fire:** ON by default (it is the soul of Bomberman), with a lobby toggle. With FF on, a teammate's flame stuns instead of kills for the first 2 stages of World 1 as a tutorial.
- **Pings:** quick-chat wheel ("Exit here!", "Power-up!", "Help!", "Run!"), plus tapping the minimap. Essential since many players will be on mute.
- **Exit bombing risk/reward:** bombing the revealed exit spawns a wave of tougher enemies but also drops one bonus chest. Teams can choose to farm it.

### 4.2 Versus Battle
Classic Super Bomberman battle mode. 2 to 4 players (later 8 on large maps), single screen arena 15 × 13 (fits a phone without scrolling).
- Last one standing wins the round; best of 3/5.
- Pre-seeded power-ups under bricks (random but symmetric per spawn quadrant for fairness).
- Sudden Death shrinking arena after 2 minutes.
- **Revenge carts** (from Super Bomberman 4): eliminated players ride along the arena edge and lob bombs into the field. Optional, but great for keeping eliminated friends playing.
- Skull curses (§5.4) available in versus only.

### 4.3 Additional modes (post-launch)
| Mode | Summary |
|---|---|
| Team Battle 2v2 | Versus with teams, friendly fire optional. |
| Gold Rush | Coins hidden under bricks; most coins at time-up wins. Low skill floor. |
| Exit Race | Competitive version of co-op: same maze, first player to reach the exit (after killing a quota of enemies) wins. Blends both of your ideas. |
| Daily Dungeon | One seeded co-op maze per day, global leaderboard by time. Drives retention. |
| Solo Campaign | Same stages as co-op played alone, scaled down. Doubles as the tutorial. |

---

## 5. Power-ups

### 5.1 The original eight (NES 1985), kept as-is
| Icon | Name | Effect | Lost on death? |
|---|---|---|---|
| 💣 | **Bomb Up** | +1 bomb on screen at once (max 8). | Yes |
| 🔥 | **Fire Up** | +1 blast range (max 8). | Yes |
| 👟 | **Speed Up** | +0.5 tiles/s (max 6). | Yes |
| 🧱 | **Wall Pass** | Walk through soft bricks. | Yes |
| 📡 | **Detonator / Remote** | Bombs don't explode until you press the Detonate button (oldest first). | Yes |
| ⚫ | **Bomb Pass** | Walk through bombs. | Yes |
| 🛡 | **Flame Pass** | Immune to flames (in co-op only enemy flames; in versus it's a 10 s timed pickup, or it would be broken). | Yes |
| ❓ | **Mystery** | 10 s full invincibility, sprite flashes. | Timed |

### 5.2 Later-series staples worth including
These are well-known mechanics from later Bomberman games. Mechanics can't be copyrighted, but name them our own way (§13).
| Name | Effect |
|---|---|
| **Kick** | Walk into a bomb to kick it; it slides until it hits something. Tap Action to stop it mid-slide. |
| **Glove / Throw** | Pick up a bomb (hold Action) and throw it 3 tiles over walls. |
| **Punch** | Punch an adjacent bomb 3 tiles over obstacles. |
| **Line Bomb** | Double-tap Bomb to place all your bombs in a line in front of you. |
| **Pierce Bomb** | Flames pass through soft bricks, destroying all bricks in range. |
| **Full Fire** | Max blast range instantly. Rare. |
| **Heart** | Absorbs one hit (co-op and solo only). |

### 5.3 New power-ups (original designs)
Designed around co-op teamwork, mobile-friendly single-button use, and a few versus spice items.

| Name | Mode | Effect | Design notes |
|---|---|---|---|
| **Sonar Ping** | All | Instantly reveals what's under every brick within 5 tiles for 6 s, visible to the whole team. | Speeds up the "where is the exit" search; makes the item-hunt social. |
| **Tether** | Co-op | Revive a downed teammate from up to 4 tiles away, no walking to the tombstone. One use. | Hero moments. |
| **Team Boost** | Co-op | +1 bomb and +1 fire to every living teammate (not yourself). | Rewards sharing; avoids "whoever grabbed it" fights. |
| **Frost Bomb** | All | Next 3 bombs freeze instead of burn: enemies and players frozen 3 s, flame tiles become ice (slide across them). Frozen enemies shatter if hit by a normal blast. | Combo with teammate's regular bomb. |
| **Sticky Bomb** | All | Thrown/kicked bombs stick to the first enemy or player they hit and explode on them. | Counters fast enemies. |
| **Cluster Bomb** | All | Explosion launches 4 mini-bombs diagonally that detonate 1 s later with range 1. | Covers diagonal blind spots of the plus shape. |
| **Portal Pair** | All | Place two portals (Action button); players, enemies and *kicked bombs* travel through. Lasts 30 s. | High skill ceiling. Kicking a bomb into a portal is a highlight-reel move. |
| **Decoy** | All | Drops a clone that enemies (and in versus, auto-aim items) target for 5 s. | Lures chasers away; useful to herd enemies into a teammate's blast. |
| **Magnet** | All | Pulls the nearest bomb (any owner) 1 tile per second towards you; tap again to repel. | Steal or redirect bombs. |
| **Dig** | Co-op | Burrow underground for 3 s: untouchable, can move under bricks and bombs. Cooldown 15 s. | Escape tool. |
| **Shield Bubble** | All | Bubble that bounces enemies and absorbs one flame, 8 s. | |
| **Mine** | Versus | Next bomb is invisible to opponents and has no fuse: it triggers when anyone else steps on it. | |
| **Shockwave Stomp** | All | Pushes all bombs within 2 tiles one tile away from you. | A panic button. |
| **Gold Fuse** | All | Your bombs' fuse becomes 1.5 s (faster, for experts). Can be toggled off. | |
| **Lantern** | Dark stages | Lights a radius around you in World 4 dark stages; shared light for nearby teammates. | |

**Balance rules**
- Max one "active ability" item (Detonator, Portal, Decoy, Dig, Magnet, Tether) at a time; picking another swaps it out. This keeps the HUD to one Action button.
- Passive stat items (Bomb, Fire, Speed, Passes) stack freely.

### 5.4 Skull curses (versus only, plus late co-op traps)
Picking up a skull gives a 15 s curse, which **transfers by touch** to another player.
- **Sluggish:** minimum speed. **Hyper:** maximum uncontrollable speed.
- **Butterfingers:** drops bombs constantly.
- **Dud:** can't place bombs.
- **Short Fuse:** 0.8 s fuse.
- **Mirror:** controls reversed.
- **Tiny Flame:** range 1.
- **Swap:** every 5 s you swap positions with a random player.

---

## 6. Enemies (NPCs), easy to hard

### 6.1 AI framework (how all enemies work)
Every enemy is built from small, reusable behaviour blocks, so new enemies are mostly data:

- **Movement types:** `Wander` (random direction at junctions), `Patrol` (fixed path), `Chase` (BFS pathfinding towards the nearest player within sight range), `Flee` (path away from bombs/players), `Phase` (moves through soft bricks), `Teleport`.
- **Perception:** sight range in tiles, whether walls block sight, whether it "sees" bombs (bomb-aware enemies avoid tiles in a bomb's future blast area; computed from a "danger map" updated every tick).
- **Decision tick:** most enemies decide only when centred on a tile (cheap, deterministic and very "NES-feeling"). Smart enemies use 4–10 Hz.
- **Speed tiers:** Slow 1.5, Normal 2.5, Fast 3.5, Very fast 4.5 tiles/s.
- **Target selection in multiplayer:** chasers pick the nearest player, but re-target at most every 3 s, and prefer players not already chased (spreads pressure so one player isn't swarmed).
- **Difficulty scaling with player count:** +25% enemies per extra player, not more HP. More bodies, same rules, keeps it readable.

### 6.2 The original NES roster (kept, renamed for IP, §13)
| Tier | Original name | Our name (suggestion) | Speed | Smart? | Special | Points |
|---|---|---|---|---|---|---|
| 1 | Ballom | **Puffball** | Slow | No | Pure random wander. The pink balloon in your screenshot. | 100 |
| 2 | Onil | **Blue Drop** | Normal | Low | Wanders, occasionally chases if you're in a straight line. | 200 |
| 3 | Dahl | **Barrelhop** | Normal | No | Erratic: changes direction randomly mid-corridor. | 400 |
| 4 | Minvo | **Grinface** | Fast | Medium | Chases within 4 tiles. | 800 |
| 5 | Kondoria | **Slime Sage** | Slow | High | Passes through soft bricks, chases intelligently. | 1000 |
| 6 | Ovapi | **Wisp** | Normal | Medium | Passes through soft bricks. | 2000 |
| 7 | Pass | **Tigerclaw** | Fast | High | Pathfinds to the player, avoids bombs. | 4000 |
| 8 | Pontan | **Hunter Coin** | Very fast | High | Passes bricks, chases relentlessly; spawns at time-out. | 8000 |

### 6.3 New enemies (original designs), easy to hard
| Tier | Name | HP | Speed | Behaviour | How to beat it | Introduced |
|---|---|---|---|---|---|---|
| 1 | **Pebble** | 1 | Slow | Patrols a fixed back-and-forth line. | Time a bomb at the end of its path. Tutorial enemy. | W1-1 |
| 2 | **Hopper** | 1 | Normal | Jumps 2 tiles over bricks every 3 s; telegraphs with a squat animation. | Watch the squat, bomb the landing tile. | W1-4 |
| 3 | **Splitter** | 1 | Normal | When killed, splits into 2 small Splitlings (fast, 1 HP, die in 10 s). | Use big blast range so the children die in the same flame. | W2-2 |
| 4 | **Shellback** | 2 | Slow | Armoured from the front; a frontal flame flips it on its back (stunned 3 s), second hit kills. | Hit from behind/side, or two bombs. | W2-5 |
| 5 | **Mimic** | 1 | Normal | Looks like a power-up lying on the floor; bites when you step next to it. Slight shimmer gives it away. | Bomb suspicious items. Teaches Sonar Ping. | W3-1 |
| 6 | **Bomb Goblin** | 1 | Normal | Places its own bombs (range 2) when within 3 tiles of a player, then flees. | Its bombs also chain your bombs. Kill it or use its bombs against it. | W3-4 |
| 7 | **Kicker Crab** | 2 | Normal | Kicks any bomb it touches back along its lane. | Place bombs where it can't reach, or use Remote. | W3-7 |
| 8 | **Shade** | 1 | Fast | Invisible except within 3 tiles of a player or when lit (Lantern, flames). | Lanterns, Sonar, listen for its audio cue. | W4-1 |
| 9 | **Mole Queen spawner** | 3 | Static | Nest hidden under a brick; spawns a Pebble every 8 s until destroyed. | Find and destroy nests first. | W4-3 |
| 10 | **Mirror Knight** | 2 | Normal | Copies the nearest player's movement mirrored horizontally. | Lead it into your blast by moving away from your own bomb. | W4-6 |
| 11 | **Fuse Eater** | 1 | Fast | Runs to the nearest bomb and eats it (bomb disappears), then fleeing 2 s. | Use the bait: place a bomb, then a second bomb along its path. Remote detonate while it eats. | W5-1 |
| 12 | **Phase Wraith** | 2 | Fast | Passes bricks, teleports to a random tile near a player every 6 s, bomb-aware. | Pin it with chain reactions; Frost Bomb. | W5-4 |
| 13 | **Herder** | 3 | Normal | Doesn't attack; pushes other enemies towards players and buffs nearby enemies +30% speed. Priority target. | Focus it as a team. | W5-6 |

**Telegraphing rule:** every special ability has a 0.5 s visible/audio tell (squat, glow, sound). Mobile players get no fair reaction time otherwise.

---

## 7. Bosses
One boss at the end of each world (stage 10). Single-screen arena, multi-phase, scales HP with player count (+60% per extra player).

| World | Boss | Mechanic |
|---|---|---|
| 1 Meadow | **King Puffball** | Giant balloon, bounces diagonally, splits into 4 Puffballs at 50% HP. Teaches dodging and splash damage. |
| 2 Caverns | **Rockjaw Worm** | Burrows under bricks; only the head is vulnerable when it surfaces (rumble + dust tell). Teams can "trap" the surfacing spot with bombs. |
| 3 Factory | **Bomb-O-Tron** | Mech that rains bombs in patterns (lines, rings). Its own bombs can be kicked back into its exposed core. |
| 4 Haunted Manor | **The Lantern Witch** | Dark arena, she steals Lantern light and summons Shades. Phase 2: she possesses a player (controls reversed) unless a teammate bombs the curse orb. Strong co-op beat. |
| 5 Sky Fortress | **Overlord Pontan** | Final boss: copies power-ups players have, cycles through earlier bosses' attacks, shrinking arena in the last phase. |

---

## 8. Worlds and level design

### 8.1 Structure
5 worlds × 10 stages (stage 5 is a bonus stage, stage 10 is the boss) = 50 stages, a nod to the original's 50.

| World | Theme | New mechanic | Hazards | Brick density | Timer |
|---|---|---|---|---|---|
| 1 Meadow | Green fields | Basics, Kick | None | 35–45% | 240 s |
| 2 Caverns | Stone caves | Conveyor-free; **cracked floor** (collapses after 2 walk-overs) | Falling stalactites (telegraphed shadow) | 45–50% | 220 s |
| 3 Factory | Industrial | **Conveyor belts** move players and bombs; **pressure plates** open gates | Steam vents (timed flame jets) | 50–55% | 210 s |
| 4 Haunted Manor | Dark | **Darkness** (vision radius 4), **warp doors** | Possessed bricks (regrow 20 s after destroyed) | 55–60% | 200 s |
| 5 Sky Fortress | Clouds | **Wind** pushes kicked bombs and slow players; **ice** tiles | Cannons fire at random rows | 60–65% | 180 s |

**Difficulty knobs per stage:** enemy count and tier mix, brick density, timer, maze size, hidden traps (skulls, Mimics, nests), whether the exit spawns monsters when bombed, number of power-ups hidden.

### 8.2 Stage table (co-op, 2 players; +25% enemies per extra player)
| Stage | Enemies | Hidden power-ups | Notes |
|---|---|---|---|
| 1-1 | 4 Pebble, 2 Puffball | Bomb Up ×2 | Tutorial prompts. Friendly flame stuns only. |
| 1-2 | 6 Puffball | Fire Up ×2 | Tutorial on chain reactions. |
| 1-3 | 5 Puffball, 2 Blue Drop | Speed Up | |
| 1-4 | 4 Blue Drop, 3 Hopper | Kick | Kick tutorial: a corridor where kicking is the fastest route. |
| 1-5 | Bonus | many | 60 s infinite Puffballs, score attack. |
| 1-6 | 4 Barrelhop, 3 Blue Drop | Bomb Up, Sonar Ping | |
| 1-7 | 6 Hopper, 2 Barrelhop | Remote | |
| 1-8 | 4 Grinface, 4 Puffball | Fire Up, Team Boost | First real chaser. |
| 1-9 | 4 Grinface, 3 Hopper, 3 Blue Drop | Heart | Mini-gauntlet. |
| 1-10 | **King Puffball** | — | |
| 2-1…2-9 | Introduce Splitter (2-2), Shellback (2-5), Slime Sage, Wisp | Wall Pass, Glove, Frost Bomb, Tether | Cracked floors in 2-3 and 2-7. |
| 2-10 | **Rockjaw Worm** | | |
| 3-1…3-9 | Mimic (3-1), Bomb Goblin (3-4), Kicker Crab (3-7), Tigerclaw | Punch, Line Bomb, Portal Pair, Bomb Pass | Conveyors, pressure plates. |
| 3-10 | **Bomb-O-Tron** | | |
| 4-1…4-9 | Shade (4-1), Mole Queen nests (4-3), Mirror Knight (4-6) | Lantern, Dig, Decoy, Flame Pass | Darkness; regrowing bricks. |
| 4-10 | **Lantern Witch** | | |
| 5-1…5-9 | Fuse Eater (5-1), Phase Wraith (5-4), Herder (5-6), Hunter Coin | Pierce, Magnet, Cluster, Full Fire | Wind, ice, cannons. |
| 5-10 | **Overlord Pontan** | | |

### 8.3 Example hand-made layouts
Legend: `#` pillar/outer wall, `+` soft brick, `.` floor, `P` player spawn, `E` exit (hidden), `U` power-up (hidden), `>` conveyor, `~` cracked floor, `e` enemy spawn.

**1-1 "First Spark" (easy, 15 × 11, teaches bombing and the exit)**
```
###############
#P.+.+...+.+.P#
#.#+#.#+#.#+#.#
#+..+.e.+..+..#
#.#.#+#.#+#.#+#
#+.+...U+..e.+#
#.#+#.#.#+#.#.#
#..+..e.+..+.+#
#+#.#+#.#E#.#.#
#P.+...+...+.P#
###############
```
Wide-open corridors, enemies start far from spawns, exit and power-up placed central so players naturally meet.

**3-3 "Assembly Line" (medium, conveyors carry kicked bombs to a gate)**
```
#####################
#P.+.+..>>>>>..+.+.P#
#.#+#.#+#.#.#+#.#+#.#
#+..+...+.e.+...+..+#
#.#.#+#.#####.#+#.#.#
#+.+..+.#.U.#.+..+.+#
#.#+#.#.#[ ]#.#.#+#.#
#..e.+..+...+..+.e..#
#.#.#+#.#+#.#+#.#.#.#
#P.+.<<<<<..+..+.+.P#
#####################
```
`[ ]` is a gate opened by a pressure plate hidden under a brick; the power-up room teaches conveyors + kick.

**5-7 "Gale Gauntlet" (hard)**: 41 × 17, 65% bricks, wind gusts alternate left/right every 8 s, 2 Herders protecting 10 mixed enemies, Hunter Coins spawn at 120 s, exit placed behind a regrowing-brick wall that must be broken twice. Design intent: forces team split (one group distracts Herders, one digs to the exit).

### 8.4 Procedural generation (for infinite/daily play)
Hand-made stages for the campaign; a generator for Daily Dungeon and Versus:
1. Lay the pillar grid.
2. Carve spawn safe zones.
3. Fill bricks to target density using seeded random noise (biased so the centre is denser).
4. Place exit at max BFS distance from the average spawn point (±20% random); place power-ups at medium distances, one per player quadrant.
5. Place enemies weighted by stage difficulty budget (each enemy has a "cost"; stage budget grows with stage number).
6. Validate: every spawn can reach the exit after brick removal; no enemy within 4 tiles of a spawn.

**Level format:** build in [Tiled](https://www.mapeditor.org/) and load with `flame_tiled`, with object layers for spawns, enemies and hidden items. Lets you (or a level designer) create stages without code.

---

## 9. Mobile UI/UX

### 9.1 Orientation and layout
- **Landscape only.** The grid is wider than tall, and thumbs sit on both sides.
- Pixel art at integer scaling (16 × 16 tiles scaled ×3 or ×4) with letterboxing, so pixels stay crisp on every screen size. Handle notches with `SafeArea`.
- Versus arena (15 × 13) fits on screen without scrolling. Co-op mazes scroll; the camera leads slightly in the movement direction.

### 9.2 Controls
```
┌──────────────────────────────────────────────────┐
│ ♥3  ⏱ 2:41   💣3 🔥4 👟2      [mini-map] [⏸]   │
│                                                  │
│                  (game field)                    │
│                                                  │
│  ╭───╮                                  (⚡)      │
│ ╭┤ ▲ ├╮                              ( 💣 )      │
│ │◀   ▶│                                          │
│ ╰┤ ▼ ├╯                         (💬 ping)        │
└──────────────────────────────────────────────────┘
```
- **Left: floating D-pad** (appears where the thumb lands). Default is 4-direction D-pad, not an analog stick: the game is grid-based. Option for a "swipe-and-hold" stick. Option to lock it in a fixed position.
- **Right: big Bomb button** (≥ 72 dp), with a smaller **Action** button above it that only shows when you own an active item (Detonate, Kick-stop, Throw, Portal...). One context button keeps it simple.
- **Ping button** with a radial quick-chat wheel.
- **Customisable layout:** drag buttons, resize, opacity. Left-handed mirror mode.
- **Haptics:** light tick on bomb place, heavy on nearby explosion, double pulse on power-up pickup, long pulse on death (`HapticFeedback` / `vibration` package).
- **Gamepad support** (Bluetooth controllers work on both platforms). Big win for retro fans.
- **Input buffering:** a direction pressed up to 150 ms before reaching a junction is remembered and executed at the junction.

### 9.3 HUD
- Top bar: lives (co-op shared pool), timer, own stats (bomb count, fire range, speed), active-item icon with cooldown ring.
- Co-op: teammate portraits with name, alive/ghost state, and off-screen arrows pointing to teammates.
- Mini-map (toggle): revealed exit and pinged items.
- Danger readability: bombs flash red and the future blast area is faintly tinted for the last 1 s (option, default ON for casual, OFF for "Classic" settings).

### 9.4 Screens and flow
```
Splash → Title → Home
  Home: [Play Co-op] [Versus] [Solo] [Daily] · Profile · Shop/Cosmetics · Settings
  Play Co-op/Versus → [Quick Match] [Create Room] [Join with Code] [Local Wi-Fi]
    Create Room → Lobby (code shown big + Share button, invite link, slots, ready toggles,
                 host settings: mode, stage/world, friendly fire, time, items)
    Join → enter 6-character code, or tap invite link (deep link opens lobby)
  Lobby → Countdown → Stage → Results (team score, MVP stats, unlocks) → Next stage / Lobby
```
- Room codes: 6 characters, no ambiguous letters (no O/0, I/1). Share via native share sheet as a deep link (`bombario://join/K7QX4M` + universal/app link).
- Reconnect: if a player drops, their character stands still and is protected for 20 s; rejoining puts them straight back.
- Onboarding: Solo stage 1-1 with in-world prompts, under 90 seconds, before showing online modes.

### 9.5 Art and audio direction
- "Modern retro": 16-bit-era pixel art (closer to SNES Super Bomberman than NES), with modern touches: screen shake on blasts, particle debris, smooth lighting in World 4.
- Each player gets a distinct colour plus a distinct hat/silhouette (colourblind safe; don't rely on colour alone).
- Chiptune soundtrack per world with tempo increase in the last 30 s; distinct sound for "your bomb" vs others' bombs.

### 9.6 Accessibility
Colourblind palettes, reduced screen shake, adjustable game speed for Solo, larger buttons, high-contrast flames, subtitles for audio cues (e.g. Shade audio tell shown as a visual ripple).

---

## 10. Multiplayer architecture

### 10.1 Terminology
- **Room / Lobby:** a group of 1–4 players waiting together, identified by a 6-character code.
- **Match:** a game session running inside a room.
- **Authority:** the program that decides "what really happened" (who died, what exploded).

### 10.2 The three ways to play together
| Way | How it works | Needs internet? | Notes |
|---|---|---|---|
| **Online room with custom code** | Host taps Create Room; server creates a room and returns a code; friends join with the code or invite link. | Yes | Main mode for friends. |
| **Online quick match** | Matchmaker puts you with strangers by mode and region. | Yes | Needs enough players to be useful; launch with bots that fill empty slots after 20 s. |
| **Local Wi-Fi / hotspot** | One phone hosts and runs the game server itself; others on the same Wi-Fi discover it automatically (mDNS/Bonjour) or join by code. | No | Great for travel, school, parties. Works with a phone hotspot. |

Bluetooth was considered and rejected for v1: Android `nearby_connections` and iOS Multipeer don't interoperate cross-platform, and Wi-Fi/hotspot covers the same use case.

### 10.3 Recommended approach: one Dart game simulation everywhere
The biggest technical decision. Write the game rules (grid, bombs, flames, enemies, power-ups) as a **pure Dart package** (`bombario_core`) with no Flutter or Flame imports. Then:
- The **online server** is a Dart program that runs `bombario_core` (Dart runs fine on servers).
- The **local Wi-Fi host** phone runs the same `bombario_core` server code in a background isolate.
- **Solo play** runs it locally with no networking.
- The **Flutter/Flame client** only renders the state and sends inputs.

One codebase for rules means no bugs from "server and client disagree", and local and online play are the same code path.

### 10.4 Netcode model: server-authoritative with client prediction
- **Tick rate:** simulation runs at 30 Hz on the authority. Server sends state snapshots (or deltas) at 15–20 Hz.
- **Clients send inputs**, not positions: `{tick, direction, bombPressed, actionPressed}`. Server validates everything (anti-cheat comes for free).
- **Own player: client-side prediction.** Your character moves immediately when you press; when a server snapshot arrives, the client re-applies unacknowledged inputs on top of it (reconciliation). Grid lanes make corrections tiny.
- **Other players and enemies: interpolation** ~100 ms in the past, so they move smoothly.
- **Bombs:** shown instantly as a "ghost" bomb on press, confirmed by server; if rejected (e.g. bomb limit) it fades. Explosions and deaths are **only** decided by the server, to keep it fair.
- **Lag compensation for deaths:** the server checks flame hits against where the player was on *their* screen (rewind up to 150 ms). Prevents "I was already out of the flame!" complaints.
- **Bandwidth:** a 41 × 17 grid state is small. Send the full grid only at join; afterwards only events (`brickDestroyed`, `bombPlaced`, `itemRevealed`) plus entity positions. Binary encoding (protobuf or a custom byte writer) keeps a packet well under 1 KB.
- **Determinism:** not required (server is the truth), but use a seeded RNG per match so replays and the Daily Dungeon are reproducible.

### 10.5 Transport
- **WebSockets** over TLS for v1: works on every mobile network, simple in Dart (`web_socket_channel` client, `dart:io` / `shelf` server). At 20 Hz with small packets, TCP head-of-line blocking is acceptable for this genre.
- Later upgrade path: WebTransport/UDP if latency testing shows problems on bad mobile networks.
- Local Wi-Fi: plain WebSocket (or raw TCP) to the host phone's local IP; discovery with `bonsoir` (mDNS on Android and Bonjour on iOS). iOS requires the Local Network permission and `NSBonjourServices` in Info.plist.

### 10.6 Backend options
| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Custom Dart server** (shelf + WebSockets) on Fly.io / Google Cloud Run / a small VPS, with Redis for room codes | Shares `bombario_core` with the client; full control; cheap. | You build matchmaking, scaling, accounts yourself. | **Recommended** for game rooms. |
| **Nakama** (Heroic Labs, open source) | Ready-made accounts, friends, matchmaking, leaderboards, realtime rooms; official Flutter/Dart client. | Authoritative match logic must be written in Go/TypeScript/Lua, so game rules would be duplicated outside Dart. | Good choice if you'd rather not build social features; use it for accounts/leaderboards and keep game rooms on the Dart server. |
| **Firebase** (Auth + Firestore) | Fast to set up for login, profiles, cosmetics, leaderboards. | Firestore/Realtime DB are not suited to a 30 Hz game loop. | Use for accounts/profiles only. |
| **Photon / Colyseus** | Mature room servers. | No first-class Dart SDK, logic duplicated in another language. | Not recommended. |

**Suggested stack:** Firebase Auth (Apple/Google/guest sign-in) + Firestore for profiles and unlocks + custom Dart room server for gameplay + Redis for room-code → server mapping. Start with one server region, add regions (US, EU, India/Asia) once there are players; the room code encodes the region.

### 10.7 Room lifecycle
1. Host calls `POST /rooms` → server allocates room, returns code `K7QX4M` and WebSocket URL.
2. Players connect `wss://…/rooms/K7QX4M` with auth token. Max 4 (8 later).
3. Lobby state synced: players, ready flags, host settings. Host migration if host leaves the lobby.
4. Host starts → countdown → match ticks. In-match, the **server** is authority, so the host leaving doesn't end the game (unlike local Wi-Fi, where the host phone *is* the server).
5. Results → back to lobby; room expires after 10 minutes empty.

### 10.8 Cheating and abuse
Server authority already prevents speed hacks and fake kills. Add: rate limit inputs, report button, no free text chat at launch (only quick-chat pings and emotes), which also avoids moderation cost and makes the game easier to rate for younger players.

---

## 11. Flutter tech stack and project structure

### 11.1 Packages
| Purpose | Package |
|---|---|
| Game engine (loop, sprites, camera, input, collision helpers) | `flame` |
| Tiled level loading | `flame_tiled` |
| Sound and music | `flame_audio` (or `just_audio` / `soloud` for lower latency) |
| Menus, lobby, settings UI | Regular Flutter widgets, overlaid on the game with Flame's `overlays` |
| App state (menus, lobby, profile) | `riverpod` or `flutter_bloc` |
| Networking | `web_socket_channel`; `protobuf` for messages |
| Local discovery | `bonsoir` |
| Auth / profile | `firebase_auth`, `cloud_firestore`, `sign_in_with_apple` |
| Deep links (join codes) | `app_links` |
| Haptics | Flutter's `HapticFeedback`, `vibration` |
| Gamepads | `gamepads` |
| Analytics / crashes | `firebase_analytics`, `firebase_crashlytics` |
| Server | Dart `shelf` + `shelf_web_socket`, packaged in Docker |

Flame is the right engine here: it is the most mature 2D engine for Flutter, handles the game loop and sprite rendering well, and grid games are very light on it. Physics engines (Forge2D) are **not** needed; grid collision is simple and must live in `bombario_core` anyway.

### 11.2 Monorepo layout
```
bombario/
  packages/
    bombario_core/        # pure Dart: rules, grid, bombs, enemies AI, power-ups, RNG, level loader
      lib/sim/ (world.dart, tick.dart, bomb.dart, flame.dart, player.dart)
      lib/ai/  (behaviours.dart, pathfinding.dart, danger_map.dart)
      lib/items/
      test/    # unit tests: chain reactions, cornering, AI decisions
    blast_protocol/    # message definitions (protobuf), shared by app and server
  apps/
    mobile/            # Flutter app: Flame renderer, UI, input, netcode client
      lib/game/ (renderer, camera, effects, audio)
      lib/net/  (connection, prediction, interpolation)
      lib/ui/   (home, lobby, settings, results)
      assets/   (sprites, tilesets, levels/*.tmx, audio)
    server/            # Dart room server (also embeddable for local Wi-Fi hosting)
  tools/
    level_validator/   # checks Tiled maps: reachability, spawn safety
```
Use `melos` (or Dart workspaces) to manage the monorepo.

### 11.3 Performance targets
60 fps on mid-range Android (e.g. 3–4-year-old phones), sprite atlases (one texture per world), object pooling for flames and particles, cap particles on low-end devices, battery-friendly 30 fps option.

---

## 12. Progression, economy and retention
- **Unlocks by play:** completing worlds unlocks new characters, hats, bomb skins, explosion trails, victory emotes.
- **Cosmetic-only monetisation** (if any): character skins, bomb skins, stage themes. Never sell power-ups or stat boosts: it would break versus.
- Optional "Expedition Pass" with seasonal cosmetics later.
- Achievements and Game Center / Google Play Games integration.
- Stats: bombs placed, chain-reaction record, revives, friendly-fire kills (a funny stat people love sharing).
- Replay share: short GIF/clip of the last kill (later feature).

---

## 13. Legal and IP (important)
"Bomberman" and its characters, names (Ballom, Pontan…), art, music and logo are trademarks/copyrights of **Konami** (which acquired Hudson Soft). Game mechanics themselves are generally not protectable, which is why many Bomberman-like games exist.
- Use an **original name** (not "Bomberman" or "Bomber Man" in the title or store listing), original characters, art, music and enemy names. The renamed enemies in §6.2 are suggestions for this reason.
- Don't copy sprites or music from the NES game, even as placeholders in builds you distribute.
- App store reviewers do reject clones that use protected names or art.
- Not legal advice; a quick trademark search on your chosen name is worth doing before launch.

---

## 14. Production roadmap
| Phase | Scope | Outcome |
|---|---|---|
| **0. Prototype** | `bombario_core` grid, movement with cornering, bombs, chain reactions, 3 enemies, one map, rendered with Flame and placeholder squares. | Prove it feels right on touch. |
| **1. Local multiplayer** | Dart server embedded in host phone, `bonsoir` discovery, 2–4 players on Wi-Fi, versus mode, classic 8 power-ups. | Playtest with friends; tune netcode. |
| **2. Online rooms** | Cloud Dart server, room codes, deep link invites, Firebase guest login, reconnect. | Remote friends can play. |
| **3. Co-op campaign v1** | World 1 + 2 (20 stages + 2 bosses), ghost/revive, pings, new power-ups batch 1. | Closed beta (TestFlight / Play internal testing). |
| **4. Content and polish** | Worlds 3–5, all enemies and bosses, art and audio, accessibility, settings, achievements. | Open beta. |
| **5. Launch** | Quick match with bot fill, Daily Dungeon, leaderboards, cosmetics, analytics. | Store launch. |
| **Post-launch** | 8-player versus, Gold Rush, Team Battle, level editor sharing, seasonal events. | |

**Bots** are worth building early (Phase 1): they reuse the enemy AI framework (pathfinding + danger map + "place bomb if it traps target and I have an escape route"), fill empty slots, and let you test multiplayer alone.

---

## 15. Decisions (confirmed 2 Oct 2026)
Arvind chose the recommended option on every open question:
1. **Max players:** 4 for v1; 8-player versus is a post-launch item.
2. **Friendly fire in co-op:** ON by default, with the lobby toggle and the stun-only tutorial in the first two stages.
3. **Art style:** 16-bit "modern retro" pixel art.
4. **Monetisation:** free to play with cosmetic-only purchases; never sell power-ups or stat boosts.
5. **Accounts:** guest play by default with optional Apple/Google sign-in to keep progress across devices.
