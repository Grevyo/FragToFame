extends Node
## Application-level state and top-level scene routing. Autoloaded as "App".
##
## Every top-level scene change goes through [method go_to] so that cross-cutting concerns
## (mouse mode, future save prompts, network teardown) live in one place.

signal scene_changed(scene_id: StringName)

const VERSION: String = "0.1.0"
const MILESTONE: String = "Milestone 9 — Player & Team Database"

const SCENE_MAIN_MENU: StringName = &"main_menu"
const SCENE_CAREER_HUB: StringName = &"career_hub"
const SCENE_FPS_SANDBOX: StringName = &"fps_sandbox"
const SCENE_CREATION_STUDIO: StringName = &"creation_studio"
const SCENE_CAREER_SELECT: StringName = &"career_select"

const SCENE_PATHS: Dictionary[StringName, String] = {
	SCENE_MAIN_MENU: "res://scenes/main_menu/main_menu.tscn",
	SCENE_CAREER_HUB: "res://scenes/career_hub/career_hub.tscn",
	SCENE_FPS_SANDBOX: "res://scenes/fps_sandbox/fps_sandbox.tscn",
	SCENE_CREATION_STUDIO: "res://scenes/creation_studio/creation_studio.tscn",
	SCENE_CAREER_SELECT: "res://scenes/career_select/career_select.tscn",
}

var current_scene_id: StringName = SCENE_MAIN_MENU
## Map to load in the FPS runtime instead of the default sandbox arena (set by the editor).
var playtest_map: MapDocument = null
## Editor state preserved across a playtest so unsaved work is not lost. Consumed by the studio.
var editor_session: Dictionary = {}
## Match the FPS runtime should run when it next loads (consumed by the runtime).
var pending_match_setup: MatchSetup = null
var pending_match_rules: MatchRules = null
var pending_match_map: MapDocument = null
## Runtime options for the pending match, e.g. {"opponents": "bots", "skill": "normal"}.
var pending_match_options: Dictionary = {}
## The most recent match outcome produced by the FPS runtime (not yet submitted anywhere).
var last_match_result: MatchResult = null
## The open career (null when none is loaded). Career data stays inside its repository.
var career: CareerSession = null
var career_saves := CareerSaves.new()


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


# --- Career ----------------------------------------------------------------------------------

## Main-menu entry: the hub if a career is open, otherwise the career select screen.
func open_career_hub() -> Error:
	return go_to(SCENE_CAREER_HUB if has_career() else SCENE_CAREER_SELECT)


func has_career() -> bool:
	return career != null and career.is_ok()


## Opens a saved career and makes it current. Returns "" or an error message.
func load_career(save_id: String) -> String:
	close_career()
	var session := career_saves.open_career(save_id)
	if not session.is_ok():
		return session.error
	career = session
	return ""


## Generates a new career world and makes it current. Returns "" or an error message.
func new_career(save_name: String, world_seed: int, human_profile: Dictionary) -> String:
	close_career()
	var session := career_saves.create_career(save_name, world_seed, human_profile)
	if not session.is_ok():
		return session.error
	career = session
	return ""


func close_career() -> void:
	if career != null:
		career.close()
	career = null


## Practice match against an organisation of the open career (bots use the players' abilities).
func start_practice_against(org_id: String) -> Error:
	if not has_career():
		return ERR_UNCONFIGURED
	var map := MapTemplates.sandbox_arena()
	var setup := CareerMatches.practice_setup(career.repo, career.human_player_id, org_id, map.map_id)
	if setup == null:
		return ERR_DOES_NOT_EXIST
	return start_match(setup, MatchRules.practice(setup.max_rounds), map, {"opponents": "bots"})


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


## Starts a local practice match (MR3, 5v5 with bot teammates and opponents) on [param doc], or the sandbox arena.
func start_practice_match(doc: MapDocument = null, skill: StringName = &"normal") -> Error:
	var map := doc if doc != null else MapTemplates.sandbox_arena()
	var setup := MatchSetup.new()
	setup.fixture_id = Ids.generate("practice")
	setup.competition = "Practice"
	setup.home_team_id = "team_practice_player"
	setup.home_team_name = "You"
	setup.away_team_id = "team_practice_bots"
	setup.away_team_name = "Practice Bots"
	setup.max_rounds = 3
	setup.map_id = map.map_id
	return start_match(setup, MatchRules.practice(setup.max_rounds), map, {"opponents": "bots", "skill": String(skill)})


## Opens the FPS runtime to play [param setup] under [param rules] on [param map].
func start_match(setup: MatchSetup, rules: MatchRules, map: MapDocument, options: Dictionary = {}) -> Error:
	pending_match_options = options
	pending_match_setup = setup
	pending_match_rules = rules
	pending_match_map = map
	playtest_map = null
	return go_to(SCENE_FPS_SANDBOX)


func has_pending_match() -> bool:
	return pending_match_setup != null


## Hands the pending match to the runtime exactly once: [setup, rules, map, options].
func consume_pending_match() -> Array:
	var match_data: Array = [pending_match_setup, pending_match_rules, pending_match_map, pending_match_options]
	pending_match_setup = null
	pending_match_rules = null
	pending_match_map = null
	pending_match_options = {}
	return match_data


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		close_career()


func quit_game() -> void:
	get_tree().quit()
