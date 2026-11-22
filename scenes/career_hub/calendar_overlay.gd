class_name CareerCalendarOverlay
extends CanvasLayer
## Shown while a Continue or a holiday runs ([CalendarRun]): a tear-off calendar page that flips
## to each day, a clock that runs through it with what is happening (the morning's market and
## news, each series at its kick-off with the score), the month with the days passed so far, the
## day's top story and a Stop button. Events run between frames so the screen keeps moving; each
## stays on screen long enough to follow (see [method _day_seconds]), and long runs go faster.

## Shortest time a day stays on screen in a short run (a Continue or a week away).
const DAY_SECONDS: float = 0.16
## Longest a whole run's pacing may add up to: longer runs give each day less time.
const RUN_SECONDS: float = 6.0
## The page flip (each half); skipped when a day has less time than [constant FLIP_MIN_DAY].
const FLIP_SECONDS: float = 0.03
const FLIP_MIN_DAY: float = 0.1
## Shortest time a series and a morning event stay on screen in a short run.
const SERIES_SECONDS: float = 0.05
const WORLD_SECONDS: float = 0.015
const LAYER: int = 50

var run: CalendarRun
var _page: PanelContainer
var _month_label: Label
var _day_label: Label
var _year_label: Label
var _clock_label: Label
var _event_label: Label
var _detail_label: Label
var _shown_day: int = -1
var _grid: GridContainer
var _grid_month: int = -1
var _cells: Dictionary[int, PanelContainer] = {}
var _progress: ProgressBar
var _count_label: Label
var _story_label: Label
var _stop_button: Button


## Plays [param calendar_run] over [param host] and returns its outcome. Without a host in the
## scene tree (headless callers) the run simply goes to the end.
static func play(host: Node, calendar_run: CalendarRun) -> Dictionary:
	if calendar_run.is_finished() or host == null or not host.is_inside_tree():
		return calendar_run.run_all()
	var overlay := CareerCalendarOverlay.new()
	overlay.run = calendar_run
	host.add_child(overlay)
	var outcome: Dictionary = await overlay._play()
	overlay.queue_free()
	return outcome


func _ready() -> void:
	layer = LAYER
	_build()


func _play() -> Dictionary:
	_show_day(run.repo.current_day())
	_show_event({})
	await get_tree().process_frame
	var pace := _day_seconds()
	var scale := pace / DAY_SECONDS
	var day_started := Time.get_ticks_msec()
	while not run.is_finished():
		var started := Time.get_ticks_msec()
		# Let the current state reach the screen before the next event blocks the frame.
		await get_tree().process_frame
		run.step()
		var now := run.now()
		var day := int(now.get("day", run.repo.current_day()))
		if day != _shown_day:
			# Hold the finished day for its share of the run before turning the page.
			var day_left := pace - (Time.get_ticks_msec() - day_started) / 1000.0
			if day_left > 0.0:
				await get_tree().create_timer(day_left).timeout
			day_started = Time.get_ticks_msec()
			if pace >= FLIP_MIN_DAY:
				await _flip_to(day)
			else:
				_show_day(day)
		_show_event(now)
		var hold := (SERIES_SECONDS if str(now.get("kind", "")) != "world" else WORLD_SECONDS) * scale
		var left := hold - (Time.get_ticks_msec() - started) / 1000.0
		if left > 0.0 and not run.is_finished():
			await get_tree().create_timer(left).timeout
	return run.outcome


## If the overlay leaves the tree mid-run (the scene changed), the run finishes without it so the
## day's transaction is never left open.
func _exit_tree() -> void:
	if run != null and not run.is_finished():
		run.run_all()


func _build() -> void:
	var dim := PanelContainer.new()
	dim.theme_type_variation = &"DimPanel"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var centre := CenterContainer.new()
	dim.add_child(centre)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"OverlayPanel"
	centre.add_child(panel)
	var box := UIFactory.vbox(14)
	box.custom_minimum_size = Vector2(420, 0)
	panel.add_child(box)
	var title := "ON HOLIDAY" if run.kind == CalendarRun.Kind.HOLIDAY else "THE WORLD IS PLAYING ON"
	box.add_child(UIFactory.label(title, &"SectionLabel"))

	var page_holder := CenterContainer.new()
	box.add_child(page_holder)
	_page = PanelContainer.new()
	_page.theme_type_variation = &"CalendarPagePanel"
	_page.custom_minimum_size = Vector2(200, 0)
	page_holder.add_child(_page)
	var page_box := UIFactory.vbox(0)
	_page.add_child(page_box)
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"CalendarStripPanel"
	page_box.add_child(strip)
	_month_label = UIFactory.label("", &"CalendarMonthLabel")
	_month_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.add_child(_month_label)
	_day_label = UIFactory.label("", &"CalendarDayLabel")
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_box.add_child(_day_label)
	_year_label = UIFactory.label("", &"CalendarYearLabel")
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_box.add_child(_year_label)

	_clock_label = UIFactory.label("", &"CalendarClockLabel")
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_clock_label)
	_event_label = UIFactory.label("", &"CardTitleLabel")
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_event_label.custom_minimum_size = Vector2(420, 0)
	box.add_child(_event_label)
	_detail_label = UIFactory.label("", &"MutedLabel")
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail_label)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override(&"h_separation", 4)
	_grid.add_theme_constant_override(&"v_separation", 4)
	var grid_holder := CenterContainer.new()
	grid_holder.add_child(_grid)
	box.add_child(grid_holder)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.max_value = maxi(run.planned_days(), 1)
	_progress.visible = run.planned_days() > 0
	box.add_child(_progress)
	_count_label = UIFactory.label("", &"MutedLabel")
	box.add_child(_count_label)
	_story_label = UIFactory.label("", &"AccentLabel", true)
	_story_label.custom_minimum_size = Vector2(420, 0)
	box.add_child(_story_label)
	_stop_button = UIFactory.button("Stop")
	_stop_button.tooltip_text = "Stop after the day being played."
	_stop_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_stop_button.pressed.connect(_on_stop)
	box.add_child(_stop_button)


func _on_stop() -> void:
	run.stop_requested = true
	_stop_button.disabled = true
	_stop_button.text = "Stopping…"


## Time each day stays on screen: [constant DAY_SECONDS], less when the run is long (an
## open-ended holiday counts as a long one).
func _day_seconds() -> float:
	var planned := run.planned_days()
	if planned <= 0:
		planned = CareerCalendar.HOLIDAY_INBOX_LIMIT
	return minf(DAY_SECONDS, RUN_SECONDS / planned)


## Turns the page to [param day]: the old page folds up, the new one drops down.
func _flip_to(day: int) -> void:
	_page.pivot_offset = Vector2(_page.size.x * 0.5, 0.0)
	var fold := create_tween()
	fold.tween_property(_page, ^"scale:y", 0.0, FLIP_SECONDS).set_ease(Tween.EASE_IN)
	await fold.finished
	_show_day(day)
	var drop := create_tween()
	drop.tween_property(_page, ^"scale:y", 1.0, FLIP_SECONDS).set_ease(Tween.EASE_OUT)
	await drop.finished


## The clock and what is happening at it.
func _show_event(now: Dictionary) -> void:
	if now.is_empty() or str(now.get("label", "")).is_empty():
		_clock_label.text = GameDate.clock(int(now.get("minute", 9 * 60)))
		_event_label.text = "Getting going…" if now.is_empty() else "Between events"
		_detail_label.text = ""
		return
	_clock_label.text = GameDate.clock(int(now["minute"]))
	var kind := str(now["kind"])
	if kind == "world":
		_event_label.text = str(now["label"])
		_detail_label.text = "The world's morning"
		return
	var label := str(now["label"])
	if now.has("score"):
		var score := now["score"] as Array
		var teams := label.split(" vs ")
		if teams.size() == 2:
			label = "%s  %d – %d  %s" % [teams[0], int(score[0]), int(score[1]), teams[1]]
	_event_label.text = label
	var parts: PackedStringArray = [str(now["detail"])] if not str(now["detail"]).is_empty() else []
	if run.series_played > 0:
		parts.append("%d series played" % run.series_played)
	_detail_label.text = " · ".join(parts)


func _show_day(day: int) -> void:
	_shown_day = day
	var date := GameDate.month_and_day(day)
	_month_label.text = GameDate.MONTH_NAMES[date.x].to_upper()
	_day_label.text = str(date.y)
	_year_label.text = "%s · %s" % [_weekday_name(day), GameDate.format_year(day)]
	_fill_month(day)
	var today: PanelContainer = _cells.get(day)
	if today != null:
		today.theme_type_variation = &"CalendarTodayCell"
	var gone := day - run.start_day
	_progress.value = gone
	_count_label.text = "%d day%s passed" % [gone, "" if gone == 1 else "s"] if gone > 0 else "Getting going…"
	if run.simulated > 0:
		_count_label.text += " · %d of your maps simulated" % run.simulated
	var stories := run.repo.news_on(day)
	if not stories.is_empty():
		_story_label.text = str(stories[0]["headline"])


static func _weekday_name(day: int) -> String:
	return ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][GameDate.weekday(day)]


## Draws the month of [param day] (once per month), marking the days this run has passed.
func _fill_month(day: int) -> void:
	var month := GameDate.month_and_day(day).x
	var first := day - (GameDate.month_and_day(day).y - 1)
	if month == _grid_month:
		for cell_day: int in _cells:
			if cell_day < day and cell_day >= run.start_day:
				_cells[cell_day].theme_type_variation = &"CalendarPassedCell"
		return
	_grid_month = month
	_cells.clear()
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for offset: int in GameDate.MONTH_LENGTHS[month]:
		var cell_day := first + offset
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(30, 24)
		cell.theme_type_variation = &"CalendarPassedCell" if cell_day < day and cell_day >= run.start_day else &"CalendarCell"
		var number := UIFactory.label(str(offset + 1), &"CalendarCellLabel")
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(number)
		_grid.add_child(cell)
		_cells[cell_day] = cell
