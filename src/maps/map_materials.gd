class_name MapMaterials
extends RefCounted
## The original material palette for map pieces. Every texture is generated in code from a
## colour and a simple pattern (no imported images), mapped in world space so neighbouring
## pieces line up. Pieces store a palette id; "" means the piece type's default.

const TEXTURE_SIZE: int = 32

## pattern: plain | noise | brick | tile | planks | stripes | panel. "repeat" is metres per tile.
const PALETTE: Dictionary[String, Dictionary] = {
	"adobe": {"label": "Adobe", "color": Color("c8a878"), "pattern": "noise", "repeat": 2.0},
	"plaster_white": {"label": "White plaster", "color": Color("e4dccb"), "pattern": "noise", "repeat": 3.0},
	"plaster_ochre": {"label": "Ochre plaster", "color": Color("d19a4a"), "pattern": "noise", "repeat": 3.0},
	"sandstone": {"label": "Sandstone blocks", "color": Color("b79a70"), "pattern": "brick", "repeat": 2.0},
	"mud_brick": {"label": "Mud brick", "color": Color("9a6a48"), "pattern": "brick", "repeat": 1.0},
	"stone_paving": {"label": "Stone paving", "color": Color("9c8f7c"), "pattern": "tile", "repeat": 2.0},
	"tile_terracotta": {"label": "Terracotta tile", "color": Color("b5683f"), "pattern": "tile", "repeat": 1.0},
	"sand": {"label": "Sand", "color": Color("d3b27a"), "pattern": "noise", "repeat": 4.0},
	"packed_earth": {"label": "Packed earth", "color": Color("a9845a"), "pattern": "noise", "repeat": 3.0},
	"concrete": {"label": "Concrete", "color": Color("8f8d86"), "pattern": "panel", "repeat": 3.0},
	"planks": {"label": "Wood planks", "color": Color("8a6a46"), "pattern": "planks", "repeat": 1.2},
	"wood_dark": {"label": "Dark wood", "color": Color("4f3a28"), "pattern": "planks", "repeat": 1.2},
	"metal_rust": {"label": "Rusted metal", "color": Color("7c4a32"), "pattern": "noise", "repeat": 1.0},
	"metal_painted": {"label": "Painted metal", "color": Color("6f7a52"), "pattern": "panel", "repeat": 1.5},
	"metal_dark": {"label": "Dark metal", "color": Color("33363a"), "pattern": "plain", "repeat": 1.0},
	"rubber": {"label": "Rubber", "color": Color("1d1d1f"), "pattern": "plain", "repeat": 1.0},
	"canvas": {"label": "Canvas", "color": Color("8d8a66"), "pattern": "noise", "repeat": 1.5},
	"burlap": {"label": "Burlap", "color": Color("a8946a"), "pattern": "brick", "repeat": 0.8},
	"cloth_red": {"label": "Red cloth", "color": Color("b84a3a"), "pattern": "noise", "repeat": 1.5},
	"cloth_blue": {"label": "Blue cloth", "color": Color("3f6f8f"), "pattern": "noise", "repeat": 1.5},
	"cloth_striped": {"label": "Striped cloth", "color": Color("d8c38a"), "pattern": "stripes", "repeat": 1.0},
	"water": {"label": "Water", "color": Color("2f5f6a"), "pattern": "plain", "repeat": 1.0},
}

static var _cache: Dictionary[String, StandardMaterial3D] = {}


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
	made.albedo_texture = ImageTexture.create_from_image(_image(id, entry["color"] as Color, str(entry["pattern"])))
	made.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	made.uv1_triplanar = true
	made.uv1_world_triplanar = true
	var scale := 1.0 / float(entry["repeat"])
	made.uv1_scale = Vector3(scale, scale, scale)
	made.roughness = 0.35 if id == "water" else 0.92
	_cache[id] = made
	return made


## The material a piece is drawn with: its own id, else the type default, else the dev checker.
static func for_piece(type: String, material_id: String) -> StandardMaterial3D:
	var id := material_id if has_material(material_id) else PieceCatalog.default_material(type)
	var made := material(id)
	return made if made != null else BlockBuilder.checker_material(PieceCatalog.color(type))


static func _image(id: String, color: Color, pattern: String) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, true, Image.FORMAT_RGBA8)
	var joint := color.darkened(0.28)
	for y: int in TEXTURE_SIZE:
		for x: int in TEXTURE_SIZE:
			var pixel := color.darkened(rng.randf_range(0.0, 0.08)) if pattern != "plain" else color
			match pattern:
				"brick":
					var row := y / 8
					if y % 8 == 0 or (x + (8 if row % 2 == 1 else 0)) % 16 == 0:
						pixel = joint
				"tile":
					if y % 16 == 0 or x % 16 == 0:
						pixel = joint
				"planks":
					if x % 8 == 0:
						pixel = joint
					elif (x / 8) % 2 == 1:
						pixel = pixel.darkened(0.06)
				"stripes":
					if (x / 8) % 2 == 1:
						pixel = Color("a8473a").darkened(rng.randf_range(0.0, 0.06))
				"panel":
					if y == 0 or x == 0:
						pixel = joint
			image.set_pixel(x, y, pixel)
	image.generate_mipmaps()
	return image
