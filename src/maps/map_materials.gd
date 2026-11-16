class_name MapMaterials
extends RefCounted
## Original tileable colour and normal maps, generated once per material and shared by the
## editor and the FPS runtime. World-space mapping aligns neighbouring pieces. Pieces store a
## palette ID; "" uses the piece type's default.

const TEXTURE_SIZE: int = 128
const SWATCH_SIZE: int = 32

## "repeat" is metres per tile. Each pattern describes a surface and its relief.
const PALETTE: Dictionary[String, Dictionary] = {
	"adobe": {"label": "Adobe", "color": Color("c8a878"), "pattern": "plaster", "repeat": 2.0},
	"plaster_white": {"label": "White plaster", "color": Color("e4dccb"), "pattern": "plaster", "repeat": 3.0},
	"plaster_ochre": {"label": "Ochre plaster", "color": Color("d19a4a"), "pattern": "plaster", "repeat": 3.0},
	"sandstone": {"label": "Sandstone blocks", "color": Color("b79a70"), "pattern": "brick", "repeat": 2.0},
	"mud_brick": {"label": "Mud brick", "color": Color("9a6a48"), "pattern": "brick", "repeat": 1.0},
	"stone_paving": {"label": "Stone paving", "color": Color("9c8f7c"), "pattern": "tile", "repeat": 2.0},
	"tile_terracotta": {"label": "Terracotta tile", "color": Color("b5683f"), "pattern": "tile", "repeat": 1.0},
	"sand": {"label": "Sand", "color": Color("d3b27a"), "pattern": "dunes", "repeat": 4.0},
	"packed_earth": {"label": "Packed earth", "color": Color("a9845a"), "pattern": "noise", "repeat": 3.0},
	"concrete": {"label": "Concrete", "color": Color("8f8d86"), "pattern": "panel", "repeat": 3.0},
	"planks": {"label": "Wood planks", "color": Color("8a6a46"), "pattern": "planks", "repeat": 1.2},
	"wood_dark": {"label": "Dark wood", "color": Color("4f3a28"), "pattern": "planks", "repeat": 1.2},
	"metal_rust": {"label": "Rusted metal", "color": Color("7c4a32"), "pattern": "noise", "repeat": 1.0},
	"metal_painted": {"label": "Painted metal", "color": Color("6f7a52"), "pattern": "panel", "repeat": 1.5},
	"metal_dark": {"label": "Dark metal", "color": Color("33363a"), "pattern": "plain", "repeat": 1.0},
	"rubber": {"label": "Rubber", "color": Color("1d1d1f"), "pattern": "plain", "repeat": 1.0},
	"canvas": {"label": "Canvas", "color": Color("8d8a66"), "pattern": "woven", "repeat": 1.5},
	"burlap": {"label": "Burlap", "color": Color("a8946a"), "pattern": "woven", "repeat": 0.8},
	"cloth_red": {"label": "Red cloth", "color": Color("b84a3a"), "pattern": "woven", "repeat": 1.5},
	"cloth_blue": {"label": "Blue cloth", "color": Color("3f6f8f"), "pattern": "woven", "repeat": 1.5},
	"cloth_striped": {"label": "Striped cloth", "color": Color("d8c38a"), "pattern": "stripes", "repeat": 1.0},
	"water": {"label": "Water", "color": Color("2f5f6a"), "pattern": "plain", "repeat": 1.0, "roughness": 0.35},
	"cobblestone": {"label": "Worn cobblestone", "color": Color("8d8070"), "pattern": "cobbles", "repeat": 1.6},
	"limewash": {"label": "Aged limewash", "color": Color("d9c9ac"), "pattern": "plaster", "repeat": 2.0},
	"limestone": {"label": "Cut limestone", "color": Color("bdb69f"), "pattern": "stone", "repeat": 1.8},
	"fired_clay": {"label": "Fired clay", "color": Color("a85035"), "pattern": "clay", "repeat": 0.7},
	"weathered_wood": {"label": "Weathered timber", "color": Color("836549"), "pattern": "planks", "repeat": 1.4},
	"brass": {"label": "Hammered brass", "color": Color("a58348"), "pattern": "metal", "repeat": 0.8,
		"roughness": 0.52, "metallic": 0.76},
}

static var _cache: Dictionary[String, StandardMaterial3D] = {}
static var _swatches: Dictionary[String, Texture2D] = {}


static func has_material(id: String) -> bool:
	return PALETTE.has(id)


static func label(id: String) -> String:
	return str(PALETTE.get(id, {}).get("label", id))


static func ids() -> Array[String]:
	var list: Array[String] = []
	list.assign(PALETTE.keys())
	return list


## Shared material for a palette id, or null when the id is unknown.
static func material(id: String) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	if not PALETTE.has(id):
		return null
	var entry := PALETTE[id]
	var made := StandardMaterial3D.new()
	var textures := _textures(id, entry["color"] as Color, str(entry["pattern"]))
	made.albedo_texture = ImageTexture.create_from_image(textures[0])
	made.normal_enabled = str(entry["pattern"]) != "plain"
	if made.normal_enabled:
		made.normal_texture = ImageTexture.create_from_image(textures[1])
		made.normal_scale = 0.72
	made.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	made.uv1_triplanar = true
	made.uv1_world_triplanar = true
	var scale := 1.0 / float(entry["repeat"])
	made.uv1_scale = Vector3(scale, scale, scale)
	made.roughness = float(entry.get("roughness", 0.86))
	made.metallic = float(entry.get("metallic", 0.0))
	_cache[id] = made
	return made


## A small copy of the world texture for the Inspector dropdown.
static func swatch(id: String) -> Texture2D:
	if not has_material(id):
		return null
	if not _swatches.has(id):
		var preview := material(id).albedo_texture.get_image().duplicate() as Image
		preview.resize(SWATCH_SIZE, SWATCH_SIZE, Image.INTERPOLATE_LANCZOS)
		_swatches[id] = ImageTexture.create_from_image(preview)
	return _swatches[id]


## The material a piece is drawn with: its own id, else the type default, else the dev checker.
static func for_piece(type: String, material_id: String) -> StandardMaterial3D:
	var id := material_id if has_material(material_id) else PieceCatalog.default_material(type)
	var made := material(id)
	return made if made != null else BlockBuilder.checker_material(PieceCatalog.color(type))


static func _textures(id: String, base: Color, pattern: String) -> Array[Image]:
	var seed_value := hash(id)
	var coarse := _tile_noise(seed_value, 0.028)
	var fine := _tile_noise(seed_value + 1, 0.17)
	var height := PackedFloat32Array()
	height.resize(TEXTURE_SIZE * TEXTURE_SIZE)
	var albedo := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y: int in TEXTURE_SIZE:
		for x: int in TEXTURE_SIZE:
			var index := y * TEXTURE_SIZE + x
			var low := float(coarse[index]) / 255.0 - 0.5
			var grain := float(fine[index]) / 255.0 - 0.5
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(TEXTURE_SIZE)
			var relief := _surface(uv, low, grain, pattern)
			height[index] = relief.x
			var tint := Color("954437") if pattern == "stripes" and fposmod(uv.x * 4.0, 1.0) < 0.36 else base
			var shade := clampf(relief.y, -0.55, 0.22)
			var pixel := tint.lightened(shade) if shade >= 0.0 else tint.darkened(-shade)
			albedo.set_pixel(x, y, pixel)
	albedo.generate_mipmaps()
	return [albedo, _normal_map(height)]


static func _tile_noise(seed_value: int, frequency: float) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 3
	var tile := noise.get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE, false, false, 0.18)
	tile.convert(Image.FORMAT_L8)
	return tile.get_data()


## Returns physical relief and an independent brightness adjustment.
static func _surface(uv: Vector2, low: float, grain: float, pattern: String) -> Vector2:
	match pattern:
		"brick", "tile", "cobbles":
			return _masonry(uv, low, grain, pattern)
		"planks":
			var groove := smoothstep(0.015, 0.055, absf(fposmod(uv.x * 4.0 + 0.5, 1.0) - 0.5))
			var fibre := sin(TAU * (uv.x * 38.0 + sin(TAU * uv.y * 2.0) * 0.22 + low * 1.2))
			return Vector2(groove * 0.22 + fibre * 0.025 + grain * 0.06,
				(groove - 1.0) * 0.37 + fibre * 0.065 + low * 0.21 + grain * 0.1)
		"woven", "stripes":
			var threads := sin(TAU * uv.x * 24.0) * sin(TAU * uv.y * 24.0)
			return Vector2(threads * 0.025 + low * 0.04, threads * 0.055 + low * 0.18 + grain * 0.1)
		"panel":
			var seam := minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
			var bevel := smoothstep(0.012, 0.038, seam)
			var corner := Vector2(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
			var rivet := 1.0 - smoothstep(0.015, 0.023, corner.distance_to(Vector2(0.072, 0.072)))
			return Vector2(bevel * 0.18 + rivet * 0.1 + grain * 0.045,
				(bevel - 1.0) * 0.33 + rivet * 0.1 + low * 0.18 + grain * 0.09)
		"dunes":
			var ripples := sin(TAU * (uv.y * 8.0 + sin(TAU * uv.x * 2.0) * 0.24 + low * 0.65))
			return Vector2(ripples * 0.045 + grain * 0.048, ripples * 0.04 + low * 0.15 + grain * 0.11)
		"plaster", "stone":
			var pits := smoothstep(0.14, 0.42, -grain)
			return Vector2(low * 0.13 + grain * 0.11 - pits * 0.07, low * 0.21 + grain * 0.17 - pits * 0.15)
		"clay":
			var tooling := sin(TAU * (uv.y * 19.0 + low * 0.4))
			return Vector2(tooling * 0.018 + grain * 0.065, low * 0.23 + grain * 0.1 + tooling * 0.03)
		"metal":
			return Vector2(low * 0.12 + grain * 0.08, low * 0.23 + grain * 0.14)
		"plain":
			return Vector2.ZERO
	return Vector2(low * 0.12 + grain * 0.09, low * 0.18 + grain * 0.16)


static func _masonry(uv: Vector2, low: float, grain: float, pattern: String) -> Vector2:
	var rows := 4.0 if pattern != "tile" else 3.0
	var columns := 2.0 if pattern == "brick" else rows
	var offset := 0.5 if pattern != "tile" and int(floorf(uv.y * rows)) % 2 != 0 else 0.0
	var cell := Vector2(fposmod(uv.x * columns + offset, 1.0), fposmod(uv.y * rows, 1.0))
	var edges := cell.min(Vector2.ONE - cell)
	var approach := minf(edges.x, edges.y)
	if pattern == "cobbles":
		var round_corner := (Vector2(0.14, 0.14) - edges).max(Vector2.ZERO).length()
		approach = minf(approach, 0.14 - round_corner)
	var bevel := smoothstep(0.025, 0.1, approach + grain * 0.04)
	return Vector2(bevel * 0.25 + grain * 0.06 + low * 0.04,
		(bevel - 1.0) * 0.37 + grain * 0.13 + low * 0.26)


## Sample across the wrapped edges so normal-map gradients also tile.
static func _normal_map(height: PackedFloat32Array) -> Image:
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y: int in TEXTURE_SIZE:
		var above := posmod(y - 1, TEXTURE_SIZE) * TEXTURE_SIZE
		var below := posmod(y + 1, TEXTURE_SIZE) * TEXTURE_SIZE
		var row := y * TEXTURE_SIZE
		for x: int in TEXTURE_SIZE:
			var left := row + posmod(x - 1, TEXTURE_SIZE)
			var right := row + posmod(x + 1, TEXTURE_SIZE)
			var normal := Vector3(
				(height[left] - height[right]) * 2.4,
				(height[below + x] - height[above + x]) * 2.4, 1.0).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5))
	image.generate_mipmaps(true)
	return image
