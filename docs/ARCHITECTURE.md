# Frag to Fame — Architecture

> Living document. Update it whenever a module boundary, data format or ownership rule changes.
> Sections marked **(planned)** describe intended design that is not implemented yet.

## 1. The big picture

F2F is three applications sharing one executable, plus a persistent world that belongs to none of
them:

```
                         ┌────────────────────────────┐
                         │      Career World (data)   │  authoritative on the CAREER HOST
                         │  players, orgs, fixtures,  │  (SQLite, planned)
                         │  stats, calendar, history  │
                         └─────────────┬──────────────┘
                     repository API    │   (no Godot scene types cross this line)
          ┌────────────────────────────┼─────────────────────────────┐
          │                            │                             │
┌─────────▼─────────┐      ┌───────────▼────────────┐     ┌──────────▼───────────┐
│    Career Hub     │      │  Match Orchestration   │     │   Creation Studio    │
│  2D menus / pages │      │ MatchSetup ─► runtime  │     │ map editor, tactics  │
│  reads view-models│      │ MatchResult ◄─ runtime │     │ editor (local only)  │
└───────────────────┘      └───────────┬────────────┘     └──────────┬───────────┘
                                       │                             │
                           ┌───────────▼────────────┐     map/tactic files (versioned)
                           │      FPS Runtime       │◄────────────────┘
                           │ 3D match, bots, rules, │  hosted by a participating player's PC
                           │ event stream           │  (Godot high-level multiplayer, planned)
                           └────────────────────────┘
```

Key rules:

1. **The career world never references scenes or nodes.** It is plain data plus pure logic.
2. **The FPS runtime never touches the career database.** It receives a `MatchSetup` and emits a
   stream of match events and a final `MatchResult`. Orchestration translates between the two.
3. **The Career Hub reads data through a repository/view-model layer**, never by poking at the
   database directly from UI code.
4. **Creation Studio output is a file** (map/tactic document with a stable ID and version), consumed
   by the runtime exactly as community content would be. Official maps use the same path.
5. **Two separate networks**: career sync (career host ↔ clients, low-frequency, transactional)
   and match netcode (match host ↔ match clients, real-time). They share no state or code paths.

## 2. Current implementation (Milestones 1–6, 8–12)

```
project.godot                 Forward+, typed-GDScript warnings, App autoload
icon.svg
src/
  core/app.gd                 Autoload "App": scene routing, app-wide setup (theme, input)
src/core/input_actions.gd       InputActions: action names + default bindings, registered at boot
  core/ids.gd                 Ids: stable "<prefix>_<time><random>" string IDs
  ui/f2f_theme.gd             F2FTheme: builds the dark esports Theme in code (palette + variations)
  ui/ui_factory.gd            UIFactory: small helpers for cards, tables, stat tiles
  career/dev_sample_data.gd   DevSampleData: clearly-labelled placeholder data (NOT a database)
  career/career_world.gd      CareerWorld: in-memory authoritative fixtures + idempotent results
  orchestration/              MatchSetup / MatchResult contracts, StubMatchRunner (placeholder)
  net/career_sync/            CAREER SYNC: protocol, CareerSyncHost, CareerSyncClient,
                              career_sync_service.gd (autoload "CareerSync")
  net/match/                  IN-MATCH NETCODE: MatchSession (listen server), RemotePlayerAvatar
  world/block_builder.gd      BlockBuilder: textured static box geometry helper
  maps/                       MAPS: PieceCatalog, MapDocument (f2f.map v1), MapBuilder,
                              MapValidator, MapStorage, MapTemplates, MapEditController
  combat/                     COMBAT: WeaponDefinition/Catalog, WeaponState, ShooterMotion,
                              DamageModel, DamageInfo, Health, Hitbox, Hitscan,
                              WeaponController, CombatTally
  rules/                      COMPETITIVE RULES: MatchRules, ShopCatalog, MatchState (pure)
scenes/
  main_menu/                  Main menu (Career Hub / FPS Sandbox / Creation Studio / Quit)
  career_hub/career_hub.*     Sidebar + page host
  career_hub/pages/*.gd       One CareerPage subclass per section
  fps_sandbox/                Map-driven level, first-person controller (crouch, health, weapons),
                              target dummies, weapon effects/viewmodel, HUD + pause overlay,
                              MatchDirector + MatchHud + BombDevice (competitive matches)
  creation_studio/            Map editor: scene controller, MapEditorView, StudioUI, fly camera, grid
tests/run_tests.gd            Headless test runner (SceneTree script) over tests/suites/*
tests/test_suite.gd           TestSuite base: check(), wait_until(), scene helpers
tools/validate.ps1            Import + test runner for Windows
tools/capture_screens.gd      Non-headless screenshot capture of key screens (developer aid)
```

### Scene routing

`App.go_to(scene_id)` is the only sanctioned way to change top-level scenes. Scene IDs are
`StringName` constants in `app.gd`, mapped to paths in `SCENE_PATHS`. Routing always resets the
mouse mode to visible so a scene can never leave the cursor captured for the next one.

### UI construction

Top-level UI is built in code from small `.tscn` roots. Reasons: hand-authored scenes stay
diff-friendly, theme usage is consistent, and pages are trivially data-driven. The theme is built
once by `F2FTheme.build()`, assigned to the root `Window` and merged into the default theme
(`ThemeDB.get_default_theme()`), because Controls under a `CanvasLayer` do not inherit the Window
theme.
Named type variations (`TitleLabel`, `CardPanel`, `SidebarButton`, …) are the styling vocabulary;
avoid per-node colour overrides.

### Career Hub pages

`career_hub.gd` holds a `PAGES` registry (id, title, script). Each page is a `CareerPage`
(`VBoxContainer`) that builds itself in `build_page()`. Adding a section = add a script + a registry
entry. Since M9, Home, Player Profile, Teams and Players read the open career through
`App.career.repo`; Competitions, Calendar and Statistics still show labelled `DevSampleData` until
their milestones. Pages render a "no career open" card when no career is loaded.

### Networking (Milestone 2 proof)

Two networks that share nothing but the ENet library:

| | Career sync | In-match netcode |
|---|---|---|
| Purpose | Authoritative world data, results, calendar (later) | Real-time player state in one match |
| Owner | Career host (`CareerSyncHost`, owns `CareerWorld`) | Match host — any participating player's PC (`MatchSession`) |
| Transport | Raw `ENetMultiplayerPeer`, polled manually, no RPC | `SceneMultiplayer` on its **own scene-tree branch** (`SceneTree.set_multiplayer(api, path)`), RPCs |
| Messages | Versioned dictionaries (`CareerProtocol`, `var_to_bytes`, never objects), all reliable | RPCs: unreliable-ordered state, reliable welcome |
| Default port | 24560 | 24570 |
| Lifetime | Autoload `CareerSync`, survives scene changes | Lives inside the FPS scene, ends with it |
| Version check | `HELLO.v` vs host → `REJECT` | `_rpc_welcome(protocol)` → client leaves on mismatch |

**The career host plays through its own client.** `CareerSync.host_career()` starts the host and
then connects a local `CareerSyncClient` over loopback, so there is one code path for every player.

**Safe result submission.** A `MatchResult` carries a fixture ID and a unique submission ID.
`CareerWorld.submit_result` returns ACCEPTED / DUPLICATE / CONFLICT / UNKNOWN_FIXTURE / INVALID.
The same submission, or an identical scoreline, is a harmless DUPLICATE; a different scoreline for
an already-resolved fixture is a CONFLICT and the original stands. Clients keep submissions
pending by originating world ID. Protocol v2 tags snapshots, acknowledgements and submissions
with the world ID. Only a handshake for the same world resumes its pending submissions.
Every accepted change bumps `revision`; clients never apply an older snapshot over a newer one.

**Match authority (proof only).** Clients are authoritative for their own position; the host
relays snapshots at 20 Hz (clients send at 30 Hz). Server-authoritative movement, hit registration
and lag compensation are deliberately deferred to the FPS milestones.

**Not yet:** persistence of the career world, calendar advancement blocked on unresolved
fixtures, the career host choosing a match host, spectating, NAT traversal / Steam networking.

### Maps and the Creation Studio (Milestone 3)

```
 MapDocument (data, JSON) ──► MapBuilder.build(doc, EDITOR)  ──► MapEditorView (studio)
          ▲                └► MapBuilder.build(doc, RUNTIME) ──► SandboxLevel (FPS runtime)
          │
 MapEditController (UndoRedo, selection, dirty) ◄── creation_studio.gd ◄── StudioUI signals
          │
 MapStorage (user://maps/*.f2fmap.json, atomic + .bak)    MapValidator (errors / warnings)
```

- **Document.** `MapDocument` is plain data (`RefCounted`): metadata plus an ordered list of piece
  dictionaries `{id, type, position, rotation, size, props}`. Positions are the piece's
  *bottom-centre*; rotation is yaw in 90° steps. Piece IDs are `pc_N` from a counter that is saved
  and never reused, so deleting and re-adding cannot collide. Format `f2f.map`, version 1.
- **Catalog.** `PieceCatalog.TYPES` is the single list of piece types (kind, default size, colour,
  resizable, palette group). Kinds: block, ramp, stairs, marker, zone.
- **Builder.** `MapBuilder` turns a document into nodes. EDITOR mode shows markers and zones;
  RUNTIME mode hides them (bombsites keep a floor tint). Stairs are visual steps over an invisible
  slope collider, because `CharacterBody3D` does not step up ledges.
- **Editing.** All edits go through `MapEditController`, which records before/after piece states in
  Godot's `UndoRedo`. Drags preview without history and commit as one step. The controller emits
  per-piece signals; `MapEditorView` rebuilds only the affected piece.
- **Playtest.** The studio validates, then calls `App.start_playtest(doc, session)`. The FPS scene
  builds `App.playtest_map` instead of the default arena; "Return to editor" calls
  `App.end_playtest()` and the studio restores the session (document, path, dirty flag, camera).
  The runtime still only receives a document; it never reaches into the editor.

### Tactical Play Creator (Milestone 8)

Tactical mode lives inside Creation Studio. It uses the existing camera and `MapEditorView`
geometry for input raycasts and navigation. The saved map stays read-only while in this mode.
The editor draws colour-coded start/waypoint markers and route lines and keeps selection and
unfinished edits in memory.

`TacticDocument` serialises `f2f.tactic` version 1 as JSON. It stores a tactic ID and name, map ID,
map revision, a SHA-256 fingerprint of the canonical map data and exactly five ordered player
slots. Each slot has an explicit number, start XYZ and an ordered waypoint array. A missing map,
a mismatched revision or changed fingerprint prevents opening the tactic. `TacticStorage`
publishes verified staged files in `user://tactics` and retains the previous file as `.bak`.

The preview bakes the current map colliders with `NavigationBuilder` and assigns subsequent
goals to `BotController` instances as each waypoint is reached. Each bot uses world collision,
with combat and inter-player collision excluded from preview. Progress and unreachable points are
reported per slot. The same route data can be consumed by future M7 play execution.

### Combat (Milestone 4)

```
 owner input (player keys / later bot AI)
        │ trigger, slot, reload, ShooterMotion
        ▼
 WeaponController ──► WeaponState.update(dt, trigger, motion, rng) ──► aim offsets (deg)
        │                                (pure: cadence, ammo, reload, spread, recoil)
        ▼
 Hitscan.trace (world + hitbox layers) ──► Hitbox.zone ──► DamageModel ──► Health.apply_damage
        │
        └─ signals: shot_fired, target_hit, reload_*, weapon_switched ──► HUD, WeaponEffects, CombatTally
```

- **Data vs state.** `WeaponDefinition` (from `WeaponCatalog.DATA`) is immutable stats; each
  carried weapon has a `WeaponState`. All randomness comes from a caller-supplied
  `RandomNumberGenerator`, so a seeded run is reproducible (needed later for server checks).
- **Spread and recoil.** Spread = base + bloom + run spread × (speed ratio)² (+ air), × crouch
  multiplier. Recoil is a fixed per-weapon pattern accumulated into an offset that bullets follow in
  full; the camera shows a fraction (`view_punch`). Bloom and recoil hold during sustained fire and
  recover after `recovery_delay`.
- **Physics layers.** 1 world, 2 character bodies (movement only), 3 hitboxes (shots only). Shots
  ignore bodies, so hitboxes alone decide what was hit; the shooter's own RIDs are excluded.
- **Input-agnostic shooting.** `WeaponController` reads no input. The player controller feeds it
  from the keyboard; bots will feed it from AI. Presentation listens to signals and never changes
  outcomes.
- **Runtime entities from map markers.** `SandboxLevel` spawns `TargetDummy` nodes from
  `target_dummy` pieces; the maps module stays unaware of combat.
- **Not yet:** armour, penetration, networked/authoritative damage, player hitboxes, audio.

### Competitive rules (Milestone 5)

```
 App.start_match(MatchSetup, MatchRules, MapDocument) ──► FPS runtime (fps_sandbox.tscn)
                                                            │
                                MatchDirector (scene) ◄─────┘   reports kills, plants, defuses,
                                 │   ▲                          pickups, purchases; places players
                       tick/events│   │signals                  and combatants each round
                                 ▼   │
                         MatchState (pure rules) ──► MatchResult ──► App.last_match_result
                                 │
                                 └─► events[] (round-stamped log → career statistics)
```

- **Pure rules.** `MatchState` has no nodes. The runtime tells it what happened; it decides round
  winners, money, sides and the result. The same class will run on the match host for networked
  matches and drive bot matches.
- **Win conditions.** Defence wins on attacker elimination before a plant, time running out
  without a plant, or a defuse. Attack wins on defender elimination (even after planting) or
  detonation. After a plant, eliminating the attackers does not end the round.
- **Economy.** Win rewards per reason, a loss-bonus ladder (winners' streak drops by one), kill
  rewards per weapon, a plant bonus for the whole attacking team, money cap. Survivors keep
  weapons/armour; the dead respawn with the default pistol. Money and gear reset at half time and
  at each overtime half.
- **Overtime.** Starts on the sides regulation ended on; sides switch every overtime-MR rounds; a
  block is won with overtime-MR + 1 rounds, otherwise another block starts.
- **Runtime contract.** The FPS runtime still never touches career data: it consumes a
  `MatchSetup` and produces a `MatchResult`. Practice matches are local and are not submitted.
- **Zones.** `MapZones` answers "inside which bombsite / buy zone?" from the map document, so the
  editor's zones are the single source of truth.

### Career database (Milestone 9)

```
 career_select / Career Hub pages ──► App.career (CareerSession) ──► CareerRepository
                                                                        │ typed records, queries
 CareerSaves (folders, backups, restore) ─┐                             ▼
 WorldGenerator / HumanCareer ────────────┴──────────────────────► CareerDatabase ──► godot-sqlite
                                                                   (only SQLite user)     │
 CareerMatches.practice_setup ──► MatchSetup (lineups + AI abilities) ──► FPS runtime     ▼
                                                                         user://careers/<save>/career.db
```

- **One file per career** (`user://careers/<save_id>/career.db`), WAL journalling, foreign keys
  on. Multi-row changes run in `CareerDatabase.transaction` (nested calls join the outer one; any
  failed statement rolls everything back).
- **Schema versioning.** `CareerSchema.MIGRATIONS[n]` upgrades n → n+1; the version is SQLite's
  `user_version`. Opening an older save snapshots it first; a newer save is refused.
- **Stat layers are separate tables:** `player_ability` (true, AI only — the repository refuses
  humans), `player_perceived` (+ confidence), `player_reputation`; schema v4 adds separate
  tables for raw events, derived counters and calculated match ratings.
- **Content vs save data.** Catalogue IDs live in code. The shipped `data/databases/default.f2fdb`
  and imported standalone world databases are templates. `CareerStart` copies their stable
  identities, rosters and competition definitions into each new save. Template imports verify
  schema, allowed IDs, SQLite integrity and foreign keys. Replacement requires confirmation and
  keeps the previous template. Existing careers retain their own copies.
- **Safety.** Verified `VACUUM INTO` snapshots are kept after creation, before migrations and on
  demand (eight per save). Failed pre-migration snapshots stop the upgrade. Restore stages and
  checks a standalone snapshot before archiving the live database and journal files together.
  An unsuccessful installation attempts to put the original files back and reports any retained
  archive path. Restore requires the career to be closed.
- **Match boundary.** `CareerMatches` turns career data into a `MatchSetup` (lineups with AI
  abilities). The FPS runtime maps abilities to bot mechanics (`BotSkill.from_abilities`) and
  never opens the database. Human entries carry no abilities.
- **Career creation.** The selected database supplies the starting world. Careers copy its
  identities, rosters and competitions into independent saves, with initial AI values sampled
  from the database's authored ranges.

### Playable career fixtures (Milestone 10)

Career Home schedules one pending amateur fixture for the local career player. `CareerFixtures`
selects a lowest-tier eligible organisation and snapshots both lineups in a versioned
`MatchSetup`. The career starts the current development arena through `App`. `MatchDirector`
registers the human's career ID with the rules and weapons, then emits the same `MatchResult`
used by other FPS modes. The runtime receives no SQLite connection or career repository.

Schema v3 stores the fixture ID, player, scheduled day, setup and optional outcome. The
repository enforces one pending fixture per player and unique submission IDs. Result handling
checks the player, map and MR score, then saves the score and advances the career day in the
same transaction. Identical results can be resubmitted without advancing again. An interrupted
match can be started again from the original fixture. A failed database write leaves it pending
and the in-memory result can be retried from Career Home.

These fixtures use local 5v5 play and the existing individual bots. Career sync, world
simulation and competition scheduling will build on later milestones. M7 remains deferred
until representative maps and gameplay-relevant player traits are ready.

### Recorded match statistics (Milestone 11)

The match state records weapon attempts before hit resolution and actual enemy health damage
before any lethal hit triggers a round end. Events include the participant IDs and team
assignments, completed rounds, and objective actions. The FPS runtime sends the local event
stream with its completion result. The existing score-only network packet remains compatible
with the dev co-op proof.

`MatchStatistics` derives per-player counts from live rounds. A damage assist credits the
teammate who dealt the most damage above a 40 HP threshold. A trade credits a kill of the player
who killed a teammate within five seconds. KAST includes kills, assists, survival and traded
deaths. ADR uses applied HP after armour and overkill. First-shot accuracy measures each
player's first shot of a round. A clutch attempt starts when a side is down to one player.

The repository stores one versioned raw event stream per fixture, per-player counts, and
per-player ratings calculated with an independently versioned formula. F2F rating v1 combines
kills and damage per round with KAST and survival. Career totals combine counts across recorded
matches before computing rates. Older score-only fixtures remain in Calendar.

### Career development and scouting (Milestone 12)

`CareerDevelopment` updates amateur ELO and the human player's reputation when a recorded
amateur fixture completes. Recent match evidence can move perceived aim, crosshair placement
and composure by up to two points. Progression writes are in the same transaction as the score,
statistics and calendar advancement, so retries cannot award progression twice. Existing
careers use their difficulty's starting amateur ELO until their first recorded result.

Schema v5 also stores one training session and one scouting report per career day. Training
adds one point to the selected human career opinion. Scouting moves reported AI estimates
towards observed ability by up to four points and increases the report's confidence. Scouting
does not disclose potential or change underlying simulated ability. Recorded match counts,
versioned performance ratings, career opinions and reputation remain separate.

### Bot AI (Milestone 6)

```
 map document ─► MapBuilder ─► world colliders ─► NavigationBuilder.bake ─► NavigationRegion3D
                                                                                  │
 BotSkill (data) ─► AimModel (pure)                                              ▼
                        │            BotController (CharacterBody3D, src/ai/)
                        └──────────►  perceive → engage / move / search
                                       │ trigger, view          ▲ goals, watch points, interact
                                       ▼                         │
                               WeaponController (shared)    BotSquad (scenes/fps_sandbox/)
                                                              ▲ buy, spawn, objectives
                                                              │
                                                     MatchDirector ◄─► MatchState
```

- **Individual layer (`src/ai/`).** `BotController` only knows enemies (a Health list), a goal, a
  watch point and an interact flag. It shoots through the same `WeaponController` and hitboxes as
  the player, so bots obey every weapon rule (spread, recoil, armour, falloff).
- **Fair by construction.** Perception uses a view cone, view distance, awareness radius and
  world-only line of sight; aiming has a reaction delay, a capped turn rate and an acquisition
  error that decays. Skill presets change these numbers, never the rules.
- **Objective layer (`BotSquad`).** A deliberately simple placeholder that buys, places bots and
  sets goals (one attack site per round, carrier plants, defenders split, retake and defuse).
  Milestone 7 replaces it with the team-tactics layer + IGL; `BotController`'s API stays.
- **Navigation.** Baked at runtime from static colliders on the world layer, so any editor map
  works. Paths are re-requested when a query came back empty (e.g. before the map synced).
- **No career coupling.** Bots receive a `BotSkill`; later the career will map professionals'
  simulated abilities to skills when building a `MatchSetup` — the FPS runtime never reads them.

### Input

`InputActions.register_defaults()` adds actions only if they don't already exist, so future
user-rebinding (saved to `user://`) can be loaded first and win. Movement uses **physical**
keycodes so WASD works on non-QWERTY layouts.

## 3. Planned modules

| Module | Responsibility | Notes |
|---|---|---|
| Career world repository **(M9–11)** | Typed access to players, orgs, contracts, fixtures and recorded performance | SQLite via `godot-sqlite` behind `CareerRepository`. |
| World progression & calendar **(partial, M10)** | Career fixture list and day advancement on a saved local result | World simulation and shared calendar coordination are planned. |
| Identity & traits **(planned)** | Stable IDs, trait library, trait-conflict rules | Traits are data (resources/JSON) with effect hooks consumed by decision systems. |
| Competitions **(planned)** | League/cup/swiss/bracket generators, F2F Ladder | Formats data-driven (series, MR length, overtime, veto). |
| Match simulation **(planned)** | Resolve AI-only fixtures without 3D | Must emit the **same event schema** as the FPS runtime. |
| Match orchestration **(local fixtures, M10)** | `MatchSetup` → FPS runtime → `MatchResult`, idempotent submission by fixture ID | The dev co-op proof uses `StubMatchRunner`. |
| FPS runtime **(partial: movement, weapons, health, match rules, bots)** | Rounds, economy, weapons, utility, bombsite | `src/combat/`, `src/rules/` + `scenes/fps_sandbox/`. Server-authoritative on match host later. |
| Bot AI **(individual, M6)** / Tactical AI / IGL **(planned)** | Individual combat + team plans + calls | `src/ai/` + `BotSquad`; one team-tactics layer shared by AI and human IGLs in M7. |
| Statistics **(M11)** | Versioned events, derived per-player counts and calculated ratings | Perceived/scouted values and reputation remain separate. |
| Map editor **(basic)** | Modular pieces, snapping, gameplay markers, validation, playtest | `src/maps/` + Creation Studio; see Maps above. Navmesh, tactical markers and sharing later. |
| Tactical Play Creator **(M8)** | Five starts, ordered routes, editing, persistence and preview | Tactic documents are bound to saved map revisions. Roles, utility, triggers and playbooks are later work. |
| Content loader **(planned)** | Official vs custom content, IDs, versions, dependencies | Saves record content manifest. |
| Co-op career sync **(proof)** | Career host authority, client requests, calendar sync | Raw ENet message protocol; see Networking above. Calendar sync not yet. |
| Match netcode **(proof)** | Listen server on a player's PC, player state sync | `MatchSession`; position + facing only. |
| Persistence & backup **(career: M9)** | Staged file replacement, rotating backups, migrations | Career: SQLite transactions, verified snapshots, migrations and recovery. Maps and templates retain the previous file during publication. |

## 4. Data and identity rules

- Every persistent entity has a stable string ID, never a node path or array index.
  Proposed format: `<kind>_<ulid>` (e.g. `ply_01J…`, `org_01J…`, `fix_01J…`).
- Every file format carries `format` and `format_version` fields.
- Four stat layers stay separate: recorded events/stats, calculated ratings, perceived/scouted
  opinions, reputation/standing.
- Human career attributes are **perceived** values only; they never feed into FPS mechanics.

## 5. Decisions log

| Date | Decision | Why |
|---|---|---|
| 2026-11-15 | Build UI in code from minimal `.tscn` roots | Diff-friendly, consistent theming, data-driven pages |
| 2026-11-15 | Theme generated in code (`F2FTheme`) rather than a `.tres` | Single source of truth for palette; easy to review |
| 2026-11-15 | Input actions registered at runtime with physical keycodes | Readable, layout-independent, rebinding-friendly |
| 2026-11-15 | Sandbox level built from `BlockBuilder` boxes | Same primitive vocabulary the map editor will use |
| 2026-11-15 | Defer SQLite until the career database milestone | Avoid a GDExtension dependency before it pays for itself (superseded below: SQLite from M9) |
| 2026-11-15 | Career sync = raw ENet peer + versioned dictionary messages, no RPC | Transactional, testable, version-checkable; cannot become entangled with scene-tree RPCs |
| 2026-11-15 | Match netcode = SceneMultiplayer on its own tree branch | Native RPCs for real-time play; branch isolation lets host and client (and tests) coexist in one process |
| 2026-11-15 | Career host connects to itself as a client | One code path for every human, fewer host-only bugs |
| 2026-11-15 | Dedupe by submission ID or identical scoreline; differing score = CONFLICT | Safe resends/recovery; several participants may report the same fixture |
| 2026-11-15 | Clients own their position in the M2 proof | Smallest proof of the two-network split; authority model revisited in M4/M5 |
| 2026-11-15 | One `MapBuilder` for editor and runtime | What you edit is exactly what you play; no export step |
| 2026-11-15 | The sandbox arena is a map document (template) | Proves official content can be authored with the shipped editor |
| 2026-11-15 | Bottom-centre origin, 90° rotations, axis-aligned pieces | Simple snapping, exact AABB picking and stacking; free rotation later |
| 2026-11-15 | UndoRedo targets a weak-referencing `_Applier` | `UndoRedo` holds strong refs to RefCounted targets; targeting the controller leaked a cycle |
| 2026-11-15 | Merge `F2FTheme` into the default theme | CanvasLayer UIs (HUD, studio) otherwise render with Godot's default styling |
| 2026-11-15 | Stairs = visual steps + hidden slope collider | `CharacterBody3D` has no step-up; a slope is smooth and predictable |
| 2026-11-15 | Weapons as data (`WeaponCatalog`) + pure `WeaponState` | Balancing without code changes; unit-testable; bots and a future server reuse it |
| 2026-11-15 | Fixed recoil patterns, bullets follow full offset, camera shows a fraction | Learnable, skill-based spray control; matches the vision of mechanics belonging to the player |
| 2026-11-15 | Separate hitbox physics layer, shots ignore movement bodies | Precise zone damage; capsules stay simple for movement |
| 2026-11-15 | `WeaponController` is input-agnostic | One shooting path for humans and bots |
| 2026-11-15 | Competitive rules as a pure `MatchState` driven by reported events | Testable without scenes; reusable by the match host, bots and simulation |
| 2026-11-15 | `MatchSetup` MR value overrides the rule preset | The fixture contract decides the format; rules supply timings/economy |
| 2026-11-15 | Practice match runs inside the existing FPS runtime via `MatchDirector` | One runtime for sandbox, playtest and matches; no duplicate player/HUD code |
| 2026-11-15 | Passive combatants until M6, labelled on screen | Exercises the full rules loop honestly without pretending AI exists |
| 2026-11-15 | Runtime navmesh baking with native `NavigationServer3D` (no plugin) | Every editor map is bot-ready with no authoring step; no dependency |
| 2026-11-15 | One `HumanoidRig` hitbox layout for player, dummies and bots | Identical damage rules for everyone; bots can hit the player |
| 2026-11-15 | Bot aim = pure `AimModel` + `BotSkill` data | Testable; difficulty through human-like limits, never perfect aim |
| 2026-11-15 | Navmesh max climb = one cell | Bodies have no step-up; routing over ledges stranded bots |
| 2026-11-15 | Objective play in a thin `BotSquad`, replaced in M7 | Bot matches are playable now without pre-empting the team-tactics design |
| 2026-11-15 | Practice defaults to bots; passive targets stay as an option | Rules tests remain deterministic; players get real opponents |
| 2026-11-15 | One SQLite file per career, WAL, schema version in `user_version` | Simple copy/backup unit; crash-safe; migrations need no extra bookkeeping table |
| 2026-11-15 | Only `CareerDatabase` touches SQLite; everything else uses `CareerRepository` | The add-on stays replaceable and SQL stays reviewable in one place |
| 2026-11-15 | Trait/ability/role catalogues in code, saves store IDs | Content can grow or be rebalanced without migrating every save |
| 2026-11-15 | Lineups with AI abilities travel in `MatchSetup` (v2) | The runtime gets what bots need without ever reading the career database |
| 2026-11-15 | Sniper role instead of a weapon-specific role name | Keeps role names original; the vision's "AWPer" maps to `sniper` |
| 2026-11-15 | Save list opens databases normally, not read-only | godot-sqlite's read-only mode ignores data still in the WAL file |
| 2026-11-15 | `validate.ps1` fails on any `SCRIPT ERROR` in the test log | A runtime error aborts a test function without failing a check |
| 2026-11-15 | **Career database = SQLite from day one** (owner's decision; supersedes "defer SQLite") via `godot-sqlite` v4.9 (MIT, built for Godot 4.7.1, Windows supported) | The career world is a third of the game: thousands of players, years of history and match events need indexed queries, partial loading and crash-safe transactions. Building on JSON first would mean a rewrite. SQLite itself is public domain; both licences allow a closed commercial release (MIT notice to be shipped in credits). Access stays behind a typed repository so the add-on is isolated |
