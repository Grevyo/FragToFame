# Frag to Fame: FPS Career Simulator (F2F)

An original commercial PC game that combines an individual esports **player career**, a deep
**Football Manager-style** persistent world, and fully playable **tactical 5v5 first-person**
matches. Built with Godot 4.7.2 (typed GDScript, Forward+). Target platform: Windows / Steam.

> **Status:** Pre-alpha — Milestone 1 (application foundation). See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Documentation

| File | Purpose |
|---|---|
| [`docs/GAME_VISION.md`](docs/GAME_VISION.md) | Canonical long-term game design |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Module boundaries, data rules, decisions log |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Milestones, dependencies, progress |
| [`CLAUDE.md`](CLAUDE.md) | Coding standards and working rules for AI-assisted development |

## Setup

1. Install **Godot 4.7.2 Stable** (standard build is fine; the .NET build also works — the project
   uses GDScript only).
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
| Shift (hold) | Walk (slower, quieter later) |
| Esc | Pause menu / release mouse (Esc again resumes) |
| Left click | Recapture mouse if it was released |

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
| Grid snap dropdown | Change grid / cursor snap (0.25–4 m) |

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
- [ ] Close A: B shows *connection to host lost*.

Match netcode (FPS Sandbox → Esc → *Local match network*):

- [ ] Instance A: **Host match**. Badge shows `NET HOST · peer 1 · 1 player(s)`.
- [ ] Instance B: **Join** 127.0.0.1. Both badges show 2 players.
- [ ] Each instance sees a coloured capsule for the other player that follows its movement and
      faces the way it looks (the dark visor marks the front).
- [ ] **Leave** on B: the capsule disappears on A. Re-join works.
- [ ] Hosting a match does not disconnect the career session, and vice versa.

Ports: career sync **24560**, match **24570** (UDP).

## Project layout

```
src/core      App autoload (scene routing), input actions
src/ui        Theme builder, UI helpers
src/career    Career-world data (currently dev sample data only)
src/world     Shared 3D building blocks
scenes/       main_menu, career_hub (+pages), fps_sandbox, creation_studio
tests/        Headless test runner
tools/        Validation script
docs/         Vision, architecture, roadmap
```

## Legal

All rights reserved. This is a proprietary commercial project; no open-source licence is granted.
All game content is original. Frag to Fame is not affiliated with Valve, Counter-Strike or LIGA.
