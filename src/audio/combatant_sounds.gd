class_name CombatantSounds
extends Node
## The sounds one combatant makes (Milestone 22): shots by weapon, reloads, drawing, the knife,
## throws, being hit, running footsteps by surface and landings. It only listens to the body's,
## weapons' and health's signals. The listener's own body ([member own]) plays unspatialised,
## everyone else's from where they are. Walking and crouching are silent; running is not.

const SNIPERS: Array[StringName] = [WeaponCatalog.L118A1, WeaponCatalog.M24]
## Landings slower than this (m/s) are silent.
const SILENT_LANDING: float = 3.0
## The player's own sounds play this much quieter than they would at arm's length.
const OWN_DB: float = -3.0

var body: CombatantMovementBody
var weapons: WeaponController
var health: Health
var own: bool = false
var _step: int = 0


## Adds the sounds of [param combatant] (a player or a bot) as a child node.
static func attach(combatant: CombatantMovementBody, combatant_health: Health, is_own: bool) -> CombatantSounds:
	var sounds := CombatantSounds.new()
	sounds.name = "Sounds"
	sounds.body = combatant
	sounds.weapons = combatant.weapons
	sounds.health = combatant_health
	sounds.own = is_own
	combatant.add_child(sounds)
	return sounds


func _ready() -> void:
	weapons.shot_fired.connect(func(_origin: Vector3, _end: Vector3, _result: Hitscan.Result) -> void: _on_shot())
	weapons.reload_started.connect(func(_state: WeaponState) -> void: _play(&"reload_out", &"reload"))
	weapons.reload_finished.connect(func(_state: WeaponState) -> void: _play(&"reload_in", &"reload"))
	weapons.weapon_switched.connect(func(_state: WeaponState) -> void: _play(&"weapon_draw", &"reload", -6.0))
	weapons.melee_swung.connect(func(_heavy: bool) -> void: _play(&"knife_swing", &"knife"))
	weapons.utility_thrown.connect(func(_id: StringName) -> void: _play(&"throw", &"knife"))
	if own:
		weapons.target_hit.connect(_on_target_hit)
	health.damaged.connect(_on_damaged)
	body.stepped.connect(_on_stepped)
	body.landed.connect(_on_landed)


func _on_shot() -> void:
	var state := weapons.current()
	if state == null or state.definition == null:
		return
	var slot := SoundCatalog.shot_for(state.definition.id)
	if not slot.is_empty():
		_play(slot, &"sniper" if SNIPERS.has(state.definition.id) else &"shot")


## The player's confirmation that a shot landed (a kill sounds different).
func _on_target_hit(info: DamageInfo, _target: Health, killed: bool) -> void:
	SoundPlayer.play_flat(self, &"kill_confirm" if killed else (&"hit_head" if info.is_headshot() else &"hit_confirm"), &"UI")


func _on_damaged(info: DamageInfo) -> void:
	if not own:
		_play(&"hit_head" if info.is_headshot() else &"hit_body", &"hit")
	else:
		SoundPlayer.play_flat(self, &"hit_body", &"Effects", -4.0)


func _on_stepped() -> void:
	_step += 1
	_play(SoundCatalog.footstep(surface_below(), _step), &"footstep", -2.0)


func _on_landed(fall_speed: float) -> void:
	if fall_speed >= SILENT_LANDING:
		_play(&"land", &"land", clampf(-12.0 + fall_speed * 1.5, -12.0, 0.0))


## The footstep surface under the body, from the map piece it stands on (stone by default).
func surface_below() -> StringName:
	var from := body.global_position + Vector3(0, 0.3, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.0, 0), Hitscan.LAYER_WORLD)
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	var node := hit.get("collider") as Node
	while node != null:
		if node.has_meta(&"material_id"):
			return SoundCatalog.surface_of(str(node.get_meta(&"material_id")))
		node = node.get_parent()
	return &"stone"


func _play(slot: StringName, kind: StringName, volume_db: float = 0.0) -> void:
	if own:
		SoundPlayer.play_flat(self, slot, &"Effects", volume_db + OWN_DB, 0.03)
	else:
		SoundPlayer.play_at(body, slot, body.global_position + Vector3(0, 1.0, 0), kind, volume_db)
