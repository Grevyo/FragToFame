extends TestSuite
## Simulation maps (Milestone 21 stage A): the graph of places, connections and walking distances
## the career match engine plays rounds on, baked from each official map's navmesh.


func suite_name() -> String:
	return "Simulation maps"


func run() -> void:
	_test_format()
	_test_official_graphs()
	_test_bake_matches()


func _test_format() -> void:
	section("Graph format")
	check(SimMap.from_json("{}") == null and SimMap.from_json("not json") == null
		and SimMap.from_json(JSON.stringify({"format": SimMap.FORMAT, "format_version": 99, "nodes": [{"id": "a"}]})) == null,
		"anything but a current simulation graph is refused")
	var tiny := SimMap.from_json(JSON.stringify({"format": SimMap.FORMAT, "format_version": SimMap.FORMAT_VERSION, "map_id": "m",
		"nodes": [{"id": "spawn_attack", "kind": "spawn", "centre": [0, 0, 0]}, {"id": "mid", "kind": "area", "centre": [0, 0, 10]},
			{"id": "site_A", "kind": "site", "site": "A", "centre": [0, 0, 20]}],
		"edges": [["mid", "site_A", 10.0], ["mid", "spawn_attack", 10.0]],
		"distances": {"spawn_attack": {"site_A": 20.0}}}))
	check(tiny != null and tiny.route("spawn_attack", "site_A") == ["spawn_attack", "mid", "site_A"] and tiny.is_fully_connected()
		and tiny.entrances("site_A") == ["mid"] and is_equal_approx(tiny.seconds("spawn_attack", "site_A", 5.0), 4.0),
		"routes, entrances and walking times come from the graph")


func _test_official_graphs() -> void:
	section("Official maps")
	SimMap.clear_cache()
	for map_id: String in OfficialMaps.ids():
		var doc := OfficialMaps.load_map(map_id)
		var graph := SimMap.for_map(map_id)
		if graph == null or doc == null:
			check(false, "%s has a baked simulation graph (run tools/bake_sim_maps.gd)" % map_id)
			continue
		check(graph.content_hash == doc.content_hash, "%s: the graph matches the current map (re-bake after editing it)" % map_id)
		var sites := graph.sites()
		var attack := graph.spawn("attack")
		var defence := graph.spawn("defence")
		var timings_ok := not attack.is_empty() and not defence.is_empty() and sites.size() >= 2
		var notes: Array[String] = []
		for site: String in sites:
			var from_attack := graph.distance(attack, site)
			var from_defence := graph.distance(defence, site)
			var walk := graph.route(attack, site)
			if from_attack < 30.0 or from_attack > 220.0 or from_defence < 10.0 or from_defence >= from_attack \
					or graph.entrances(site).is_empty() or walk.is_empty() or walk[0] != attack or walk.back() != site:
				timings_ok = false
				notes.append("%s T %.0f m, CT %.0f m, %d entrances" % [site, from_attack, from_defence, graph.entrances(site).size()])
		check(timings_ok, "%s: both spawns and two sites; defenders reach each site first; attackers walk a real route to it %s"
			% [map_id, notes])
		var reachable := true
		for a: String in graph.nodes:
			for b: String in graph.nodes:
				reachable = reachable and graph.distance(a, b) >= 0.0
		check(graph.is_fully_connected() and reachable, "%s: every place connects to every other (%d places)" % [map_id, graph.nodes.size()])


func _test_bake_matches() -> void:
	section("Baking")
	var doc := OfficialMaps.load_map(OfficialMaps.DEFAULT_ID)
	var host := Node3D.new()
	tree.root.add_child(host)
	var fresh := SimGraphBuilder.build(doc, host)
	host.free()
	var baked := SimMap.for_map(OfficialMaps.DEFAULT_ID)
	var made := SimMap.from_json(JSON.stringify(fresh))
	check(made != null and baked != null and made.nodes.size() == baked.nodes.size() and made.links.size() == baked.links.size()
		and made.route(made.spawn("attack"), "site_A") == baked.route(baked.spawn("attack"), "site_A"),
		"baking the default map again gives the stored graph")
