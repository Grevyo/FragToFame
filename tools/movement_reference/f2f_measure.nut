// Frag to Fame movement reference logger (original script, measurement only).
// Logs the local player's origin / velocity / eye height / hull height once per server tick
// and plays back scripted key presses so every run is repeatable.
//
// Console (offline listen server, sv_cheats 1):
//   script_execute f2f_measure
//   script F2F_Home()            -- remember the current spot + yaw 0 as the test origin
//   script F2F_Test("run")       -- run one named test; lines starting "F2F " are the samples

::F2F <- { p = null, n = 0, steps = [], label = "idle", running = false, last = 0,
	home = Vector(0, 0, 0), yaw = 0.0, yawoff = 0.0, adv = 0.0 }

::F2F_Find <- function() {
	::F2F.p = Entities.FindByClassname(null, "player")
	return ::F2F.p
}

::F2F_Home <- function() {
	local p = ::F2F_Find()
	local o = p.GetOrigin()
	::F2F.home = Vector(o.x, o.y, o.z)
	printl(format("F2F_HOME %.3f %.3f %.3f", o.x, o.y, o.z))
}

::F2F_SetHome <- function(x, y, z, yaw) {
	::F2F.home = Vector(x, y, z)
	::F2F.yaw = yaw
}

::F2F_Tick <- function() {
	local f = ::F2F
	if (!f.running) return
	local p = f.p
	local o = p.GetOrigin()
	local v = p.GetVelocity()
	local e = p.EyePosition()
	local m = p.GetBoundingMaxs()
	printl(format("F2F %s %d %.5f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.1f", f.label, f.n, Time(),
		o.x, o.y, o.z, v.x, v.y, v.z, e.z - o.z, m.z))
	while (f.steps.len() > 0 && f.steps[0][0] <= f.n) {
		local cmd = f.steps[0][1]
		if (cmd == "@home") {
			local r = f.yaw * PI / 180.0
			p.SetOrigin(Vector(f.home.x + cos(r) * f.adv, f.home.y + sin(r) * f.adv, f.home.z))
			p.SetVelocity(Vector(0, 0, 0))
			SendToConsole("setang 0 " + (f.yaw + f.yawoff) + " 0")
		} else if (cmd.slice(0, 1) == "@") {
			// "@drop<height>": start in the air above the lane already moving at 250 u/s
			local lift = cmd.slice(5).tofloat()
			p.SetOrigin(Vector(f.home.x + 40, f.home.y, f.home.z + lift))
			p.SetVelocity(Vector(250, 0, 0))
		} else {
			SendToConsole(cmd)
		}
		f.steps.remove(0)
	}
	f.n++
	if (f.n > f.last) {
		f.running = false
		SendToConsole("-forward;-back;-moveleft;-moveright;-jump;-duck;-speed;-right;-left")
		printl("F2F_END " + f.label)
		return
	}
	EntFireByHandle(p, "RunScriptCode", "::F2F_Tick()", 0.01, null, null)
}

// steps: array of [tick, "console command"]; "@home" teleports to the test origin at rest.
::F2F_Run <- function(label, steps, last) {
	local f = ::F2F
	::F2F_Find()
	f.label = label
	f.steps = steps
	f.last = last
	f.n = 0
	f.running = true
	printl("F2F_BEGIN " + label + " tick_interval " + FrameTime())
	::F2F_Tick()
}

// Alternating +jump/-jump every tick between two ticks (scroll-wheel style jump spam).
::F2F_JumpSpam <- function(steps, from, to) {
	for (local t = from; t < to; t += 2) {
		steps.push([t, "+jump"])
		steps.push([t + 1, "-jump"])
	}
	steps.sort(function(a, b) { return a[0] - b[0] })
	return steps
}

::F2F_Test <- function(name) {
	local s = [[0, "@home"]]
	local last = 300
	local f = ::F2F
	f.yawoff = 0.0
	f.adv = 0.0
	if (name == "run") {
		s.extend([[40, "+forward"], [152, "-forward"]]); last = 240
	} else if (name == "walk") {
		s.extend([[30, "+speed"], [40, "+forward"], [168, "-forward"], [250, "-speed"]]); last = 260
	} else if (name == "crouch") {
		s.extend([[40, "+duck"], [104, "+forward"], [232, "-forward"], [300, "-duck"]]); last = 380
	} else if (name == "reverse") {
		// strafe left along the lane, then swap to right in one command
		f.yawoff = -90.0; f.adv = 120.0
		s.extend([[40, "+moveleft"], [136, "-moveleft;+moveright"], [232, "-moveright"]]); last = 320
	} else if (name == "tap") {
		// counter-strafe: opposite key held for 6 ticks after release
		f.yawoff = -90.0; f.adv = 120.0
		s.extend([[40, "+moveleft"], [136, "-moveleft;+moveright"], [142, "-moveright"]]); last = 220
	} else if (name == "diagonal") {
		f.yawoff = 45.0
		s.extend([[40, "+forward;+moveright"], [152, "-forward;-moveright"]]); last = 240
	} else if (name == "jump") {
		s.extend([[40, "+jump"], [42, "-jump"]]); last = 140
	} else if (name == "duckjump") {
		s.extend([[40, "+jump;+duck"], [42, "-jump"], [120, "-duck"]]); last = 200
	} else if (name == "runjump") {
		// run, jump and release everything: momentum with no air input, then landing + coast
		s.extend([[40, "+forward"], [120, "+jump;-forward"], [122, "-jump"]]); last = 260
	} else if (name == "runjumphold") {
		s.extend([[40, "+forward"], [120, "+jump"], [122, "-jump"], [185, "-forward"]]); last = 260
	} else if (name == "airstrafe") {
		// run, jump, release forward, hold strafe-right with no turn
		s.extend([[40, "+forward"], [120, "+jump;-forward;+moveright"], [122, "-jump"], [185, "-moveright"]]); last = 260
	} else if (name == "airturn") {
		// as above but turning left with the keyboard (cl_yawspeed) while strafing left
		s.extend([[40, "+forward"], [120, "+jump;-forward;+moveleft;+left"], [122, "-jump"],
			[185, "-moveleft;-left"]]); last = 260
	} else if (name == "airback") {
		s.extend([[40, "+forward"], [120, "+jump;-forward;+back"], [122, "-jump"], [185, "-back"]]); last = 260
	} else if (name == "bhop") {
		// run, jump, then spam jump through the landings (stock repeated-jump behaviour)
		s.extend([[40, "+forward"], [88, "+jump"], [89, "-jump"]])
		s = ::F2F_JumpSpam(s, 100, 190)
		s.push([192, "-forward"]); last = 280
	} else if (name == "holdjump") {
		s.extend([[40, "+forward"], [88, "+jump"], [190, "-jump;-forward"]]); last = 280
	} else if (name.slice(0, 4) == "drop") {
		s.extend([[40, "+forward"], [41, "@" + name], [150, "-forward"]]); last = 200
	} else if (name == "walkjump") {
		s.extend([[30, "+speed"], [40, "+forward"], [150, "+jump"], [152, "-jump"], [240, "-forward;-speed"]]); last = 280
	} else if (name == "runduck") {
		s.extend([[40, "+forward"], [90, "+duck"], [150, "-duck"], [200, "-forward"]]); last = 240
	} else if (name == "duck") {
		s.extend([[40, "+duck"], [136, "-duck"]]); last = 230
	} else if (name == "ducktap") {
		s.extend([[40, "+duck"], [136, "-duck"], [150, "+duck"], [246, "-duck"], [256, "+duck"], [330, "-duck"]]); last = 420
	}
	::F2F_Run(name, s, last)
}

// Reports how far the floor stays flat and unobstructed in each direction from the player.
::F2F_Probe <- function() {
	local p = ::F2F_Find()
	local o = p.GetOrigin()
	printl(format("F2F_PROBE_AT %.2f %.2f %.2f", o.x, o.y, o.z))
	local base = TraceLine(Vector(o.x, o.y, o.z + 40), Vector(o.x, o.y, o.z - 8), p)
	for (local yaw = 0; yaw < 360; yaw += 15) {
		local dx = cos(yaw * PI / 180.0)
		local dy = sin(yaw * PI / 180.0)
		local d = 16
		for (; d <= 2400; d += 16) {
			local ok = true
			for (local side = -20; side <= 20 && ok; side += 20) {
				local ax = o.x + dx * d - dy * side
				local ay = o.y + dy * d + dx * side
				local fr = TraceLine(Vector(ax, ay, o.z + 40), Vector(ax, ay, o.z - 8), p)
				if (fabs(fr - base) > 0.004) ok = false
				foreach (h in [18, 40, 70]) {
					if (TraceLine(Vector(o.x - dy * side, o.y + dx * side, o.z + h),
							Vector(ax, ay, o.z + h), p) < 1.0) ok = false
				}
			}
			if (!ok) break
		}
		printl("F2F_PROBE " + yaw + " " + (d - 16))
	}
}

::F2F_Cvars <- function() {
	foreach (c in ["sv_accelerate", "sv_friction", "sv_stopspeed", "sv_airaccelerate", "sv_maxspeed",
			"sv_gravity", "sv_jump_impulse", "sv_staminamax", "sv_staminajumpcost", "sv_staminalandcost",
			"sv_staminarecoveryrate", "sv_enablebunnyhopping", "sv_autobunnyhopping", "sv_maxvelocity",
			"sv_wateraccelerate", "sv_accelerate_use_weapon_speed", "sv_air_max_wishspeed",
			"sv_ladder_scale_speed", "sv_timebetweenducks", "game_type", "game_mode"]) {
		printl("F2F_CVAR " + c + " " + Convars.GetStr(c))
	}
}

printl("F2F measure script loaded")

::F2F_Dbg <- function() {
	local p = ::F2F_Find()
	local o = p.GetOrigin()
	printl("DBG o " + o.x + " " + o.y + " " + o.z + " vz " + p.GetVelocity().z)
	printl("DBG down " + TraceLine(Vector(o.x, o.y, o.z + 40), Vector(o.x, o.y, o.z - 8), p))
	printl("DBG down_null " + TraceLine(Vector(o.x, o.y, o.z + 40), Vector(o.x, o.y, o.z - 8), null))
	printl("DBG down64 " + TraceLine(Vector(o.x + 64, o.y, o.z + 40), Vector(o.x + 64, o.y, o.z - 8), p))
	printl("DBG fwd " + TraceLine(Vector(o.x, o.y, o.z + 40), Vector(o.x + 500, o.y, o.z + 40), p))
	printl("DBG long_down " + TraceLine(Vector(o.x, o.y, o.z + 40), Vector(o.x, o.y, o.z - 400), p))
}

// Floor height under a point (trace 120 units down from z), or null-ish -99999 if none.
::F2F_Floor <- function(x, y, z, p) {
	local fr = TraceLine(Vector(x, y, z), Vector(x, y, z - 120), p)
	if (fr >= 1.0) return -99999.0
	return z - 120.0 * fr
}

// Longest flat, clear lane starting at (x, y) on floor height fz; returns [distance, yaw].
::F2F_Lane <- function(x, y, fz, p) {
	local best = [0, 0]
	for (local yaw = 0; yaw < 360; yaw += 15) {
		local dx = cos(yaw * PI / 180.0)
		local dy = sin(yaw * PI / 180.0)
		local d = 16
		for (; d <= 1400; d += 16) {
			local ok = true
			for (local side = -24; side <= 24 && ok; side += 24) {
				local ax = x + dx * d - dy * side
				local ay = y + dy * d + dx * side
				if (fabs(::F2F_Floor(ax, ay, fz + 40, p) - fz) > 0.1) ok = false
				foreach (h in [18, 40, 90]) {
					if (TraceLine(Vector(x - dy * side, y + dx * side, fz + h), Vector(ax, ay, fz + h), p) < 1.0) ok = false
				}
			}
			if (!ok) break
		}
		if (d - 16 > best[0]) best = [d - 16, yaw]
	}
	return best
}

::F2F_Scan <- function() {
	local p = ::F2F_Find()
	foreach (cls in ["info_deathmatch_spawn", "info_player_terrorist", "info_player_counterterrorist"]) {
		local e = null
		while ((e = Entities.FindByClassname(e, cls)) != null) {
			local o = e.GetOrigin()
			local fz = ::F2F_Floor(o.x, o.y, o.z + 40, p)
			local b = ::F2F_Lane(o.x, o.y, fz, p)
			if (b[0] >= 500) printl(format("F2F_LANE %d yaw %d at %.1f %.1f %.2f", b[0], b[1], o.x, o.y, fz))
		}
	}
	printl("F2F_SCAN_DONE")
}
