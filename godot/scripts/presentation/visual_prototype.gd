extends Control

const Palette = preload("res://scripts/presentation/ternary_palette.gd")
const Tokens = preload("res://scripts/presentation/token_renderer.gd")
const Icons = preload("res://scripts/presentation/piece_icon_renderer.gd")
const Codec = preload("res://scripts/core/ternary_codec.gd")
const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const OpponentAI = preload("res://scripts/core/ternary_ai.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")

const BOARD_DIMENSION := 9
const PIECE_ORDER := [
	"sovereign", "infantry", "dragoon", "chariot", "griffin", "marshal",
	"trebuchet", "ballista", "spy", "reinforcement", "recall",
]

var board_rect := Rect2()
var hovered_square := ""
var selected_square := ""
var view_mode := "play"
var game_state := {}
var manual_states: Array = []
var manual_actions: Array = []
var manual_redo_states: Array = []
var manual_redo_actions: Array = []
var manual_redo_ai_annotations: Array = []
var manual_initial_state := {}
var human_game_id := ""
var human_game_path := ""
var human_recording_enabled := false
var ai_enabled := false
var ai_player := Rules.BLACK
var ai_busy := false
var ai_controller = OpponentAI.new()
var ai_thread: Thread
var ai_request_checksum := ""
var ai_annotations: Array = []
var last_ai_decision: Dictionary = {}
var selected_piece_kind := ""
var selected_recall_kind := ""
var pending_artillery_actions: Array = []
var replay_document := {}
var replay_states: Array = []
var replay_actions: Array = []
var replay_index := 0
var replay_error := ""
var setup_white_file := -1
var setup_position := {}
var file_dialog: FileDialog

var left_mode_rects := {}
var reserve_rects := {}
var right_control_rects := {}
var recall_kind_rects := {}
var inspector_collapsed := false
var notation_collapsed := false
var right_split_ratio := 0.38
var right_split_track := Rect2()
var right_workspace_rect := Rect2()
var dragging_right_split := false
var notation_copy_feedback_until := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	human_recording_enabled = true
	_build_file_dialog()
	resized.connect(queue_redraw)
	queue_redraw()


func _process(_delta: float) -> void:
	if ai_thread != null and ai_thread.is_started() and not ai_thread.is_alive():
		var decision = ai_thread.wait_to_finish()
		ai_thread = null
		_complete_threaded_ai_turn(decision)


func _exit_tree() -> void:
	if ai_thread != null and ai_thread.is_started():
		ai_thread.wait_to_finish()
		ai_thread = null


func _build_file_dialog() -> void:
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; T3RNARY replay"])
	file_dialog.title = "Open T3RNARY Replay"
	var replay_dir := ProjectSettings.globalize_path("res://../research/replays")
	if DirAccess.dir_exists_absolute(replay_dir):
		file_dialog.current_dir = replay_dir
	file_dialog.file_selected.connect(_load_replay)
	add_child(file_dialog)


func _stack(owner: String, kinds: Array) -> Dictionary:
	return {"owner": owner, "kinds": kinds}


func _position_data() -> Dictionary:
	if view_mode == "play" and game_state.is_empty():
		return setup_position
	var result := {}
	for square_value in game_state.get("board", {}):
		var square := str(square_value)
		var stack: Array = game_state.board[square]
		var kinds: Array = []
		for piece in stack:
			kinds.append(str(piece.kind))
		if not stack.is_empty():
			result[square] = _stack(str(stack[-1].owner), kinds)
	return result


func _start_new_game() -> void:
	view_mode = "play"
	game_state = {}
	manual_states.clear()
	manual_actions.clear()
	manual_redo_states.clear()
	manual_redo_actions.clear()
	manual_redo_ai_annotations.clear()
	manual_initial_state = {}
	human_game_id = ""
	human_game_path = ""
	ai_busy = false
	ai_annotations.clear()
	last_ai_decision = {}
	setup_white_file = -1
	setup_position = {}
	_clear_action_selection()
	selected_square = ""
	replay_error = ""
	queue_redraw()


func _finish_sovereign_setup(black_file: int) -> void:
	game_state = GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(setup_white_file, black_file))
	manual_states = [game_state.duplicate(true)]
	manual_initial_state = game_state.duplicate(true)
	manual_redo_states.clear()
	manual_redo_actions.clear()
	manual_redo_ai_annotations.clear()
	_begin_human_recording()
	setup_position = {}
	selected_square = ""
	queue_redraw()
	_queue_ai_turn()


func _clear_action_selection() -> void:
	selected_piece_kind = ""
	selected_recall_kind = ""
	pending_artillery_actions.clear()


func _legal_actions() -> Array:
	if view_mode != "play" or game_state.is_empty():
		return []
	return GameEngine.legal_actions(game_state)


func _apply_manual_action(action: Dictionary, ai_decision := {}) -> void:
	var next_state := GameEngine.apply_action(game_state, action)
	if next_state.is_empty():
		return
	game_state = next_state
	manual_actions.append(Codec.normalize_action(action))
	manual_states.append(game_state.duplicate(true))
	if not ai_decision.is_empty():
		last_ai_decision = ai_decision.duplicate(true)
		var annotation := ai_decision.duplicate(true)
		annotation["ply"] = manual_actions.size()
		annotation.erase("action")
		ai_annotations.append(annotation)
	manual_redo_actions.clear()
	manual_redo_states.clear()
	manual_redo_ai_annotations.clear()
	_save_human_game()
	selected_square = ""
	_clear_action_selection()
	queue_redraw()
	_queue_ai_turn()


func _is_ai_turn() -> bool:
	return ai_enabled and not game_state.is_empty() and not GameEngine.is_over(game_state) and str(game_state.turn) == ai_player


func _queue_ai_turn() -> void:
	if ai_enabled and game_state.is_empty() and setup_white_file >= 0 and not ai_busy:
		ai_busy = true
		queue_redraw()
		call_deferred("_perform_ai_sovereign_setup")
		return
	if _is_ai_turn() and not ai_busy:
		ai_busy = true
		ai_request_checksum = Codec.state_checksum(game_state)
		queue_redraw()
		ai_thread = Thread.new()
		var snapshot := game_state.duplicate(true)
		if ai_thread.start(_compute_ai_decision.bind(snapshot)) != OK:
			ai_thread = null
			call_deferred("_perform_ai_turn")


func _compute_ai_decision(snapshot: Dictionary) -> Dictionary:
	var worker_ai = OpponentAI.new()
	return worker_ai.choose_action(snapshot)


func _complete_threaded_ai_turn(decision: Variant) -> void:
	if not decision is Dictionary or not _is_ai_turn() or Codec.state_checksum(game_state) != ai_request_checksum:
		ai_busy = false
		queue_redraw()
		return
	ai_busy = false
	_apply_manual_action(decision.action, decision)


func _perform_ai_sovereign_setup() -> void:
	if not ai_enabled or not game_state.is_empty() or setup_white_file < 0:
		ai_busy = false
		queue_redraw()
		return
	# A rotationally mirrored start is deterministic and does not privilege a
	# particular board edge while the opening-placement policy is still young.
	var black_file := Rules.board_size() - 1 - setup_white_file
	ai_busy = false
	_finish_sovereign_setup(black_file)


func _perform_ai_turn() -> void:
	if not _is_ai_turn():
		ai_busy = false
		queue_redraw()
		return
	var decision: Dictionary = ai_controller.choose_action(game_state)
	if decision.is_empty():
		ai_busy = false
		replay_error = "The computer could not find a legal action."
		queue_redraw()
		return
	ai_busy = false
	_apply_manual_action(decision.action, decision)


func _undo_manual_action() -> void:
	if view_mode != "play" or manual_states.size() <= 1:
		return
	var undo_count := 1
	if ai_enabled and manual_states.size() > 2 and not ai_annotations.is_empty() and int(ai_annotations[-1].get("ply", 0)) == manual_actions.size():
		undo_count = 2
	for _step in range(undo_count):
		manual_redo_states.append(manual_states.pop_back())
		var old_ply := manual_actions.size()
		if not manual_actions.is_empty():
			manual_redo_actions.append(manual_actions.pop_back())
		if not ai_annotations.is_empty() and int(ai_annotations[-1].get("ply", 0)) == old_ply:
			manual_redo_ai_annotations.append(ai_annotations.pop_back())
	game_state = manual_states[-1].duplicate(true)
	_save_human_game()
	selected_square = ""
	_clear_action_selection()
	queue_redraw()


func _redo_manual_action() -> void:
	if view_mode != "play" or manual_redo_states.is_empty() or manual_redo_actions.is_empty():
		return
	var redo_count := mini(2, manual_redo_actions.size()) if ai_enabled else 1
	for _step in range(redo_count):
		manual_actions.append(manual_redo_actions.pop_back())
		manual_states.append(manual_redo_states.pop_back())
		var restored_ply := manual_actions.size()
		if not manual_redo_ai_annotations.is_empty() and int(manual_redo_ai_annotations[-1].get("ply", 0)) == restored_ply:
			ai_annotations.append(manual_redo_ai_annotations.pop_back())
	game_state = manual_states[-1].duplicate(true)
	_save_human_game()
	selected_square = ""
	_clear_action_selection()
	queue_redraw()


func _begin_human_recording() -> void:
	if not human_recording_enabled or manual_initial_state.is_empty():
		return
	var stamp := int(Time.get_unix_time_from_system())
	var fraction := Time.get_ticks_msec() % 1000
	human_game_id = "human-%d-%03d-W%s-B%s" % [stamp, fraction, Rules.files().substr(setup_white_file, 1), Rules.files().substr(_sovereign_file(Rules.BLACK), 1)]
	var directory := ProjectSettings.globalize_path("res://../research/replays/human")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		directory = ProjectSettings.globalize_path("user://human_games")
		DirAccess.make_dir_recursive_absolute(directory)
	human_game_path = directory.path_join(human_game_id + ".json")
	_save_human_game()


func _sovereign_file(player: String) -> int:
	for square_value in game_state.get("board", {}):
		var square := str(square_value)
		var stack: Array = game_state.board[square]
		if not stack.is_empty() and stack[-1].owner == player and stack[-1].kind == Rules.SOVEREIGN:
			return Rules.files().find(square.substr(0, 1))
	return -1


func _human_replay_document() -> Dictionary:
	var outcome := "in_progress"
	if not game_state.is_empty() and bool(game_state.get("is_draw", false)):
		outcome = "draw"
	elif not game_state.is_empty() and game_state.get("winner") != null:
		outcome = "%s_win" % str(game_state.winner)
	return {
		"contract_version": Rules.CONTRACT_VERSION,
		"game_id": human_game_id,
		"initial_state": manual_initial_state.duplicate(true),
		"actions": manual_actions.duplicate(true),
		"metadata": {
			"source": "human_vs_ai" if ai_enabled else "human_hotseat",
			"ruleset": str(manual_initial_state.get("rules", {}).get("id", "")),
			"outcome": outcome,
			"completed": not game_state.is_empty() and GameEngine.is_over(game_state),
			"plies": manual_actions.size(),
			"updated_unix": int(Time.get_unix_time_from_system()),
		},
		"annotations": ai_annotations.duplicate(true),
	}


func _save_human_game() -> void:
	if not human_recording_enabled or human_game_path.is_empty() or manual_initial_state.is_empty():
		return
	var error := Codec.save_json(human_game_path, _human_replay_document())
	if error != OK:
		replay_error = "Human game could not be recorded."


func _open_replay_dialog() -> void:
	file_dialog.popup_centered_ratio(0.78)


func _load_replay(path: String) -> void:
	var parsed = Codec.load_json(path)
	if not parsed is Dictionary or not parsed.has("initial_state") or not parsed.has("actions"):
		replay_error = "That file is not a T3RNARY replay."
		queue_redraw()
		return
	_load_replay_document(parsed)


func _load_replay_document(document: Dictionary) -> void:
	if not document.has("initial_state") or not document.has("actions"):
		replay_error = "That document is not a T3RNARY replay."
		return
	view_mode = "replay"
	replay_document = document.duplicate(true)
	replay_actions = document.actions.duplicate(true)
	replay_states = [Codec.normalize_state(document.initial_state)]
	replay_error = ""
	var state: Dictionary = replay_states[0]
	for index in range(replay_actions.size()):
		var action: Dictionary = Codec.normalize_action(replay_actions[index])
		if not Codec.actions_contain(GameEngine.legal_actions(state), action):
			replay_error = "Replay stops at ply %d: recorded action is not legal under the current engine." % (index + 1)
			break
		var next_state := GameEngine.apply_action(state, action, false)
		if next_state.is_empty():
			replay_error = "Replay stops at ply %d: action could not be applied." % (index + 1)
			break
		replay_states.append(next_state)
		state = next_state
	replay_index = 0
	game_state = replay_states[0].duplicate(true)
	selected_square = ""
	_clear_action_selection()
	queue_redraw()


func _set_replay_index(index: int) -> void:
	if replay_states.is_empty():
		return
	replay_index = clampi(index, 0, replay_states.size() - 1)
	game_state = replay_states[replay_index].duplicate(true)
	selected_square = ""
	queue_redraw()


func _draw() -> void:
	_draw_table()
	_calculate_board_rect()
	_draw_left_panel()
	_draw_board()
	_draw_action_markers()
	_draw_position()
	_draw_game_over_overlay()
	_draw_right_panel()


func _draw_table() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKGROUND)
	var glow_center := size * Vector2(0.52, 0.45)
	for index in range(8, 0, -1):
		var alpha := 0.012 * float(9 - index)
		draw_circle(glow_center, minf(size.x, size.y) * float(index) * 0.11, Color(Palette.BRASS, alpha))
	for index in range(34):
		var y := fmod(float(index * 83), maxf(1.0, size.y))
		draw_line(Vector2(0.0, y), Vector2(size.x, y + 13.0), Color(0.65, 0.54, 0.40, 0.018), 1.0)


func _draw_game_over_overlay() -> void:
	if game_state.is_empty() or not GameEngine.is_over(game_state):
		return
	var font := ThemeDB.fallback_font
	draw_rect(board_rect, Color(0.015, 0.018, 0.020, 0.50))
	var banner_width := minf(board_rect.size.x * 0.68, 610.0)
	var banner_height := minf(board_rect.size.y * 0.19, 150.0)
	var banner := Rect2(
		board_rect.get_center() - Vector2(banner_width, banner_height) * 0.5,
		Vector2(banner_width, banner_height)
	)
	draw_rect(banner, Color(Palette.PANEL, 0.97))
	draw_rect(banner, Palette.BRASS_LIGHT, false, 3.0)
	draw_line(banner.position + Vector2(18.0, 13.0), Vector2(banner.end.x - 18.0, banner.position.y + 13.0), Palette.BRASS, 1.0)
	draw_line(Vector2(banner.position.x + 18.0, banner.end.y - 13.0), banner.end - Vector2(18.0, 13.0), Palette.BRASS, 1.0)
	var headline := "DRAW"
	if game_state.get("winner") != null:
		headline = "%s VICTORY" % str(game_state.winner).to_upper()
	draw_string(font, banner.position + Vector2(0.0, banner_height * 0.48), headline, HORIZONTAL_ALIGNMENT_CENTER, banner_width, 32, Palette.TEXT)
	draw_string(font, banner.position + Vector2(0.0, banner_height * 0.72), _game_end_method(), HORIZONTAL_ALIGNMENT_CENTER, banner_width, 14, Palette.BRASS_LIGHT)


func _game_end_method() -> String:
	if game_state.is_empty() or not GameEngine.is_over(game_state):
		return ""
	if bool(game_state.get("is_draw", false)):
		return "NO LEGAL ACTIONS"
	var action: Dictionary = {}
	var before: Dictionary = {}
	if view_mode == "play" and not manual_actions.is_empty() and manual_states.size() >= 2:
		action = Codec.normalize_action(manual_actions[-1])
		before = manual_states[-2]
	elif view_mode == "replay" and replay_index > 0 and replay_index <= replay_actions.size():
		action = Codec.normalize_action(replay_actions[replay_index - 1])
		before = replay_states[replay_index - 1]
	if action.is_empty() or str(action.get("type", "")) != "move":
		return "GAME COMPLETE"
	var destination := str(action.get("destination", ""))
	var target: Array = before.get("board", {}).get(destination, [])
	if not target.is_empty() and str(target[-1].kind) == Rules.SOVEREIGN:
		return "SOVEREIGN CAPTURE"
	var source: Array = before.get("board", {}).get(str(action.get("source", "")), [])
	if not source.is_empty() and str(source[-1].kind) == Rules.SOVEREIGN:
		var destination_rank := Rules.square_to_xy(destination).y
		var winner := str(game_state.get("winner", ""))
		if destination_rank == (Rules.board_size() - 1 if winner == Rules.WHITE else 0):
			return "CONQUER"
	return "VICTORY"


func _calculate_board_rect() -> void:
	var available_height := maxf(540.0, size.y - 72.0)
	var available_width := maxf(540.0, size.x - 510.0)
	var side := floorf(minf(available_height, available_width))
	var left := floorf((size.x - side) * 0.5 - 4.0)
	var top := floorf((size.y - side) * 0.5)
	board_rect = Rect2(Vector2(left, top), Vector2(side, side))


func _draw_board() -> void:
	var frame := board_rect.grow(24.0)
	draw_rect(frame.grow(10.0), Color(0.0, 0.0, 0.0, 0.50))
	draw_rect(frame, Palette.FRAME_DARK)
	draw_rect(frame.grow(-5.0), Palette.FRAME_EDGE, false, 3.0)
	draw_rect(board_rect.grow(6.0), Palette.FRAME_MID)
	var cell := board_rect.size.x / BOARD_DIMENSION
	for row in range(BOARD_DIMENSION):
		for column in range(BOARD_DIMENSION):
			var square_rect := Rect2(board_rect.position + Vector2(column, row) * cell, Vector2(cell, cell))
			var base := Palette.LIGHT_SQUARE if (column + row) % 2 == 0 else Palette.DARK_SQUARE
			if row >= 3 and row <= 5:
				base = Palette.NEUTRAL_LIGHT_SQUARE if (column + row) % 2 == 0 else Palette.NEUTRAL_DARK_SQUARE
			draw_rect(square_rect, base)
			_draw_square_grain(square_rect, column, row, base)
			draw_rect(square_rect, Palette.GRID_LINE, false, maxf(1.0, cell * 0.018))

	# Two orientation-neutral lines are the board's only territory markings.
	for boundary_row in [3, 6]:
		var y: float = board_rect.position.y + cell * int(boundary_row)
		draw_line(Vector2(board_rect.position.x, y), Vector2(board_rect.end.x, y), Palette.NEUTRAL_BOUNDARY, maxf(3.0, cell * 0.045), true)
	_draw_coordinates(cell)


func _draw_square_grain(rect: Rect2, column: int, row: int, base: Color) -> void:
	for index in range(3):
		var seed_value := column * 61 + row * 37 + index * 19
		var x_offset := float((seed_value * 17) % 71) / 100.0
		var y_offset := float((seed_value * 29) % 73) / 100.0
		var start := rect.position + Vector2(rect.size.x * x_offset, rect.size.y * y_offset)
		var length := rect.size.x * (0.16 + float(seed_value % 11) / 80.0)
		draw_line(start, start + Vector2(length, 1.5), Color(base.lightened(0.35), 0.075), 1.0)


func _draw_coordinates(cell: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(10, roundi(cell * 0.17))
	for column in range(BOARD_DIMENSION):
		var label := String.chr(65 + column)
		var x := board_rect.position.x + float(column) * cell
		draw_string(font, Vector2(x, board_rect.end.y + 18.0), label, HORIZONTAL_ALIGNMENT_CENTER, cell, font_size, Palette.TEXT_MUTED)
	for row in range(BOARD_DIMENSION):
		var rank := str(9 - row)
		var y := board_rect.position.y + (float(row) + 0.57) * cell
		draw_string(font, Vector2(board_rect.end.x + 10.0, y), rank, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Palette.TEXT_MUTED)


func _draw_action_markers() -> void:
	var markers := _current_action_markers()
	for destination_value in markers:
		var destination := str(destination_value)
		var marker_kind := str(markers[destination])
		var center := _square_center(destination)
		if marker_kind == "capture":
			var capture_radius := board_rect.size.x / BOARD_DIMENSION * 0.40
			draw_circle(center, capture_radius * 0.80, Color(Palette.CAPTURE, 0.10))
			draw_arc(center, capture_radius, 0.0, TAU, 30, Palette.CAPTURE, 4.0, true)
		else:
			var move_radius := board_rect.size.x / BOARD_DIMENSION * 0.12
			draw_circle(center, move_radius, Color(Palette.MOVE, 0.28))
			draw_arc(center, move_radius * 1.34, 0.0, TAU, 24, Color(Palette.MOVE, 0.78), 2.0, true)


func _current_action_markers() -> Dictionary:
	if view_mode != "play" or game_state.is_empty() or GameEngine.is_over(game_state):
		return {}
	var position := _position_data()
	var markers := {}
	if not pending_artillery_actions.is_empty():
		for action in pending_artillery_actions:
			if action.get("effect_target") != null:
				markers[str(action.effect_target)] = "capture"
		return markers
	for action in _legal_actions():
		var action_type := str(action.get("type", ""))
		if not selected_square.is_empty() and action_type == "move" and str(action.get("source", "")) == selected_square:
			var destination := str(action.destination)
			markers[destination] = "capture" if position.has(destination) else "move"
		elif not selected_piece_kind.is_empty() and action_type in ["place", "recall"]:
			if selected_piece_kind == Rules.RECALL:
				if action_type != "recall" or selected_recall_kind.is_empty() or str(action.get("piece", "")) != selected_recall_kind:
					continue
			elif action_type != "place" or str(action.get("piece", "")) != selected_piece_kind:
				continue
			markers[str(action.destination)] = "move"
	return markers


func _draw_position() -> void:
	var cell := board_rect.size.x / BOARD_DIMENSION
	var radius := cell * 0.37
	var position := _position_data()
	var ordered_squares: Array = position.keys()
	ordered_squares.sort_custom(func(a, b): return _screen_row(str(a)) < _screen_row(str(b)))
	for square_value in ordered_squares:
		var square := str(square_value)
		var data: Dictionary = position[square]
		var center := _square_center(square)
		Tokens.draw_stack(
			self, center, radius, str(data.owner), data.kinds,
			square == selected_square, square == hovered_square
		)


func _draw_left_panel() -> void:
	var panel_width := maxf(210.0, board_rect.position.x - 48.0)
	var rect := Rect2(Vector2(20.0, 24.0), Vector2(panel_width - 20.0, size.y - 48.0))
	_draw_panel(rect)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(18.0, 38.0), "T3RNARY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 29, Palette.TEXT)
	draw_string(font, rect.position + Vector2(19.0, 61.0), "PLAY & REPLAY SIMULATOR", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Palette.BRASS_LIGHT)
	draw_line(rect.position + Vector2(18.0, 76.0), Vector2(rect.end.x - 18.0, rect.position.y + 76.0), Palette.PANEL_LINE, 1.0)
	left_mode_rects.clear()
	var tabs := [["play", "PLAY"], ["replay", "REPLAY"]]
	var tab_gap := 5.0
	var tab_width := (rect.size.x - 36.0 - tab_gap) / 2.0
	for index in range(tabs.size()):
		var tab_rect := Rect2(rect.position + Vector2(18.0 + float(index) * (tab_width + tab_gap), 86.0), Vector2(tab_width, 29.0))
		left_mode_rects[tabs[index][0]] = tab_rect
		_draw_button(tab_rect, tabs[index][1], view_mode == tabs[index][0])

	reserve_rects.clear()
	var usable_width := rect.size.x - 36.0
	var column_width := usable_width * 0.5
	var grid_start := 154.0
	var reference_owner := _reference_owner()
	if view_mode == "play":
		var status := _play_status_text()
		draw_string(font, rect.position + Vector2(18.0, 136.0), status, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.TEXT_MUTED)
	elif view_mode == "replay":
		var replay_name := str(replay_document.get("game_id", "No replay loaded"))
		draw_string(font, rect.position + Vector2(18.0, 136.0), replay_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.TEXT_MUTED)
	for index in range(PIECE_ORDER.size()):
		var column := index % 2
		var row := index / 2
		var center := rect.position + Vector2(18.0 + column_width * (float(column) + 0.5), grid_start + float(row) * 76.0)
		var kind: String = PIECE_ORDER[index]
		var icon_rect := Rect2(center - Vector2(column_width * 0.46, 31.0), Vector2(column_width * 0.92, 67.0))
		if view_mode == "play" and not game_state.is_empty():
			reserve_rects[kind] = icon_rect
		if selected_piece_kind == kind:
			draw_rect(icon_rect.grow(2.0), Color(Palette.SELECTED, 0.18))
			draw_rect(icon_rect.grow(2.0), Palette.SELECTED, false, 2.0)
		var remaining := _reserve_count(kind)
		var capacities := _reserve_pile_capacities(kind)
		var pile_counts := _reserve_pile_counts(kind, remaining)
		var pile_radius := minf(17.0, column_width * (0.16 if capacities.size() > 1 else 0.20))
		var pile_gap := pile_radius * 2.25
		for pile_index in range(capacities.size()):
			var pile_x := center.x + (float(pile_index) - float(capacities.size() - 1) * 0.5) * pile_gap
			_draw_reserve_pile(Vector2(pile_x, center.y - 3.0), pile_radius, reference_owner, kind, int(pile_counts[pile_index]))
		var label := _display_name(kind)
		var label_size := 8 if label.length() > 10 else 10
		draw_string(font, center + Vector2(-column_width * 0.46, 31.0), label, HORIZONTAL_ALIGNMENT_CENTER, column_width * 0.92, label_size, Palette.TEXT if selected_piece_kind == kind else Palette.TEXT_MUTED)
	if view_mode == "play":
		draw_string(font, Vector2(rect.position.x + 18.0, rect.end.y - 35.0), "Click a reserve piece to PLACE.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 10, Palette.BRASS_LIGHT)
	elif view_mode == "replay":
		draw_string(font, Vector2(rect.position.x + 18.0, rect.end.y - 35.0), "Use ← and → to review turns.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 10, Palette.BRASS_LIGHT)


func _reserve_count(kind: String) -> int:
	if view_mode == "play" and not game_state.is_empty():
		return int(game_state.reserves[game_state.turn].get(kind, 0))
	return int(Rules.piece_definition(kind).get("starting_count", 0))


func _reserve_pile_capacities(kind: String) -> Array:
	if kind == Rules.INFANTRY:
		return [5, 4]
	return [int(Rules.piece_definition(kind).get("starting_count", 0))]


func _reserve_pile_counts(kind: String, remaining: int) -> Array:
	if kind == Rules.INFANTRY:
		# The four-piece pile is consumed first, followed by the five-piece pile.
		return [mini(remaining, 5), maxi(remaining - 5, 0)]
	return [remaining]


func _draw_reserve_pile(center: Vector2, radius: float, owner: String, kind: String, count: int) -> void:
	if count <= 0:
		Tokens.draw_empty_token(self, center, radius, owner)
	else:
		var kinds: Array = []
		for _piece_index in range(count):
			kinds.append(kind)
		Tokens.draw_stack(self, center + Vector2(0.0, radius * 0.15), radius, owner, kinds)
	var badge_center := center + Vector2(radius * 0.78, radius * 0.72)
	draw_circle(badge_center, radius * 0.43, Palette.PANEL)
	draw_arc(badge_center, radius * 0.43, 0.0, TAU, 24, Palette.PANEL_LINE, 1.0, true)
	var font := ThemeDB.fallback_font
	draw_string(font, badge_center + Vector2(-radius * 0.42, 3.5), str(count), HORIZONTAL_ALIGNMENT_CENTER, radius * 0.84, 9, Palette.TEXT if count > 0 else Palette.TEXT_MUTED)


func _play_status_text() -> String:
	if game_state.is_empty():
		if ai_enabled and setup_white_file >= 0:
			return "Computer is placing the Black Sovereign."
		return "Place White Sovereign on rank 1." if setup_white_file < 0 else "Place Black Sovereign on rank 9."
	if GameEngine.is_over(game_state):
		return "DRAW" if game_state.is_draw else "%s WINS" % str(game_state.winner).to_upper()
	if _is_ai_turn():
		return "COMPUTER THINKING"
	var phase := "OPENING" if GameEngine.in_development(game_state) else "OPEN PLAY"
	return "%s · %s TO ACT" % [phase, str(game_state.turn).to_upper()]


func _reference_owner() -> String:
	if view_mode != "play":
		return Rules.WHITE
	if game_state.is_empty():
		return Rules.WHITE if setup_white_file < 0 else Rules.BLACK
	return str(game_state.turn)


func _draw_right_panel() -> void:
	var panel_x := board_rect.end.x + 44.0
	var rect := Rect2(Vector2(panel_x, 24.0), Vector2(maxf(220.0, size.x - panel_x - 20.0), size.y - 48.0))
	_draw_panel(rect)
	var font := ThemeDB.fallback_font
	right_control_rects.clear()
	recall_kind_rects.clear()
	var position := _position_data()
	var selected: Dictionary = position.get(selected_square, {})
	draw_string(font, rect.position + Vector2(18.0, 34.0), view_mode.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Palette.BRASS_LIGHT)
	var status := _right_status_text()
	draw_string(font, rect.position + Vector2(18.0, 62.0), status, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 16, Palette.TEXT)
	var controls_y := rect.position.y + 78.0
	if view_mode == "play":
		var control_gap := 6.0
		var control_width := (rect.size.x - 36.0 - control_gap) * 0.5
		var undo_rect := Rect2(Vector2(rect.position.x + 18.0, controls_y), Vector2(control_width, 30.0))
		var redo_rect := Rect2(Vector2(undo_rect.end.x + control_gap, controls_y), Vector2(control_width, 30.0))
		right_control_rects["undo"] = undo_rect
		right_control_rects["redo"] = redo_rect
		_draw_button(undo_rect, "UNDO", false)
		_draw_button(redo_rect, "REDO", false)
		var opponent_rect := Rect2(Vector2(rect.position.x + 18.0, controls_y + 37.0), Vector2(rect.size.x - 36.0, 28.0))
		right_control_rects["toggle_ai"] = opponent_rect
		_draw_button(opponent_rect, "OPPONENT: COMPUTER" if ai_enabled else "OPPONENT: HUMAN", ai_enabled)
		if not human_game_path.is_empty():
			draw_string(font, Vector2(rect.position.x + 18.0, controls_y + 80.0), "AUTO-RECORDED · %s" % human_game_id, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 9, Palette.TEXT_MUTED)
		if not pending_artillery_actions.is_empty():
			var no_shoot_rect := Rect2(Vector2(rect.position.x + 18.0, controls_y + 89.0), Vector2(rect.size.x - 36.0, 34.0))
			right_control_rects["no_shoot"] = no_shoot_rect
			_draw_button(no_shoot_rect, "PLACE WITHOUT SHOOTING", true)
	elif view_mode == "replay":
		var open_rect := Rect2(Vector2(rect.position.x + 18.0, controls_y), Vector2(rect.size.x - 36.0, 30.0))
		right_control_rects["open_replay"] = open_rect
		_draw_button(open_rect, "OPEN REPLAY FILE", false)
		var nav_y := controls_y + 38.0
		var gap := 5.0
		var nav_width := (rect.size.x - 36.0 - gap * 3.0) / 4.0
		for index in range(4):
			var nav_rect := Rect2(Vector2(rect.position.x + 18.0 + float(index) * (nav_width + gap), nav_y), Vector2(nav_width, 30.0))
			var names := ["first", "previous", "next", "last"]
			var labels := ["|<", "<", ">", ">|"]
			right_control_rects[names[index]] = nav_rect
			_draw_button(nav_rect, labels[index], false)
		if not replay_states.is_empty():
			draw_string(font, Vector2(rect.position.x + 18.0, nav_y + 50.0), "PLY %d / %d" % [replay_index, replay_actions.size()], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 12, Palette.TEXT_MUTED)
			draw_string(font, Vector2(rect.position.x + 18.0, nav_y + 70.0), _replay_action_text(), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.BRASS_LIGHT)

	var divider_y := rect.position.y + 190.0
	if view_mode == "play" and selected_piece_kind == Rules.RECALL and selected_recall_kind.is_empty() and not game_state.is_empty():
		_draw_recall_choices(rect, divider_y)
		return
	draw_line(Vector2(rect.position.x + 18.0, divider_y), Vector2(rect.end.x - 18.0, divider_y), Palette.PANEL_LINE, 1.0)
	right_workspace_rect = Rect2(
		Vector2(rect.position.x + 12.0, divider_y + 8.0),
		Vector2(rect.size.x - 24.0, rect.end.y - divider_y - 20.0)
	)
	_draw_sidebar_panes(right_workspace_rect, selected)


func _draw_sidebar_panes(workspace: Rect2, selected: Dictionary) -> void:
	const HEADER_HEIGHT := 30.0
	const SPLITTER_HEIGHT := 10.0
	const MIN_EXPANDED_HEIGHT := 112.0
	right_split_track = Rect2()
	var inspector_rect: Rect2
	var notation_rect: Rect2
	if inspector_collapsed and notation_collapsed:
		inspector_rect = Rect2(workspace.position, Vector2(workspace.size.x, HEADER_HEIGHT))
		notation_rect = Rect2(Vector2(workspace.position.x, inspector_rect.end.y + 4.0), Vector2(workspace.size.x, HEADER_HEIGHT))
	elif inspector_collapsed:
		inspector_rect = Rect2(workspace.position, Vector2(workspace.size.x, HEADER_HEIGHT))
		notation_rect = Rect2(Vector2(workspace.position.x, inspector_rect.end.y + 4.0), Vector2(workspace.size.x, workspace.end.y - inspector_rect.end.y - 4.0))
	elif notation_collapsed:
		notation_rect = Rect2(Vector2(workspace.position.x, workspace.end.y - HEADER_HEIGHT), Vector2(workspace.size.x, HEADER_HEIGHT))
		inspector_rect = Rect2(workspace.position, Vector2(workspace.size.x, notation_rect.position.y - workspace.position.y - 4.0))
	else:
		var usable := workspace.size.y - SPLITTER_HEIGHT
		var inspector_height := clampf(usable * right_split_ratio, MIN_EXPANDED_HEIGHT, usable - MIN_EXPANDED_HEIGHT)
		inspector_rect = Rect2(workspace.position, Vector2(workspace.size.x, inspector_height))
		right_split_track = Rect2(Vector2(workspace.position.x, inspector_rect.end.y), Vector2(workspace.size.x, SPLITTER_HEIGHT))
		notation_rect = Rect2(Vector2(workspace.position.x, right_split_track.end.y), Vector2(workspace.size.x, workspace.end.y - right_split_track.end.y))
		draw_rect(right_split_track, Color(0.0, 0.0, 0.0, 0.22))
		draw_line(Vector2(right_split_track.position.x + 34.0, right_split_track.get_center().y), Vector2(right_split_track.end.x - 34.0, right_split_track.get_center().y), Palette.PANEL_LINE, 2.0)
	_draw_stack_inspector_pane(inspector_rect, selected)
	_draw_notation_pane(notation_rect)


func _draw_pane_header(rect: Rect2, title: String, collapsed: bool, control_name: String) -> Rect2:
	var font := ThemeDB.fallback_font
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.18))
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Palette.PANEL_LINE, 1.0)
	draw_string(font, rect.position + Vector2(7.0, 20.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 42.0, 11, Palette.BRASS_LIGHT)
	var toggle := Rect2(Vector2(rect.end.x - 28.0, rect.position.y + 4.0), Vector2(24.0, 22.0))
	right_control_rects[control_name] = toggle
	_draw_button(toggle, "+" if collapsed else "−", false)
	return toggle


func _draw_stack_inspector_pane(rect: Rect2, selected: Dictionary) -> void:
	var header := Rect2(rect.position, Vector2(rect.size.x, minf(30.0, rect.size.y)))
	_draw_pane_header(header, "STACK INSPECTOR", inspector_collapsed, "toggle_inspector")
	if inspector_collapsed or rect.size.y <= 34.0:
		return
	var font := ThemeDB.fallback_font
	var content := Rect2(Vector2(rect.position.x + 7.0, header.end.y + 5.0), Vector2(rect.size.x - 14.0, rect.end.y - header.end.y - 9.0))
	if selected.is_empty():
		draw_string(font, content.position + Vector2(0.0, 17.0), "—", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Palette.TEXT)
		draw_string(font, content.position + Vector2(0.0, 42.0), _selection_help_text(), HORIZONTAL_ALIGNMENT_LEFT, content.size.x, 11, Palette.TEXT_MUTED)
		if not replay_error.is_empty():
			draw_string(font, content.position + Vector2(0.0, 66.0), replay_error, HORIZONTAL_ALIGNMENT_LEFT, content.size.x, 10, Palette.CAPTURE)
		return
	var kinds: Array = selected.kinds
	var owner := str(selected.owner)
	draw_string(font, content.position + Vector2(0.0, 17.0), "%s · HEIGHT %d" % [selected_square, kinds.size()], HORIZONTAL_ALIGNMENT_LEFT, content.size.x, 15, Palette.TEXT)
	var available_height := maxf(58.0, content.size.y - 27.0)
	var radius := minf(23.0, maxf(16.0, available_height / 4.8))
	var overlap_step := radius * 1.18
	var stack_height := radius * 2.0 + overlap_step * float(kinds.size() - 1)
	var first_center_y := content.position.y + 29.0 + maxf(radius, (available_height - stack_height) * 0.5 + radius)
	var center_x := content.position.x + radius + 4.0
	var label_x := center_x + radius + 12.0
	for reverse_index in range(kinds.size()):
		var index := kinds.size() - 1 - reverse_index
		var center := Vector2(center_x, first_center_y + float(reverse_index) * overlap_step)
		Tokens.draw_token(self, center, radius, owner, str(kinds[index]), true, index == kinds.size() - 1)
		var role := "TOP" if index == kinds.size() - 1 else "BURIED"
		var label := "%s · %s" % [_display_name(str(kinds[index])).to_upper(), role]
		draw_string(font, Vector2(label_x, center.y + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, maxf(40.0, content.end.x - label_x), 9, Palette.SELECTED if role == "TOP" else Palette.TEXT_MUTED)


func _draw_notation_pane(rect: Rect2) -> void:
	var header := Rect2(rect.position, Vector2(rect.size.x, minf(30.0, rect.size.y)))
	var toggle := _draw_pane_header(header, "GAME NOTATION", notation_collapsed, "toggle_notation")
	var copy_rect := Rect2(Vector2(toggle.position.x - 55.0, header.position.y + 4.0), Vector2(49.0, 22.0))
	right_control_rects["copy_notation"] = copy_rect
	_draw_button(copy_rect, "COPIED" if Time.get_ticks_msec() < notation_copy_feedback_until else "COPY", Time.get_ticks_msec() < notation_copy_feedback_until)
	if notation_collapsed or rect.size.y <= 34.0:
		return
	var font := ThemeDB.fallback_font
	var entries := _notation_entries()
	var content := Rect2(Vector2(rect.position.x + 7.0, header.end.y + 5.0), Vector2(rect.size.x - 14.0, rect.end.y - header.end.y - 8.0))
	var current_actions := _notation_action_count()
	draw_string(font, content.position + Vector2(0.0, 13.0), "THROUGH PLY %d" % current_actions, HORIZONTAL_ALIGNMENT_LEFT, content.size.x, 9, Palette.TEXT_MUTED)
	if entries.is_empty():
		draw_string(font, content.position + Vector2(0.0, 37.0), "No game notation yet.", HORIZONTAL_ALIGNMENT_LEFT, content.size.x, 11, Palette.TEXT_MUTED)
		return
	var line_height := 17.0
	var available_lines := maxi(1, int((content.size.y - 21.0) / line_height))
	var first := maxi(0, entries.size() - available_lines)
	var y := content.position.y + 31.0
	for index in range(first, entries.size()):
		draw_string(font, Vector2(content.position.x, y), str(entries[index]), HORIZONTAL_ALIGNMENT_LEFT, content.size.x, 10, Palette.TEXT)
		y += line_height


func _right_status_text() -> String:
	if view_mode == "replay":
		return "TOURNAMENT REVIEW"
	if game_state.is_empty():
		return "SOVEREIGN SETUP"
	if GameEngine.is_over(game_state):
		return "GAME COMPLETE"
	if _is_ai_turn():
		return "BLACK · COMPUTER THINKING"
	return "%s · PLY %d" % [str(game_state.turn).to_upper(), int(game_state.ply)]


func _selection_help_text() -> String:
	if view_mode == "play":
		if not pending_artillery_actions.is_empty():
			return "Click a red target to SHOOT, or place without shooting."
		if not selected_piece_kind.is_empty():
			return "Click a highlighted square to PLACE."
		return "Select a stack to MOVE or a reserve piece to PLACE."
	if view_mode == "replay":
		return "Select any occupied square to inspect its stack."
	return "Select any occupied square."


func _replay_action_text() -> String:
	if replay_index <= 0 or replay_index > replay_actions.size():
		return "Initial position"
	return _action_text(replay_actions[replay_index - 1])


func _action_text(action: Dictionary) -> String:
	var normalized := Codec.normalize_action(action)
	if normalized.type == "move":
		return "MOVE %s → %s" % [normalized.source, normalized.destination]
	var verb := "RECALL" if normalized.type == "recall" else ("SHOOT" if normalized.get("effect_target") != null else "PLACE")
	var text := "%s %s @ %s" % [verb, Rules.piece_notation(str(normalized.piece)), normalized.destination]
	if normalized.get("effect_target") != null:
		text += " → %s" % normalized.effect_target
	return text


func _notation_action_count() -> int:
	if view_mode == "play":
		return manual_actions.size()
	if view_mode == "replay":
		return mini(replay_index, replay_actions.size())
	return 0


func _notation_source() -> Dictionary:
	if view_mode == "play":
		if manual_initial_state.is_empty():
			return {"initial_state": {}, "actions": [], "states": [], "game_id": "New game"}
		return {
			"initial_state": manual_initial_state,
			"actions": manual_actions,
			"states": manual_states,
			"game_id": human_game_id,
		}
	if view_mode == "replay" and not replay_states.is_empty():
		var count := mini(replay_index, replay_actions.size())
		return {
			"initial_state": replay_states[0],
			"actions": replay_actions.slice(0, count),
			"states": replay_states.slice(0, count + 1),
			"game_id": str(replay_document.get("game_id", "Replay")),
		}
	return {"initial_state": {}, "actions": [], "states": [], "game_id": ""}


func _sovereign_square_in_state(state: Dictionary, owner: String) -> String:
	for square_value in state.get("board", {}):
		var square := str(square_value)
		var stack: Array = state.board[square]
		if not stack.is_empty() and str(stack[-1].owner) == owner and str(stack[-1].kind) == Rules.SOVEREIGN:
			return square
	return ""


func _notation_entries() -> Array:
	var source := _notation_source()
	var initial: Dictionary = source.initial_state
	if initial.is_empty():
		return []
	var entries: Array = []
	var white_square := _sovereign_square_in_state(initial, Rules.WHITE)
	var black_square := _sovereign_square_in_state(initial, Rules.BLACK)
	if not white_square.is_empty():
		entries.append("1W P-V@%s" % white_square)
	if not black_square.is_empty():
		entries.append("1B P-V@%s" % black_square)
	var turn_numbers := {Rules.WHITE: 2, Rules.BLACK: 2}
	var actions: Array = source.actions
	var states: Array = source.states
	for index in range(actions.size()):
		if index + 1 >= states.size():
			break
		var before: Dictionary = states[index]
		var after: Dictionary = states[index + 1]
		var owner := str(before.get("turn", Rules.WHITE))
		var owner_code := "W" if owner == Rules.WHITE else "B"
		entries.append("%d%s %s" % [int(turn_numbers[owner]), owner_code, _action_notation(actions[index], before, after)])
		turn_numbers[owner] = int(turn_numbers[owner]) + 1
	return entries


func _action_notation(action: Dictionary, before: Dictionary, after: Dictionary) -> String:
	var normalized := Codec.normalize_action(action)
	var result := ""
	if normalized.type == "move":
		var stack: Array = before.get("board", {}).get(str(normalized.source), [])
		var piece_code := "?"
		if not stack.is_empty():
			piece_code = Rules.piece_notation(str(stack[-1].kind))
		var separator := "x" if before.get("board", {}).has(str(normalized.destination)) else "-"
		result = "M-%s:%s%s%s" % [piece_code, normalized.source, separator, normalized.destination]
	else:
		var destination := str(normalized.destination)
		var target = normalized.get("effect_target")
		if normalized.type == "recall":
			result = "P-Rc(%s)@%s" % [Rules.piece_notation(str(normalized.piece)), destination]
		elif str(normalized.piece) == Rules.SPY and before.get("board", {}).has(destination):
			result = "P-Spx%s" % destination
		else:
			result = "P-%s@%s" % [Rules.piece_notation(str(normalized.piece)), destination]
		if target != null:
			result += "x%s" % str(target)
	var actor := str(before.get("turn", Rules.WHITE))
	if str(after.get("winner", "")) == actor:
		result += "#"
	return result


func _notation_copy_text() -> String:
	var source := _notation_source()
	var entries := _notation_entries()
	var initial: Dictionary = source.initial_state
	var ruleset := str(initial.get("rules", {}).get("id", "unknown")) if not initial.is_empty() else "unknown"
	var lines: Array[String] = [
		"T3RNARY GAME NOTATION",
		"Game: %s" % str(source.game_id),
		"Ruleset: %s" % ruleset,
		"Through recorded ply: %d" % _notation_action_count(),
		"",
	]
	for entry in entries:
		lines.append(str(entry))
	return "\n".join(lines)


func _copy_notation_to_clipboard() -> void:
	DisplayServer.clipboard_set(_notation_copy_text())
	notation_copy_feedback_until = Time.get_ticks_msec() + 1200
	queue_redraw()


func _update_right_split(mouse_y: float) -> void:
	if right_workspace_rect.size.y <= 0.0:
		return
	right_split_ratio = clampf(
		(mouse_y - right_workspace_rect.position.y) / right_workspace_rect.size.y,
		0.2,
		0.8
	)
	queue_redraw()


func _draw_recall_choices(rect: Rect2, start_y: float) -> void:
	var font := ThemeDB.fallback_font
	draw_line(Vector2(rect.position.x + 18.0, start_y), Vector2(rect.end.x - 18.0, start_y), Palette.PANEL_LINE, 1.0)
	draw_string(font, Vector2(rect.position.x + 18.0, start_y + 26.0), "CHOOSE A DISCARDED PIECE", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.BRASS_LIGHT)
	var available: Array = []
	for kind in PIECE_ORDER:
		if kind != Rules.RECALL and int(game_state.discards[game_state.turn].get(kind, 0)) > 0:
			for action in _legal_actions():
				if str(action.get("type", "")) == "recall" and str(action.get("piece", "")) == kind:
					available.append(kind)
					break
	for index in range(available.size()):
		var choice_rect := Rect2(Vector2(rect.position.x + 18.0, start_y + 40.0 + float(index) * 32.0), Vector2(rect.size.x - 36.0, 27.0))
		recall_kind_rects[available[index]] = choice_rect
		_draw_button(choice_rect, "%s ×%d" % [_display_name(available[index]), int(game_state.discards[game_state.turn][available[index]])], false)
	if available.is_empty():
		draw_string(font, Vector2(rect.position.x + 18.0, start_y + 62.0), "No legal Recall is available.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.TEXT_MUTED)


func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.34))
	draw_rect(rect.grow(-2.0), Palette.PANEL)
	draw_rect(rect.grow(-2.0), Palette.PANEL_LINE, false, 1.0)
	draw_line(rect.position + Vector2(10.0, 8.0), Vector2(rect.end.x - 10.0, rect.position.y + 8.0), Color(Palette.BRASS, 0.55), 2.0)


func _draw_button(rect: Rect2, label: String, active: bool) -> void:
	var fill := Color(Palette.SELECTED, 0.22) if active else Color(0.0, 0.0, 0.0, 0.28)
	var border := Palette.SELECTED if active else Palette.PANEL_LINE
	draw_rect(rect, fill)
	draw_rect(rect, border, false, 1.0)
	var font := ThemeDB.fallback_font
	var baseline := rect.position.y + rect.size.y * 0.5 + 4.0
	draw_string(font, Vector2(rect.position.x, baseline), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 10, Palette.TEXT if active else Palette.TEXT_MUTED)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if dragging_right_split:
			_update_right_split(event.position.y)
			return
		var new_hover := _square_at(event.position)
		if new_hover != hovered_square:
			hovered_square = new_hover
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not right_split_track.has_point(event.position):
				_handle_click(event.position)
			else:
				dragging_right_split = true
		else:
			dragging_right_split = false
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			selected_square = ""
			_clear_action_selection()
			queue_redraw()
		elif view_mode == "replay" and event.keycode == KEY_LEFT:
			_set_replay_index(replay_index - 1)
		elif view_mode == "replay" and event.keycode == KEY_RIGHT:
			_set_replay_index(replay_index + 1)
		elif view_mode == "play" and event.keycode == KEY_BACKSPACE and event.shift_pressed:
			_redo_manual_action()
		elif view_mode == "play" and event.keycode == KEY_BACKSPACE:
			_undo_manual_action()
		elif view_mode == "play" and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_Z and event.shift_pressed:
			_redo_manual_action()
		elif view_mode == "play" and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_Z:
			_undo_manual_action()
		elif view_mode == "play" and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_Y:
			_redo_manual_action()
		elif view_mode == "play" and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not pending_artillery_actions.is_empty():
			_apply_artillery_without_shooting()


func _handle_click(position: Vector2) -> void:
	for mode in left_mode_rects:
		if left_mode_rects[mode].has_point(position):
			if mode == "play":
				_start_new_game()
			else:
				view_mode = "replay"
				if replay_states.is_empty():
					_open_replay_dialog()
			queue_redraw()
			return
	for control in right_control_rects:
		if right_control_rects[control].has_point(position):
			_handle_right_control(str(control))
			return
	for kind in recall_kind_rects:
		if recall_kind_rects[kind].has_point(position):
			selected_recall_kind = str(kind)
			queue_redraw()
			return
	for kind in reserve_rects:
		if reserve_rects[kind].has_point(position):
			_select_reserve_piece(str(kind))
			return
	var square := _square_at(position)
	if square.is_empty():
		return
	if view_mode == "play":
		_handle_play_square(square)
	else:
		var position_data := _position_data()
		selected_square = square if position_data.has(square) else ""
		queue_redraw()


func _handle_right_control(control: String) -> void:
	match control:
		"undo":
			_undo_manual_action()
		"redo":
			_redo_manual_action()
		"toggle_ai":
			ai_enabled = not ai_enabled
			_clear_action_selection()
			_save_human_game()
			queue_redraw()
			_queue_ai_turn()
		"no_shoot":
			_apply_artillery_without_shooting()
		"open_replay":
			_open_replay_dialog()
		"first":
			_set_replay_index(0)
		"previous":
			_set_replay_index(replay_index - 1)
		"next":
			_set_replay_index(replay_index + 1)
		"last":
			_set_replay_index(replay_states.size() - 1)
		"toggle_inspector":
			inspector_collapsed = not inspector_collapsed
			queue_redraw()
		"toggle_notation":
			notation_collapsed = not notation_collapsed
			queue_redraw()
		"copy_notation":
			_copy_notation_to_clipboard()


func _select_reserve_piece(kind: String) -> void:
	if view_mode != "play" or game_state.is_empty() or GameEngine.is_over(game_state) or _is_ai_turn():
		return
	var has_action := false
	for action in _legal_actions():
		if kind == Rules.RECALL and str(action.get("type", "")) == "recall":
			has_action = true
			break
		if str(action.get("type", "")) == "place" and str(action.get("piece", "")) == kind:
			has_action = true
			break
	if not has_action:
		return
	selected_square = ""
	pending_artillery_actions.clear()
	selected_piece_kind = kind
	selected_recall_kind = ""
	queue_redraw()


func _handle_play_square(square: String) -> void:
	if game_state.is_empty():
		if ai_busy:
			return
		var rank := square.substr(1).to_int()
		var file := square.unicode_at(0) - 65
		if setup_white_file < 0 and rank == 1:
			setup_white_file = file
			setup_position = {square: _stack(Rules.WHITE, [Rules.SOVEREIGN])}
			_queue_ai_turn()
		elif setup_white_file >= 0 and rank == 9:
			_finish_sovereign_setup(file)
		queue_redraw()
		return
	if GameEngine.is_over(game_state):
		return
	if _is_ai_turn():
		return
	if not pending_artillery_actions.is_empty():
		for action in pending_artillery_actions:
			if str(action.get("effect_target", "")) == square:
				_apply_manual_action(action)
				return
		return
	var legal := _legal_actions()
	if not selected_square.is_empty():
		for action in legal:
			if str(action.get("type", "")) == "move" and str(action.get("source", "")) == selected_square and str(action.get("destination", "")) == square:
				_apply_manual_action(action)
				return
	if not selected_piece_kind.is_empty():
		var matching: Array = []
		for action in legal:
			var action_type := str(action.get("type", ""))
			if str(action.get("destination", "")) != square:
				continue
			if selected_piece_kind == Rules.RECALL:
				if action_type == "recall" and str(action.get("piece", "")) == selected_recall_kind:
					matching.append(action)
			elif action_type == "place" and str(action.get("piece", "")) == selected_piece_kind:
				matching.append(action)
		if matching.size() == 1:
			_apply_manual_action(matching[0])
			return
		if matching.size() > 1:
			pending_artillery_actions = matching
			selected_square = square
			queue_redraw()
			return
	var position := _position_data()
	if position.has(square):
		selected_square = square
		selected_piece_kind = ""
		selected_recall_kind = ""
		var stack: Array = game_state.board[square]
		if stack[-1].owner != game_state.turn:
			pending_artillery_actions.clear()
	else:
		selected_square = ""
	queue_redraw()


func _apply_artillery_without_shooting() -> void:
	for action in pending_artillery_actions:
		if action.get("effect_target") == null:
			_apply_manual_action(action)
			return


func _square_at(position: Vector2) -> String:
	if not board_rect.has_point(position):
		return ""
	var cell := board_rect.size.x / BOARD_DIMENSION
	var column := clampi(floori((position.x - board_rect.position.x) / cell), 0, 8)
	var row := clampi(floori((position.y - board_rect.position.y) / cell), 0, 8)
	return String.chr(65 + column) + str(9 - row)


func _square_center(square: String) -> Vector2:
	var column := square.unicode_at(0) - 65
	var rank := square.substr(1).to_int()
	var row := 9 - rank
	var cell := board_rect.size.x / BOARD_DIMENSION
	return board_rect.position + Vector2(float(column) + 0.5, float(row) + 0.5) * cell


func _screen_row(square: String) -> int:
	return 9 - square.substr(1).to_int()


func _display_name(kind: String) -> String:
	return Rules.piece_display_name(kind)
