extends SceneTree
## Bakes the simulation graph ([SimGraphBuilder]) of every official map into
## res://data/maps/sim/<map_id>.json, the data the career match engine plays rounds on.
## Re-run after editing an official map (the graph records the map's content hash, and a test
## fails when a baked graph is out of date). The Creation Studio bakes through the same
## [method SimGraphBuilder.bake_to] (on save, and with its "Bake sim graph" button).
##
## A local map can be baked too; its graph goes to user://maps/sim/ (never into the project):
##   <godot> --headless --path <project> --script res://tools/bake_sim_maps.gd -- --map=user://maps/<id>.f2fmap.json


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var local := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):
			local = argument.substr(6)
	var jobs: Array[Array] = []
	if local.is_empty():
		for map_id: String in OfficialMaps.ids():
			jobs.append([OfficialMaps.load_map(map_id), SimMap.OFFICIAL_DIR])
	else:
		jobs.append([MapStorage.new().load_path(local), SimMap.LOCAL_DIR])
	var failed := 0
	for job: Array in jobs:
		var doc := job[0] as MapDocument
		if doc == null:
			print("could not load a map")
			failed += 1
			continue
		var baked := SimGraphBuilder.bake_to(doc, root, str(job[1]))
		if not bool(baked["ok"]):
			print("%s: %s" % [doc.map_id, baked["error"]])
			failed += 1
			continue
		print("%s: %d places, %d connections" % [doc.map_id, int(baked["places"]), int(baked["connections"])])
	quit(1 if failed > 0 else 0)
