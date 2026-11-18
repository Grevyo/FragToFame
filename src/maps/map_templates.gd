class_name MapTemplates
extends RefCounted
## Starting documents for the editor. These are ordinary MapDocuments built only from catalog
## pieces, so anything here can be reproduced (and edited) in the Creation Studio.

const SANDBOX_ARENA_ID: String = "map_dev_sandbox_arena"
const TRAINING_RANGE_ID: String = "map_f2f_training_range"
const TRAINING_COURSE_ID: String = "map_f2f_training_course"


static func blank() -> MapDocument:
	var doc := MapDocument.create("Untitled map")
	doc.add_piece(MapDocument.make_piece("floor", Vector3(0, -0.2, 0), 0, Vector3(16, 0.2, 16)))
	doc.add_piece(MapDocument.make_piece("spawn_attack", Vector3(0, 0, 4)))
	return doc


## The FPS Sandbox test arena (development map): floor, walls, cover, ramp, stairs, platform.
static func sandbox_arena() -> MapDocument:
	var doc := MapDocument.create("Sandbox Arena (dev)")
	doc.map_id = SANDBOX_ARENA_ID
	doc.author = "F2F development"
	doc.description = "Movement and shooting test arena used by the FPS Sandbox."
	var s := 30.0
	var h := 4.0
	_add(doc, "floor", Vector3(0, -1, 0), 0, Vector3(s * 2, 1, s * 2))
	_add(doc, "wall", Vector3(0, 0, -s), 0, Vector3(s * 2, h, 1))
	_add(doc, "wall", Vector3(0, 0, s), 0, Vector3(s * 2, h, 1))
	_add(doc, "wall", Vector3(-s, 0, 0), 90, Vector3(s * 2, h, 1))
	_add(doc, "wall", Vector3(s, 0, 0), 90, Vector3(s * 2, h, 1))

	_add(doc, "crate", Vector3(-4, 0, 2))
	_add(doc, "crate", Vector3(-2.8, 0, 2))
	_add(doc, "crate", Vector3(-3.4, 1.2, 2))
	_add(doc, "crate_large", Vector3(5, 0, -2))
	_add(doc, "low_cover", Vector3(0, 0, -6), 0, Vector3(6, 1.1, 0.4))
	_add(doc, "wall", Vector3(-10, 0, -4), 90, Vector3(8, 3, 0.6))

	# Raised platform (top at y = 3) reached by a ramp from the south and stairs from the east.
	_add(doc, "block", Vector3(14, 0, -5), 0, Vector3(10, 3, 8))
	_add(doc, "ramp", Vector3(14, 0, 4), 0, Vector3(4, 3, 10))
	_add(doc, "stairs", Vector3(21.5, 0, -5), 90, Vector3(3, 3, 5))

	for x: float in [-18.0, -12.0, -6.0]:
		_add(doc, "pillar", Vector3(x, 0, 14), 0, Vector3(0.8, 3.2, 0.8))

	# Five spawns per team (competitive requirement).
	for x: float in [0.0, -1.5, 1.5, -3.0, 3.0]:
		_add(doc, "spawn_attack", Vector3(x, 0, 12))
		_add(doc, "spawn_defence", Vector3(x, 0, -20), 180)
	_add(doc, "bombsite", Vector3(14, 3, -5), 0, Vector3(8, 3, 6), {"site": "A"})
	_add(doc, "bombsite", Vector3(-18, 0, -18), 0, Vector3(8, 3, 8), {"site": "B"})
	_add(doc, "callout", Vector3(0, 0, 0), 0, Vector3(10, 3, 10), {"name": "Mid"})
	_add(doc, "buy_zone", Vector3(0, 0, 14), 0, Vector3(14, 3, 10), {"team": "attack"})
	_add(doc, "buy_zone", Vector3(0, 0, -22), 0, Vector3(14, 3, 10), {"team": "defence"})

	# Training targets facing the attacker spawn: close, far (half behind low cover), strafing.
	_add(doc, "target_dummy", Vector3(-6, 0, 4), 180)
	_add(doc, "target_dummy", Vector3(4, 0, -14), 180)
	_add(doc, "target_dummy", Vector3(-15, 0, -2), 180, Vector3.ZERO, {"motion": "strafe"})
	_add(doc, "target_dummy", Vector3(14, 3, -7), 180)
	return doc


## The training ground's shooting range: static targets at many distances and heights, two on
## raised blocks, and a strafing target for the tracking lane. All facing the spawn.
static func training_range() -> MapDocument:
	var doc := MapDocument.create("Training Range")
	doc.map_id = TRAINING_RANGE_ID
	doc.author = "F2F"
	doc.description = "Flick, reaction and tracking drills. Move or add target dummies in the Creation Studio."
	var w := 20.0
	var d := 30.0
	_add(doc, "floor", Vector3(0, -1, 0), 0, Vector3(w * 2, 1, d * 2))
	_add(doc, "wall", Vector3(0, 0, -d), 0, Vector3(w * 2, 5, 1))
	_add(doc, "wall", Vector3(0, 0, d), 0, Vector3(w * 2, 5, 1))
	_add(doc, "wall", Vector3(-w, 0, 0), 90, Vector3(d * 2, 5, 1))
	_add(doc, "wall", Vector3(w, 0, 0), 90, Vector3(d * 2, 5, 1))
	_add(doc, "low_cover", Vector3(0, 0, 12), 0, Vector3(8, 1.1, 0.4))
	for x: float in [-1.5, 0.0, 1.5]:
		_add(doc, "spawn_attack", Vector3(x, 0, 18))
	_add(doc, "block", Vector3(-8, 0, -12), 0, Vector3(3, 1.5, 3))
	_add(doc, "block", Vector3(8, 0, -14), 0, Vector3(3, 2.5, 3))
	_add(doc, "crate", Vector3(-3, 0, -14))
	_add(doc, "crate_large", Vector3(13, 0, -4))
	var targets: Array[Vector3] = [Vector3(-10, 0, -4), Vector3(-5, 0, -8), Vector3(0, 0, -6), Vector3(6, 0, -5),
		Vector3(11, 0, -9), Vector3(-13, 0, -16), Vector3(-4, 0, -20), Vector3(4, 0, -18), Vector3(12, 0, -22),
		Vector3(0, 0, -27), Vector3(-8, 1.5, -12), Vector3(8, 2.5, -14)]
	for spot: Vector3 in targets:
		_add(doc, "target_dummy", spot, 180)
	_add(doc, "target_dummy", Vector3(0, 0, -12), 180, Vector3.ZERO, {"motion": "strafe"})
	return doc


## The training ground's movement course: platforms over a pit, with gaps, steps up, a narrow
## beam and three checkpoints. Every jump is a plain running jump (no tricks needed).
static func training_course() -> MapDocument:
	var doc := MapDocument.create("Movement Course")
	doc.map_id = TRAINING_COURSE_ID
	doc.author = "F2F"
	doc.description = "Run and jump from START through each CHECKPOINT to FINISH. Edit it in the Creation Studio."
	_add(doc, "floor", Vector3(0, -7, -20), 0, Vector3(60, 1, 80))
	_add(doc, "wall", Vector3(0, -6, -60), 0, Vector3(60, 14, 1))
	_add(doc, "wall", Vector3(0, -6, 20), 0, Vector3(60, 14, 1))
	_add(doc, "wall", Vector3(-30, -6, -20), 90, Vector3(80, 14, 1))
	_add(doc, "wall", Vector3(30, -6, -20), 90, Vector3(80, 14, 1))
	# [centre x, centre z, top height, width x, depth z]
	var platforms: Array[Array] = [[0.0, 0.0, 0.0, 6.0, 6.0], [0.0, -7.0, 0.0, 4.0, 3.0], [0.0, -12.5, 0.8, 4.0, 3.0],
		[0.0, -18.0, 1.6, 4.0, 4.0], [6.0, -18.0, 1.6, 3.0, 3.0], [11.5, -18.0, 2.4, 3.0, 3.0], [11.5, -23.5, 2.4, 3.0, 3.0],
		[11.5, -30.5, 2.4, 1.2, 8.0], [11.5, -38.0, 3.2, 4.0, 4.0], [5.5, -38.0, 3.2, 3.0, 3.0], [0.0, -38.0, 4.0, 3.0, 3.0],
		[-6.5, -38.0, 4.0, 5.0, 5.0]]
	for p: Array in platforms:
		var top := float(p[2])
		_add(doc, "block", Vector3(float(p[0]), -6.0, float(p[1])), 0, Vector3(float(p[3]), top + 6.0, float(p[4])))
	_add(doc, "spawn_attack", Vector3(0, 0, 1.5))
	_add(doc, "course_start", Vector3(0, 0, 0), 0, Vector3(6, 3, 6))
	_add(doc, "course_checkpoint", Vector3(0, 1.6, -18), 0, Vector3(4, 3, 4), {"order": 1})
	_add(doc, "course_checkpoint", Vector3(11.5, 2.4, -23.5), 0, Vector3(3, 3, 3), {"order": 2})
	_add(doc, "course_checkpoint", Vector3(11.5, 3.2, -38), 0, Vector3(4, 3, 4), {"order": 3})
	_add(doc, "course_finish", Vector3(-6.5, 4.0, -38), 0, Vector3(5, 3, 5), {"par": 30.0})
	return doc


static func _add(doc: MapDocument, type: String, position: Vector3, rotation_y: int = 0,
		size: Vector3 = Vector3.ZERO, props: Dictionary = {}) -> void:
	var piece := MapDocument.make_piece(type, position, rotation_y, size)
	if not props.is_empty():
		(piece["props"] as Dictionary).merge(props, true)
	doc.add_piece(piece)
