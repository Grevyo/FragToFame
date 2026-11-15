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

## 2. Current implementation (Milestones 1–2)

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
scenes/
  main_menu/                  Main menu (Career Hub / FPS Sandbox / Creation Studio / Quit)
  career_hub/career_hub.*     Sidebar + page host
  career_hub/pages/*.gd       One CareerPage subclass per section
  fps_sandbox/                Test level, first-person controller, HUD + pause overlay
  creation_studio/            Fly camera, grid, snapped cursor, editor UI shell
tests/run_tests.gd            Headless test runner (SceneTree script) over tests/suites/*
tests/test_suite.gd           TestSuite base: check(), wait_until(), scene helpers
tools/validate.ps1            Import + test runner for Windows
```

### Scene routing

`App.go_to(scene_id)` is the only sanctioned way to change top-level scenes. Scene IDs are
`StringName` constants in `app.gd`, mapped to paths in `SCENE_PATHS`. Routing always resets the
mouse mode to visible so a scene can never leave the cursor captured for the next one.

### UI construction

Top-level UI is built in code from small `.tscn` roots. Reasons: hand-authored scenes stay
diff-friendly, theme usage is consistent, and pages are trivially data-driven. The theme is built
once by `F2FTheme.build()` and assigned to the root `Window`, so every Control inherits it.
Named type variations (`TitleLabel`, `CardPanel`, `SidebarButton`, …) are the styling vocabulary;
avoid per-node colour overrides.

### Career Hub pages

`career_hub.gd` holds a `PAGES` registry (id, title, script). Each page is a `CareerPage`
(`VBoxContainer`) that builds itself in `build_page()`. Adding a section = add a script + a registry
entry. Pages currently read only `DevSampleData`; they will switch to repository view-models when
the database arrives, without changing the hub.

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
pending until acknowledged and resend them after reconnecting — safe because of deduplication.
Every accepted change bumps `revision`; clients never apply an older snapshot over a newer one.

**Match authority (proof only).** Clients are authoritative for their own position; the host
relays snapshots at 20 Hz (clients send at 30 Hz). Server-authoritative movement, hit registration
and lag compensation are deliberately deferred to the FPS milestones.

**Not yet:** persistence of the career world, calendar advancement blocked on unresolved
fixtures, the career host choosing a match host, spectating, NAT traversal / Steam networking.

### Input

`InputActions.register_defaults()` adds actions only if they don't already exist, so future
user-rebinding (saved to `user://`) can be loaded first and win. Movement uses **physical**
keycodes so WASD works on non-QWERTY layouts.

## 3. Planned modules

| Module | Responsibility | Notes |
|---|---|---|
| Career world repository **(planned)** | Typed access to players, orgs, contracts, fixtures | SQLite via a GDExtension (evaluate `godot-sqlite`) once data volume justifies it; JSON documents before that. Versioned schema + migrations. |
| World progression & calendar **(planned)** | Day-by-day advancement, blocking on unresolved fixtures | Pure logic, deterministic given seed + inputs. |
| Identity & traits **(planned)** | Stable IDs, trait library, trait-conflict rules | Traits are data (resources/JSON) with effect hooks consumed by decision systems. |
| Competitions **(planned)** | League/cup/swiss/bracket generators, F2F Ladder | Formats data-driven (series, MR length, overtime, veto). |
| Match simulation **(planned)** | Resolve AI-only fixtures without 3D | Must emit the **same event schema** as the FPS runtime. |
| Match orchestration **(contracts + stub)** | `MatchSetup` → runtime → `MatchResult`, idempotent submission by fixture ID | Contracts in `src/orchestration/`; only `StubMatchRunner` exists so far. |
| FPS runtime **(partial: movement)** | Rounds, economy, weapons, utility, bombsite | Server-authoritative on match host. |
| Bot AI / Tactical AI / IGL **(planned)** | Individual combat + team plans + calls | One team-tactics layer shared by AI and human IGLs. |
| Statistics **(planned)** | Event log → derived stats → ratings | Raw events stored; stats recomputable. Perceived/scouted values stored separately. |
| Map editor **(shell)** | Modular pieces, snapping, gameplay markers, validation, playtest | Saves versioned map documents; official maps use it too. |
| Tactical Play Creator **(planned)** | Routes, roles, utility, triggers, playbooks | Produces tactic documents consumed by Tactical AI. |
| Content loader **(planned)** | Official vs custom content, IDs, versions, dependencies | Saves record content manifest. |
| Co-op career sync **(proof)** | Career host authority, client requests, calendar sync | Raw ENet message protocol; see Networking above. Calendar sync not yet. |
| Match netcode **(proof)** | Listen server on a player's PC, player state sync | `MatchSession`; position + facing only. |
| Persistence & backup **(planned)** | Atomic saves, rotating backups, migrations | Write-temp-then-rename; schema version in every save. |

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
| 2026-11-15 | Defer SQLite until the career database milestone | Avoid a GDExtension dependency before it pays for itself |
| 2026-11-15 | Career sync = raw ENet peer + versioned dictionary messages, no RPC | Transactional, testable, version-checkable; cannot become entangled with scene-tree RPCs |
| 2026-11-15 | Match netcode = SceneMultiplayer on its own tree branch | Native RPCs for real-time play; branch isolation lets host and client (and tests) coexist in one process |
| 2026-11-15 | Career host connects to itself as a client | One code path for every human, fewer host-only bugs |
| 2026-11-15 | Dedupe by submission ID or identical scoreline; differing score = CONFLICT | Safe resends/recovery; several participants may report the same fixture |
| 2026-11-15 | Clients own their position in the M2 proof | Smallest proof of the two-network split; authority model revisited in M4/M5 |
