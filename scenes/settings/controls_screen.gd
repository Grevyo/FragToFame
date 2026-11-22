class_name ControlsScreen
extends Control
## Controls: rebind keys and mouse buttons, up to four per action. Used as a top-level scene
## from the main menu and embedded as an overlay in the FPS pause menu.
##
## Click a slot, then press the key or mouse button to bind. While waiting: Esc cancels and
## Backspace clears the slot. Changes apply at once and are saved to user://.

signal closed

## When true the screen is an overlay: Back emits [signal closed] instead of changing scene.
var embedded: bool = false
var bindings_path: String = InputBindings.DEFAULT_PATH
## Slot buttons per action (four each), for refreshes and tests.
var slot_buttons: Dictionary[StringName, Array] = {}
var back_button: Button
var reset_button: Button
## The action and slot waiting for a key press ("" / -1 when not listening).
var listening_action: StringName = &""
var listening_slot: int = -1

var _status: Label
## Bus -> its volume slider (0..100).
var volume_sliders: Dictionary[StringName, HSlider] = {}
const VOLUME_LABELS: Dictionary[StringName, String] = {&"Master": "Master volume", &"Effects": "Game sounds",
	&"UI": "Interface", &"Voice": "Voice"}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()
	back_button.grab_focus.call_deferred()


func is_listening() -> bool:
	return listening_slot >= 0


## Starts waiting for the input to put in a slot.
func begin_listen(action: StringName, slot: int) -> bool:
	if InputActions.is_locked(action) or not slot_buttons.has(action) or slot < 0 or slot >= InputBindings.MAX_BINDINGS:
		return false
	listening_action = action
	listening_slot = slot
	refresh()
	_status.text = "Press a key or mouse button for \"%s\".  Esc cancels  ·  Backspace clears the slot." % _label(action)
	return true


func cancel_listen() -> void:
	listening_action = &""
	listening_slot = -1
	refresh()


## Handles the input received while listening. Returns true if it ended the capture.
func apply_event(event: InputEvent) -> bool:
	if not is_listening() or not event.is_pressed() or event.is_echo():
		return false
	var action := listening_action
	var slot := listening_slot
	var key := event as InputEventKey
	if key != null and key.physical_keycode == KEY_ESCAPE:
		cancel_listen()
		_status.text = "Cancelled."
		return true
	if key != null and key.physical_keycode == KEY_BACKSPACE:
		InputBindings.clear_slot(action, slot)
		cancel_listen()
		_finish("Cleared a binding of \"%s\"." % _label(action))
		return true
	var binding := InputActions.event_to_binding(event)
	if binding.is_empty():
		return false
	var refusal := InputBindings.refusal(action, binding)
	if not refusal.is_empty():
		_status.text = refusal
		return false
	var unbound: Array[StringName] = InputBindings.assign(action, slot, binding)
	cancel_listen()
	var message := "%s is now bound to \"%s\"." % [InputBindings.label(binding), _label(action)]
	if not unbound.is_empty():
		var names: Array[String] = []
		for other: StringName in unbound:
			names.append(_label(other))
		message += "  Removed it from: %s." % ", ".join(names)
	_finish(message)
	return true


func reset_all() -> void:
	cancel_listen()
	InputBindings.reset_all()
	_finish("All controls reset to defaults.")


func reset_action(action: StringName) -> void:
	cancel_listen()
	InputBindings.reset_action(action)
	_finish("\"%s\" reset to default." % _label(action))


## Updates every slot button from the current bindings.
func refresh() -> void:
	for action: StringName in slot_buttons:
		var current := InputBindings.bindings(action)
		for slot: int in InputBindings.MAX_BINDINGS:
			var button := slot_buttons[action][slot] as Button
			if action == listening_action and slot == listening_slot:
				button.text = "press…"
			else:
				button.text = InputBindings.label(current[slot]) if slot < current.size() else "—"
			# Slots fill from the left: only the first empty one can be bound.
			button.disabled = InputActions.is_locked(action) or slot > current.size()


func _finish(message: String) -> void:
	var err := InputBindings.save(bindings_path)
	_status.text = message if err == OK else "%s  (Could not save: %s)" % [message, error_string(err)]
	refresh()


func _label(action: StringName) -> String:
	return str(InputActions.definition(action).get("label", action))


func _input(event: InputEvent) -> void:
	if not is_listening() or not is_visible_in_tree():
		return
	if event is InputEventKey or event is InputEventMouseButton:
		apply_event(event)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(InputActions.PAUSE_MENU):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	cancel_listen()
	if embedded:
		closed.emit()
	else:
		App.go_to(App.SCENE_MAIN_MENU)


func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"BackgroundPanel"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := UIFactory.vbox(12)
	column.custom_minimum_size.x = 900
	center.add_child(column)
	column.add_child(UIFactory.label("CONTROLS & AUDIO", &"HeaderLabel"))
	column.add_child(UIFactory.label(
		"Each action can have up to four keys or mouse buttons. Click a slot, then press the input. "
		+ "Binding an input that another action in the same mode uses moves it here.", &"MutedLabel", true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 560
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := UIFactory.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	list.add_child(UIFactory.label("AUDIO", &"SectionLabel"))
	for bus: StringName in AudioSettings.BUSES:
		list.add_child(_build_volume_row(bus))
	for group: String in InputActions.GROUP_ORDER:
		list.add_child(UIFactory.label(group.to_upper(), &"SectionLabel"))
		for action: StringName in InputActions.actions_in_group(group):
			list.add_child(_build_row(action))
	_status = UIFactory.label("", &"AccentLabel", true)
	column.add_child(_status)
	var footer := UIFactory.hbox(8)
	back_button = UIFactory.button("◂ Back", &"AccentButton")
	back_button.pressed.connect(_close)
	footer.add_child(back_button)
	footer.add_child(UIFactory.expand_spacer())
	reset_button = UIFactory.button("Reset all to defaults")
	reset_button.pressed.connect(reset_all)
	footer.add_child(reset_button)
	column.add_child(footer)


func _build_volume_row(bus: StringName) -> Control:
	var row := UIFactory.hbox(6)
	var caption := UIFactory.label(VOLUME_LABELS.get(bus, String(bus)))
	caption.custom_minimum_size.x = 250
	row.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = roundf(AudioSettings.volume(bus) * 100.0)
	slider.custom_minimum_size.x = 320
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var amount := UIFactory.label("%d%%" % int(slider.value), &"MutedLabel")
	row.add_child(amount)
	slider.value_changed.connect(func(value: float) -> void:
		amount.text = "%d%%" % int(value)
		AudioSettings.set_volume(bus, value / 100.0))
	volume_sliders[bus] = slider
	return row


func _build_row(action: StringName) -> Control:
	var row := UIFactory.hbox(6)
	var caption := UIFactory.label(_label(action))
	caption.custom_minimum_size.x = 250
	row.add_child(caption)
	var buttons: Array = []
	for slot: int in InputBindings.MAX_BINDINGS:
		var button := UIFactory.button("—")
		button.custom_minimum_size.x = 130
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Click, then press a key or mouse button"
		button.pressed.connect(func() -> void: begin_listen(action, slot))
		row.add_child(button)
		buttons.append(button)
	slot_buttons[action] = buttons
	var reset := UIFactory.button("Default")
	reset.focus_mode = Control.FOCUS_NONE
	reset.disabled = InputActions.is_locked(action)
	reset.tooltip_text = "Reset this action"
	reset.pressed.connect(func() -> void: reset_action(action))
	row.add_child(reset)
	return row
