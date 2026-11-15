# Frag to Fame: FPS Career Simulator (F2F)

An original commercial PC game that combines an individual esports **player career**, a deep
**Football Manager-style** persistent world, and fully playable **tactical 5v5 first-person**
matches. Built with Godot 4.7.2 (typed GDScript, Forward+). Target platform: Windows / Steam.

> **Status:** Pre-alpha — Milestone 11 recorded match statistics. See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Documentation

| File | Purpose |
|---|---|
| [`docs/GAME_VISION.md`](docs/GAME_VISION.md) | Canonical long-term game design |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Module boundaries, data rules, decisions log |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Milestones, dependencies, progress |
| [`CLAUDE.md`](CLAUDE.md) | Coding standards and working rules for AI-assisted development |

## Setup

1. Install **Godot 4.7.2 Stable** (standard build is fine; the .NET build also works — the project
   uses GDScript only). On the owner's PC a self-contained copy lives in `C:\GrevCo\Tools\Godot\`
   (run `Godot_v4.7.2-stable_mono_win64.exe`).
2. Clone: `git clone https://github.com/Grevyo/FragToFame.git C:\GrevCo\FragToFame`
3. Open Godot → **Import** → select `C:\GrevCo\FragToFame\project.godot` → **Import & Edit**.
4. Press **F5** (Run Project). The main menu opens.

## Controls

**Main menu / Career Hub:** mouse, or Tab/arrow keys + Enter.

**FPS Sandbox**

| Input | Action |
|---|---|
| W A S D | Move |
| Mouse | Look |
| Space | Jump |
| Shift (hold) | Walk (slower, more accurate, quieter later) |
| Ctrl or C (hold) | Crouch (slower, more accurate; you stay crouched under low ceilings) |
| Left click | Fire (or recapture the mouse if it was released) |
| R | Reload |
| 1 / 2 / 3 · mouse wheel | VK-12 Vanta rifle / P-4 Kestrel pistol / M-5 Wasp SMG · cycle |
| B | Buy menu (practice match, in your buy zone during the buy window) |
| E (hold) | Plant the bomb on a bombsite / defuse a planted bomb (practice match) |

Practice matches are 5v5: you + 4 bot teammates (orange) vs 5 bots (teal), normal skill.

| Esc | Pause menu / release mouse (Esc again resumes; closes the buy menu first) |

Weapons, numbers and names are original development values and will be tuned.

**Creation Studio**

| Input | Action |
|---|---|
| Right mouse (hold) | Look around (captures mouse) |
| RMB + W A S D | Fly |
| RMB + E / Q | Fly up / down |
| RMB + Shift | Fly faster |
| RMB + mouse wheel | Change fly speed |
| Mouse wheel | Dolly forward / back |
| F | Reset view |
| Left click | Select tool: select a piece and drag to move it · Place tool: place a piece |
| 1 / 2 | Select tool / Place tool (last palette piece) |
| R / Shift+R | Rotate selected piece (or placement ghost) by ±90° |
| Arrow keys | Nudge selected piece by one snap step on X / Z |
| PgUp / PgDn | Nudge selected piece up / down, or raise / lower the build height |
| Delete / Backspace | Delete selected piece |
| Ctrl+D | Duplicate selected piece |
| Ctrl+Z · Ctrl+Y / Ctrl+Shift+Z | Undo · Redo |
| Ctrl+S · Ctrl+O · Ctrl+N | Save · Open · New |
| F5 | Validate and playtest the map in the FPS runtime |
| Esc | Cancel drag / leave Place tool / deselect |
| Snap dropdown | Change grid / placement snap (0.25–4 m) |

Maps are saved to `%APPDATA%\Godot\app_userdata\Frag to Fame\maps\*.f2fmap.json`
(the previous version is kept as `.bak`).

### Tactical Play Creator

Open a saved map in **Creation Studio** and select **Tactics**. The tool uses the map's saved
revision. To try it on the sandbox arena, open the template and save the resulting map first.

1. Select a player from **Player 1–5**, choose **Set start**, and click a walkable surface.
2. Choose **Add waypoint** and click the route points in traversal order. The map shows coloured
   routes and numbered markers for the selected player. To relocate a point, select it in the
   list, choose **Move selected point**, and click its new position. **Remove selected waypoint**
   deletes the selected waypoint. A player without waypoints holds at their start.
3. Name the tactic and press **Save**. To reopen it, load the same saved map and use **Tactics →
   Open**. Tactics live under `user://tactics` as `*.f2ftactic.json`. Re-saving also keeps the previous
   tactic as `.bak`.
4. Press **Preview** to spawn the five navigation bots, then watch their progress in the sidebar.
   **Stop** removes them. **Preview** starts again at the authored positions. Unreachable points
   are reported per player. **Map Creator** returns to the saved map.

## Testing

Automated (headless) validation — imports the project and runs `tests/run_tests.gd`:

```powershell
powershell -ExecutionPolicy Bypass -File tools\validate.ps1
```

The script finds Godot 4.7.2 automatically (PATH, known local installs, then a shallow search of
`C:\GrevCo` and common install folders). To use a specific binary, pass
`-Godot "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"` or set `$env:GODOT_BIN`.

Or directly:

```powershell
& $env:GODOT_BIN --headless --path . --import
& $env:GODOT_BIN --headless --path . --script res://tests/run_tests.gd
```

Exit code 0 means all tests passed. Two `ERROR:` lines in the output (`unknown page
'does_not_exist'`, `unknown scene id 'nope'`) are expected — they come from negative tests.

### Manual test checklist (Milestone 1)

- [ ] Main menu shows **FRAG TO FAME** / **FPS Career Simulator** and four buttons.
- [ ] **Career Hub** opens; all six sidebar pages switch; the active item is highlighted;
      the yellow *development sample data* badge is visible; **Main Menu** returns.
- [ ] **FPS Sandbox** captures the mouse; WASD/mouse/jump/Shift-walk feel correct; you collide with
      walls and crates; you can walk up the ramp and the stairs onto the platform.
- [ ] Esc shows the pause menu and frees the mouse; **Resume** recaptures; **Return to Main Menu** works
      and the cursor is visible in the menu.
- [ ] **Creation Studio** shows the grid with red X / blue Z axes and an orange snapped cursor under
      the mouse; RMB fly controls work; snap dropdown changes grid density and cursor size;
      **Main Menu** returns.
- [ ] **Quit** closes the game.
- [ ] Window resizing keeps layouts usable.

### Manual test checklist (Milestone 2 — networking proof)

Run two game instances. In the Godot editor: **Debug → Customize Run Instances…**, enable
*Enable Multiple Instances*, set the count to **2**, then press F5. (Or export and run the
build twice.) Windows may show a firewall prompt the first time you host — allow it for
private networks if you want LAN friends to join; local two-instance testing works either way.

Career sync (Career Hub → **Co-op (Dev)**):

- [ ] Instance A: **Host career**. Status shows Role HOST, Connection READY, five fixtures.
- [ ] Instance B: **Join career** (127.0.0.1). Status shows Role CLIENT, same World ID and revision.
- [ ] On B, **Play stub match** on a fixture: the log shows `ACCEPTED`; the score appears on
      **both** instances and the revision increases on both.
- [ ] On B, **Resend** that fixture: log shows `DUPLICATE`; nothing changes.
- [ ] On A, **Conflict test** on the same fixture: log shows `CONFLICT`; the original score stays.
- [ ] Visit FPS Sandbox and come back: the career connection is still READY (it persists).
- [ ] Disconnect B and rejoin A without restarting A. The same world and fixtures return.
- [ ] Join a different career host with a new dev world. Its own fixtures and revision appear.
      Return to A and confirm its original results are still present.
- [ ] Close A and confirm B's connection and fixture view clear.

Match netcode (FPS Sandbox → Esc → *Local match network*):

- [ ] Instance A: **Host match**. Badge shows `NET HOST · peer 1 · 1 player(s)`.
- [ ] Instance B: **Join** 127.0.0.1. Both badges show 2 players.
- [ ] Each instance sees a coloured capsule for the other player that follows its movement and
      faces the way it looks (the dark visor marks the front).
- [ ] **Leave** on B: the capsule disappears on A. Re-join works.
- [ ] Hosting a match does not disconnect the career session, and vice versa.

Ports: career sync **24560**, match **24570** (UDP).

### Manual test checklist (Milestone 3 — map editing)

- [ ] **Creation Studio → Open → Templates → Sandbox Arena (dev)**: the arena appears with coloured
      spawn markers, translucent bombsite / buy-zone volumes and floating labels.
- [ ] Click a palette piece (e.g. *Crate*): a ghost follows the mouse, snapped to the grid and
      stacking on top of solid pieces; **R** rotates it; left click places it.
- [ ] **1** then click a piece: it gets a yellow outline and the inspector shows its position,
      rotation and size. Drag moves it on the grid; arrows / PgUp / PgDn nudge it.
- [ ] Edit a size in the inspector: the piece resizes. **Ctrl+Z** undoes each step, **Ctrl+Y**
      redoes; a whole drag undoes in one step.
- [ ] **Delete** and **Ctrl+D** work on the selection.
- [ ] **Validate** lists errors / warnings (try deleting all attacker spawns: Playtest is blocked).
- [ ] Rename the map in the inspector, **Save**, **New**, then **Open** the saved map: it comes
      back identical. Closing with unsaved changes asks for confirmation.
- [ ] **Playtest** (F5): you spawn at the attacker spawn and can walk up the ramp and stairs and
      onto the platform. Esc → **Return to editor** brings back the map, unsaved edits and camera.
- [ ] **FPS Sandbox** from the main menu still loads the default arena (not the last playtest).

### Manual test checklist (Milestone 4 — FPS mechanics)

- [ ] FPS Sandbox: four target dummies face the spawn (one close, one far behind low cover,
      one strafing, one on the platform). A gun model is visible bottom right.
- [ ] Left click fires: muzzle flash, tracer, a hit marker on hits, floating damage numbers on the
      dummy (yellow-red for headshots), dark impact marks on walls. Ammo counts down.
- [ ] Hold fire with the rifle: the spray climbs, then drifts left and right in the same pattern
      every time; pulling the mouse down compensates. Releasing lets the view settle back.
- [ ] The crosshair opens while running/jumping and tightens when still or crouched; first shots
      while standing still land on the crosshair, running shots scatter.
- [ ] One rifle headshot (or one close pistol headshot) eliminates a dummy: it tips over, the kill
      feed and training stats update, and it stands back up after ~2.5 s.
- [ ] **R** reloads (bar under the ammo); an empty magazine reloads on the next click.
      Switching weapons cancels a reload and has a short draw delay; each weapon keeps its ammo.
- [ ] Crouch lowers the view and slows you down. To check ceilings, place a block in the studio
      raised 1.3 m (PgUp) over open floor, playtest, crouch under it and release: you stay crouched.
- [ ] Jump off the arena (or fly off in a playtest map without walls): the ELIMINATED overlay
      counts down and you respawn at the spawn with full health and ammo.
- [ ] Creation Studio: the **Training → Target dummy** piece can be placed, set to *strafe* in the
      inspector and shot at in Playtest.

### Manual test checklist (Milestone 5 — competitive match rules)

Start from **FPS Sandbox → Esc → Start practice match** (MR3, first to 4). Since Milestone 6 the
practice match uses bots, so the opposing team now fights back and the scoreboard shows
"Practice Bots".

- [ ] Round 1 opens in freeze time: scoreboard `You [ATT] 0 · BUY 0:05 · 0 [DEF] Training Targets`,
      you cannot move or shoot but can look around; "Press B to buy" shows at spawn.
- [ ] **B** opens the buy menu: $900; buy a vest ($650) → money $250, rifle disabled (too
      expensive), defuse kit marked *defence only*. B / Esc closes it. The menu closes by itself
      when the buy window ends or you walk out of the buy zone.
- [ ] Kill all five targets: "ATTACKERS WIN · Enemy team eliminated", money rises by kill rewards
      plus the win reward, next round starts after a few seconds with your vest kept.
- [ ] Walk to bombsite B (far-left corner) or A (top of the platform): "Hold E to plant"; holding
      E freezes you, shows a progress bar, then "BOMB PLANTED"; the clock turns red and the bomb
      blinks faster until it detonates → attackers win.
- [ ] After round 3 the sides switch: you defend from the north spawn with money reset to $900.
      Letting the clock run out wins the round for defence.
- [ ] Falling off the map in a match shows "You will respawn next round" (no instant respawn).
- [ ] Reaching 4 rounds shows VICTORY / DEFEAT with the final score and the recorded result ID;
      **Play again** restarts, **Return to Main Menu** leaves.
- [ ] Esc during a match pauses the clock; Resume continues.

### Manual test checklist (Milestone 9 — player/team database)

Start from **Main menu → Career Hub** (opens the career screen when no career is loaded).

- [ ] With no careers, the left card says "No careers yet". Fill in the new career form (try
      leaving the nickname empty first: a clear error appears and nothing is created).
- [ ] Select the default world template. **Create career** opens the hub with the career name and
      the date `01 Jan Y1` in the top bar.
- [ ] **Home** greets your nickname, shows you as a free agent with a reputation matching the
      difficulty, world counts (40 organisations, ~296 professionals) and the top organisations.
- [ ] **Player Profile** shows your professional with perceived attributes only.
- [ ] **Teams** lists organisations by tier; selecting one shows its info and a 5–6 player roster
      with roles, ages, nations, perceived ratings and contract end dates. Names are original.
- [ ] **Players**: search by nickname, filter by role, region and free agents; selecting a player
      shows identity, contract, reputation, scouting confidence, traits and perceived attributes.
- [ ] **Practice match vs <team>** starts a match against that organisation's starters (their
      nicknames in the kill feed and scoreboard); a tier-1 side should feel clearly harder than an
      amateur side.
- [ ] Back to the main menu, quit the game, relaunch: **Career Hub → Continue** reopens the same
      world with the same players.
- [ ] Create two careers from the same world database. Confirm they start with the same
      organisations, professionals, rosters and competitions, and appear as separate saves.
- [ ] In a live practice round with bots, press Esc. The clock, bots and combat stop. Resume and
      verify they continue. **Play again** and **Restart practice match** retain the opponent and
      its roster, with a fresh score.
- [ ] From Career Select, use **Import world template** on a valid standalone `.f2fdb`. Select
      it for a new career. Re-importing that ID asks before replacing it and keeps the previous
      file as `.bak`. A rejected import leaves it available.
- [ ] With a disposable career only, test restoring from a known-good snapshot through Career
      Select. Reopen the career and verify the original database is retained under a
      `career.db.damaged-…` filename. Close other game instances before restoring.

Saves live in `%APPDATA%\Godot\app_userdata\Frag to Fame\careers\<save>\career.db` with
snapshots in `backups\`.

### Manual test checklist (Milestone 6 — combat and navigation AI)

Start from **FPS Sandbox → Esc → Start practice match (MR3 · 5v5 with bots)**.

- [ ] The notice reads "PRACTICE · 5v5 with bots (normal)"; four
      teammates stand beside you and five opponents at the far spawn.
- [ ] During freeze time nobody moves; when the round goes live bots run to bombsites using the
      ramp and stairs, not through walls or off ledges.
- [ ] Bots spot you only when you are in front of them or close, after a short reaction delay;
      they miss sometimes; hiding behind walls breaks line of sight.
- [ ] Bots reload behind cover when possible and search where they last saw you.
- [ ] Teammate bots never shoot you; kills appear in the kill feed with weapon and headshot tag.
- [ ] As attacker, die with the bomb: a teammate bot picks it up and plants on a site.
- [ ] On defence, after a plant, bots go to the bomb and defuse when they see no enemy.
- [ ] Bots buy rifles/SMGs and armour when they can afford them (watch round 2+).
- [ ] The match finishes with VICTORY / DEFEAT as before.

Known limits: bots do not coordinate as a team yet (M7), there is no audio so bots cannot hear
you, and there are no grenades/utility. On the open sandbox arena both teams can see each other
from spawn, so rounds often start with a long-range fight.

### Manual test checklist (Milestone 8 — tactical route authoring)

- [ ] Open a saved map, switch to **Tactics**, and place all five starts and several waypoints
      for each player. Check that the selected slot, numbered points and coloured routes agree.
- [ ] Move a waypoint and delete another. Add its replacement and verify the displayed order.
- [ ] Save, quit, relaunch and reopen the map and tactic. Start preview, watch all five bots
      attempt their routes, then stop and replay from the starts.
- [ ] Edit and save the tactic again. Reopen it and verify the edits and route order.
- [ ] Try an unreachable surface and confirm the affected slot reports the issue. Return to Map
      Creator, save a new map revision, and try opening the old tactic. Check that the editor
      reports the mismatch and the tactic file is preserved.
- [ ] Return to Map Creator and use normal map selection, save/open and FPS playtest. Try leaving
      Tactical Play Creator with unsaved edits and verify the discard prompt.

### Manual test checklist (Milestone 10 — playable career fixtures)

- [ ] Continue an existing career or create one. From **Career Hub → Home**, choose **Schedule
      amateur match**. Check the opponent, date and MR5 format, then check Calendar for the entry.
- [ ] Choose **Play fixture**. Confirm it opens five versus five against the scheduled roster.
      Pause and return to the Career Hub mid-match. The same fixture and date remain available.
- [ ] Play again and complete the match. Check the final score and saved-result message. Return
      to the Hub and confirm the career advances one day and Calendar records the score.
- [ ] Quit and reopen the career. The score and date persist. Scheduling another match creates
      a new fixture on the new date. Ordinary practice from Teams stays off the career calendar.

### Manual test checklist (Milestone 11 — recorded statistics)

- [ ] Play a career fixture. Take several shots, land hits and complete the match. Return to
      **Career Hub → Statistics** and check K-D-A, ADR, KAST, accuracy and the recent-match score.
- [ ] Check the weapon breakdown and the performance rating on your player profile. Find an
      AI opponent in the Players browser and verify their profile also shows the recorded match.
- [ ] Reopen the career and confirm the recorded match remains visible. A practice match from
      Teams leaves the statistics unchanged.

## Project layout

```
addons/godot-sqlite  SQLite GDExtension (Windows + Linux x86_64 binaries only)
src/core      App autoload (scene routing), input actions
src/ui        Theme builder, UI helpers
src/career    Career database: SQLite layer (db/), repository, records, catalogues, traits,
              world generation (generation/), saves, human career, match setups
src/world     Shared 3D building blocks
src/maps      Map document format, builder, validator, storage, edit controller
src/combat    Weapons, spread/recoil, damage, health, armour, hitboxes, hitscan, shooting tally
src/rules     Competitive rules: MatchRules (format/economy data), ShopCatalog, MatchState
src/statistics  Round-event reduction, career counters and the F2F performance formula
src/ai        Bot AI: navmesh baking, skills, aim model, BotController (individual combat)
src/tactics   Versioned, map-bound tactic documents, save/open and navigation preview
src/orchestration  MatchSetup / MatchResult contracts
src/net       career_sync (career host) and match (in-match netcode), kept separate
scenes/       main_menu, career_select, career_hub (+pages), fps_sandbox, creation_studio
tests/        Headless test runner
tools/        Validation script
docs/         Vision, architecture, roadmap
```

## Legal

All rights reserved. This is a proprietary commercial project; no open-source licence is granted.
All game content is original. Frag to Fame is not affiliated with Valve, Counter-Strike or LIGA.

Third-party components (must be credited in the shipped game):

| Component | Licence | Location |
|---|---|---|
| Godot Engine 4.7.2 | MIT | engine |
| godot-sqlite 4.9 (Piet Bronders & Jeroen De Geeter) | MIT | `addons/godot-sqlite/LICENSE.md` |
| SQLite 3.51 | Public domain | bundled in godot-sqlite |
