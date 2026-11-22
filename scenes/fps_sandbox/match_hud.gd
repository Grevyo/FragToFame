class_name MatchHud
extends CanvasLayer
## Competitive match overlay: scoreboard + clock, money, announcements, plant/defuse progress,
## context hints, buy menu and the match-end screen. Displays state; owns no rules.

signal item_chosen(item_id: StringName)
## A knife look picked in the FPS Sandbox shop's knife column (see [method show_knives]).
signal knife_chosen(model_id: StringName)
signal buy_menu_closed
signal main_menu_requested
signal play_again_requested

var practice_shop_only: bool = false
var buy_panel: Control
var end_panel: Control
var main_menu_button: Button
var play_again_button: Button

var _home_label: Label
var _away_label: Label
var _clock_label: Label
var _round_label: Label
var _money_label: Label
var _banner: Label
var _banner_left: float = 0.0
var _progress_box: Control
var _progress_label: Label
var _progress_bar: ProgressBar
var _hint_label: Label
var _notice: Label
var _buy_list: VBoxContainer
var _buy_money: Label
var _buy_message: Label
## FPS Sandbox only: the knife column beside the shop (null in matches).
var _knife_list: VBoxContainer
var _end_title: Label
var _end_detail: Label
## The team-call menu (IGL) and the last call made for the player's team.
var _call_menu: PanelContainer
var _call_list: Label
var _call_label: Label
var _call_left: float = 0.0


func _ready() -> void:
	layer = 2
	if practice_shop_only:
		_build_buy_panel()
		return
	_build_scoreboard()
	_build_money()
	_build_center()
	_build_calls()
	_build_buy_panel()
	_build_end_panel()


func _process(delta: float) -> void:
	if _banner_left > 0.0:
		_banner_left -= delta
		_banner.visible = _banner_left > 0.0
	if _call_left > 0.0:
		_call_left -= delta
		_call_label.visible = _call_left > 0.0


## Opens the team-call menu with one line per call (numbered from 1).
func show_call_menu(lines: Array[String]) -> void:
	var numbered: Array[String] = []
	for index: int in lines.size():
		numbered.append("%d  %s" % [index + 1, lines[index]])
	_call_list.text = "\n".join(numbered)
	_call_menu.visible = true


func hide_call_menu() -> void:
	_call_menu.visible = false


func is_call_menu_open() -> bool:
	return _call_menu != null and _call_menu.visible


func call_menu_text() -> String:
	return _call_list.text if is_call_menu_open() else ""


## Shows a call made for the player's team for a few seconds.
func show_call(text: String, seconds: float = 4.0) -> void:
	_call_label.text = text
	_call_label.visible = true
	_call_left = seconds


func call_text() -> String:
	return _call_label.text if _call_label.visible else ""


func set_scoreboard(home: String, home_score: int, home_side: StringName, away: String,
		away_score: int, away_side: StringName, round_text: String) -> void:
	_home_label.text = "%s  [%s]   %d" % [home, _side_tag(home_side), home_score]
	_away_label.text = "%d   [%s]  %s" % [away_score, _side_tag(away_side), away]
	_round_label.text = round_text


## Shows the round clock, or the bomb timer in red when [param bomb] is true.
func set_clock(seconds: float, bomb: bool, phase_text: String) -> void:
	var s := maxi(ceili(seconds), 0)
	_clock_label.text = "%s  %d:%02d" % [phase_text, floori(s / 60.0), s % 60]
	_clock_label.theme_type_variation = &"WarningLabel" if bomb else &"StatValueLabel"


func set_money(amount: int) -> void:
	_money_label.text = "$ %d" % amount


func show_banner(text: String, seconds: float = 3.0) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_left = seconds


func banner_text() -> String:
	return _banner.text if _banner.visible else ""


## Plant/defuse progress; [param fraction] < 0 hides it.
func set_progress(label_text: String, fraction: float) -> void:
	_progress_box.visible = fraction >= 0.0
	_progress_label.text = label_text
	_progress_bar.value = clampf(fraction, 0.0, 1.0)


func set_notice(text: String) -> void:
	_notice.text = text


func notice_text() -> String:
	return _notice.text


func set_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = not text.is_empty()


func hint_text() -> String:
	return _hint_label.text if _hint_label.visible else ""


## Opens (or refreshes) the buy menu. Entries: {id, name, price, enabled, note}.
func show_buy_menu(entries: Array[Dictionary], money: int, message: String = "") -> void:
	for child: Node in _buy_list.get_children():
		_buy_list.remove_child(child)
		child.queue_free()
	for entry: Dictionary in entries:
		var row := UIFactory.hbox(10)
		var label := str(entry["name"]) if practice_shop_only else "%s   $%d" % [entry["name"], entry["price"]]
		var b := UIFactory.button(label)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not bool(entry["enabled"])
		var id: StringName = entry["id"]
		b.pressed.connect(func() -> void: item_chosen.emit(id))
		row.add_child(b)
		var note := UIFactory.label(str(entry.get("note", "")), &"MutedLabel")
		note.custom_minimum_size.x = 120
		row.add_child(note)
		_buy_list.add_child(row)
	_buy_money.text = "Free equipment" if practice_shop_only else "Money: $%d" % money
	_buy_message.text = message
	buy_panel.visible = true


## FPS Sandbox only: fills the knife column, one button per knife look, the carried one marked.
func show_knives(ids: Array[StringName], carried: StringName) -> void:
	if _knife_list == null:
		return
	for child: Node in _knife_list.get_children():
		_knife_list.remove_child(child)
		child.queue_free()
	for id: StringName in ids:
		var button := UIFactory.button(WeaponModels.display_name(id) + ("  ✓" if id == carried else ""))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = id == carried
		button.pressed.connect(func() -> void: knife_chosen.emit(id))
		_knife_list.add_child(button)


func knife_buttons() -> Array[Button]:
	var list: Array[Button] = []
	if _knife_list != null:
		for node: Node in _knife_list.get_children():
			list.append(node as Button)
	return list


func hide_buy_menu() -> void:
	buy_panel.visible = false


func is_buy_menu_open() -> bool:
	return buy_panel.visible


func buy_buttons() -> Array[Button]:
	var list: Array[Button] = []
	for node: Node in _buy_list.find_children("*", "Button", true, false):
		list.append(node as Button)
	return list


func show_match_end(title: String, detail: String) -> void:
	_end_title.text = title
	_end_detail.text = detail
	end_panel.visible = true
	buy_panel.visible = false
	var focused := play_again_button if play_again_button.visible else main_menu_button
	focused.grab_focus.call_deferred()


func set_career_fixture(active: bool) -> void:
	play_again_button.visible = not active
	if active:
		main_menu_button.text = "Return to Career Hub"


func set_result_message(message: String) -> void:
	if not message.is_empty():
		_end_detail.text += "\n" + message


static func _side_tag(side: StringName) -> String:
	return "ATT" if side == MatchRules.SIDE_ATTACK else "DEF"


func _build_scoreboard() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -270
	panel.offset_right = 270
	panel.offset_top = 12
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UIFactory.vbox(2)
	var row := UIFactory.hbox(18)
	_home_label = UIFactory.label("", &"CardTitleLabel")
	_home_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_home_label)
	_clock_label = UIFactory.label("", &"StatValueLabel")
	_clock_label.custom_minimum_size.x = 150
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_clock_label)
	_away_label = UIFactory.label("", &"CardTitleLabel")
	_away_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_away_label)
	column.add_child(row)
	_round_label = UIFactory.label("", &"MutedLabel")
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_round_label)
	_notice = UIFactory.label("PRACTICE", &"WarningLabel")
	var notice := _notice
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(notice)
	panel.add_child(column)
	add_child(panel)


func _build_money() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -260
	panel.offset_right = -16
	panel.offset_top = -150
	panel.offset_bottom = -104
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_money_label = UIFactory.label("$ 0", &"AccentLabel")
	panel.add_child(_money_label)
	add_child(panel)


func _build_center() -> void:
	_banner = UIFactory.label("", &"HeaderLabel", true)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -500
	_banner.offset_right = 500
	_banner.offset_top = 150
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)

	_progress_box = UIFactory.vbox(4)
	_progress_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_progress_box.offset_left = -160
	_progress_box.offset_right = 160
	_progress_box.offset_top = 80
	_progress_box.offset_bottom = 130
	_progress_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_label = UIFactory.label("", &"CardTitleLabel")
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_box.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size.y = 10
	_progress_box.add_child(_progress_bar)
	_progress_box.visible = false
	add_child(_progress_box)

	_hint_label = UIFactory.label("", &"AccentLabel")
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hint_label.offset_left = -300
	_hint_label.offset_right = 300
	_hint_label.offset_top = 40
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = false
	add_child(_hint_label)


func _build_calls() -> void:
	_call_label = UIFactory.label("", &"AccentLabel")
	_call_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_call_label.offset_left = 24
	_call_label.offset_right = 520
	_call_label.offset_top = -120
	_call_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_call_label.visible = false
	add_child(_call_label)
	_call_menu = PanelContainer.new()
	_call_menu.theme_type_variation = &"OverlayPanel"
	_call_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_call_menu.offset_left = 24
	_call_menu.offset_top = -80
	_call_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UIFactory.vbox(6)
	column.custom_minimum_size.x = 220
	_call_menu.add_child(column)
	column.add_child(UIFactory.label("TEAM CALL", &"CardTitleLabel"))
	_call_list = UIFactory.label("", &"")
	column.add_child(_call_list)
	column.add_child(UIFactory.label("Number to call · Z or Esc to close", &"MutedLabel"))
	_call_menu.visible = false
	add_child(_call_menu)


func _build_buy_panel() -> void:
	buy_panel = CenterContainer.new()
	buy_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := UIFactory.hbox(12)
	buy_panel.add_child(row)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"OverlayPanel"
	row.add_child(panel)
	var column := UIFactory.vbox(10)
	column.custom_minimum_size.x = 460
	panel.add_child(column)
	if practice_shop_only:
		row.add_child(_build_knife_column())
	column.add_child(UIFactory.label("BUY", &"HeaderLabel"))
	_buy_money = UIFactory.label("", &"AccentLabel")
	column.add_child(_buy_money)
	_buy_list = UIFactory.vbox(6)
	column.add_child(_buy_list)
	_buy_message = UIFactory.label("", &"WarningLabel", true)
	column.add_child(_buy_message)
	var close := UIFactory.button("Close (B / Esc)")
	close.pressed.connect(buy_menu_closed.emit)
	column.add_child(close)
	buy_panel.visible = false
	add_child(buy_panel)


## FPS Sandbox: a column beside the shop for trying every knife look.
func _build_knife_column() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"OverlayPanel"
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var column := UIFactory.vbox(6)
	column.custom_minimum_size.x = 220
	panel.add_child(column)
	column.add_child(UIFactory.label("KNIFE", &"HeaderLabel"))
	column.add_child(UIFactory.label("Switch the knife you carry. Same as Carry this knife in the Armoury; it is saved.", &"MutedLabel", true))
	_knife_list = UIFactory.vbox(6)
	column.add_child(_knife_list)
	return panel


func _build_end_panel() -> void:
	end_panel = ColorRect.new()
	(end_panel as ColorRect).color = Color(0, 0, 0, 0.6)
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"OverlayPanel"
	center.add_child(panel)
	var column := UIFactory.vbox(12)
	column.custom_minimum_size.x = 480
	panel.add_child(column)
	_end_title = UIFactory.label("", &"TitleLabel")
	column.add_child(_end_title)
	_end_detail = UIFactory.label("", &"MutedLabel", true)
	column.add_child(_end_detail)
	play_again_button = UIFactory.button("Play again", &"AccentButton")
	play_again_button.pressed.connect(play_again_requested.emit)
	column.add_child(play_again_button)
	main_menu_button = UIFactory.button("Return to Main Menu")
	main_menu_button.pressed.connect(main_menu_requested.emit)
	column.add_child(main_menu_button)
	end_panel.visible = false
	add_child(end_panel)
