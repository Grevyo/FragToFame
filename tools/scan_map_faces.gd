extends SceneTree
## Report coincident, outward-facing surfaces from different saved pieces.
## Run with --script res://tools/scan_map_faces.gd -- map_f2f_cluts

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var doc := OfficialMaps.load_map(args[0])
	if doc == null:
		quit(1)
		return
	var world := MapBuilder.build(doc,MapBuilder.Mode.RUNTIME)
	root.add_child(world)
	var planes := {}
	var hits := {}
	var solids: Array = []
	var crossings := {}
	for holder: Node in world.get_children():
		var id := str(holder.name)
		var piece := doc.get_piece(id)
		if not PieceCatalog.kind(str(piece.type)) in PieceCatalog.SOLID_KINDS:
			continue
		var triangles: Array = []
		var bounds := AABB()
		for node: Node in holder.find_children("*","MeshInstance3D",true,false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null:
				continue
			var vertices := mesh.mesh.get_faces()
			for i in range(0,vertices.size(),3):
				var a := mesh.global_transform * vertices[i]
				var b := mesh.global_transform * vertices[i+1]
				var c := mesh.global_transform * vertices[i+2]
				var normal := (b-a).cross(c-a).normalized()
				if normal.length_squared() < 0.9:
					continue
				var face_box := AABB(a,Vector3.ZERO).expand(b).expand(c).grow(0.0001)
				if triangles.is_empty():
					bounds = face_box
				else:
					bounds = bounds.merge(face_box)
				triangles.append([a,b,c,face_box])
				var key := Vector4(normal.x,normal.y,normal.z,normal.dot(a)).snapped(Vector4.ONE*0.001)
				var axis := normal.abs().max_axis_index()
				var poly := PackedVector2Array()
				for v: Vector3 in [a,b,c]:
					poly.append(Vector2(v[(axis+1)%3],v[(axis+2)%3]))
				var box := Rect2(poly[0],Vector2.ZERO).expand(poly[1]).expand(poly[2])
				if not planes.has(key):
					planes[key] = []
				for other: Array in planes[key]:
					if other[0] == id or not box.intersects(other[1]):
						continue
					for overlap in Geometry2D.intersect_polygons(poly,other[2]):
						var area := 0.0
						for j in overlap.size():
							area += overlap[j].cross(overlap[(j+1)%overlap.size()])
						if absf(area) > 0.002:
							var pair := "%s %s" % [other[0],id]
							hits[pair] = float(hits.get(pair,0)) + absf(area)*0.5/absf(normal[axis])
				planes[key].append([id,box,poly])
		for solid: Array in solids:
			var penetration := bounds.intersection(solid[1]).size
			if penetration[penetration.min_axis_index()] > 0.001 and _crosses(triangles,solid[2]):
				crossings["%s %s" % [solid[0],id]] = true
		solids.append([id,bounds,triangles])
	for pair: String in crossings:
		print("Crossing ",pair)
	print("Crossing piece pairs: ",crossings.size())
	for pair: String in hits:
		print("Faces ",pair," area %.3f" % hits[pair])
	print("Coincident piece pairs: ",hits.size())
	world.free()
	quit()


# Require triangles to straddle each other's planes. Touching edges and mounted
# faces are contacts; they do not cut through one another.
func _crosses(left: Array, right: Array) -> bool:
	for a: Array in left:
		for b: Array in right:
			if not (a[3] as AABB).intersects(b[3]):
				continue
			if not _straddles(a,b) or not _straddles(b,a):
				continue
			for i in 3:
				if Geometry3D.segment_intersects_triangle(a[i],a[(i+1)%3],b[0],b[1],b[2]) != null:
					return true
				if Geometry3D.segment_intersects_triangle(b[i],b[(i+1)%3],a[0],a[1],a[2]) != null:
					return true
	return false


func _straddles(tri: Array, other: Array) -> bool:
	var plane := Plane(other[0],other[1],other[2])
	var a := plane.distance_to(tri[0])
	var b := plane.distance_to(tri[1])
	var c := plane.distance_to(tri[2])
	return minf(a,minf(b,c)) < -0.001 and maxf(a,maxf(b,c)) > 0.001
