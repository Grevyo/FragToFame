class_name MovementSuite
extends TestSuite
## Human movement: the [PlayerMovement] model against the recorded reference curves (stepped at
## the reference's own 64 Hz), then the real [FirstPersonController] in the sandbox at the
## project tick rate. Reference figures are in game units (u); see PlayerMovement for the
## conversion and tools/movement_reference/ for how they were recorded.

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"
const REF_DT: float = 1.0 / 64.0
const FORWARD: Vector2 = Vector2(0, -1)
const BACK: Vector2 = Vector2(0, 1)
const RIGHT: Vector2 = Vector2(1, 0)
## A clear, flat 50 m lane along +X in the sandbox arena.
const LANE_START: Vector3 = Vector3(-24, 0, 22)
const LANE_YAW: float = -PI / 2.0

# Recorded reference speeds (u/s) per 64 Hz tick, melee weapon out (250 u/s).
const REF_ACCEL: Array[float] = [21.48, 36.47, 51.45, 66.44, 81.42, 96.29, 109.95, 122.50,
	134.03, 144.63, 154.36, 163.30, 171.52, 179.07, 186.00, 192.38]
const REF_COAST: Array[float] = [229.69, 211.03, 193.88, 178.13, 163.65, 150.36, 138.14, 126.92,
	116.61, 107.13, 98.43, 90.43, 83.08, 76.33, 69.83, 63.33]
const REF_REVERSE: Array[float] = [208.20, 169.80, 134.52, 102.11, 72.33, 44.34, 16.36, -11.63,
	-26.61, -41.59]
## Speed in the ticks after landing from a standing-height jump with forward held.
const REF_LANDING: Array[float] = [185.06, 189.12, 193.21, 197.36, 201.54, 205.77, 210.05, 214.37,
	218.43, 222.17, 225.60]

var _player: FirstPersonController


func suite_name() -> String:
	return "Movement (human player)"


func run() -> void:
	_test_ground_model()
	_test_stop_model()
	_test_diagonal_model()
	_test_air_model()
	_test_stamina_model()
	await _test_controller()


func _u(units: float) -> float:
	return PlayerMovement.from_units(units)


func _units(metres: float) -> float:
	return PlayerMovement.to_units(metres)


func _near(value: float, target: float, tolerance: float) -> bool:
	return absf(value - target) <= tolerance


## Largest gap (u/s) between a simulated series (m/s) and a recorded one (u/s).
func _worst_gap(simulated: Array[float], reference: Array[float]) -> float:
	var worst := 0.0
	for i: int in reference.size():
		worst = maxf(worst, absf(_units(simulated[i]) - reference[i]))
	return worst


## Steps the model on flat ground along X; returns the signed speed after each tick.
func _ground_series(model: PlayerMovement, start: float, wish: float, ticks: int, limit: float) -> Array[float]:
	var velocity := Vector2(start, 0)
	var series: Array[float] = []
	for i: int in ticks:
		model.recover(REF_DT)
		velocity = model.ground_step(velocity, Vector2(wish, 0), limit, REF_DT)
		series.append(velocity.x)
	return series


func _test_ground_model() -> void:
	section("Ground acceleration (model at the reference 64 Hz)")
	var model := PlayerMovement.new()
	var run := model.run_speed
	check(_near(_units(run), 250.0, 0.01), "run speed is 250 u/s (%.3f m/s)" % run)
	var accel := _ground_series(model, 0.0, 1.0, 40, run)
	check(_worst_gap(accel, REF_ACCEL) < 0.02, "acceleration from rest follows the recorded curve (worst gap %.3f u/s)" % _worst_gap(accel, REF_ACCEL))
	check(_near(_units(accel[31]), 245.85, 0.02), "0.5 s after pressing: %.2f u/s (recorded 245.85)" % _units(accel[31]))
	check(accel[33] < run and is_equal_approx(accel[34], run), "full speed is reached on tick 35 (0.547 s) and never exceeded")
	var walk := _ground_series(model, 0.0, 1.0, 80, model.max_speed(true, 0.0))
	check(_near(_units(walk[15]), 81.25, 0.02) and _near(_units(walk[79]), 130.0, 0.01),
		"walk: %.2f u/s after 0.25 s, tops out at %.1f u/s (recorded 81.25, 130)" % [_units(walk[15]), _units(walk[79])])
	var crouch := _ground_series(model, 0.0, 1.0, 140, model.max_speed(false, 1.0))
	check(_near(_units(crouch[31]), 32.25, 0.02) and _near(_units(crouch[139]), 85.0, 0.01),
		"crouch: %.2f u/s after 0.5 s, tops out at %.1f u/s (recorded 32.25, 85)" % [_units(crouch[31]), _units(crouch[139])])
	var rifle := PlayerMovement.new()
	var rifle_speed := rifle.max_speed(false, 0.0, WeaponCatalog.get_definition(WeaponCatalog.VANTA_RIFLE).mobility)
	check(_near(_units(rifle_speed), 215.0, 0.01), "the rifle's mobility gives a 215 u/s run (recorded 215)")
	var rifle_accel := _ground_series(rifle, 0.0, 1.0, 16, rifle_speed)
	check(_near(_units(rifle_accel[0]), 18.48, 0.02) and _near(_units(rifle_accel[15]), 163.47, 0.02),
		"the same rates reproduce the recorded 215 u/s rifle curve (%.2f u/s at 0.25 s)" % _units(rifle_accel[15]))


func _test_stop_model() -> void:
	section("Stopping: coast versus counter-strafe (model at 64 Hz)")
	var model := PlayerMovement.new()
	var run := model.run_speed
	var coast := _ground_series(model, run, 0.0, 40, run)
	check(_worst_gap(coast, REF_COAST) < 0.02, "releasing the key follows the recorded friction curve (worst gap %.3f u/s)" % _worst_gap(coast, REF_COAST))
	var coast_ticks := coast.find(0.0) + 1
	check(coast_ticks == 26, "coasting from full speed stops in 26 ticks / 0.406 s (got %d)" % coast_ticks)
	var coast_distance := 0.0
	for speed: float in coast:
		coast_distance += speed * REF_DT
	check(_near(_units(coast_distance), 37.10, 0.05), "coast stop distance %.2f u (recorded 37.10)" % _units(coast_distance))

	var reverse := _ground_series(model, run, -1.0, 60, run)
	check(_worst_gap(reverse, REF_REVERSE) < 0.02, "holding the opposite key follows the recorded reversal curve (worst gap %.3f u/s)" % _worst_gap(reverse, REF_REVERSE))
	var cross := 0
	while reverse[cross] > 0.0:
		cross += 1
	check(cross == 7, "counter-strafe passes through zero during tick 8 (0.118 s), 3.4x sooner than coasting")
	check((cross + 1) * 3 < coast_ticks, "counter-strafing stops in under a third of the coast time")
	var full := 0
	while reverse[full] > -run + 0.0001:
		full += 1
	check(full + 1 == 43, "a full A-to-D reversal takes 43 ticks / 0.672 s (got %d)" % (full + 1))

	# Tap: opposite key for 6 ticks, then release (recorded: stopped after 13 ticks, 13.45 u).
	var tap := _ground_series(model, run, -1.0, 6, run)
	tap.append_array(_ground_series(model, tap[5], 0.0, 20, run))
	var tap_distance := 0.0
	for speed: float in tap:
		tap_distance += speed * REF_DT
	check(tap.find(0.0) + 1 == 13 and _near(_units(tap_distance), 13.45, 0.05),
		"a 6-tick counter-strafe tap stops in 13 ticks over %.2f u (recorded 13.45)" % _units(tap_distance))


func _test_diagonal_model() -> void:
	section("Diagonal input")
	var model := PlayerMovement.new()
	var run := model.run_speed
	var diagonal := Vector2(1, 1).normalized()
	var velocity := Vector2.ZERO
	var straight := _ground_series(PlayerMovement.new(), 0.0, 1.0, 64, run)
	var worst := 0.0
	var fastest := 0.0
	for i: int in 64:
		velocity = model.ground_step(velocity, diagonal, run, REF_DT)
		worst = maxf(worst, absf(velocity.length() - straight[i]))
		fastest = maxf(fastest, velocity.length())
	check(worst < 0.0001, "forward + strafe accelerates exactly like a single key")
	check(fastest <= run + 0.0001, "forward + strafe tops out at the run speed (%.1f u/s)" % _units(fastest))
	# Swinging the wish direction while at full speed must not build extra ground speed.
	velocity = Vector2(run, 0)
	for i: int in 128:
		velocity = model.ground_step(velocity, Vector2.from_angle(float(i) * 0.2), run, REF_DT)
		fastest = maxf(fastest, velocity.length())
	check(fastest <= run + 0.0001, "changing direction on the ground never exceeds the run speed")


func _test_air_model() -> void:
	section("Air movement (model at 64 Hz)")
	var model := PlayerMovement.new()
	var run := model.run_speed
	var velocity := Vector2(run, 0)
	for i: int in 47:
		velocity = model.air_step(velocity, Vector2.ZERO, run, REF_DT)
	check(velocity.is_equal_approx(Vector2(run, 0)), "with no input the take-off momentum is kept exactly (no air friction)")
	for i: int in 47:
		velocity = model.air_step(velocity, Vector2(1, 0), run, REF_DT)
	check(velocity.is_equal_approx(Vector2(run, 0)), "holding forward in the air adds no speed")
	velocity = model.air_step(velocity, Vector2(0, 1), run, REF_DT)
	check(_near(_units(velocity.y), 30.0, 0.01) and is_equal_approx(velocity.x, run),
		"a pure air strafe adds 30 u/s sideways in one tick and keeps forward speed (recorded 30.0)")
	for i: int in 40:
		velocity = model.air_step(velocity, Vector2(0, 1), run, REF_DT)
	check(_near(_units(velocity.length()), 251.79, 0.02), "and no more after that: %.2f u/s total (recorded 251.79)" % _units(velocity.length()))
	velocity = model.air_step(Vector2(run, 0), Vector2(-1, 0), run, REF_DT)
	check(_near(_units(velocity.x), 203.125, 0.01), "holding back in the air sheds 46.9 u/s per tick while fresh (recorded 203.1)")
	# Turning with the strafe (reference: 210 deg/s keyboard turn) gains speed.
	velocity = Vector2(run, 0)
	var yaw := 0.0
	for i: int in 16:
		yaw += deg_to_rad(210.0) * REF_DT
		velocity = model.air_step(velocity, Vector2.from_angle(yaw + PI / 2.0), run, REF_DT)
	check(velocity.length() > run * 1.04 and velocity.length() < run * 1.10,
		"a turning air strafe gains speed: %.1f u/s after 0.25 s (recorded 268.3; turn rate assumed)" % _units(velocity.length()))


func _test_stamina_model() -> void:
	section("Jump and landing stamina (model at 64 Hz)")
	var model := PlayerMovement.new()
	check(_near(_units(model.jump_speed()), 295.74, 0.05), "fresh jump leaves the ground at 295.7 u/s effective (%.3f m/s)" % model.jump_speed())
	check(_near(2.0 * model.jump_speed() / model.gravity, 0.7394, 0.001), "standing jump hang time is 0.739 s")
	model.jump()
	check(_near(model.stamina, 23.66, 0.01), "a jump costs 23.66 stamina (recorded 23.66)")
	check(_near(model.speed_scale(), 0.5828, 0.001), "which scales air acceleration to 58% (recorded 0.5828)")
	model.reset()
	# Landing from a standing-height jump, forward held: recorded impact 279.26 u/s.
	var run := model.run_speed
	model.land(_u(279.26))
	var velocity := model.cap_ground_speed(Vector2(run, 0), run)
	var landing: Array[float] = [velocity.x]
	landing.append_array(_ground_series(model, velocity.x, 1.0, 10, run))
	check(_worst_gap(landing, REF_LANDING) < 0.02, "landing cuts speed to 74%% and recovers along the recorded curve (worst gap %.3f u/s)" % _worst_gap(landing, REF_LANDING))
	model.reset()
	model.land(_u(279.26))
	model.recover(2.0 * REF_DT)
	var height := pow(model.jump(), 2.0) / (2.0 * model.gravity)
	check(_near(_units(height), 42.24, 0.2), "jumping again two ticks after landing only reaches %.2f u (recorded 42.24)" % _units(height))


# --- Real controller in the sandbox -------------------------------------------------------


## Puts the player at rest on the test lane (or another spot) and waits for it to settle.
func _reset(feet: Vector3 = LANE_START, yaw: float = LANE_YAW) -> void:
	_player.scripted_move = Vector2.ZERO
	_player.scripted_walk = false
	_player.wants_crouch = false
	_player.frozen = false
	_player.set_spawn(feet, yaw)
	_player.respawn()
	await wait_physics_frames(20)


## Runs exactly [param count] physics ticks with the current scripted input.
func _ticks(count: int) -> void:
	await wait_physics_frames(count)


func _speed() -> float:
	return _player.horizontal_speed()


func _test_controller() -> void:
	section("Controller in the sandbox (project tick rate)")
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(30)
	_player = sandbox.get_node("Player") as FirstPersonController
	_player.input_enabled = false
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var run := _player.movement.run_speed
	print("  INFO  physics tick rate %d Hz" % Engine.physics_ticks_per_second)
	await _test_controller_rifle(dt)
	# Everything below uses the pistol (mobility 1.0), matching the 250 u/s recordings.
	_player.weapons.select_slot(2)

	# Acceleration and top speed.
	await _reset()
	await wait_physics_frames(1)
	var start_x := _player.global_position.x
	_player.scripted_move = FORWARD
	await _ticks(roundi(0.25 / dt))
	var at_quarter := _units(_speed())
	await _ticks(roundi(0.25 / dt))
	var at_half := _units(_speed())
	var half_distance := _units(_player.global_position.x - start_x)
	await _ticks(roundi(0.5 / dt))
	check(_near(at_quarter, 192.38, 6.0), "run: %.1f u/s after 0.25 s (reference 192.4)" % at_quarter)
	check(_near(at_half, 245.85, 3.0), "run: %.1f u/s after 0.5 s (reference 245.9), %.1f u covered (reference 86.5)" % [at_half, half_distance])
	check(is_equal_approx(_speed(), run) and _player.is_on_floor(), "run tops out at exactly %.2f m/s (250 u/s)" % _speed())
	check(is_equal_approx(_player.weapons.motion.speed, ShooterMotion.REFERENCE_SPEED),
		"weapon accuracy still sees a full run as its reference speed (balance preserved)")

	# Coast to a stop.
	var from := _player.global_position
	_player.scripted_move = Vector2.ZERO
	var coast_ticks := 0
	while _speed() > 0.0 and coast_ticks < 120:
		await _ticks(1)
		coast_ticks += 1
	coast_ticks -= 1  # the first awaited frame has not simulated the release yet
	var coast_time := coast_ticks * dt
	var coast_distance := _units(_player.global_position.distance_to(from))
	check(_near(coast_time, 0.406, 0.03), "coast stop takes %.3f s (reference 0.406 s)" % coast_time)
	check(_near(coast_distance, 37.10, 2.0), "coast stop covers %.1f u / %.2f m (reference 37.1 u)" % [coast_distance, _u(coast_distance)])

	# Counter-strafe: opposite key until the body stops, then release.
	_player.scripted_move = FORWARD
	await _ticks(roundi(1.0 / dt))
	from = _player.global_position
	_player.scripted_move = BACK
	var counter_ticks := 0
	while _player.velocity.x > 0.0 and counter_ticks < 60:
		await _ticks(1)
		counter_ticks += 1
	counter_ticks -= 1
	var counter_distance := _units(_player.global_position.x - from.x)
	check(_near(counter_ticks * dt, 0.1185, 0.02), "counter-strafe stops in %.3f s (reference 0.118 s)" % (counter_ticks * dt))
	check(_near(counter_distance, 11.58, 1.5), "counter-strafe covers %.1f u / %.2f m (reference 11.6 u)" % [counter_distance, _u(counter_distance)])
	check(counter_ticks * 3 < coast_ticks, "counter-strafing stops over three times sooner than coasting")
	var reverse_ticks := counter_ticks
	while _player.velocity.x > -run + 0.0001 and reverse_ticks < 120:
		await _ticks(1)
		reverse_ticks += 1
	check(_near(reverse_ticks * dt, 0.672, 0.03), "full reversal to top speed takes %.3f s (reference 0.672 s)" % (reverse_ticks * dt))

	# Diagonal, walk, crouch.
	await _reset()
	_player.scripted_move = Vector2(1, -1)
	await _ticks(roundi(1.0 / dt))
	check(is_equal_approx(_speed(), run), "forward + strafe runs at %.1f u/s, no faster than one key" % _units(_speed()))
	await _reset()
	_player.scripted_move = FORWARD
	_player.scripted_walk = true
	await _ticks(roundi(1.5 / dt))
	check(_near(_units(_speed()), 130.0, 0.1), "Shift-walk speed %.1f u/s (reference 130)" % _units(_speed()))
	_player.scripted_walk = false
	_player.wants_crouch = true
	await _ticks(roundi(2.5 / dt))
	check(_near(_units(_speed()), 85.0, 0.1) and _player.is_crouched(), "crouch speed %.1f u/s (reference 85)" % _units(_speed()))

	await _test_controller_jumps(dt)
	await _test_controller_world(dt)
	await despawn(sandbox)


## Rifle in hand (the spawn weapon): the recorded 215 u/s figures.
func _test_controller_rifle(dt: float) -> void:
	await _reset()
	check(_player.weapons.current().definition.id == WeaponCatalog.VANTA_RIFLE, "player starts with the rifle")
	await wait_physics_frames(1)
	_player.scripted_move = FORWARD
	await _ticks(roundi(0.25 / dt))
	var at_quarter := _units(_speed())
	await _ticks(roundi(0.75 / dt))
	check(_near(at_quarter, 163.47, 5.0), "rifle run: %.1f u/s after 0.25 s (reference 163.5)" % at_quarter)
	check(_near(_units(_speed()), 215.0, 0.01), "rifle run tops out at %.1f u/s (reference 215)" % _units(_speed()))
	check(is_equal_approx(_player.weapons.motion.speed, ShooterMotion.REFERENCE_SPEED),
		"a full rifle run is still the accuracy reference speed (balance preserved)")
	var from := _player.global_position
	_player.scripted_move = Vector2.ZERO
	var coast_ticks := 0
	while _speed() > 0.0 and coast_ticks < 120:
		await _ticks(1)
		coast_ticks += 1
	coast_ticks -= 1
	var distance := _units(_player.global_position.distance_to(from))
	check(_near(coast_ticks * dt, 0.375, 0.03) and _near(distance, 30.91, 2.0),
		"rifle coast stop: %.3f s over %.1f u (reference 0.375 s, 30.9 u)" % [coast_ticks * dt, distance])
	_player.scripted_move = FORWARD
	await _ticks(roundi(1.0 / dt))
	_player.scripted_move = Vector2.ZERO
	_player.scripted_jump = true
	await _ticks(2)
	while not _player.is_on_floor():
		await _ticks(1)
	check(_near(_units(_speed()), 159.15, 5.0), "rifle landing speed %.1f u/s (reference 159.2)" % _units(_speed()))
	_player.weapons.select_slot(3)
	_player.scripted_move = FORWARD
	await _ticks(roundi(1.5 / dt))
	check(_near(_units(_speed()), 250.0, 0.01), "switching to the SMG raises the run to %.1f u/s" % _units(_speed()))


func _test_controller_jumps(dt: float) -> void:
	section("Controller jumps (project tick rate)")
	var run := _player.movement.run_speed
	# Standing jump.
	await _reset()
	var floor_y := _player.global_position.y
	_player.scripted_jump = true
	var peak := 0.0
	var air_ticks := 0
	await _ticks(2)
	while not _player.is_on_floor() and air_ticks < 200:
		peak = maxf(peak, _player.global_position.y - floor_y)
		air_ticks += 1
		await _ticks(1)
	var hang := (air_ticks + 1) * dt
	check(_near(_units(peak), 54.65, 1.0), "standing jump peaks at %.2f u / %.3f m (reference 54.65 u)" % [_units(peak), peak])
	check(_near(hang, 0.739, 0.03), "standing jump hang time %.3f s (reference 0.739 s, 0.750 s as whole 64 Hz ticks)" % hang)

	# Running jump with everything released: momentum kept, then the landing slowdown.
	await _reset()
	_player.scripted_move = FORWARD
	await _ticks(roundi(1.0 / dt))
	_player.scripted_move = Vector2.ZERO
	_player.scripted_jump = true
	await _ticks(2)
	var slowest_air := run
	while not _player.is_on_floor():
		slowest_air = minf(slowest_air, _speed())
		await _ticks(1)
	check(is_equal_approx(slowest_air, run), "a running jump keeps its full take-off speed in the air with no input")
	check(_near(_units(_speed()), 185.06, 6.0), "landing cuts speed to %.1f u/s (reference 185.1 = 74%%)" % _units(_speed()))

	# Chained jump right after landing is lower and no faster.
	_player.scripted_move = FORWARD
	floor_y = _player.global_position.y
	_player.scripted_jump = true
	peak = 0.0
	await _ticks(2)
	while not _player.is_on_floor():
		peak = maxf(peak, _player.global_position.y - floor_y)
		await _ticks(1)
	check(_near(_units(peak), 42.24, 3.0), "an immediate second jump only reaches %.1f u (reference 42.2 u)" % _units(peak))
	check(_units(_speed()) < 190.0, "and chained jumps do not regain speed (%.1f u/s; reference 185)" % _units(_speed()))

	# Air strafe without turning.
	await _reset()
	_player.scripted_move = FORWARD
	await _ticks(roundi(1.0 / dt))
	_player.scripted_move = RIGHT
	_player.scripted_jump = true
	await _ticks(10)
	var sideways := absf(_player.velocity.z)
	check(_near(_units(sideways), 30.0, 0.1) and is_equal_approx(_player.velocity.x, run),
		"air strafe adds %.1f u/s sideways and keeps forward speed (reference 30)" % _units(sideways))

	# Crouch-jump: tucking the legs lifts the feet.
	await _reset()
	floor_y = _player.global_position.y
	_player.scripted_jump = true
	await _ticks(3)
	_player.wants_crouch = true
	peak = 0.0
	while not _player.is_on_floor():
		peak = maxf(peak, _player.global_position.y - floor_y)
		await _ticks(1)
	check(_near(_units(peak), 66.0, 2.0), "crouch-jump lifts the feet to %.1f u / %.2f m (reference 66.0 u)" % [_units(peak), peak])
	check(_player.is_crouched() and is_equal_approx(_player.current_height(), FirstPersonController.CROUCH_HEIGHT),
		"landing from a crouch-jump stays crouched with the collider in sync")


func _test_controller_world(dt: float) -> void:
	section("Controller against the level (project tick rate)")
	var run := _player.movement.run_speed
	# Freeze time.
	await _reset()
	_player.frozen = true
	_player.scripted_move = FORWARD
	_player.scripted_jump = true
	var held := _player.global_position
	await _ticks(20)
	check(_player.global_position.is_equal_approx(held), "a frozen player cannot move or jump")
	_player.frozen = false

	# Up the ramp (rises toward -Z between z = 9 and z = -1) and back down.
	await _reset(Vector3(14, 0, 13), 0.0)
	_player.scripted_move = FORWARD
	var airborne := 0
	var ramp_speed := 0.0
	for i: int in roundi(2.6 / dt):
		await _ticks(1)
		if i > 20 and not _player.is_on_floor():
			airborne += 1
		if _player.global_position.y > 1.0 and _player.global_position.y < 2.0:
			ramp_speed = _speed()
	check(_player.global_position.y > 2.9, "runs up the ramp onto the platform (y = %.2f)" % _player.global_position.y)
	check(airborne == 0, "stays grounded up the ramp and over its top edge (%d airborne ticks)" % airborne)
	print("  INFO  horizontal speed going up the 16.7 degree ramp: %.1f u/s (not compared with the reference)" % _units(ramp_speed))
	await _reset(Vector3(14, 3, -3), PI)
	_player.scripted_move = FORWARD
	airborne = 0
	for i: int in roundi(2.2 / dt):
		await _ticks(1)
		if not _player.is_on_floor():
			airborne += 1
	check(_player.global_position.y < 0.2 and airborne == 0, "runs down the ramp without leaving the ground (%d airborne ticks)" % airborne)

	# Up the stairs (hidden slope rising toward -X from x = 24 to x = 19).
	await _reset(Vector3(27, 0, -5), PI / 2.0)
	_player.scripted_move = FORWARD
	airborne = 0
	for i: int in roundi(2.2 / dt):
		await _ticks(1)
		if i > 20 and not _player.is_on_floor():
			airborne += 1
	check(_player.global_position.y > 2.9 and airborne == 0, "runs up the stairs onto the platform (y = %.2f, %d airborne ticks)" % [_player.global_position.y, airborne])

	# Glancing a wall at 45 degrees keeps sliding along it.
	await _reset(Vector3(-20, 0, 24), -PI * 0.75)
	_player.scripted_move = FORWARD
	await _ticks(roundi(2.5 / dt))
	var along := _player.velocity.x
	check(along > run * 0.5 and absf(_player.velocity.z) < 0.05, "glancing a wall at 45 degrees slides along it at %.1f u/s (not compared with the reference)" % _units(along))

	# Stand-up clearance while moving, and respawn clears movement state.
	await _reset()
	_player.wants_crouch = true
	await _ticks(20)
	var eye := _player.head.position.y
	check(is_equal_approx(eye, FirstPersonController.CROUCH_EYE), "crouched eye height %.2f m with the camera on the head" % eye)
	_player.wants_crouch = false
	await _ticks(roundi(_player.movement.stand_time / dt) + 2)
	check(not _player.is_crouched() and is_equal_approx(_player.head.position.y, FirstPersonController.STAND_EYE), "stands back up in %.3f s" % _player.movement.stand_time)
	_player.scripted_move = FORWARD
	_player.scripted_jump = true
	await _ticks(30)
	_player.respawn()
	check(_player.velocity == Vector3.ZERO and _player.movement.stamina == 0.0 and _player.crouch_amount == 0.0,
		"respawn clears velocity, stamina and stance")
	_player.scripted_move = Vector2.ZERO
