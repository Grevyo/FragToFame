class_name CareerCoopPage
extends CareerPage
## Co-op (Dev): Milestone 2 career-sync proof. Host or join a shared DEVELOPMENT SAMPLE world,
## see its fixtures, "play" fixtures with the stub match runner and submit results. Includes
## buttons that deliberately resend and conflict, to demonstrate safe result submission.

const LOG_LIMIT: int = 12

static var _log: Array[String] = []
## fixture_id -> last result dict this client submitted (for the duplicate test).
static var _last_submitted: Dictionary[String, Dictionary] = {}

var _status_box: VBoxContainer
var _fixtures_box: VBoxContainer
var _log_box: VBoxContainer
var _address_edit: LineEdit
var _port_edit: LineEdit


func get_page_title() -> String:
	return "Co-op (Dev)"


func build_page() -> void:
	add_sample_notice("Development networking proof — the shared world is a dev sample held in memory by the host. Nothing is saved.")
	_build_connection_card()
	_status_box = UIFactory.card(self, "Status")
	_fixtures_box = UIFactory.card(self, "Shared fixtures")
	_log_box = UIFactory.card(self, "Event log")

	# Bound-method connections are removed automatically when this page is freed.
	var client := CareerSync.client
	client.connected_to_host.connect(_on_connected)
	client.rejected.connect(_on_rejected)
	client.disconnected.connect(_on_disconnected)
	client.fixtures_changed.connect(_on_fixtures_changed)
	client.result_acknowledged.connect(_on_ack)
	_refresh()


func _on_connected(_peer_id: int) -> void:
	_add_log("Connected to career host")


func _on_rejected(reason: String) -> void:
	_add_log("Rejected by host: " + reason)


func _on_disconnected(reason: String) -> void:
	_add_log("Disconnected: " + reason)
	_refresh()


func _on_fixtures_changed(_revision: int) -> void:
	_refresh()


func _process(_delta: float) -> void:
	# Cheap status refresh so the connecting/handshaking states update live.
	_refresh_status()


func _build_connection_card() -> void:
	var card := UIFactory.card(self, "Career connection")
	card.add_child(UIFactory.label(
		"The career host owns the world. Every player — including the host — talks to it through "
		+ "the same client connection. Run a second game instance and choose Join to test.",
		&"MutedLabel", true))
	var row := UIFactory.hbox(10)
	_address_edit = LineEdit.new()
	_address_edit.text = "127.0.0.1"
	_address_edit.placeholder_text = "Host address"
	_address_edit.custom_minimum_size.x = 200
	row.add_child(_address_edit)
	_port_edit = LineEdit.new()
	_port_edit.text = str(CareerProtocol.DEFAULT_PORT)
	_port_edit.custom_minimum_size.x = 90
	row.add_child(_port_edit)
	var host_button := UIFactory.button("Host career", &"AccentButton")
	host_button.pressed.connect(_on_host_pressed)
	row.add_child(host_button)
	var join_button := UIFactory.button("Join career")
	join_button.pressed.connect(_on_join_pressed)
	row.add_child(join_button)
	var leave_button := UIFactory.button("Disconnect")
	leave_button.pressed.connect(func() -> void:
		CareerSync.leave()
		_add_log("Left career session")
		_refresh())
	row.add_child(leave_button)
	card.add_child(row)


func _port() -> int:
	var text := _port_edit.text.strip_edges()
	return int(text) if text.is_valid_int() else CareerProtocol.DEFAULT_PORT


func _on_host_pressed() -> void:
	var err: Error = CareerSync.host_career(_port())
	_add_log("Hosting career on port %d" % _port() if err == OK else "Could not host (error %d)" % err)
	_refresh()


func _on_join_pressed() -> void:
	var address := _address_edit.text.strip_edges()
	var err: Error = CareerSync.join_career(address, _port())
	_add_log("Joining %s:%d..." % [address, _port()] if err == OK else "Could not join (error %d)" % err)
	_refresh()


func _refresh() -> void:
	_refresh_status()
	_refresh_fixtures()
	_refresh_log()


func _refresh_status() -> void:
	if _status_box == null:
		return
	var client := CareerSync.client
	var state_name: String = CareerSyncClient.State.keys()[client.state]
	var rows: Array[PackedStringArray] = [
		PackedStringArray(["Role", CareerSync.role_name()]),
		PackedStringArray(["Connection", state_name]),
		PackedStringArray(["Host", "%s:%d" % [client.host_address, client.host_port] if client.state != CareerSyncClient.State.OFFLINE else "—"]),
		PackedStringArray(["Peer ID", str(client.peer_id) if client.peer_id != 0 else "—"]),
		PackedStringArray(["World", client.world_id if not client.world_id.is_empty() else "—"]),
		PackedStringArray(["World revision", str(client.revision) if client.revision >= 0 else "—"]),
		PackedStringArray(["Pending submissions", str(client.pending_submissions.size())]),
		PackedStringArray(["Connected players (host only)", str(CareerSync.host.authenticated_peer_ids().size()) if CareerSync.host.is_running() else "—"]),
		PackedStringArray(["Protocol", "career v%d" % CareerProtocol.PROTOCOL_VERSION]),
	]
	var signature := str(rows)
	if _status_box.get_meta(&"signature", "") == signature:
		return
	_status_box.set_meta(&"signature", signature)
	_clear(_status_box, 2)
	UIFactory.key_value_grid(_status_box, rows)


func _refresh_fixtures() -> void:
	_clear(_fixtures_box, 2)
	var client := CareerSync.client
	if not client.is_ready():
		_fixtures_box.add_child(UIFactory.label("Not connected to a career host.", &"MutedLabel"))
		return
	for fixture: Dictionary in client.fixtures:
		_fixtures_box.add_child(_fixture_row(fixture))


func _fixture_row(fixture: Dictionary) -> Control:
	var row := UIFactory.hbox(12)
	var id := str(fixture["id"])
	var date := UIFactory.label(str(fixture.get("date", "")), &"AccentLabel")
	date.custom_minimum_size.x = 90
	row.add_child(date)
	var teams := UIFactory.label("%s  vs  %s" % [fixture["home_team_name"], fixture["away_team_name"]])
	teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(teams)
	var meta := UIFactory.label("%s · BO%d MR%d" % [id, int(fixture.get("best_of", 1)), int(fixture.get("max_rounds", 10))], &"MutedLabel")
	row.add_child(meta)

	var result: Dictionary = fixture.get("result", {})
	if result.is_empty():
		var play := UIFactory.button("Play stub match")
		play.tooltip_text = "Generates a random valid result with the placeholder match runner and submits it."
		play.pressed.connect(_play_stub.bind(fixture))
		row.add_child(play)
	else:
		var score := UIFactory.label("%d – %d" % [int(result["home_score"]), int(result["away_score"])], &"CardTitleLabel")
		score.custom_minimum_size.x = 80
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(score)
		row.add_child(UIFactory.label("by %s" % result.get("submitted_by", "?"), &"MutedLabel"))
		var resend := UIFactory.button("Resend")
		resend.tooltip_text = "Resends this client's last submission unchanged. Expected: DUPLICATE (ignored safely)."
		resend.disabled = not _last_submitted.has(id)
		resend.pressed.connect(func() -> void:
			CareerSync.client.resend_submission(_last_submitted[id])
			_add_log("Resent submission for %s" % id))
		row.add_child(resend)
		var conflict := UIFactory.button("Conflict test")
		conflict.tooltip_text = "Submits a new, different result for this fixture. Expected: CONFLICT (rejected)."
		conflict.pressed.connect(_submit_conflict.bind(fixture))
		row.add_child(conflict)
	return row


func _play_stub(fixture: Dictionary) -> void:
	var setup := MatchSetup.from_fixture(fixture)
	var result := StubMatchRunner.run(setup)
	CareerSync.client.submit_result(result)
	_last_submitted[setup.fixture_id] = result.to_dict()
	_add_log("Played stub match %s: %d–%d, submitting" % [setup.fixture_id, result.home_score, result.away_score])


func _submit_conflict(fixture: Dictionary) -> void:
	var existing: Dictionary = fixture.get("result", {})
	var setup := MatchSetup.from_fixture(fixture)
	# Flip the winner so the scoreline is guaranteed to differ.
	var result := MatchResult.create(setup.fixture_id, int(existing["away_score"]), int(existing["home_score"]), MatchResult.SOURCE_STUB)
	CareerSync.client.submit_result(result)
	_add_log("Submitted conflicting result for %s: %d–%d" % [setup.fixture_id, result.home_score, result.away_score])


func _on_ack(ack: Dictionary) -> void:
	_add_log("Host: %s for %s — %s" % [ack.get("status", "?"), ack.get("fixture_id", "?"), ack.get("message", "")])


func _add_log(line: String) -> void:
	_log.push_front("%s  %s" % [Time.get_time_string_from_system(), line])
	if _log.size() > LOG_LIMIT:
		_log.resize(LOG_LIMIT)
	_refresh_log()


func _refresh_log() -> void:
	if _log_box == null:
		return
	_clear(_log_box, 2)
	if _log.is_empty():
		_log_box.add_child(UIFactory.label("No events yet.", &"MutedLabel"))
	for line: String in _log:
		_log_box.add_child(UIFactory.label(line, &"MutedLabel"))


## Removes children after the first [param keep] (the card title and separator).
func _clear(box: Container, keep: int) -> void:
	for i: int in range(box.get_child_count() - 1, keep - 1, -1):
		var child := box.get_child(i)
		box.remove_child(child)
		child.queue_free()
