class_name GroundMounds
extends RefCounted
## Uneven ground: a patch of earth that rises and dips in soft mounds. Its edges, and the hollows
## between mounds, sink just below the piece's base (EDGE_SINK), so laid on any floor the join
## follows each mound's own contour instead of showing a rectangle. The piece's size is its
## footprint (X/Z) and the tallest a mound may rise (Y). Slopes are capped at MAX_SLOPE_DEGREES so players and bots walk all of it;
## mounds that would be steeper are lowered. The mesh is also its collider (exact match).
##
## Props: "feature" (metres between mound crests), "seed" (variation), "edge" (metres of flat
## border), "oval" (fade toward an ellipse instead of the rectangle).

const MAX_SLOPE_DEGREES: float = 21.0
## How far the edges and hollows sit below the base, hidden by the floor they are laid on.
const EDGE_SINK: float = 0.02
const CELL: float = 0.5
const MAX_CELLS: int = 96


## Height of every grid point, row by row (Z) then column (X), in metres above the piece origin.
## Returns [columns, rows, heights].
static func heights(size: Vector3, props: Dictionary) -> Array:
	var columns := clampi(ceili(size.x / CELL), 2, MAX_CELLS)
	var rows := clampi(ceili(size.z / CELL), 2, MAX_CELLS)
	var feature := clampf(float(props.get("feature", 3.0)), 0.5, 40.0)
	var edge := clampf(float(props.get("edge", 1.0)), 0.0, minf(size.x, size.z) * 0.5)
	var oval := bool(props.get("oval", false))
	var noise := FastNoiseLite.new()
	noise.seed = int(props.get("seed", 0))
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / feature
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	var rise := maxf(size.y + EDGE_SINK, 0.0)
	var values := PackedFloat32Array()
	values.resize((columns + 1) * (rows + 1))
	for row: int in rows + 1:
		for column: int in columns + 1:
			var local := Vector2(size.x * (float(column) / columns - 0.5), size.z * (float(row) / rows - 0.5))
			var crest := clampf(noise.get_noise_2d(local.x, local.y) * 0.85 + 0.5, 0.0, 1.0)
			values[row * (columns + 1) + column] = rise * crest * _falloff(local, size, edge, oval)
	_limit_slopes(values, columns, rows, size)
	for i: int in values.size():
		values[i] -= EDGE_SINK
	return [columns, rows, values]


## 0 at the patch's edge, 1 beyond the flat border, eased so the ground meets the floor smoothly.
static func _falloff(local: Vector2, size: Vector3, edge: float, oval: bool) -> float:
	var inset: float
	if oval:
		var radius := Vector2(size.x, size.z) * 0.5
		var reach := (local / radius).length()
		inset = (1.0 - reach) * minf(radius.x, radius.y)
	else:
		inset = minf(size.x * 0.5 - absf(local.x), size.z * 0.5 - absf(local.y))
	if edge <= 0.0:
		return 1.0 if inset > 0.0 else 0.0
	var t := clampf(inset / edge, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Lowers the mounds until no triangle of the surface is steeper than MAX_SLOPE_DEGREES. Each
## grid cell is split along the same diagonal as the mesh, so this measures exactly what is drawn.
static func _limit_slopes(values: PackedFloat32Array, columns: int, rows: int, size: Vector3) -> void:
	var step := Vector2(size.x / columns, size.z / rows)
	var steepest := 0.0
	for row: int in rows:
		for column: int in columns:
			var a := values[row * (columns + 1) + column]
			var b := values[row * (columns + 1) + column + 1]
			var c := values[(row + 1) * (columns + 1) + column + 1]
			var d := values[(row + 1) * (columns + 1) + column]
			steepest = maxf(steepest, Vector2((b - a) / step.x, (c - b) / step.y).length())
			steepest = maxf(steepest, Vector2((c - d) / step.x, (d - a) / step.y).length())
	var allowed := tan(deg_to_rad(MAX_SLOPE_DEGREES))
	if steepest > allowed:
		var scale := allowed / steepest
		for i: int in values.size():
			values[i] *= scale


## Ground surface mesh (a single sheet; its sunken edges need no sides), or null for a degenerate
## size.
static func mesh(size: Vector3, props: Dictionary) -> ArrayMesh:
	if size.x < 0.5 or size.z < 0.5 or size.y < 0.05:
		return null
	var grid := heights(size, props)
	var columns: int = grid[0]
	var rows: int = grid[1]
	var values: PackedFloat32Array = grid[2]
	var point := func(column: int, row: int) -> Vector3:
		return Vector3(size.x * (float(column) / columns - 0.5), values[row * (columns + 1) + column],
			size.z * (float(row) / rows - 0.5))
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in rows:
		for column: int in columns:
			var a: Vector3 = point.call(column, row)
			var b: Vector3 = point.call(column + 1, row)
			var c: Vector3 = point.call(column + 1, row + 1)
			var d: Vector3 = point.call(column, row + 1)
			# Clockwise seen from above: Godot front faces point up.
			_triangle(builder, a, b, c)
			_triangle(builder, a, c, d)
	builder.generate_normals()
	return builder.commit()


## Surface height at a local X/Z point (bilinear over the grid); used by tests and tools.
static func height_at(size: Vector3, props: Dictionary, local: Vector2) -> float:
	var grid := heights(size, props)
	var columns: int = grid[0]
	var rows: int = grid[1]
	var values: PackedFloat32Array = grid[2]
	var fx := clampf((local.x / size.x + 0.5) * columns, 0.0, columns)
	var fz := clampf((local.y / size.z + 0.5) * rows, 0.0, rows)
	var column := mini(floori(fx), columns - 1)
	var row := mini(floori(fz), rows - 1)
	var u := fx - column
	var v := fz - row
	var top := lerpf(values[row * (columns + 1) + column], values[row * (columns + 1) + column + 1], u)
	var bottom := lerpf(values[(row + 1) * (columns + 1) + column], values[(row + 1) * (columns + 1) + column + 1], u)
	return lerpf(top, bottom, v)


static func _triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	builder.add_vertex(a)
	builder.add_vertex(b)
	builder.add_vertex(c)
