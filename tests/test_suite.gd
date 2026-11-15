class_name TestSuite
extends RefCounted
## Base class for headless test suites run by tests/run_tests.gd.
## Subclasses implement [method run] as a coroutine and call [method check].

var tree: SceneTree
var passed: int = 0
var failed: int = 0


func suite_name() -> String:
	return "Unnamed suite"


## Override. May await.
func run() -> void:
	pass


func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", description)
	else:
		failed += 1
		printerr("  FAIL  ", description)


func section(title: String) -> void:
	print("[%s]" % title)


func wait_frames(count: int) -> void:
	for i: int in count:
		await tree.process_frame


func wait_physics_frames(count: int) -> void:
	for i: int in count:
		await tree.physics_frame


## Waits until [param condition] returns true or [param timeout_sec] elapses (real time).
## Returns whether the condition became true.
func wait_until(condition: Callable, timeout_sec: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await tree.process_frame
	return bool(condition.call())


## Waits a fixed amount of real time (lets network traffic flow).
func wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame


func spawn_scene(path: String) -> Node:
	var packed := load(path) as PackedScene
	check(packed != null, "scene loads: %s" % path)
	if packed == null:
		return null
	var instance := packed.instantiate()
	check(instance != null, "scene instantiates: %s" % path)
	tree.root.add_child(instance)
	return instance


func despawn(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await tree.process_frame
