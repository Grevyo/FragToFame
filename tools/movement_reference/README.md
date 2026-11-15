# Movement reference measurements

How the reference numbers behind `src/movement/player_movement.gd` were recorded, so they can
be repeated. Only our own logger script and its output live here; no reference-game code,
assets or maps are in the project.

## Conditions (recorded 2026-11-15)

- The **reference game**: a released competitive tactical shooter, stock install (version recorded
  in the owner's notes), offline local server, competitive mode, 64 tick, real time.
  The owner chose not to name it in the project (see CLAUDE.md, original content only).
- Stock movement settings, read back from the console before recording: ground acceleration
  5.5, friction 5.2, stop speed 80, air acceleration 12, air wish-speed cap 30, max speed 320,
  gravity 800, jump impulse 301.993377, stamina max 80, jump cost .08, landing cost .05,
  stamina recovery 60, no bunny-hop assistance, weapon speed scales acceleration.
  Cheats were on only to run the logger and teleport to the start point.
- A flat, straight lane on a stock map: start origin `-2020 1358 -190`, yaw 0, about 620 u long.
- Melee weapon out (250 u/s) for `logs/melee.txt` and `logs/extra.txt`; the standard rifle
  (215 u/s) for `logs/rifle.txt`.
- Input is played back by the script from fixed tick numbers, so runs are repeatable.

## Repeating it

1. Copy `f2f_measure.nut` into the reference game's VScript folder.
2. Start an offline local server with the remote console port open (`-netconport 2121`) on the
   lane's map, in competitive mode, with no bots and no round time limit.
3. In the console enable cheats, join a team, then run
   `script_execute f2f_measure`, `script F2F_SetHome(-2020.0, 1358.0, -190.0, 0.0)` and
   equip the melee weapon (or the rifle for the rifle runs).
4. Run a test: `script F2F_Test("run")`. Tests: `run walk crouch reverse tap diagonal jump duckjump
   runjump runjumphold airstrafe airturn airback bhop holdjump duck ducktap runduck walkjump drop60`.
   `netcon.py` sends the command and saves the console output
   (`python netcon.py 12 F2F_END out.txt "script F2F_Test(\"run\")"`).

## Log format

`F2F <test> <tick> <time> <x> <y> <z> <vx> <vy> <vz> <eye height above origin> <hull height>`,
one line per server tick, in game units. The sample at tick N is taken before that tick's
scripted key presses are sent.

## Not measured

Ramps, stairs/step-up, wall glancing, landings faster than 300 u/s, standing up in mid-air,
walking off ledges, ladders and water. `drop120`/`drop180` in `logs/extra.txt` started inside
geometry and are not usable.
