class_name InspectLibrary
extends RefCounted
## Weapon inspections as data: each is a short choreography of poses the viewmodel moves
## through when the player presses Inspect. Presentation only.
##
## A pose key is {"t": 0..1 share of the inspection, "pos": metres added to the viewmodel,
## "rot": degrees (x pitch, y yaw, z roll) added to it}. Keys may also turn the item about a
## point other than its centre: "pivot" is that point as a share of the item's size in weapon
## space (z -0.5 = muzzle / blade tip … 0.5 = butt / pommel). Keys may also swing a model's moving
## parts: "parts" maps a part name (WeaponModels.parts) to degrees from rest; a part a key does not
## name is at rest there. Keys may also move the firing hand's fingers: "fingers" maps a finger
## ("Index", "Middle", "Ring", "Little", "Thumb") to how closed it is as a share of its usual grip (1 holds
## as usual, 0 open, a little over 1 clenched); a finger a key does not name holds as usual there.
## Between keys poses ease in and out. Every inspection starts and ends at
## rest (t 0 and t 1 have no offset; whole turns count as rest).
##
## Euler angles apply roll first, then pitch, then yaw, so a roll ("rot" z) spins an item about its
## own length and a pitch about its own side-to-side axis before the yaw turns it.
##
## A knife's "rot" turns it in the fist's own axes instead (see WeaponModels.knife_hold): x
## twists the forearm, y bends the wrist toward the thumb or little finger (the plane of a
## hammer-held blade), z bends it up or down. So a knife turns the way a hand can turn it, and a
## spin past what the wrist allows carries on in the fingers.
##
## Entries are keyed by the model in hand: utility by its item ID, knives by their knife look
## (WeaponModels.KNIVES), so every knife has its own. Guns use [constant DEFAULT] (rifles) or
## [constant PISTOL] (show the left side, then the right).
##
## Optional entry fields shape how the player's hands take part: "grip_pivot" true turns the
## item about the firing hand's grip (a wrist turn), "support" false lets the support hand go for
## the inspection, and "toss" (Vector2 start, end share) is when the item is in the air, out of
## the hand.

const DEFAULT_SECONDS: float = 3.2

## Rifles: lifted, then rolled and turned to show each side, both hands staying on.
const DEFAULT: Dictionary = {
	"seconds": DEFAULT_SECONDS,
	"grip_pivot": true,
	"keys": [
		{"t": 0.0},
		{"t": 0.15, "pos": Vector3(-0.05, 0.05, -0.04), "rot": Vector3(6, 0, 0)},
		{"t": 0.35, "pos": Vector3(-0.05, 0.06, 0.03), "rot": Vector3(5, 55, 10)},
		{"t": 0.5, "pos": Vector3(-0.05, 0.05, -0.04), "rot": Vector3(6, 0, 0)},
		{"t": 0.7, "pos": Vector3(-0.04, 0.07, 0.01), "rot": Vector3(8, 50, -115)},
		{"t": 0.85, "pos": Vector3(-0.05, 0.05, -0.04), "rot": Vector3(6, 0, 0)},
		{"t": 1.0},
	],
}

## Pistols: the support hand lets go and the firing hand turns the pistol over to show each side.
const PISTOL: Dictionary = {
	"seconds": 2.8,
	"grip_pivot": true,
	"support": false,
	"keys": [
		{"t": 0.0},
		{"t": 0.15, "pos": Vector3(-0.06, 0.06, -0.02), "rot": Vector3(10, 0, 0)},
		{"t": 0.35, "pos": Vector3(-0.06, 0.06, 0.0), "rot": Vector3(5, 70, 10)},
		{"t": 0.5, "pos": Vector3(-0.06, 0.06, -0.02), "rot": Vector3(10, 0, 0)},
		{"t": 0.7, "pos": Vector3(-0.06, 0.06, 0.0), "rot": Vector3(5, 60, 105)},
		{"t": 0.85, "pos": Vector3(-0.06, 0.06, -0.02), "rot": Vector3(10, 0, 0)},
		{"t": 1.0},
	],
}

const INSPECTS: Dictionary[StringName, Dictionary] = {
	# Frag: tossed up, a full flip, caught, then rolled between the fingers.
	EquipmentCatalog.FRAG: {
		"seconds": 2.8,
		"toss": Vector2(0.13, 0.46),
		"keys": [
			{"t": 0.0},
			{"t": 0.12, "pos": Vector3(-0.08, 0.02, -0.08), "rot": Vector3(-10, 0, 0)},
			{"t": 0.3, "pos": Vector3(-0.08, 0.2, -0.1), "rot": Vector3(-190, 20, 0)},
			{"t": 0.46, "pos": Vector3(-0.08, 0.03, -0.08), "rot": Vector3(-360, 30, 0)},
			{"t": 0.7, "pos": Vector3(-0.1, 0.05, -0.1), "rot": Vector3(-360, 160, 15)},
			{"t": 0.86, "pos": Vector3(-0.08, 0.03, -0.08), "rot": Vector3(-360, 360, 0)},
			{"t": 1.0, "rot": Vector3(-360, 360, 0)},
		],
	},
	# Flashbang: turned round to read the side, held up to the light, back.
	EquipmentCatalog.FLASH: {
		"seconds": 2.6,
		"keys": [
			{"t": 0.0},
			{"t": 0.2, "pos": Vector3(-0.1, 0.06, -0.08), "rot": Vector3(0, 0, 70)},
			{"t": 0.45, "pos": Vector3(-0.1, 0.06, -0.08), "rot": Vector3(0, 180, 70)},
			{"t": 0.65, "pos": Vector3(-0.08, 0.12, -0.12), "rot": Vector3(-25, 180, 10)},
			{"t": 0.85, "pos": Vector3(-0.06, 0.04, -0.06), "rot": Vector3(0, 360, 0)},
			{"t": 1.0, "rot": Vector3(0, 360, 0)},
		],
	},
	# Smoke: shaken like a can, then a quick look at the top.
	EquipmentCatalog.SMOKE: {
		"seconds": 2.4,
		"keys": [
			{"t": 0.0},
			{"t": 0.12, "pos": Vector3(-0.06, 0.06, -0.06), "rot": Vector3(0, 0, 20)},
			{"t": 0.2, "pos": Vector3(-0.06, 0.12, -0.06), "rot": Vector3(0, 0, -10)},
			{"t": 0.28, "pos": Vector3(-0.06, 0.04, -0.06), "rot": Vector3(0, 0, 20)},
			{"t": 0.36, "pos": Vector3(-0.06, 0.12, -0.06), "rot": Vector3(0, 0, -10)},
			{"t": 0.44, "pos": Vector3(-0.06, 0.04, -0.06), "rot": Vector3(0, 0, 20)},
			{"t": 0.52, "pos": Vector3(-0.06, 0.12, -0.06), "rot": Vector3(0, 0, -10)},
			{"t": 0.75, "pos": Vector3(-0.08, 0.06, -0.1), "rot": Vector3(-55, 30, 0)},
			{"t": 1.0},
		],
	},
	# Incendiary: the bottle swirled in a slow circle, then tipped to check the rag.
	EquipmentCatalog.FIRE: {
		"seconds": 3.0,
		"keys": [
			{"t": 0.0},
			{"t": 0.12, "pos": Vector3(-0.08, 0.05, -0.08), "rot": Vector3(10, 0, 10)},
			{"t": 0.24, "pos": Vector3(-0.04, 0.05, -0.12), "rot": Vector3(-10, 0, 10)},
			{"t": 0.36, "pos": Vector3(-0.08, 0.05, -0.16), "rot": Vector3(-10, 0, -10)},
			{"t": 0.48, "pos": Vector3(-0.12, 0.05, -0.12), "rot": Vector3(10, 0, -10)},
			{"t": 0.6, "pos": Vector3(-0.08, 0.05, -0.08), "rot": Vector3(10, 0, 10)},
			{"t": 0.8, "pos": Vector3(-0.1, 0.1, -0.1), "rot": Vector3(-20, -40, 60)},
			{"t": 1.0},
		],
	},
	# --- knives -------------------------------------------------------------------------------
	# Knife turns are in the fist's own axes (see the class notes): x twists the forearm, y bends
	# the wrist toward the thumb (+) or little finger, z bends it up or down.
	# Combat knife: the forearm twisted to show one face, then the other, then the blade raised
	# to catch the light with the index finger along the spine, and a squeeze to regrip.
	&"knf_combat": {
		"seconds": 3.0,
		"keys": [
			{"t": 0.0},
			{"t": 0.2, "pos": Vector3(-0.03, 0.036, -0.04), "rot": Vector3(-85, 0, 15), "fingers": {"Index": 0.8}},
			{"t": 0.45, "pos": Vector3(-0.03, 0.036, -0.04), "rot": Vector3(80, 0, 15), "fingers": {"Index": 0.8}},
			{"t": 0.65, "pos": Vector3(-0.024, 0.054, -0.06), "rot": Vector3(0, 20, 30), "fingers": {"Index": 0.15, "Middle": 0.9, "Thumb": 1.3}},
			{"t": 0.85, "pos": Vector3(-0.012, 0.018, -0.02), "fingers": {"Index": 1.1, "Middle": 1.1, "Ring": 1.1, "Little": 1.1}},
			{"t": 1.0},
		],
	},
	# Bayonet: two flat helicopter spins about the guard, flicked round by the fingers, then a look
	# down the side.
	&"knf_bayonet": {
		"seconds": 3.2,
		"keys": [
			{"t": 0.0, "pivot": Vector3(0, 0, 0.1)},
			{"t": 0.12, "pos": Vector3(-0.024, 0.03, -0.04), "pivot": Vector3(0, 0, 0.1), "fingers": {"Index": 0.7, "Middle": 0.6, "Ring": 0.5, "Little": 0.4}},
			{"t": 0.36, "pos": Vector3(-0.024, 0.03, -0.04), "rot": Vector3(0, 360, 0), "pivot": Vector3(0, 0, 0.1), "fingers": {"Index": 0.9, "Middle": 0.3, "Ring": 0.2, "Little": 0.2, "Thumb": 0.4}},
			{"t": 0.6, "pos": Vector3(-0.024, 0.03, -0.04), "rot": Vector3(0, 720, 0), "pivot": Vector3(0, 0, 0.1), "fingers": {"Index": 0.5, "Middle": 0.8, "Ring": 0.4, "Little": 0.3}},
			{"t": 0.8, "pos": Vector3(-0.03, 0.042, -0.05), "rot": Vector3(-80, 720, 10), "pivot": Vector3(0, 0, 0.1)},
			{"t": 1.0, "rot": Vector3(0, 720, 0), "pivot": Vector3(0, 0, 0.1)},
		],
	},
	# Butterfly knife: the handles swing round their pins to close it, then roll on round to open
	# it again while the knife rolls over in the fingers.
	&"knf_butterfly": {
		"seconds": 3.6,
		"keys": [
			{"t": 0.0},
			{"t": 0.12, "pos": Vector3(-0.024, 0.03, -0.04), "rot": Vector3(-30, 0, 0), "fingers": {"Little": 0.6}},
			{"t": 0.28, "pos": Vector3(-0.024, 0.036, -0.04), "rot": Vector3(-50, 0, 10), "parts": {&"handle_a": 180.0},
				"fingers": {"Middle": 0.7, "Ring": 0.2, "Little": 0.1, "Thumb": 0.4}},
			{"t": 0.44, "pos": Vector3(-0.03, 0.036, -0.05), "rot": Vector3(-20, 15, 25),
				"parts": {&"handle_a": 180.0, &"handle_b": -180.0}, "fingers": {"Index": 0.4, "Middle": 0.5, "Ring": 0.9, "Little": 0.9}},
			{"t": 0.6, "pos": Vector3(-0.024, 0.042, -0.05), "rot": Vector3(180, 0, 0),
				"parts": {&"handle_a": 360.0, &"handle_b": -180.0}, "fingers": {"Index": 0.8, "Ring": 0.2, "Little": 0.1, "Thumb": 0.4}},
			{"t": 0.78, "pos": Vector3(-0.024, 0.03, -0.04), "rot": Vector3(360, 0, 0),
				"parts": {&"handle_a": 360.0, &"handle_b": -360.0}},
			{"t": 1.0, "rot": Vector3(360, 0, 0), "parts": {&"handle_a": 360.0, &"handle_b": -360.0}},
		],
	},
	# Karambit: spun twice round the index finger through the ring, the other fingers opening out of
	# its way, then caught and held up side-on.
	&"knf_karambit": {
		"seconds": 3.0,
		"keys": [
			{"t": 0.0, "pivot": Vector3(0, 0.152, 0.385)},
			{"t": 0.1, "pos": Vector3(-0.018, 0.018, -0.03), "pivot": Vector3(0, 0.152, 0.385), "fingers": {"Middle": 0.5, "Ring": 0.4, "Little": 0.3, "Thumb": 0.3}},
			{"t": 0.325, "pos": Vector3(-0.018, 0.018, -0.03), "rot": Vector3(0, -360, 0), "pivot": Vector3(0, 0.152, 0.385),
				"fingers": {"Index": 1.05, "Middle": 0.05, "Ring": 0.05, "Little": 0.05, "Thumb": 0.25}},
			{"t": 0.55, "pos": Vector3(-0.018, 0.018, -0.03), "rot": Vector3(0, -720, 0), "pivot": Vector3(0, 0.152, 0.385),
				"fingers": {"Middle": 0.15, "Ring": 0.15, "Little": 0.15, "Thumb": 0.25}},
			{"t": 0.78, "pos": Vector3(-0.03, 0.042, -0.05), "rot": Vector3(80, -720, 15), "pivot": Vector3(0, 0.152, 0.385)},
			{"t": 1.0, "rot": Vector3(0, -720, 0), "pivot": Vector3(0, 0.152, 0.385)},
		],
	},
	# Nomad: tossed up end over end from a clenched fist, the hand opening to catch it, then a look
	# along the side.
	&"knf_nomad": {
		"seconds": 2.8,
		"toss": Vector2(0.13, 0.55),
		"keys": [
			{"t": 0.0},
			{"t": 0.12, "pos": Vector3(-0.018, -0.006, -0.03), "rot": Vector3(0, 0, -15), "fingers": {"Index": 1.1, "Middle": 1.1, "Ring": 1.1, "Little": 1.1}},
			{"t": 0.35, "pos": Vector3(-0.04, 0.28, -0.08), "rot": Vector3(0, 180, 0), "fingers": {"Index": 0.1, "Middle": 0.1, "Ring": 0.1, "Little": 0.1, "Thumb": 0.25}},
			{"t": 0.55, "pos": Vector3(-0.018, 0.012, -0.04), "rot": Vector3(0, 360, 0)},
			{"t": 0.77, "pos": Vector3(-0.03, 0.036, -0.05), "rot": Vector3(-80, 360, 15), "fingers": {"Index": 0.6}},
			{"t": 1.0, "rot": Vector3(0, 360, 0)},
		],
	},
	# Skeleton knife: twisted flat to face the player and spun like a wheel on the open palm.
	&"knf_skeleton": {
		"seconds": 3.0,
		"keys": [
			{"t": 0.0},
			{"t": 0.16, "pos": Vector3(-0.03, 0.036, -0.05), "rot": Vector3(85, 0, 0), "fingers": {"Index": 0.6, "Middle": 0.6, "Ring": 0.6, "Little": 0.6}},
			{"t": 0.36, "pos": Vector3(-0.03, 0.036, -0.05), "rot": Vector3(85, 180, 0), "fingers": {"Index": 0.15, "Middle": 0.15, "Ring": 0.15, "Little": 0.15, "Thumb": 0.1}},
			{"t": 0.56, "pos": Vector3(-0.03, 0.036, -0.05), "rot": Vector3(85, 360, 0), "fingers": {"Index": 0.3, "Middle": 0.3, "Ring": 0.3, "Little": 0.3, "Thumb": 0.3}},
			{"t": 0.76, "pos": Vector3(-0.024, 0.048, -0.06), "rot": Vector3(30, 360, 20), "fingers": {"Index": 0.7}},
			{"t": 1.0, "rot": Vector3(0, 360, 0)},
		],
	},
	# T-handle dagger: drawn back, punched forward, then twisted to show both faces.
	&"knf_t_dagger": {
		"seconds": 2.6,
		"keys": [
			{"t": 0.0},
			{"t": 0.14, "pos": Vector3(0, -0.006, 0.05), "rot": Vector3(0, 0, 15), "fingers": {"Index": 1.15, "Middle": 1.15, "Ring": 1.15, "Little": 1.15}},
			{"t": 0.28, "pos": Vector3(-0.012, 0, -0.12), "fingers": {"Index": 1.15, "Middle": 1.15, "Ring": 1.15, "Little": 1.15, "Thumb": 1.3}},
			{"t": 0.44, "pos": Vector3(-0.024, 0.03, -0.04), "fingers": {"Index": 0.8, "Middle": 0.8, "Ring": 0.8, "Little": 0.8}},
			{"t": 0.66, "pos": Vector3(-0.03, 0.036, -0.05), "rot": Vector3(-85, 0, 10), "fingers": {"Index": 0.6, "Little": 0.6}},
			{"t": 0.86, "pos": Vector3(-0.018, 0.018, -0.03), "rot": Vector3(80, 0, 10)},
			{"t": 1.0},
		],
	},
}


static func has_inspect(id: StringName) -> bool:
	return INSPECTS.has(id)


static func for_item(id: StringName) -> Dictionary:
	if INSPECTS.has(id):
		return INSPECTS[id]
	var grips: Dictionary = WeaponModels.GRIPS.get(id, {})
	return PISTOL if grips.has("right") and not grips.has("left") else DEFAULT


static func seconds(id: StringName) -> float:
	return float(for_item(id).get("seconds", DEFAULT_SECONDS))


## The pose at [param progress] 0..1 of [param id]'s inspection:
## {"pos": Vector3, "rot": Vector3 degrees, "pivot": Vector3 share of the item's size,
## "parts": {part name: degrees}}.
static func sample(id: StringName, progress: float) -> Dictionary:
	var keys: Array = for_item(id)["keys"]
	var t := clampf(progress, 0.0, 1.0)
	var before: Dictionary = keys[0]
	var after: Dictionary = keys[keys.size() - 1]
	for i: int in range(1, keys.size()):
		var key: Dictionary = keys[i]
		if float(key["t"]) >= t:
			before = keys[i - 1]
			after = key
			break
	var span := float(after["t"]) - float(before["t"])
	var blend := smoothstep(0.0, 1.0, (t - float(before["t"])) / span) if span > 0.0 else 1.0
	return {
		"pos": (before.get("pos", Vector3.ZERO) as Vector3).lerp(after.get("pos", Vector3.ZERO), blend),
		"rot": (before.get("rot", Vector3.ZERO) as Vector3).lerp(after.get("rot", Vector3.ZERO), blend),
		"pivot": (before.get("pivot", Vector3.ZERO) as Vector3).lerp(after.get("pivot", Vector3.ZERO), blend),
		"parts": _blend_parts(before.get("parts", {}), after.get("parts", {}), blend),
		"fingers": _blend_fingers(before.get("fingers", {}), after.get("fingers", {}), blend),
	}


## Finger grips between two keys (see the class notes); fingers neither key names are left out.
static func _blend_fingers(before: Dictionary, after: Dictionary, blend: float) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for finger: Variant in before.keys() + after.keys():
		result[StringName(str(finger))] = lerpf(float(before.get(finger, 1.0)), float(after.get(finger, 1.0)), blend)
	return result


static func _blend_parts(before: Dictionary, after: Dictionary, blend: float) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for part: Variant in before.keys() + after.keys():
		result[StringName(str(part))] = lerpf(float(before.get(part, 0.0)), float(after.get(part, 0.0)), blend)
	return result
