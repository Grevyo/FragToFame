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
assets/weapons/, assets/magnets/   Runtime weapon models, Coat zone masks and Magnet artwork
authoring/coat_kits/           Coat kits and templates for artists (.gdignore: never imported or exported)
data/weapons/, data/coats/     Magnet slot data; official Coat records
src/
  cosmetics/                  WeaponModels, WeaponVisual, CoatLibrary, MagnetCatalog, CosmeticProfile
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
  maps/                       MAPS: PieceCatalog, PieceShapes, MapMaterials, MapDocument (f2f.map v2),
                              MapBuilder, MapValidator, MapStorage, MapAutosave, MapTemplates,
                              MapEditController, MapSnapping, MapClipboard, MapPrefabs, MapLighting,
                              MapZones, MapTactical, OfficialMaps
  ai/map_analysis.gd          MapAnalysis: navmesh reachability, islands, route timings
  tactics/                    TacticDocument (f2f.tactic v2), TacticStorage, TacticPreview,
                              TacticCompatibility
data/maps/official/           Official maps: ordinary saved map documents
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

`career_hub.gd` holds a `PAGES` registry (id, label, sidebar group, script). Each page is a
`CareerPage` (`VBoxContainer`) that builds itself in `build_page()`. Adding a section = add a
script + a registry entry. The career pages get their world data through `App.career.repo`.
Pages render a "no career open" card when no career is loaded.

- **Routes:** a page is opened by route, `{page id, args}` (for example
  `{"team", {"org_id": …, "tab": "squad"}}`). The hub keeps a history (Back/Forward, 60 entries)
  and rebuilds the current route on `refresh()` after the date moves.
- Entries with an empty group are reached through links only: `team`, `player`, `compare` and
  `series`. Each must render with no args.
- **Links:** `CareerPage.link`/`link_table`/`story_table` make clickable names (`NavLink`
  `LinkButton`s) that call `go(page, args)`. The page finds the hub through the
  `career_hub` group. Tabs (`add_tabs`) re-open the same page with `tab` merged into its args.
- **Continue and Holiday** live in the top bar. Holiday is `CareerCalendar.holiday` via
  `App.holiday_career`; like Continue it never plays the human's match.

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
- **Draw tools.** The first point establishes a height and the second fixes the snapped footprint
  or wall direction. The ghost uses the same dimensions committed to the document. A stroke adds
  one ordinary floor, wall or block to the active layer, so the existing builder handles collision
  and the file format needs no new geometry. The navmesh overlay invalidates on piece edits,
  including undo and redo, and rebakes once the active drag or a burst of edits ends.
  The snap marker uses the same intersection as placement and follows the locked plane mid-drag.
  Drawn floors and palette floor slabs align their walking surface to the anchor, with their
  thickness stored below it. Other structural pieces place by their base.
- **Drawn surfaces.** Creation Studio can author a simple polygon with a different elevation at each
  corner. The document stores its outline relative to its bounds so the normal placement, sizing
  and material tools still work. The builder uses one triangulated surface for rendering,
  collision and navigation baking.
- **Mesh brushes.** Numeric vertex and face editing covers irregular walls, ceilings and terrain
  when the procedural pieces cannot express the shape. Brush coordinates are stored relative to
  the bounds and use the same editor transforms, history, materials and navigation bake as other
  solid pieces.
- **Placement previews.** The palette groups collapse independently and render thumbnails from the
  same mesh geometry as the 3D placement highlight. Preview nodes contain meshes only and never
  enter the document or physics queries.
- **Textures.** The palette offers geometry; the Inspector applies materials to placed solid
  pieces. Former material variants remain valid in saved maps and prefabs. Compound pieces keep
  their fixed trim materials while the selected texture changes their main surfaces.
- **Playtest.** The studio validates, then calls `App.start_playtest(doc, session)`. The FPS scene
  builds `App.playtest_map` instead of the default arena. Enabling **Bots** starts a standard
  practice match on that snapshot with the selected starting side and spawn. Restarts reuse
  the snapshot. `App.end_playtest()` restores the editor controller with its undo history, plus
  the map path, active layer, overlay setting and camera.
  The runtime receives the map document and match options through App.

### Map creator tools, AI support and official maps (Milestone 16)

```
 StudioUI ── intent signals ──► creation_studio.gd ──► MapEditController (multi-piece undo steps)
 EditorGizmo ── handle values ─┘        │                     │ signals
 MapSnapping / MapClipboard / MapPrefabs┘                     ▼
                                                        MapEditorView (nodes, outlines, overlay)
 MapDocument ──► MapAnalysis.analyse(doc, host) ──► issues + timings + overlay mesh
                   └ NavigationBuilder.bake_mesh (same settings as bots)
 TacticStorage ──► TacticCompatibility.check/scan(tactic, map, analysis) ──► named warnings
```

- **Format `f2f.map` v2.** Pieces gain `material`, `layer` and `group`, and yaw is any angle.
  The document gains `lighting`, editor-only `layers`, saved `prefabs`, and `content_version` +
  `content_hash`. v1 files migrate on load (default layer, no material, no group, empty
  lighting/prefabs, content version 0). Zones and picking use each piece's oriented box.
- **Content version.** `MapDocument.content_fingerprint()` hashes only what changes play: solid
  geometry and gameplay pieces with their props. `MapStorage.save` raises `content_version` only
  when that hash changes, so renames, materials, lights and layers never flag tactics.
- **Catalogue.** `block`, `ramp`, `stairs` and `compound` pieces are solid.
  `PieceShapes.parts()` describes compound pieces as boxes, cylinders and tapered sections.
  `MapBuilder` pairs each mesh with matching collision. A tapered section uses its convex mesh
  silhouette. Stairs are visual steps over a solid wedge. `walkable` marks floor-like types.
- **Materials and lighting.** `MapMaterials` generates and caches original 128 px albedo and
  normal maps with mipmaps. World-space mapping keeps repeats aligned across neighbouring pieces.
  The Inspector uses 32 px swatches. A piece's material falls back to its type default, then to the dev
  checker. `MapLighting` applies a map's sun and ambient settings in the editor and the runtime;
  empty settings leave the scene defaults. `light_lamp` and `light_spot` pieces emit in both.
- **Editing.** Every edit is a list of piece before/after states recorded as one undo step:
  group move/rotate/duplicate/delete, paste, prefab placement, grouping, material and layer
  changes. Lighting, layers and prefabs are document state recorded the same way. Gizmo and
  mouse drags preview without history and commit once. `MapClipboard` is app-wide, so a copy
  survives opening another map. A placed prefab shares a group ID and selects as one unit.
- **Snapping.** `MapSnapping` holds the pure rules: grid, angle, surface height, edge offset,
  group transforms and the measuring readout. `MapEditorView` checks the upward face under the
  cursor and confirms the snapped point is supported. Sloped faces and stair treads follow
  their local height, and snapping into a hole falls back to the build plane.
- **Autosave.** `MapAutosave` writes one recovery file per map ID while there are unsaved
  changes (every 45 s). Saving or discarding removes it; opening the studio offers the newest.
- **Layers.** Stored in the map but editor-only: hidden layers are not drawn or pickable in the
  editor, locked layers are not pickable, and the runtime builds every piece regardless.
- **Picking.** `MapEditorView` uses the piece bounds to find candidates, then tests the visible
  triangles for drawn surfaces, compound pieces, ramps and stairs. Open doors and windows allow
  selection through the opening.
- **Structural vs navigation validation.** `MapValidator` stays pure data in `src/maps`.
  `MapAnalysis` lives in `src/ai` because it bakes with `NavigationBuilder`: it builds the map
  under a host node for the duration of the call, bakes, and queries a private navigation map.
  It reports spawns off the navmesh, objectives a team cannot reach, unreachable islands of
  playable floor, and floor that people reach by jump or crouch but bots cannot (found by baking
  a second navmesh for a crouched agent with a 1.1 m climb). All are warnings. Pockets of navmesh
  sealed inside boxes, the solid wedges used by ramps and stairs, and compound geometry are
  ignored. Tops of non-walkable pieces are also ignored.
- **Route timings.** From the same analysis: shortest path from each team's spawns to every
  callout area with a timing role (`mid`, `entrance_a`, `entrance_b`) and to each site, site-to-site
  rotations and entrance-to-entrance crossings, at 6.35 m/s and at the rifle's 0.86 mobility.
- **Tactical pieces.** Callout areas, tactical anchors (plant, default, utility) and AI hints
  (cover, hold, angle) are pieces, so their piece ID is their stable ID. `MapTactical` is the
  query API. Readers: the editor, the Tactical Play Creator (areas, anchors as snap targets), the
  FPS HUD (current area), `MapAnalysis` (timing targets), `TacticCompatibility`, and `BotSquad`
  (defenders stand on `ai_hold` points for their site and watch along the hint's facing).
  `ai_cover` and `ai_angle` are stored and queryable; nothing consumes them until M7.
- **Format `f2f.tactic` v2.** Adds `map_content_version` and, per start and waypoint, the callout
  area ID and anchor ID. v1 files migrate with no references and content version 0. A tactic for
  a changed map now opens with warnings instead of being refused; only a different map is refused.
- **Tactic compatibility.** `TacticCompatibility` names the tactic, player and step for a missing
  or left area, a missing or moved anchor and an unreachable step. The editor runs it after a
  save that raised the content version and in Validate; the Tactical Play Creator runs it when
  opening a tactic. Tactic files are written only by `TacticStorage.save`, when the author saves.
- **Bot slopes.** `MapAnalysis.bot_slope_limit()` is the steepest stair or ramp the bot navmesh
  can follow: atan(climb / cell size), less a margin for rasterisation. Steeper pieces get a
  `steep_slope` warning that gives the length needed.
- **Authoring sessions.** `tools/map_author_base.gd` holds the shared steps for official map
  scripts (`tools/author_*.gd`): open the studio, place and edit pieces, validate, save, then
  publish. `slab_with_holes` lays a floor as several slabs around rectangular openings (shafts,
  ramps and drops between levels) and `floor_shape` does the same for any outline with the Draw
  Surface tool; `wall_line`/`walls_around` place angled walls with gaps, and `prism` draws an
  upright brush of any footprint. `_revision()` sets the revision a republished map ships as.
- **Sealed pockets.** The face-based bake leaves navmesh inside closed solids. The island check
  skips points inside blocks, wedges, compound parts and closed brushes (an upward ray crossing
  the brush's faces an odd number of times).
  `tools/capture_map.gd` saves screenshots of any map (it needs a window).
- **Official maps.** `OfficialMaps` lists files in `res://data/maps/official` (Kilnmarket,
  Switchyard, Kestrel Keep). They load through
  `MapDocument.from_dict` like any saved map. Opening one in the studio allows playtest and
  tactics as shipped; saving creates the player's copy under a new ID. `App.map_by_id` resolves
  official maps, the dev arena and saved maps for practice and career fixtures.
- **Map select.** The main menu's FPS Sandbox entry opens `scenes/map_select` (official maps, the
  dev arena, saved maps). `App.start_sandbox(doc)` hands the choice to the runtime once.

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
amateur fixture completes. Nothing moves by a fixed amount:
- `amateur_reputation` (pure) weighs the surprise of the result against the ELO win chance,
  the margin and your rating, and counts for less the better known you are. Simulated results
  without match statistics use a neutral performance contribution.
- `amateur_confidence_gain` grows with rounds played and shrinks as the world becomes sure of
  you.
- Perceived aim, crosshair placement and composure move toward what the match showed by a share
  that grows with the sample (shots, first shots, clutches).

Progression writes are in the same transaction as the score,
statistics and calendar advancement, so retries cannot award progression twice. Existing
careers use their difficulty's starting amateur ELO until their first recorded result.

Schema v5 also stores one scouting report per career day. (Its abstract "train one attribute
today" action was replaced in v13 by real training, below.) Scouting moves reported AI estimates
towards actual ability by an amount that depends on the evidence and increases the report's
confidence. Scouting does not disclose potential or change underlying simulated ability. Recorded match counts,
versioned performance ratings, career opinions and reputation remain separate.

### People (`src/career/people/`)

- `CareerPeople` gives every active AI professional a `person` row: six personality values
  (1–20), a drive, a background, a goal, happiness and whether they want a move. Rows are made at
  career start and lazily for rookies and older saves. Humans never get one: the person is the
  one playing.
- **Monthly** (from `WorldSimulation`): relationships between teammates (`relationship`, a < b,
  -100..100) move with compatibility and results. Moods move toward a target built from named
  reasons, and goals and life events are checked. Stories use `NEWS_PEOPLE`; interviews use
  `NEWS_INTERVIEW` with text from `PersonVoice` (all original lines).
- **Feedback:**
  - `WorldMarket` adds `renewal_modifier` and `sell_modifier`, and asks `accepts_move` before a
    transfer.
  - `CareerSeriesEngine` turns a line-up's average relationship into `SimTeam.chemistry`, which
    adds to coordination.
- Personality is shown as words (descriptors, mood, relationship labels), not raw numbers.

### Real training (owner, 2026-11-18)

The human professional has no hidden stats: the person at the keyboard is the player, so
training is played, not simulated.

- **Drills** (`src/training/`, pure): `TrainingDrills` defines the flick range, reaction test,
  tracking lane and movement course, and turns measured numbers into a 1–100 score.
  `TrainingSession` is the drill's rules without nodes (countdown, targets, reps, course clock
  and checkpoints). `TrainingResult` (`format_version`) is what a run measured.
- **Runtime:** `App.start_training` opens the FPS runtime with a training map
  (`MapTemplates.training_range` / `training_course`, built only from catalog pieces, including
  the new `course_start` / `course_checkpoint` / `course_finish` zones, so they are editable in
  the Creation Studio). `TrainingDirector` moves one target dummy, feeds shots and hits, watches
  the course pads and shows the result. It emits the result and never writes the career.
- **Scrims:** `App.start_scrim` plays an MR8 5v5 practice match against an organisation (your
  own team's players as bot teammates when signed). The score is kept as a training session,
  never as a fixture.
- **Career:** `CareerTraining.record` stores every completed session (`training_session`,
  schema v13). Every completed session is evidence; `CareerTraining.assess` (pure) decides how
  much. The perceived attribute moves toward the score by a share of the gap, scaled by:
  - how unsure the world is (its confidence);
  - how consistent the run is with your last five (a fluke says little, and a first run with no
    record says less);
  - how many times you ran the drill today;
  - whether a coach or bootcamp reviewed it.
  Confidence rises when a run confirms the view and falls when it contradicts it. Nothing
  changes FPS mechanics.
- **Scrim bonds:** `App` records each teammate's line (`MatchStatistics`) in the scrim's
  metrics. `CareerPeople.scrim_reaction` moves each teammate's relationship with you by the
  result and margin, your rating against theirs, and their temperament, ego, sociability,
  professionalism, mood and current bond.
- **Bootcamp:** booking it (`CareerSpending.buy_bootcamp`) only opens a programme
  (`BOOTCAMP_PROGRAMME`: every drill and a scrim, within `BOOTCAMP_DAYS`).
  `CareerSpending.bootcamp_state` derives progress from sessions marked `bootcamp = 1` (schema
  v15) since the booking day. `CareerTraining.record` marks the first session of each item as
  reviewed. Completing the programme judges the week (`_finish_bootcamp`):
  - confidence follows how steady the sessions were against the world's view;
  - the verdict follows how they compare with your reputation;
  - each teammate reacts by their professionalism and the quality of the week;
  - a news item reports the verdict.

### League seasons (Milestone 13)

The fixed world database provides definitions with a region, tier, field size and starting month.
Schema v6 stores published editions, locked organisations and their fixtures in the career save.
`CareerCompetitions` plans the current in-game year's season on career creation, open and the
amateur calendar's year boundary. A competition with too few eligible organisations stays
unscheduled. The initial policy admits active organisations founded by opening day, from the
specified region and the competition's tier or above. It orders invitations by tier, reputation
and stable organisation ID.

The first format is a single round-robin of BO3 series. Rounds start on the first of the authored
month. Dates are weekly where possible and fit before the next anniversary. A team plays at most
one series per round within each league. Conflicts between different competitions are a future
calendar concern. The Hub derives the table from stored series scores, ordered by wins and map
differential. The local career result writer checks the due date, the score and conflicting
submissions.

**Calendar and simulated series.** `CareerCalendar` is the only code that moves a career's date.
`advance_to(day)` runs in one transaction: it resolves every unscored series scheduled before the
new day, publishes league seasons for any year boundary crossed, then sets the date. A failure
rolls back the date as well. Saving a played fixture result calls it too, so days spent playing
are simulated as well. `advance_day` refuses while the player has an unplayed fixture due (a
calendar conflict). `SeriesSimulator` is pure: each map is won with a logistic chance from the
gap between the two starting fives' mean true ability (scale 6 points, 5–95% clamp), until one side
reaches the best-of target. Series of an organisation with a human under contract are never
simulated; playable league series follow once humans can sign for organisations (M14).
Cup brackets, promotion and relegation, and the F2F Universal Ladder remain planned.

### Living world (Milestone 14)

`advance_to` now walks the days one at a time. Each day first resolves the series due before
it, then runs `WorldSimulation.simulate_day`. The whole jump is still one transaction. Pure rules
sit beside small appliers, so the maths is tested without a database:

- **Results (`WorldSimulation.apply_series`):** form (`organisation_form`, −100..100: old × 0.6 +
  40 × map margin) and Elo-style reputation (scale 25, K by competition tier, AI starters get half,
  stochastic rounding). Form feeds `organisation_strength` (0.03 points per form point).
- **Daily (`WorldMarket`):** expiring contracts are renewed or released. Every 7th day of the year
  (`is_market_day`) organisations may try to upgrade their weakest AI starter. The weekly
  chance comes from `buy_chance(in_window, form)`: high in the January and July windows, low
  outside them, and raised for poor form. If no transfer happens, a clearly better free agent
  is signed instead and the starter is benched or released (`_make_room`). The buyer goes by tier, then reputation. The target must be 4+
  perceived points better and want the move (`wants_move`), and the seller must agree
  (`sell_chance`). Fees and finances do not exist yet. Then organisations short of five starters
  promote a substitute or sign a free agent, 35% chance per day. Decisions use
  perceived values (what the world believes), never the hidden truth. A human's contract just
  expires, as a headline.
- **Monthly (`WorldDevelopment`):** growth towards potential by age, mechanical decline from 30,
  experience decline from 33 (`player_ability_history` keeps the overall). Perceived values
  drift towards the truth, scaled by `exposure` (maps watched that month, from
  `sim_player_map`). `confidence_after` closes part of the room to the tier's visibility cap
  per map watched and lets an unseen player's read go stale. Reputation drifts towards the tier
  range.
- **Scouting and PR follow evidence:** `CareerDevelopment.scout_report` (pure) weighs the
  subject's maps in the last 90 days and tier visibility. Thin evidence can stall an estimate's
  progress towards actual ability. `CareerSpending.pr_effect` (pure) sells the human's month
  (`form_since`: maps, rating, wins) against the gap between reputation and perceived level.
- **Money (`WorldFinance`):** balances live in `organisation_finance` and `player_finance`. Every
  movement is a `finance_ledger` row, so a balance always equals its ledger sum. `ensure` gives
  organisations without finances an opening balance, which covers older saves. Monthly: income
  `TIER_INCOME × (0.75 + 0.5 × reputation)`, wages out, and humans paid. A series win pays
  `SERIES_PRIZE` by tier. Transfer fee = `(rating − 40)² × 60 × age factor × contract share`.
  Every signing uses `affordable_salary`.
- **Season endings (`WorldSeasons.close_finished`, daily):** a season with every series scored
  and no `league_record` is closed once:
  - the final table is stored (`league_record`);
  - prizes are paid through the ledger;
  - podium and last-place reputation changes apply;
  - podium squads gain `player_honour` rows and reputation;
  - humans in a paid squad get a `bonus`;
  - a human's finish is a headline.
- **Match engine (`src/career/sim/`):**
  - `MatchEngine` is pure. It takes two `SimTeam`s of `SimPlayer`s and plays a map round by
    round, returning the score, every player's counts and rating (`MatchStatistics.rating`),
    the MVP, a round log and highlights.
  - `CareerSeriesEngine` builds teams from the career (AI players' true abilities, humans'
    perceived values, traits, morale). It plays the series and writes `sim_map`,
    `sim_player_map` and `player_morale`, plus reputation and news. Monthly it fades morale
    and moves AI perceived duel skills towards recent form.
  - Simulated lines never enter the recorded statistics tables.
  - The engine lives on the career layer and never touches the FPS runtime, so career
    attributes still never affect real aim, recoil or movement.
- **Cups (`CareerCups`):** editions are published with the leagues. `cup_seed` holds the seed
  order, and the bracket is derived from the seeds and the scored series each day. A round's
  series are inserted into `league_fixture` once both sides are known, so cups reuse
  simulation, the human's playable series and the series prize money. `CareerCups.progress`
  runs daily after league closing. A decided final calls `WorldSeasons.close_cup`.
- **Promotion and relegation:** organisation tiers change only by swaps at season or cup end,
  recorded in `organisation_move`. Tier drives income, scouting caps, salaries and reputation
  drift, so a promoted organisation grows into its new level over the following months.
- **Contracted humans (`CareerHumanContracts`):**
  - transfer and renewal offers are `career_offer` kinds; the table was rebuilt in v11 to add
    them and a `fee` column;
  - benching is a contract flag;
  - `organisation_has_human_starter` decides whether an organisation's series are the
    human's to play.
- **Per-save start (`CareerStart.vary_world`):** runs once at career creation, after the
  database is copied. It only uses balanced tier swaps, form, contract dates and potential
  rolls inside authored ranges.
- **Human spending (`CareerSpending`):** `human_service` holds monthly services, charged in
  `WorldFinance.monthly` and ended when unaffordable. `human_purchase` holds one-offs with
  cooldowns. Effects touch perceived values, confidence and reputation only, never FPS
  mechanics.
- **Cup rounds and finals (`CareerCups.progress`, daily)** after league seasons close.
- **Yearly:** retirements by age and level, then an original rookie class (`WorldRookies`, name
  pools shared with the generator) of at least 10, enough to replace the retired. League seasons
  for the new year are published after the turnover.
- **News (`world_news`):** one row per story with importance 1–3. `continue_until_event` stops on
  the player's match day, any headline, or after 31 days.

**Simulate match (development option).** `CareerMatchSimulator`, shown in debug builds only,
resolves the pending career match with the world's series model:
- Strength is the lineup's mean ability (AI true abilities, human perceived rating) plus form.
- `map_win_chance` picks the winner; the loser's rounds are closer when the sides are even.
- The result is saved through the normal `record_result` with `allow_simulated`, carrying
  `SOURCE_SIMULATION` and no telemetry. No statistics or performance rating are recorded and no
  opinions move. The result still counts (owner, 2026-11-17): amateur ELO and reputation
  change from the win or loss, and league series move the human's reputation.
- League series simulate every remaining map in one press.

Whether this becomes a player-facing feature is the owner's call.

Humans are never developed, retired or re-rated by the world. Their skill is the person, and their
reputation and ELO move only through played matches (`CareerDevelopment`, and their own league
series via `apply_series(..., played = true)`).

**Path to pro.** `CareerOffers.daily` runs inside the world day:
- Lapsed offers expire.
- An unsigned human may be invited to a trial by the best tier that can see them. Visibility is
  half their reputation, plus (ELO − 800) / 20, plus recent form; their perceived level must be
  within 12 of the tier's norm.

Offers live in `career_offer`. The status flow is pending → accepted (trial booked) → passed /
failed, or declined / expired / withdrawn. A partial unique index allows one open approach per
organisation.

A trial is an ordinary `CareerFixture`. `CareerFixtures.record_result` finds it through
`career_offer.fixture_id`, and `apply_trial_result` decides the contract offer. Signing benches
the weakest AI starter.

`CareerLeagueMatches.schedule_due` books the first map of the oldest due series for a contracted
human. Each saved map is linked through `league_series_map`. `record_map` either books the next
map without advancing the day, or publishes the series with `record_league_result` and
`apply_series`.

The FPS runtime always plays the human at home, so `human_home` maps the score back to the
league's sides. Map choice is a fixed pool (`MAP_POOL`), and league maps are MR8, until per-
competition settings arrive with M19.

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
- **Shared movement.** The player and bots inherit `CombatantMovementBody` and use the same
  `PlayerMovement` tuning. They share acceleration, friction, weapon and stance speed limits,
  jumps, landings, stamina, capsule clearance and the speed passed to weapon spread. Bot
  navigation and combat supply movement intent.
- **Sandbox free-for-all (`SandboxBots`, `RoamPlanner`).** Sandbox bots each get their own team,
  so they fight the human and each other. They share one combatant list; team checks skip
  themselves. They spawn at the clear spot farthest from every living combatant, using both
  teams' spawns and the roam points. With no team plan, `RoamPlanner` (pure) scores interest
  points built from the map (bombsites, callout areas, anchors, AI hints, spawns and random
  navmesh corners):
  - interest weight, plus a bell around a 22 m trip;
  - a penalty for the last 4 destinations;
  - a pull towards gunfire heard within 45 m during the last 6 s, which becomes a push when the
    bot is at 40% health or below.
  On arrival a bot lingers for 1.2–3.5 s, watching the latest gunfire or the farthest visible
  point of interest. It walks within 14 m of recent gunfire. Fighting and searching stay the
  bot's own (`BotController`). This is sandbox behaviour only; matches use `BotSquad`, and team AI
  is M7.
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

### Weapons, Coats and Magnets

Terminology used everywhere, including the UI: a **Coat** is a weapon finish (camo/skin); a
**Magnet** is a weapon sticker.

```
 assets/weapons/<id>/model.glb ─► WeaponVisual ─► first-person viewmodel (WeaponEffects)
 WeaponModels (orientation, size,      │        ─► inspection (F) and the Armoury preview
   Coat layout, zones, slot layout)    ├─ apply_coat(texture)   replaces albedo on painted surfaces
 data/weapons/magnet_slots.json ───────┴─ set_magnet(slot, id)  one Decal per slot, on top
 CoatLibrary   official res://data/coats/coats.json + player user://coats/*.coat.json
 MagnetCatalog res://assets/magnets/<id>.png (26)
 CosmeticProfile  user://profile/cosmetics.json  ◄── Armoury (draft, Save)
```

- **Two layers per weapon.** `WeaponCatalog` keeps gameplay numbers; `WeaponModels` keeps
  presentation (model, how to turn and scale it into weapon space, Coat texture size, kit,
  zones, slot layout, credit). Nothing in `src/cosmetics` affects how a weapon shoots. The sandbox
  starts with an AK-47 and G17. Matches start with a G17; bots buy an AK-47 or SKS.
  Career statistics resolve retired weapon IDs to their original labels.
- **Weapon space.** Barrel along −Z, up +Y, left side −X, centred, true length in metres.
  `WeaponVisual` computes the fit once per weapon; skinned models are measured through their
  skeleton. Parts a source file lays out beside the gun can be hidden or aligned (`hide`, `align`).
- **Factory finish.** Each model keeps its own materials and textures. A Coat duplicates the
  factory material and swaps only its albedo texture; removing the Coat restores the factory
  material object. An empty Coat ID always means factory.
- **Coats are data.** A Coat is a PNG in the weapon's Coat layout plus a record
  (`f2f.coats` v1: id, name, weapon, rarity, texture, source, unlock). Official records live in
  `res://data/coats/coats.json` (empty today), player Coats in `user://coats`. Adding one needs
  no code. A Coat only fits the weapon it names, and its texture must match the layout size.
- **Kit conversion.** The simplified kits export a full-size PNG in the layout of the model
  shipped in `assets/weapons` (the model each kit's `Which_Model.txt` names), so an export is
  used as-is by `CoatLibrary.import_png`. The kits' zone masks ship in
  `assets/weapons/<id>/zones`; `CoatLibrary.compose` paints zones (flat colour or artwork) over
  a base image through those masks, which is the basis for in-game painting later.
- **Magnets.** Five slots per weapon. The layout (side, position along and up the weapon, size)
  is authored in `WeaponModels`; `tools/build_magnet_slots.gd` projects each onto the mesh and
  stores the surface point and the Coat UV under it. At runtime each slot is a `Decal` that
  projects in from its side, so a Magnet follows the surface, sits on top of any Coat and is
  never baked into one. Decals and weapon meshes share a render layer so Magnets never mark the
  world. A fixed matt, non-metallic ORM keeps Magnets readable on bare metal.
- **Customisation.** `CosmeticProfile` (`f2f.cosmetics` v1) stores, per weapon, the Coat ID and
  five Magnet IDs. It belongs to the player, not to a career, so the career database is not
  involved. Stale entries load as factory finish / empty slot. The Armoury edits a draft and
  writes on Save.
- **Authoring vs runtime.** `authoring/coat_kits` holds the kits and templates (with a
  `.gdignore`, so Godot neither imports nor exports them). `tools/import_weapon_assets.py`
  copies everything from the source folders and can be re-run.
- **Not yet:** shipped Coats, in-game painting, unlocks, drops, rarity effects, inventory.
  The records already carry rarity and unlock fields, and `is_unlocked` is the single gate.

### Input

`InputActions.DEFINITIONS` lists every action with its label, Controls-screen group, context
and default bindings. `register_defaults()` adds missing actions at boot, then
`InputBindings.load_file()` applies the player's saved bindings from
`user://input_bindings.json` (`f2f.input_bindings` v1). Everything else reads input by action
name, so rebinding needs no changes in gameplay code. Movement defaults use **physical**
keycodes so WASD works on non-QWERTY layouts.

- **Bindings.** A binding is `key:<physical keycode>` or `mouse:<button>`. An action holds up to
  four. Assigning an input removes it from other actions of the same context (`game` or
  `editor`; the two are never active together, so E can be Interact and editor Up). The pause
  key is locked to Esc and Esc cannot be bound elsewhere.
- **Controls screen.** `scenes/settings/controls_screen` is a top-level scene from the main menu
  and an overlay in the FPS pause menu. Changes apply and save at once.
- **Not remappable yet.** The Creation Studio's editing shortcuts (Ctrl+Z, G/T/X, Tab and so on)
  are fixed keys handled in `creation_studio.gd`; only its camera actions are remappable.
- **Noclip.** `FirstPersonController.set_noclip` disables the body's collision and flies along
  the view (jump up, crouch down, walk key faster). The runtime sets `noclip_allowed` only in
  free roam (sandbox and editor playtest); matches never allow it.

## 3. Planned modules

| Module | Responsibility | Notes |
|---|---|---|
| Career world repository **(M9–11)** | Typed access to players, orgs, contracts, fixtures and recorded performance | SQLite via `godot-sqlite` behind `CareerRepository`. |
| World progression & calendar **(partial, M10)** | Career fixture list and day advancement on a saved local result | World simulation and shared calendar coordination are planned. |
| Identity & traits **(planned)** | Stable IDs, trait library, trait-conflict rules | Traits are data (resources/JSON) with effect hooks consumed by decision systems. |
| Competitions **(partial, M13)** | Persistent round-robin seasons, standings and series results | Brackets, the Universal Ladder and authored series rules are planned. |
| Match simulation **(planned)** | Resolve AI-only fixtures without 3D | Must emit the **same event schema** as the FPS runtime. |
| Match orchestration **(local fixtures, M10)** | `MatchSetup` → FPS runtime → `MatchResult`, idempotent submission by fixture ID | The dev co-op proof uses `StubMatchRunner`. |
| FPS runtime **(partial: movement, weapons, health, match rules, bots)** | Rounds, economy, weapons, utility, bombsite | `src/combat/`, `src/rules/` + `scenes/fps_sandbox/`. Server-authoritative on match host later. |
| Training **(drills and scrims)** | Played drills with measured results | `src/training/` (pure) + `TrainingDirector` in the FPS runtime; `CareerTraining` records results. |
| Bot AI **(individual, M6)** / Tactical AI / IGL **(planned)** | Individual combat + team plans + calls | `src/ai/` + `BotSquad`; one team-tactics layer shared by AI and human IGLs in M7. |
| Statistics **(M11)** | Versioned events, derived per-player counts and calculated ratings | Perceived/scouted values and reputation remain separate. |
| Map editor **(M3, M16)** | Modular pieces, group editing, prefabs, snapping, materials, lighting, navigation validation, playtest | `src/maps/` + Creation Studio; see the M16 section. Sharing is M17. |
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
| 2026-11-16 | Sandbox bots play free-for-all and roam by scored interest points and heard gunfire instead of homing on the human | They no longer know where the player is through walls. Gunplay testing gets varied, fair fights. The planner is pure and testable, and reusable when M7 adds team intent |
| 2026-11-17 | Simulated (dev) matches count for ELO and reputation (owner) | Quick testing should exercise the same career progression as played matches; without telemetry they still record no statistics or opinion changes |
| 2026-11-17 | The transfer market is open all year; windows only raise the odds (owner) | Struggling teams can react mid-season, which makes the world feel alive, while windows keep most movement predictable |
| 2026-11-17 | Trials and league series maps are ordinary career fixtures linked by side tables (`career_offer.fixture_id`, `league_series_map`) | One fixture pipeline (validation, telemetry, statistics, calendar conflicts) serves every playable match. The FPS runtime still only sees a `MatchSetup` |
| 2026-11-17 | Cup series reuse `league_fixture`; tiers move only by swaps; each save varies its start | One series pipeline for leagues and cups (simulation, playable series, prizes). Swaps keep every tier the same size, so finances and competitions stay balanced while the world changes. Starting variation stays within authored ranges |
| 2026-11-17 | Simulated series are played round by round by a pure engine on the career layer; simulated player lines are stored apart from recorded statistics | Results come from people and moments (form, morale, traits, economy, clutches), not one strength roll, so the world feels alive and less predetermined. Recorded stats stay a record of played matches only. A simulated year takes a few seconds |
| 2026-11-17 | The Career Hub navigates by routes with a history; pages link to each other | Manager games are browsed by clicking through teams, squads, players and matches. Routes keep pages independent (each builds from its args), Back works everywhere, and new pages only add a registry entry |
| 2026-11-18 | Training is played in the FPS (drills and scrims); results are measured evidence for the human's perceived attributes | The human has no hidden stats to raise, so "train aim today" was fiction. Real drills train the person at the keyboard; the career only records what they measured, and the runtime still never writes the career |
| 2026-11-18 | AI professionals are people (personality, mood, relationships) whose feelings change world decisions and match chemistry | A living world needs individuals, not ratings: who renews, who leaves, who refuses a move and how well a five plays together now depend on the people involved. Moods are explained by named reasons so the hub can say why |
| 2026-11-18 | The bootcamp is a programme of real sessions, not a purchase that raises attributes | Consistent with real training: money buys structure (a week's plan, reviewed evidence), but only sessions you play move the world's view of you |
| 2026-11-18 | No fixed rates in training (owner) | Changes to the world's view, confidence and relationships are derived from what happened in the session and from the people involved, so the same action can help, do nothing or backfire. Constants are weights and limits, never the outcome |
| 2026-11-16 | The living world runs day by day inside the calendar's transaction; AI decisions use perceived values; Continue stops on headlines | One writer keeps days atomic and replayable in tests. Judging by opinion keeps the hidden-truth layer hidden. News importance gives one simple stop rule that offers and invites can join later |
| 2026-11-15 | One calendar writer (`CareerCalendar`); unplayed series are simulated from true lineup ability as the day passes | Results can never be skipped or double-counted, and off-screen outcomes follow real squad strength rather than reputation |
| 2026-11-15 | One movement model (`PlayerMovement`) for humans and bots via `CombatantMovementBody`; values fitted to recorded reference runs and tagged measured/estimate | Bots can never move better or worse than a person; competitive feel comes from data, and estimates stay visible for later tuning |
| 2026-11-15 | Run speed comes from the held weapon's `mobility`; weapon spread sees speed rescaled so a full run is always the reference speed | Retuning movement never silently changes weapon balance |
| 2026-11-15 | Navigation validation lives in `src/ai` (`MapAnalysis`), structural validation stays in `src/maps` | The checks must bake with the exact bot settings; `src/maps` stays free of AI and navigation code |
| 2026-11-15 | Reachability findings are warnings, not errors | A half-built map must stay playtestable; official maps are held to "no warnings" by their test |
| 2026-11-15 | "Playable floor" = navmesh resting on a `walkable` catalogue type | Roofs, crate tops and wall tops always form islands; only floors matter |
| 2026-11-15 | Jump/crouch routes found by a second bake for a crouched, climbing agent | One mechanism covers both cases without modelling jumps |
| 2026-11-15 | Areas, anchors and hints are pieces; piece ID = stable ID | One ID scheme, one undo path, one file; no parallel registry to keep in sync |
| 2026-11-15 | Tactics bind to a map content version and warn, instead of refusing any changed map | Any edit used to orphan every tactic without saying what broke |
| 2026-11-15 | Content fingerprint excludes names, materials, lights, layers, groups and prefabs | Cosmetic work must not flag tactics |
| 2026-11-15 | Compound pieces are lists of boxes and cylinders with identical colliders | Collision matches visuals by construction; no imported meshes |
| 2026-11-15 | Stairs collide as a solid wedge, not a thin slope sheet | Nothing can pass under a stair run |
| 2026-11-15 | Palette textures generated in code | Original content, no asset pipeline, reviewable in a diff |
| 2026-11-15 | Official maps are saved map files in `res://data/maps/official`; saving one makes a copy | Official content uses the community path and cannot be shadowed by a player file |
| 2026-11-15 | Kilnmarket authored by a session script that drives the Creation Studio scene (`tools/author_kilnmarket.gd`) | A headless agent cannot click; this uses only editor operations and leaves a rebuildable record. To be replaced by hand edits in the editor as the map is iterated |
| 2026-11-19 | Bot slope limit derived from the navmesh settings, not the agent's max slope | The 46° agent slope never applies to stairs: a 0.1 m climb over a 0.2 m cell splits any slope above about 26°, so validation warns at 24° |
| 2026-11-19 | Official maps share `tools/map_author_base.gd` | Each map script holds only its own layout; validate, save and publish behave the same for every map |
| 2026-11-15 | User bindings stored as strings per action and applied to `InputMap`; conflicts scoped by context | Gameplay code keeps using action names; game and editor can reuse keys |
| 2026-11-15 | Esc is locked to the pause menu | A player can never bind themselves out of the menus |
| 2026-11-16 | Third-party weapon models (CC BY 4.0) and real weapon names, at the owner's direction | Supersedes "all content original" for weapons only; attribution in CREDITS.md. Two models have no recorded licence (open item) |
| 2026-11-16 | Magnets are decals on fixed slots, not texture edits | Independent of Coats, work on any future Coat, cheap to add and remove |
| 2026-11-16 | A Coat swaps albedo only and must match the kit's layout size | Kits export exactly what the game loads; factory normal/roughness maps stay |
| 2026-11-16 | Cosmetics saved in a player profile file, not the career database | A look follows the player across careers and modes; no schema change |
| 2026-11-16 | The ten modelled weapons replace the development roster | Sandbox, match shop and bots use the modelled roster; names of retired weapon IDs stay readable in career history |
| 2026-11-15 | **Career database = SQLite from day one** (owner's decision; supersedes "defer SQLite") via `godot-sqlite` v4.9 (MIT, built for Godot 4.7.1, Windows supported) | The career world is a third of the game: thousands of players, years of history and match events need indexed queries, partial loading and crash-safe transactions. Building on JSON first would mean a rewrite. SQLite itself is public domain; both licences allow a closed commercial release (MIT notice to be shipped in credits). Access stays behind a typed repository so the add-on is isolated |

### Surface relief (2026-11-20)

Every solid piece may carry `props.relief` (0–3, default 1). `MapMaterials.material(id, relief)`
returns a cached variant of the palette material that shares its albedo, normal and occlusion
textures and only changes `normal_scale` and `ao_light_affect`, so relief costs no texture
generation. Height (parallax) mapping is deliberately not used: Godot does not support it with
the world-space triplanar mapping every map surface relies on.
