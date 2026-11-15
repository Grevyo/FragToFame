extends Node
## Application-level state and top-level scene routing. Autoloaded as "App".
##
## Every top-level scene change goes through [method go_to] so that cross-cutting concerns
## (mouse mode, future save prompts, network teardown) live in one place.

signal scene_changed(scene_id: StringName)

const VERSION: String = "0.1.0"
const MILESTONE: String = "Milestone 1 — Application Foundation"

const SCENE_MAIN_MENU: StringName = &"main_menu"
const SCENE_CAREER_HUB: StringName = &"career_hub"
const SCENE_FPS_SANDBOX: StringName = &"fps_sandbox"
const SCENE_CREATION_STUDIO: StringName = &"creation_studio"

const SCENE_PATHS: Dictionary[StringName, String] = {
	SCENE_MAIN_MENU: "res://scenes/main_menu/main_menu.tscn",
	SCENE_CAREER_HUB: "res://scenes/career_hub/career_hub.tscn",
	SCENE_FPS_SANDBOX: "res://scenes/fps_sandbox/fps_sandbox.tscn",
	SCENE_CREATION_STUDIO: "res://scenes/creation_studio/creation_studio.tscn",
}

var current_scene_id: StringName = SCENE_MAIN_MENU
## Map to load in the FPS runtime instead of the default sandbox arena (set by the editor).
var playtest_map: MapDocument = null
## Editor state preserved across a playtest so unsaved work is not lost. Consumed by the studio.
var editor_session: Dictionary = {}


func _ready() -> void:
	InputActions.register_defaults()
	var theme := F2FTheme.build()
	get_tree().root.theme = theme
	# Controls under a CanvasLayer do not inherit the Window theme; they fall back to the default
	# theme. Merging ours into it makes HUDs and editor overlays use the same styling.
	ThemeDB.get_default_theme().merge_with(theme)


## Switches the active top-level scene. Returns OK, or an error if the ID is unknown or loading fails.
func go_to(scene_id: StringName) -> Error:
	if not SCENE_PATHS.has(scene_id):
		push_error("App.go_to: unknown scene id '%s'" % scene_id)
		return ERR_DOES_NOT_EXIST
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var err: Error = get_tree().change_scene_to_file(SCENE_PATHS[scene_id])
	if err != OK:
		push_error("App.go_to: failed to load '%s' (error %d)" % [SCENE_PATHS[scene_id], err])
		return err
	current_scene_id = scene_id
	scene_changed.emit(scene_id)
	return OK


## Opens the FPS runtime on [param doc]; [param session] is restored when the editor reopens.
func start_playtest(doc: MapDocument, session: Dictionary) -> Error:
	playtest_map = doc
	editor_session = session
	return go_to(SCENE_FPS_SANDBOX)


func is_playtesting() -> bool:
	return playtest_map != null


func end_playtest() -> Error:
	playtest_map = null
	return go_to(SCENE_CREATION_STUDIO)


func quit_game() -> void:
	get_tree().quit()
