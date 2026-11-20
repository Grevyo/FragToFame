class_name UtilityVisuals
extends RefCounted
## What utility looks like in the world: the smoke cloud, burning floor, the frag blast and the
## flash pop. The smoke must hide what it hides from bots, so the cloud is built from many
## overlapping soft puffs that fill the same volume [UtilityField] tests sight against.

const SMOKE_PUFFS: int = 44
const PUFF_SIZE: float = 2.3

static var _puff_texture: Texture2D = null
static var _flame_texture: Texture2D = null


## A smoke cloud filling an upright ellipsoid of [param radius] × [param height] (origin at its
## base). Call [method set_smoke_growth] each frame to bloom and fade it.
static func smoke_cloud(radius: float, height: float, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SmokeCloud"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _puff()
	material.albedo_color = colour
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * PUFF_SIZE
	var golden := PI * (3.0 - sqrt(5.0))
	for i: int in SMOKE_PUFFS:
		# Points spread evenly through the ellipsoid (a sunflower spiral on shells of rising radius).
		var t := (float(i) + 0.5) / SMOKE_PUFFS
		var shell := pow(t, 0.42)
		var y := 1.0 - 2.0 * fmod(float(i) * 0.618034, 1.0)
		var ring := sqrt(maxf(1.0 - y * y, 0.0))
		var angle := golden * float(i)
		var local := Vector3(cos(angle) * ring, y, sin(angle) * ring) * shell
		var puff := MeshInstance3D.new()
		puff.mesh = quad
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.set_meta("home", Vector3(local.x * radius * 0.8, height * 0.5 + local.y * height * 0.36, local.z * radius * 0.8))
		puff.set_meta("drift", float(i) * 1.37)
		root.add_child(puff)
	root.set_meta("material", material)
	root.set_meta("colour", colour)
	set_smoke_growth(root, 0.0, 1.0, 0.0)
	return root


## [param growth] 0..1 (bloom), [param opacity] 0..1 (fade), [param time] seconds (slow drift).
static func set_smoke_growth(cloud: Node3D, growth: float, opacity: float, time: float) -> void:
	var material := cloud.get_meta("material") as StandardMaterial3D
	var colour := cloud.get_meta("colour") as Color
	material.albedo_color = Color(colour, 0.9 * opacity)
	var spread := 0.25 + 0.75 * growth
	for node: Node in cloud.get_children():
		var puff := node as MeshInstance3D
		var home: Vector3 = puff.get_meta("home")
		var drift := float(puff.get_meta("drift"))
		var sway := Vector3(sin(time * 0.31 + drift), sin(time * 0.23 + drift * 0.7) * 0.4, cos(time * 0.27 + drift)) * 0.18
		puff.position = Vector3(home.x * spread, home.y * (0.4 + 0.6 * growth), home.z * spread) + sway * growth
		puff.scale = Vector3.ONE * (0.35 + 0.65 * growth)


## Flames over each floor patch (positions relative to the returned node), with one light.
static func fire_patches(patches: PackedVector3Array, patch_radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = _flame()
	material.albedo_color = Color(1.0, 0.55, 0.2)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(patch_radius * 2.0, patch_radius * 2.2)
	quad.center_offset = Vector3(0, patch_radius * 1.1, 0)
	var scorch_material := StandardMaterial3D.new()
	scorch_material.albedo_color = Color(0.06, 0.05, 0.04, 0.75)
	scorch_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch_material.albedo_texture = _puff()
	var scorch := PlaneMesh.new()
	scorch.size = Vector2.ONE * patch_radius * 2.6
	var centre := Vector3.ZERO
	for i: int in patches.size():
		var at := patches[i]
		centre += at
		for k: int in 2:
			var flame := MeshInstance3D.new()
			flame.mesh = quad
			flame.material_override = material
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flame.position = at + Vector3(0.18 * (k - 0.5), 0, 0.12 * (0.5 - k))
			flame.set_meta("phase", float(i * 2 + k) * 2.39)
			root.add_child(flame)
		var mark := MeshInstance3D.new()
		mark.mesh = scorch
		mark.material_override = scorch_material
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.position = at + Vector3(0, 0.02, 0)
		mark.set_meta("scorch", true)
		root.add_child(mark)
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 2.2
	light.omni_range = 7.0
	light.position = (centre / maxf(patches.size(), 1.0)) + Vector3(0, 0.8, 0)
	root.add_child(light)
	return root


## Flicker the flames; [param strength] 0..1 shrinks them as the fire burns out.
static func animate_fire(fire: Node3D, time: float, strength: float) -> void:
	for node: Node in fire.get_children():
		if node is MeshInstance3D and not node.has_meta("scorch"):
			var phase := float(node.get_meta("phase"))
			var flicker := 0.8 + 0.25 * sin(time * 11.0 + phase) + 0.12 * sin(time * 23.0 + phase * 1.7)
			(node as Node3D).scale = Vector3(1.0, flicker, 1.0) * maxf(strength, 0.05)
		elif node is OmniLight3D:
			(node as OmniLight3D).light_energy = (1.8 + 0.5 * sin(time * 17.0)) * strength


## A short-lived burst of light (frag and flash). Frees itself.
static func burst(parent: Node, at: Vector3, colour: Color, energy: float, light_range: float, seconds: float,
		ball_radius: float) -> void:
	var root := Node3D.new()
	root.name = "Burst"
	parent.add_child(root)
	root.global_position = at
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = energy
	light.omni_range = light_range
	root.add_child(light)
	if ball_radius > 0.0:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(colour, 0.85)
		var sphere := SphereMesh.new()
		sphere.radius = ball_radius
		sphere.height = ball_radius * 2.0
		var ball := MeshInstance3D.new()
		ball.mesh = sphere
		ball.material_override = material
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ball)
		var grow := root.create_tween()
		grow.tween_property(ball, "scale", Vector3.ONE * 1.8, seconds)
		grow.parallel().tween_property(material, "albedo_color:a", 0.0, seconds)
	var fade := root.create_tween()
	fade.tween_property(light, "light_energy", 0.0, seconds)
	fade.tween_callback(root.queue_free)


static func _puff() -> Texture2D:
	if _puff_texture == null:
		_puff_texture = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)], [0.0, 0.45, 1.0])
	return _puff_texture


static func _flame() -> Texture2D:
	if _flame_texture == null:
		_flame_texture = _radial([Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.1, 0.8), Color(0.6, 0.1, 0.0, 0)], [0.0, 0.4, 1.0])
	return _flame_texture


static func _radial(colours: Array[Color], offsets: Array[float]) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colours)
	gradient.offsets = PackedFloat32Array(offsets)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
