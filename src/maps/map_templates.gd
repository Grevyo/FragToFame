class_name MapTemplates
extends RefCounted
## Starting documents for the editor. These are ordinary MapDocuments built only from catalog
## pieces, so anything here can be reproduced (and edited) in the Creation Studio.


static func blank() -> MapDocument:
	var doc := MapDocument.create("Untitled map")
	doc.add_piece(MapDocument.make_piece("floor", Vector3(0, -0.2, 0), 0, Vector3(16, 0.2, 16)))
	doc.add_piece(MapDocument.make_piece("spawn_attack", Vector3(0, 0, 4)))
	return doc


## The FPS Sandbox test arena (development map): floor, walls, cover, ramp, stairs, platform.
static func sandbox_arena() -> MapDocument:
	var doc := MapDocument.create("Sandbox Arena (dev)")
	doc.map_id = "map_dev_sandbox_arena"
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

	_add(doc, "spawn_attack", Vector3(0, 0, 12))
	_add(doc, "spawn_defence", Vector3(0, 0, -20), 180)
	_add(doc, "bombsite", Vector3(14, 3, -5), 0, Vector3(8, 3, 6), {"site": "A"})
	_add(doc, "bombsite", Vector3(-18, 0, -18), 0, Vector3(8, 3, 8), {"site": "B"})
	_add(doc, "callout", Vector3(0, 0, 0), 0, Vector3(10, 3, 10), {"name": "Mid"})
	_add(doc, "buy_zone", Vector3(0, 0, 22), 0, Vector3(12, 3, 10), {"team": "attack"})

	# Training targets facing the attacker spawn: close, far (half behind low cover), strafing.
	_add(doc, "target_dummy", Vector3(-6, 0, 4), 180)
	_add(doc, "target_dummy", Vector3(4, 0, -14), 180)
	_add(doc, "target_dummy", Vector3(-15, 0, -2), 180, Vector3.ZERO, {"motion": "strafe"})
	_add(doc, "target_dummy", Vector3(14, 3, -7), 180)
	return doc


static func _add(doc: MapDocument, type: String, position: Vector3, rotation_y: int = 0,
		size: Vector3 = Vector3.ZERO, props: Dictionary = {}) -> void:
	var piece := MapDocument.make_piece(type, position, rotation_y, size)
	if not props.is_empty():
		(piece["props"] as Dictionary).merge(props, true)
	doc.add_piece(piece)
