extends "res://tools/map_author_base.gd"

func _official_id() -> String:
	return "map_f2f_cluts"


func _revision() -> int:
	return 13


# Trace coordinates from the supplied ground-floor sketch. North is negative Z.
func _plan(x: float, y: float) -> Vector2:
	return Vector2((x - 350) * 0.14, (y - 280) * 0.14)


func _trace(points: Array, material: String, height: float = 4.45, gaps: Dictionary = {}) -> void:
	var corners: Array = []
	for pt: Vector2 in points:
		corners.append(_plan(pt.x,pt.y))
	_joined_walls(corners,false,height,0,material,0.65,gaps)


func walls_around(outline: Array, height: float, base: float, material: String, gaps: Dictionary = {},
		skip: Array = [], type: String = "wall", thickness: float = 0.6) -> void:
	if not skip.is_empty() or type != "wall":
		super.walls_around(outline,height,base,material,gaps,skip,type,thickness)
		return
	_joined_walls(outline,true,height,base,material,thickness,gaps)


# Mitred cross-sections share an edge. No overlapping top faces or buried end caps.
func _joined_walls(points: Array, closed: bool, height: float, base: float, material: String,
		width: float, gaps: Dictionary) -> void:
	var offsets: Array[Vector2] = []
	var n := points.size()
	for i in n:
		var here: Vector2 = points[i]
		var before := (here - Vector2(points[posmod(i-1,n)])).normalized().orthogonal()
		var after := (Vector2(points[(i+1)%n]) - here).normalized().orthogonal()
		if not closed and i == 0:
			before = after
		if not closed and i == n-1:
			after = before
		offsets.append((before+after) * (width*0.5 / (1.0+before.dot(after))))
	for i in range(n if closed else n-1):
		var j := (i+1)%n
		var a: Vector2 = points[i]
		var b: Vector2 = points[j]
		var length := a.distance_to(b)
		var cuts: Array = [0.0]
		for gap: Array in gaps.get(i,[]):
			cuts.append_array(gap)
		cuts.append(length)
		for k in range(0,cuts.size(),2):
			var start := float(cuts[k])/length
			var end := float(cuts[k+1])/length
			var side := (b-a).normalized().orthogonal()*width*0.5
			var left := offsets[i] if start == 0 else side
			var right := offsets[j] if end == 1 else side
			var u := a.lerp(b,start)
			var v := a.lerp(b,end)
			var vertices := []
			for y: float in [base,base+height]:
				for pt: Vector2 in [u-left,v-right,v+right,u+left]:
					vertices.append([pt.x,y,pt.y])
			var faces := [4,5,6,4,6,7,0,2,1,0,3,2,0,1,5,0,5,4,2,3,7,2,7,6]
			if end < 1 or (not closed and j == n-1):
				faces.append_array([1,2,6,1,6,5])
			if start > 0 or (not closed and i == 0):
				faces.append_array([3,0,4,3,4,7])
			_convex_shell(vertices,faces,material)


# Closed convex shells need only their outward triangles (Godot uses clockwise winding).
func _convex_shell(vertices: Array, faces: Array, material: String) -> void:
	var centre := Vector3.ZERO
	var points: Array[Vector3] = []
	for xyz: Array in vertices:
		var point := Vector3(xyz[0],xyz[1],xyz[2])
		points.append(point)
		centre += point
	centre /= points.size()
	for i in range(0,faces.size(),3):
		var a := points[faces[i]]
		var b := points[faces[i+1]]
		var c := points[faces[i+2]]
		if (b-a).cross(c-a).dot(a-centre) > 0:
			var swap: int = faces[i+1]
			faces[i+1] = faces[i+2]
			faces[i+2] = swap
	studio.call("draw_brushes",[{"vertices":vertices,"faces":faces,"material":material}])


func prism(outline: Array, base: float, height: float, material: String = "") -> void:
	var n := outline.size()
	var vertices := []
	var faces := []
	for y: float in [base,base+height]:
		for pt: Vector2 in outline:
			vertices.append([pt.x,y,pt.y])
	for i in range(1,n-1):
		faces.append_array([0,i,i+1,n,n+i,n+i+1])
	for i in n:
		var j := (i+1)%n
		faces.append_array([i,j,n+j,i,n+j,n+i])
	_convex_shell(vertices,faces,material)


func _build() -> void:
	controller.set_metadata("Cluts","F2F official","A harbour chronometer exchange. From the ticket quay, thread the exchange corridors to the dispatch yard or take the glass-plate stairs below the harbour office.")
	controller.set_lighting({"sun_yaw":135.0,"sun_pitch":47.0,"ambient_color":"cbd9eb","ambient_energy":0.7})
	layer("Ground plan")
	var outline: Array = []
	for point: Vector2 in [Vector2(9,48),Vector2(120,47),Vector2(220,53),Vector2(470,40),
			Vector2(720,36),Vector2(711,265),Vector2(731,530),Vector2(504,524),
			Vector2(503,465),Vector2(250,470),Vector2(245,430),Vector2(26,427),Vector2(12,200)]:
		outline.append(_plan(point.x,point.y))
	# Shafts at west exchange, northern service bay, and southeast dispatch.
	# Shafts at west exchange, northern service bay, southeast dispatch and the east lane pump stair.
	floor_shape(outline,0,0.6,"stone_paving",[[-43,-37,-3,10],[16,29,-24,-19],[26,39,25,31],[33,37,-14,-1],[-44,-40,-20,-16]])
	_harbour_boundary(outline)
	# The lines between lanes are the exchange's yard walls: brick on a granite plinth with stone
	# coping and piers, granite along the quay. They stand 3.6 m or more so nobody can jump-peek.
	_yard_wall([Vector2(15,194),Vector2(72,194),Vector2(104,184),Vector2(104,98),Vector2(120,92),Vector2(166,94),Vector2(182,101),Vector2(290,105)],3.8,"granite")
	_yard_wall([Vector2(167,209),Vector2(170,140),Vector2(205,134),Vector2(293,136),Vector2(400,146)],4.2,"brick")
	_yard_wall([Vector2(580,122),Vector2(564,95),Vector2(459,98),Vector2(457,147),Vector2(512,147),Vector2(633,166),Vector2(676,163)],4.6,"brick")
	_yard_wall([Vector2(309,209),Vector2(393,209),Vector2(470,218),Vector2(576,220),Vector2(575,355)],3.8,"brick")
	_yard_wall([Vector2(357,259),Vector2(426,256),Vector2(462,265),Vector2(498,266),Vector2(503,282),Vector2(502,355)],3.6,"brick")
	_yard_wall([Vector2(405,290),Vector2(405,355),Vector2(321,357),Vector2(303,369)],3.6,"brick")
	_yard_wall([Vector2(137,235),Vector2(170,248),Vector2(200,273),Vector2(221,307),Vector2(227,327),Vector2(226,355)],4.0,"brick")
	_yard_wall([Vector2(200,359),Vector2(256,359),Vector2(276,381)],3.6,"brick")
	_yard_wall([Vector2(224,407),Vector2(242,426)],3.6,"brick")
	_yard_wall([Vector2(628,523),Vector2(629,460),Vector2(600,463),Vector2(572,456),Vector2(546,436),Vector2(539,415),Vector2(644,415),Vector2(645,438),Vector2(642,448)],3.8,"brick",{0:[[0.6,2.9]]},[1,8])
	_receiving_house()
	_tide_well()
	_raised_ground()
	_lower()
	_harbour_basin()
	_skyline()
	_fixtures()
	layer("Match layout")
	# Start at the quay end of the line so a teammate collecting a dropped
	# bomb can turn toward dispatch without retracing across the carrier.
	for x: int in [-40,-38,-36,-34,-32]:
		put("spawn_attack",Vector3(x,0,16))
	put("buy_zone",Vector3(-36,0,16),Vector3(13,3,7),0,{"team":"attack"})
	spawns("defence",Vector3(42,0,-24),180,Vector3(9,3,6))
	for site: String in ["A","B"]:
		var at := Vector3(45,0,30) if site == "A" else Vector3(31,-5,15)
		put("bombsite",at,Vector3(9,3,8),0,{"site":site})
		for dx: int in [-2,2]:
			anchor(site + str(dx),"plant",at+Vector3(dx,0,1))
			hint("ai_hold",at+Vector3(dx,0,-2),180,site)
	for pt: Vector3 in [Vector3(-32,0,16),Vector3(37,0,-24),Vector3(13,-5,9)]:
		anchor("Collect " + str(pt.x),"default",pt)
		anchor("Throw " + str(pt.x),"utility",pt+Vector3(1,0,0))
	area("Ticket Quay",-43,-30,12,19)
	area("Harbour Office",35,50,-32,-19)
	area("Meridian Corridor",-7,5,-17,-11,"mid")
	area("Reading Room",-6,5,-2,9)
	area("Public Counter",-18,-12,12,18)
	area("Lens Elbow",-32,-26,-17,-11)
	area("Dispatch Yard",40,50,26,34)
	area("Hoist Gate",43,49,18,23,"entrance_a")
	area("Dispatch Bend",39,42,25,30,"entrance_a")
	area("West Shaft",-43,-37,-6,-3,"",-5)
	area("Negative Store",-18,-6,-23,-18,"",-5)
	area("Darkroom",27,35,11,19,"",-5)
	area("Darkroom Door",24,29,9,13,"entrance_b",-5)
	area("Drying Passage",26,31,18,21,"entrance_b",-5)
	area("Dispatch",25,38,21,25)
	area("North Stair",29,34,-24,-19,"",-5)
	area("East Approach",38,45,1,7)
	area("Ramp Yard",22,37.4,31.2,34)
	area("Yard Door",37.6,41.4,31,33.4,"entrance_a")


# Each boundary follows the floor outline. The deep building faces extend outwards
# so the playable side keeps the original route widths.
func _harbour_boundary(outline: Array) -> void:
	layer("Quay perimeter")
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i+1)%outline.size()]
		var delta := b-a
		var length := delta.length()
		var along := delta/length
		var outside := Vector2(along.y,-along.x)
		var centre := (a+b)/2
		var yaw := rad_to_deg(atan2(-along.y,along.x))
		var prev_dir := (a - Vector2(outline[posmod(i-1,outline.size())])).normalized()
		var next_dir := (Vector2(outline[(i+2)%outline.size()]) - b).normalized()
		var prev_out := Vector2(prev_dir.y,-prev_dir.x)
		var next_out := Vector2(next_dir.y,-next_dir.x)
		var seam_a := (outside+prev_out)/(1+outside.dot(prev_out))
		var seam_b := (outside+next_out)/(1+outside.dot(next_out))
		if i in [0,3,7,11,12]:
			prism([a-seam_a*0.21,b-seam_b*0.21,b+seam_b*0.21,a+seam_a*0.21],0,2.65,"granite_blocks")
			put("quay_fence",Vector3(centre.x,2.65,centre.y),Vector3(length-0.24,1.75,0.2),yaw)
		elif i in [1,5,10]:
			var gap := minf(8,length*0.6)
			var left := centre-along*gap/2
			var right := centre+along*gap/2
			prism([a-seam_a*0.25,left-outside*0.25,left+outside*0.25,a+seam_a*0.25],0,4.25,"mud_brick")
			prism([right-outside*0.25,b-seam_b*0.25,b+seam_b*0.25,right+outside*0.25],0,4.25,"mud_brick")
			put("freight_gate",Vector3(centre.x,0,centre.y),Vector3(gap,3.8,0.42),yaw)
		else:
			var depth := 2.4
			var footprint := [a,b,b+seam_b*depth,a+seam_a*depth]
			var height: float = {2: 6.6, 4: 9.4, 6: 6.2, 8: 7.8, 9: 5.8}.get(i, 6.4)
			var brick := i in [2, 6, 9]
			prism(footprint,0,height,"mud_brick" if brick else "limewash")
			_joined_walls([a+seam_a*0.02,b+seam_b*0.02],false,0.26,2.95,"limestone",0.3,{})
			_gable(a+seam_a*1.2,b+seam_b*1.2,3.1,height-0.02,1.3,"slate" if brick else "tile_terracotta")
			if length >= 12.0:
				_chimney((a+seam_a*1.2).lerp(b+seam_b*1.2,0.3),height+0.7,1.6,"mud_brick")
			_building_front(a,b,outside,height)
	layer("Ground plan")


func _lower() -> void:
	layer("Sublevel plate works")
	# A bent west passage and two branches feed a single processing hall.
	var outline := [Vector2(-46,-11),Vector2(-20,-11),Vector2(-20,-23),Vector2(-4,-23),Vector2(-4,-11),Vector2(6,-11),Vector2(6,-26),Vector2(34,-26),
		Vector2(34,-16),Vector2(18,-16),Vector2(18,-4),Vector2(38,-4),Vector2(38,22),
		Vector2(41,22),Vector2(41,33),Vector2(20,33),Vector2(20,20),Vector2(5,20),
		Vector2(5,-2),Vector2(-11,-2),Vector2(-11,-17),Vector2(-15,-17),Vector2(-15,-2),Vector2(-34,-2),Vector2(-34,12),Vector2(-46,12)]
	surface(outline,-5,0.8,"slate")
	# Open the west stair branch and the second B doorway in the original perimeter.
	var doors := {}
	for i in outline.size():
		if outline[i] == Vector2(-15,-2):
			doors[i] = [[12,17]]
		if outline[i] == Vector2(5,20):
			doors[i] = [[6,12]]
		if outline[i] == Vector2(18,-4):
			doors[i] = [[14.7,19.3]]
		if outline[i] == Vector2(-46,-11):
			doors[i] = [[0.9,9.6]]
	walls_around(outline,4.4,-5,"concrete",doors)
	var bypass := [Vector2(-32,-2),Vector2(-27,-2),Vector2(-27,3),Vector2(-9,3),
		Vector2(-9,8),Vector2(5,8),Vector2(5,14),Vector2(-15,14),Vector2(-15,9),Vector2(-32,9)]
	surface(bypass,-5,0.8,"concrete")
	_joined_walls([Vector2(-27,-1.7),bypass[2],bypass[3],bypass[4],Vector2(4.7,8)],false,4.4,-5,"mud_brick",0.6,{})
	_joined_walls([Vector2(4.7,14),bypass[7],bypass[8],bypass[9],Vector2(-32,-1.7)],false,4.4,-5,"mud_brick",0.6,{})
	area("Cable Passage",-26,-16,4,8,"",-5)
	lamp(Vector3(-23,-1.6,6),2,10)
	lamp(Vector3(-6,-1.6,11),2,10)
	
	
	put("stairs",Vector3(-40,-5,3.5),Vector3(6,5,13),180,{},"limestone")
	put("stairs",Vector3(22.5,-5,-21.5),Vector3(5,5,13),270,{},"steel_grating")
	put("ramp",Vector3(32.5,-5,28),Vector3(6,5,13),90,{},"concrete")
	_pump_stair()
	mass("wall",-45.7,-34.3,10,11.7,4.4,"concrete",-5)
	mass("wall",39.9,40.7,24,32,4.4,"concrete",-5)
	wall_line(Vector2(23,-3),Vector2(23,8),4.4,-5,"slate")
	for point: Vector2 in [Vector2(-26,-7),Vector2(-5,-7),Vector2(13,-18),Vector2(12,-2),Vector2(28,19)]:
		lamp(Vector3(point.x,-1.4,point.y),2.5,11,"a6d6ff")
	_plate_lab()


# Defenders' short way down from the east lane into the plate works, beside the flood pump.
func _pump_stair() -> void:
	put("stairs",Vector3(35,-5,-7.5),Vector3(4,5,13),0,{},"steel_grating")
	for x: float in [32.7,37.3]:
		wall_line(Vector2(x,-14.3),Vector2(x,-4.3),4.4,-5,"concrete")
		wall_line(Vector2(x,-14),Vector2(x,-1),1.1,0,"metal_dark",[],"wall",0.2)
	wall_line(Vector2(32.7,-1),Vector2(37.3,-1),1.1,0,"metal_dark",[],"wall",0.2)
	wall_line(Vector2(32.7,-14.3),Vector2(37.3,-14.3),4.4,-5,"concrete")
	lamp(Vector3(35,-1.6,-9),1.8,9,"a6d6ff")
	_sign("PUMP STAIR  /  PLATE WORKS",Vector3(35,1.1,-0.9),3.8,0.4,180)
	area("Pump Stair",33,37,-16,-13.6,"entrance_b")


func _fixtures() -> void:
	layer("Exchange fittings")
	layer("Exchange fittings")
	# The small iris instrument occupies the reading court inside the central dogleg.
	var hub := Vector2(3,4)
	var hex: Array = []
	var ring: Array = []
	for i in 6:
		var axis := Vector2.RIGHT.rotated(TAU*i/6.0)
		hex.append(hub+axis*1.15)
		ring.append(hub+axis*2.6)
		put("column",Vector3(hub.x+axis.x*2.6,0,hub.y+axis.y*2.6),Vector3(0.24,3.1,0.24))
	walls_around(ring,0.22,3.1,"brass")
	prism(hex,0,2.1,"slate")
	put("transit_scope",Vector3(3,2.1,4),Vector3(1.6,2.8,4),0)
	
	put("vehicle_cart",Vector3(-34,0,-6),Vector3.ZERO,-18)
	put("braced_crate",Vector3(-37,0,-8),Vector3(2,1.3,1.2))
	

	put("stone_bench",Vector3(-28,0,-24),Vector3(4,1,1))
	put("market_shelf",Vector3(-23,0,-23.4),Vector3(3,2,0.8))
	put("freight_gate",Vector3(-17,0,-24.3),Vector3(4.4,2.9,0.36),-2.3)
	_sign("CHRONOMETER EXCHANGE",Vector3(-17,3.0,-24.1),6.5,0.55,-2.3)
	put("freight_gate",Vector3(0,0,-9.38),Vector3(4,2.9,0.36),0)
	_sign("CHRONOMETER RETURNS",Vector3(0,3.0,-9.18),5,0.45)
	put("stone_bench",Vector3(2,0,-8.35),Vector3(4,0.9,1))
	put("freight_gate",Vector3(33,0,18.38),Vector3(5,2.9,0.36),0)
	_sign("GLASS PLATES  /  GOODS IN",Vector3(33,3.0,18.18),6,0.5,180)
	# The old public entrance is now a gauging room and a waiting bench on the quay.
	mass("building",-46,-38,-30,-25,4.1,"limewash")
	mass("roof",-46.3,-37.7,-30.3,-24.7,0.24,"slate",4.1)
	put("door",Vector3(-43.6,0,-24.85),Vector3(1.2,2.5,0.3),0,{"panels":2,"fanlight":true})
	put("window",Vector3(-40.4,0.9,-24.85),Vector3(1.8,1.5,0.3),0,{"panes_x":3,"panes_y":2})
	_sign("TIDE OFFICE   /   SOUNDINGS",Vector3(-42,3.12,-24.92),6.8,0.48)
	put("stone_bench",Vector3(-42,0,-22.9),Vector3(3.3,0.74,0.8))
	area("Tide Office",-46,-38,-24,-20)
	# Packed instruments await inspection at the gated dispatch yard.
	put("braced_crate",Vector3(48,0,12.8),Vector3(2.1,1.45,1.5),-7)
	put("vehicle_cart",Vector3(47.5,0,16),Vector3.ZERO,11)
	area("Weighbridge",44,49,11,17)
	area("Lens Delivery",-41,-33,-10,-5)
	for x: int in range(-12,6):
		mass("wall",x,x+0.09,-14.4,-14.06,0.1,"brass",-0.09)
	mass("wall",-13,6,-14.06,-13.94,0.1,"brass",-0.088)
	# A masonry clock house beyond the north wall carries the harbour's noon signal.
	mass("building", -35,-24,-45,-36,13,"mud_brick")
	mass("roof", -35.5,-23.5,-45.5,-35.5,0.5,"limestone",13)
	put("signal_ball",Vector3(-29.5,13.5,-40),Vector3(4.5,10,4.5))
	for x: int in [-33,-30,-27]:
		mass("wall",x-0.6,x+0.6,-36,-35.85,2.1,"slate",9)
	_sign("CLUTS  /  HARBOUR TIME SERVICE",Vector3(-29.5,6.6,-35.8),10,1.45)


func _sign(words: String, at: Vector3, width: float, height: float, yaw: float = 0) -> void:
	put("enamel_sign", at, Vector3(width,height,0.08), yaw, {"text": words})


func _shed_roof(origin: Vector3, size: Vector3, material: String) -> void:
	var vertices: Array = []
	for x: float in [0.0,size.x]:
		for yz: Vector2 in [Vector2.ZERO,Vector2(0,size.z),Vector2(size.y,size.z)]:
			vertices.append([origin.x+x,origin.y+yz.x,origin.z+yz.y])
	_convex_shell(vertices,[0,1,2,3,5,4,0,3,4,0,4,1,
		1,4,5,1,5,2,2,5,3,2,3,0],material)


func _harbour_basin() -> void:
	layer("Tidal basin")
	mass("block",-180,-48,-90,85,0.5,"water",-3.6)
	# One moored survey lighter gives the signal tower a visible audience.
	prism([Vector2(-74,-22),Vector2(-68,-16),Vector2(-68,12),Vector2(-71,17),
		Vector2(-78,17),Vector2(-81,12),Vector2(-81,-16)],-3.3,5.4,"metal_dark")
	mass("building",-79,-70,1,10,3.3,"limewash",2.1)
	mass("roof",-79.4,-69.6,0.6,10.4,0.32,"metal_painted",5.4)
	for z: int in [2,5,8]:
		mass("wall",-70,-69.9,z,z+1.6,1,"slate",3.8)
	put("column",Vector3(-75,2.1,-9),Vector3(0.45,13,0.45),0,{},"weathered_wood")
	put("banner",Vector3(-74.1,12,-9),Vector3(1.8,2,0.14),0,{},"cloth_striped")
	for z: int in [-17,-4,9,22,35]:
		put("column",Vector3(-49.5,-4,z),Vector3(1.1,7.8,1.1),0,{},"weathered_wood")


func _skyline() -> void:
	layer("Quayside buildings")
	# Neighbouring sail lofts rise beyond the enclosure. Each has north-facing roof lights.
	for x: int in [5,17,29]:
		mass("building",x,x+11.8,-50,-38,9,"mud_brick")
		_shed_roof(Vector3(x,9,-50),Vector3(11.8,3.4,12),"slate")
		for window: int in [2,5,8]:
			mass("wall",x+window,x+window+1.8,-38,-37.9,1.7,"metal_dark",6.8)
			mass("wall",x+window,x+window+1.8,-38,-37.9,1.25,"metal_painted",9.6)
	for z: int in [-15,1,17]:
		mass("building",56,64,z,z+14,8.3,"limewash")
		_shed_roof(Vector3(56,8.3,z),Vector3(8,2.5,14),"metal_rust")
		for offset: int in [2,5,8,11]:
			mass("wall",55.87,56,z+offset,z+offset+1.5,1.6,"slate",6.2)


func _plate_lab() -> void:
	layer("Plate washing and flood repairs")
	# Three baths progress along one feed pipe. Plates hang from the drying rail downstream.
	put("pipe_run",Vector3(12,-3.55,18.45),Vector3(12,0.16,0.16),0,{},"brass")
	for x: int in [7,11,15]:
		put("stone_trough",Vector3(x,-5,17.8),Vector3(3,0.95,1.45),0,{},"plaster_white")
		put("pipe_run",Vector3(x,-3.7,18.08),Vector3(0.95,0.12,0.12),90,{},"brass")
	put("market_shelf",Vector3(21,-5,17.8),Vector3(4,2.8,1.2),0,{},"metal_dark")
	for x: float in [19.7,20.15,20.6,21.05,21.95,22.4]:
		put("wall",Vector3(x,-3.4768,17.8),Vector3(0.06,0.80,0.75),-9,{},"slate")
	_sign("PLATE ROOM  /  WASH  01 - 03",Vector3(10,-2.75,18.63),6,0.58,180)
	_sign("DRY PLATES ONLY",Vector3(21,-2.65,17.14),3.6,0.4,180)
	# Flood-height witness strip and replacement pump at the intake.
	put("storage_tank",Vector3(36,-5,6),Vector3(2.1,2.7,2.1),0,{},"metal_painted")
	put("pipe_run",Vector3(36.8,-2.7,3),Vector3(5,0.34,0.34),90,{},"metal_rust")
	mass("wall",37.54,37.66,0,10,0.09,"brass",-2.85)
	_sign("HIGH WATER  /  NOV 1978",Vector3(37.49,-2.68,5),3.3,0.45,-90)
	lamp(Vector3(14,-2.4,16.7),1.6,7,"ff925c")
	area("Wash Baths",4,16,15,18,"",-5)
	area("Flood Pump",33,37,4,8,"",-5)




func _check(analysis: MapAnalysis) -> bool:
	# Test the three descents and Cable Passage directly so a long detour cannot mask a closed shaft.
	var routes := [
		[Vector3(-40,-5,-6),Vector3(-29,-5,5)],
		[Vector3(-29,-5,5),Vector3(-12,-5,10)],
		[Vector3(-12,-5,10),Vector3(7,-5,11)],
		[Vector3(-40,0,11.6), Vector3(-40,-5,-5)],
		[Vector3(31,0,-21), Vector3(14,-5,-21)],
		[Vector3(24,0,28), Vector3(39.4,-5,28)],
		[Vector3(35,0,-15), Vector3(35,-5,1)],
		[Vector3(30,0,32.5), Vector3(44,0,31)],
	]
	for route: Array in routes:
		var distance := analysis.path_length(route[0],route[1])
		print("Level access ",route[0]," -> ",route[1],": ",distance)
		if distance < 0 or distance > 26:
			return false
	return analysis.issues.is_empty()


## Pitched roof ridge along a wall top (a triangular prism with open gable ends).
func _gable(a: Vector2, b: Vector2, width: float, base: float, rise: float, material: String) -> void:
	var side := (b-a).normalized().orthogonal()*width*0.5
	var vertices: Array = []
	for pt: Vector2 in [a-side,b-side,b+side,a+side]:
		vertices.append([pt.x,base,pt.y])
	for pt: Vector2 in [a,b]:
		vertices.append([pt.x,base+rise,pt.y])
	_convex_shell(vertices,[0,1,2,0,2,3,0,1,5,0,5,4,3,2,5,3,5,4,0,3,4,1,2,5],material)


## A brick stack through a ridge, with a stone cap.
func _chimney(at: Vector2, base: float, height: float, material: String) -> void:
	prism([at+Vector2(-0.45,-0.45),at+Vector2(0.45,-0.45),at+Vector2(0.45,0.45),at+Vector2(-0.45,0.45)],
		base-0.8,height+0.8,material)
	prism([at+Vector2(-0.58,-0.58),at+Vector2(0.58,-0.58),at+Vector2(0.58,0.58),at+Vector2(-0.58,0.58)],
		base+height,0.18,"granite_blocks")


## The plate receiving house: its curved street wall is the building's outer face. A wide
## doorway on the quay side opens onto the West Shaft stair; a side door leads to a packing room
## with a view down the stairwell.
func _receiving_house() -> void:
	layer("Plate receiving house")
	var curve: Array = []
	for pt: Vector2 in [Vector2(21,273),Vector2(52,249),Vector2(79,248),Vector2(109,272),Vector2(131,310),Vector2(138,354)]:
		curve.append(_plan(pt.x,pt.y))
	var front_z: float = (curve[5] as Vector2).y
	var east_end: float = (curve[5] as Vector2).x
	var house: Array = curve.duplicate()
	house[0] = Vector2(-45.85,(curve[0] as Vector2).y)
	house.append(Vector2(-45.85,front_z))
	# Front doorways in metres from the east corner: the packing-room door and the stair (6.4 m).
	var side_door := [east_end+32.0, east_end+34.2]
	var stair_door := [east_end+36.8, east_end+43.2]
	_joined_walls(house,true,7.2,0,"limestone",0.65,{5:[side_door,stair_door]})
	for door: Array in [[side_door,2.6],[stair_door,3.6]]:
		var span: Array = door[0]
		var from := Vector2(east_end-float(span[0])+0.1,front_z)
		var to := Vector2(east_end-float(span[1])-0.1,front_z)
		wall_line(from,to,7.2-float(door[1]),float(door[1]),"limestone",[],"wall",0.64)
	_joined_walls(house,true,0.26,3.45,"granite_blocks",0.82,{})
	var eaves: Array = []
	for ring: PackedVector2Array in Geometry2D.offset_polygon(PackedVector2Array(house),0.45):
		for v: Vector2 in ring:
			eaves.append(v)
		break
	prism(eaves,7.15,0.4,"slate")
	_joined_walls([curve[5],_plan(160,354)],false,4.45,0,"limestone",0.65,{})
	# Upper windows face the curved lane and the quay.
	for i in curve.size()-1:
		var a: Vector2 = curve[i]
		var b: Vector2 = curve[i+1]
		var along := (b-a).normalized()
		var p: Vector2 = a.lerp(b,0.5)+along.orthogonal()*0.475
		var facing := rad_to_deg(atan2(-along.y,along.x))+180.0
		put("window",Vector3(p.x,4.2,p.y),Vector3(1.2,1.7,0.3),facing,{"panes_x":2,"panes_y":3})
		if a.distance_to(b) > 4.5:
			put("window",Vector3(p.x,1.0,p.y),Vector3(1.2,1.5,0.3),facing,{"panes_x":2,"panes_y":2,"shutters":true})
	for x: float in [-44.4,-34.6,-31.0]:
		put("window",Vector3(x,4.2,front_z+0.475),Vector3(1.2,1.7,0.3),0,{"panes_x":2,"panes_y":3})
	_sign("PLATE RECEIVING",Vector3(-40,4.15,front_z+0.37),5.4,0.6)
	_sign("PACKING",Vector3(-33.1,2.85,front_z+0.37),2.0,0.4)
	_sign("DARKROOM   /   LOWER LEVEL",Vector3(-40,2.9,-3.95),5.1,0.4)
	lamp(Vector3(-40,5.6,4),1.8,10,"ffd09b")
	lamp(Vector3(-33.5,3.2,3),1.4,8,"ffd09b")
	# A stone bench fills the strip between the stairwell and the quay wall.
	mass("wall",-45.55,-43.0,-0.9,10.05,1.0,"granite_blocks")
	# Packing room: a rail along the stairwell, shelves and boxed plates.
	wall_line(Vector2(-36.85,-2.6),Vector2(-36.85,5.5),1.05,0,"metal_dark",[],"wall",0.12)
	put("market_shelf",Vector3(-31.95,0,3.58),Vector3(3,2.2,0.7),-60.5)
	put("braced_crate",Vector3(-35.4,0,0.6),Vector3(1.6,1.1,1.1),12)
	put("crate_stack",Vector3(-32.4,0,7.6),Vector3(2.2,2.2,1.1),90)
	area("Packing Room",-36.5,-31.5,0,9.5)
	area("Receiving House",-43,-37,8,11)
	layer("Ground plan")


## The tide office's gauge well: an open shaft in the yard drops 5 m into the gauge chamber,
## which joins the plate works beside the West Shaft stair.
func _tide_well() -> void:
	layer("Tide well")
	for wall: Array in [[Vector2(-44.1,-16),Vector2(-44.1,-20.1)],[Vector2(-44.1,-20.1),Vector2(-39.9,-20.1)],[Vector2(-39.9,-20.1),Vector2(-39.9,-16)]]:
		wall_line(wall[0],wall[1],0.85,0,"granite_blocks",[],"wall",0.25)
	put("pipe_run",Vector3(-42,0.85,-20.1),Vector3(4.6,0.18,0.18),0,{},"brass")
	_sign("TIDE WELL  /  KEEP CLEAR",Vector3(-42,0.9,-19.95),3.6,0.45)
	surface([Vector2(-46,-24.5),Vector2(-35.5,-24.5),Vector2(-35.5,-11),Vector2(-46,-11)],-5,0.8,"granite_blocks")
	wall_line(Vector2(-46.1,-11.4),Vector2(-46.1,-24.5),4.4,-5,"granite_blocks")
	wall_line(Vector2(-46.1,-24.6),Vector2(-35.5,-24.6),4.4,-5,"granite_blocks")
	wall_line(Vector2(-35.4,-24.5),Vector2(-35.4,-11.4),4.4,-5,"granite_blocks")
	put("storage_tank",Vector3(-37.6,-5,-22.4),Vector3(2.2,3.2,2.2),0,{},"metal_painted")
	put("pipe_run",Vector3(-41,-1.8,-23.95),Vector3(5,0.3,0.3),0,{},"metal_rust")
	put("stone_trough",Vector3(-44.6,-5,-14),Vector3(1.2,0.9,3),90,{},"granite_blocks")
	mass("wall",-45.8,-35.7,-24.3,-24.2,0.1,"brass",-2.0)
	lamp(Vector3(-41,-1.8,-15),1.8,9,"a6d6ff")
	area("Gauge Chamber",-45.5,-36,-24,-11.5,"",-5)
	layer("Ground plan")


## Level changes that make the streets read as a working place: a raised terrace along the
## south hall and a loading dock in the dispatch yard.
func _raised_ground() -> void:
	layer("Terraces and docks")
	put("platform",Vector3(6,0,24.05),Vector3(16,1.4,3.1),0,{},"granite_blocks")
	put("stairs",Vector3(-3.9,0,24.05),Vector3(3.1,1.4,3.8),270,{},"granite_blocks")
	put("stairs",Vector3(15.9,0,24.05),Vector3(3.1,1.4,3.8),90,{},"granite_blocks")
	for x: float in [1.0,6.0,11.0]:
		put("railing",Vector3(x,1.4,22.55),Vector3(3.2,1.0,0.08))
	put("crate_stack",Vector3(9.2,1.4,24.7),Vector3(2.2,2.2,1.1))
	put("barrel_cluster",Vector3(2.4,1.4,24.8),Vector3(1.5,1.0,1.2))
	put("awning",Vector3(6,1.4,24.6),Vector3(5,2.6,2.2),180)
	area("Exchange Terrace",-2,14,22.5,25.6,"",1.4)
	put("platform",Vector3(48.25,0,33.525),Vector3(8.5,1.2,2.45),0,{},"concrete")
	put("stairs",Vector3(42.6,0,33.525),Vector3(2.45,1.2,3.0),270,{},"steel_grating")
	put("crate_stack",Vector3(50.8,1.2,34.15),Vector3(2.2,2.2,1.0))
	put("barrel_cluster",Vector3(46.4,1.2,34.2),Vector3(1.5,1.0,0.95))
	area("Loading Dock",44,52.5,32.5,34.6,"",1.2)
	layer("Ground plan")


## A yard wall along a traced line: body, plinth and coping drawn as mitred runs, with piers at
## every corner, at least every 5 m and either side of each gateway. [param family]: "brick" or
## "granite" (quay walls). Corners listed in [param bare] get no pier (tight openings).
func _yard_wall(points: Array, height: float, family: String, gaps: Dictionary = {}, bare: Array = []) -> void:
	var corners: Array = []
	for pt: Vector2 in points:
		corners.append(_plan(pt.x,pt.y))
	var body := "mud_brick" if family == "brick" else "granite_blocks"
	_joined_walls(corners,false,height,0,body,0.65,gaps)
	_joined_walls(corners,false,0.24,height-0.04,"limestone" if family == "brick" else "granite_blocks",0.84,gaps)
	if family == "brick":
		_joined_walls(corners,false,0.5,0,"granite_blocks",0.73,gaps)
	for i in corners.size():
		var at: Vector2 = corners[i]
		var before: Vector2 = (at-Vector2(corners[maxi(i-1,0)])).normalized() if i > 0 else Vector2.ZERO
		var after: Vector2 = (Vector2(corners[mini(i+1,corners.size()-1)])-at).normalized() if i < corners.size()-1 else Vector2.ZERO
		var dir := (before+after).normalized()
		if not bare.has(i):
			_pier(at,dir,height,body)
		if i == corners.size()-1:
			break
		var b: Vector2 = corners[i+1]
		var length := at.distance_to(b)
		var along := (b-at)/length
		var spans: Array = gaps.get(i,[])
		var count := ceili(length/5.0)
		for k in range(1,count):
			var t := length*k/count
			var clear := true
			for gap: Array in spans:
				if t > float(gap[0])-1.0 and t < float(gap[1])+1.0:
					clear = false
			if clear:
				_pier(at+along*t,along,height,body)
		for gap: Array in spans:
			for t: float in [float(gap[0])-0.45,float(gap[1])+0.45]:
				if t > 0.6 and t < length-0.6:
					_pier(at+along*t,along,height,body)


func _pier(at: Vector2, along: Vector2, height: float, material: String) -> void:
	put("wall_pier",Vector3(at.x,0,at.y),Vector3(0.9,height+0.45,0.9),rad_to_deg(atan2(-along.y,along.x)),{},material)


## Windows on each storey of a perimeter building's street face, with a door every third bay at
## street level. [param outside] points away from the playable side.
func _building_front(a: Vector2, b: Vector2, outside: Vector2, height: float) -> void:
	var length := a.distance_to(b)
	var along := (b-a)/length
	var yaw := rad_to_deg(atan2(-along.y,along.x))
	var bays := maxi(1,floori(length/3.6))
	var storeys := clampi(floori(height/2.95),1,3)
	for j in bays:
		var spot: Vector2 = a+along*(j+0.5)*length/bays-outside*0.15
		for storey in storeys:
			if storey == 0 and j % 3 == 1:
				put("door",Vector3(spot.x,0,spot.y),Vector3(1.2,2.5,0.3),yaw,{"panels":2,"fanlight":true})
			else:
				var sill := 0.9 if storey == 0 else 3.4+(storey-1)*2.95
				put("window",Vector3(spot.x,sill,spot.y),Vector3(1.15,1.6,0.3),yaw,{"panes_x":2,"panes_y":3})
