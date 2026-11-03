extends Control

const Palette = preload("res://scripts/presentation/ternary_palette.gd")
const Tokens = preload("res://scripts/presentation/token_renderer.gd")
const Icons = preload("res://scripts/presentation/piece_icon_renderer.gd")
const Codec = preload("res://scripts/core/ternary_codec.gd")
const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const OpponentAI = preload("res://scripts/core/ternary_ai.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")

const BOARD_DIMENSION := 9
const MOVE_ANIMATION_DURATION := 0.34
const PIECE_ORDER := [
	"sovereign", "infantry", "dragoon", "chariot", "griffin", "marshal",
	"trebuchet", "ballista", "spy", "reinforcement", "recall",
]

var board_rect := Rect2()
var hovered_square := ""
var selected_square := ""
var stack_inspection_expanded := false
var stack_inspection_progress := 0.0
var stack_inspection_target := 0.0
var stack_inspection_hit_rects: Array[Rect2] = []
var move_animation := {}
var move_animation_progress := 0.0
var queue_ai_after_move_animation := false
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
var manual_end_method := ""
var replay_end_method := ""
var selected_piece_kind := ""
var selected_recall_kind := ""
var pending_artillery_actions: Array = []
var replay_document := {}
var replay_states: Array = []
var replay_actions: Array = []
var replay_index := 0
var replay_error := ""
var setup_white_file := -1
var setup_black_file := -1
var setup_position := {}
var file_dialog: FileDialog

var left_mode_rects := {}
var reserve_rects := {}
var reserve_owner_toggle_rect := Rect2()
var reserve_view_owner := ""
var right_control_rects := {}
var recall_kind_rects := {}
var inspector_collapsed := false
var notation_collapsed := false
var right_split_ratio := 0.38
var right_split_track := Rect2()
var right_workspace_rect := Rect2()
var dragging_right_split := false
var notation_copy_feedback_until := 0
var hamburger_rect := Rect2()
var hamburger_open := false
var hamburger_menu_rect := Rect2()
var hamburger_control_rects := {}
var notation_popover_open := false
var notation_overlay_rect := Rect2()
var discard_rects := {}
var expanded_discard_owner := ""
var discard_overlay_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	human_recording_enabled = true
	_build_file_dialog()
	resized.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_equal_approx(stack_inspection_progress, stack_inspection_target):
		stack_inspection_progress = move_toward(stack_inspection_progress, stack_inspection_target, delta * 6.5)
		queue_redraw()
	if not move_animation.is_empty():
		move_animation_progress = minf(1.0, move_animation_progress + delta / MOVE_ANIMATION_DURATION)
		queue_redraw()
		if move_animation_progress >= 1.0:
			move_animation.clear()
			move_animation_progress = 0.0
			if queue_ai_after_move_animation:
				queue_ai_after_move_animation = false
				call_deferred("_queue_ai_turn")
	if ai_thread != null and ai_thread.is_started() and not ai_thread.is_alive():
		var decision = ai_thread.wait_to_finish()
		ai_thread = null
		_complete_threaded_ai_turn(decision)


func _exit_tree() -> void:
	if ai_thread != null and ai_thread.is_started():
		ai_thread.wait_to_finish()
		ai_thread = null


func _build_file_dialog() -> void:
	if is_instance_valid(file_dialog):
		return
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.display_mode = FileDialog.DISPLAY_LIST
	# The native picker supplies the platform's normal detail columns, including
	# Date Modified on macOS, while honoring the requested list layout.
	file_dialog.use_native_dialog = true
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
	manual_end_method = ""
	replay_end_method = ""
	setup_white_file = -1
	setup_black_file = -1
	setup_position = {}
	reserve_view_owner = ""
	_clear_action_selection()
	selected_square = ""
	_reset_stack_inspection()
	_clear_move_animation()
	replay_error = ""
	notation_popover_open = false
	expanded_discard_owner = ""
	hamburger_open = false
	queue_redraw()
	_queue_ai_turn()


func _sovereign_response_files() -> Array[int]:
	if setup_black_file < 0:
		return []
	var reflected := Rules.board_size() - 1 - setup_black_file
	if reflected == setup_black_file:
		return [setup_black_file]
	return [setup_black_file, reflected]


func _finish_sovereign_setup(white_file: int, queue_computer := true) -> void:
	if setup_black_file < 0 or white_file not in _sovereign_response_files():
		return
	setup_white_file = white_file
	game_state = GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(setup_white_file, setup_black_file))
	manual_states = [game_state.duplicate(true)]
	manual_initial_state = game_state.duplicate(true)
	manual_redo_states.clear()
	manual_redo_actions.clear()
	manual_redo_ai_annotations.clear()
	_begin_human_recording()
	setup_position = {}
	selected_square = ""
	_reset_stack_inspection()
	_clear_move_animation()
	queue_redraw()
	if queue_computer:
		_queue_ai_turn()


func _clear_action_selection() -> void:
	selected_piece_kind = ""
	selected_recall_kind = ""
	pending_artillery_actions.clear()


func _reset_stack_inspection() -> void:
	stack_inspection_expanded = false
	stack_inspection_progress = 0.0
	stack_inspection_target = 0.0
	stack_inspection_hit_rects.clear()


func _toggle_stack_inspection() -> void:
	stack_inspection_expanded = not stack_inspection_expanded
	stack_inspection_target = 1.0 if stack_inspection_expanded else 0.0
	queue_redraw()


func _clear_move_animation() -> void:
	move_animation.clear()
	move_animation_progress = 0.0
	queue_ai_after_move_animation = false


func _visual_stack_from_state(state: Dictionary, square: String) -> Dictionary:
	var stack: Array = state.get("board", {}).get(square, [])
	if stack.is_empty():
		return {}
	var kinds: Array = []
	for piece in stack:
		kinds.append(str(piece.kind))
	return {"owner": str(stack[-1].owner), "kinds": kinds}


func _begin_move_animation(before: Dictionary, action: Dictionary) -> bool:
	var normalized := Codec.normalize_action(action)
	if str(normalized.get("type", "")) != "move":
		return false
	var source := str(normalized.get("source", ""))
	var destination := str(normalized.get("destination", ""))
	var moving := _visual_stack_from_state(before, source)
	if moving.is_empty() or source.is_empty() or destination.is_empty():
		return false
	move_animation = {
		"source": source,
		"destination": destination,
		"owner": moving.owner,
		"kinds": moving.kinds.duplicate(),
		"target": _visual_stack_from_state(before, destination),
	}
	move_animation_progress = 0.0
	return true


func _legal_actions() -> Array:
	if view_mode != "play" or game_state.is_empty():
		return []
	return GameEngine.legal_actions(game_state)


func _apply_manual_action(action: Dictionary, ai_decision := {}) -> void:
	var before := game_state.duplicate(true)
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
	var animated_move := _begin_move_animation(before, action)
	selected_square = ""
	_reset_stack_inspection()
	_clear_action_selection()
	queue_redraw()
	if animated_move:
		queue_ai_after_move_animation = _is_ai_turn()
	else:
		_queue_ai_turn()


func _is_ai_turn() -> bool:
	return ai_enabled and not game_state.is_empty() and not GameEngine.is_over(game_state) and str(game_state.turn) == ai_player


func _queue_ai_turn() -> void:
	if not move_animation.is_empty():
		queue_ai_after_move_animation = _is_ai_turn()
		return
	if ai_enabled and game_state.is_empty() and not ai_busy:
		var computer_setup_turn := (ai_player == Rules.BLACK and setup_black_file < 0) or (ai_player == Rules.WHITE and setup_black_file >= 0 and setup_white_file < 0)
		if computer_setup_turn:
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
	if bool(decision.get("resign", false)):
		_apply_ai_resignation(decision)
		return
	_apply_manual_action(decision.action, decision)


func _perform_ai_sovereign_setup() -> void:
	if not ai_enabled or not game_state.is_empty():
		ai_busy = false
		queue_redraw()
		return
	if ai_player == Rules.BLACK and setup_black_file < 0:
		setup_black_file = ai_controller.choose_sovereign_file()
		var black_square := "%s9" % Rules.files().substr(setup_black_file, 1)
		setup_position = {black_square: _stack(Rules.BLACK, [Rules.SOVEREIGN])}
	elif ai_player == Rules.WHITE and setup_black_file >= 0 and setup_white_file < 0:
		var white_file := ai_controller.choose_sovereign_response_file(setup_black_file)
		ai_busy = false
		_finish_sovereign_setup(white_file, false)
		call_deferred("_queue_ai_turn")
		return
	ai_busy = false
	queue_redraw()


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
	if bool(decision.get("resign", false)):
		_apply_ai_resignation(decision)
		return
	_apply_manual_action(decision.action, decision)


func _apply_ai_resignation(decision: Dictionary) -> void:
	if game_state.is_empty() or str(game_state.get("turn", "")) != ai_player:
		return
	game_state = game_state.duplicate(true)
	game_state.winner = Rules.opponent(ai_player)
	game_state.is_draw = false
	manual_end_method = "RESIGNATION"
	last_ai_decision = decision.duplicate(true)
	var annotation := decision.duplicate(true)
	annotation["event"] = "resignation"
	annotation["ply"] = manual_actions.size()
	ai_annotations.append(annotation)
	if not manual_states.is_empty():
		manual_states[-1] = game_state.duplicate(true)
	_save_human_game()
	selected_square = ""
	_reset_stack_inspection()
	_clear_move_animation()
	_clear_action_selection()
	queue_redraw()


func _undo_manual_action() -> void:
	if view_mode != "play" or manual_states.size() <= 1:
		return
	var undo_count := 1
	if ai_enabled and manual_states.size() > 2 and not ai_annotations.is_empty() and str(ai_annotations[-1].get("event", "")) != "resignation" and int(ai_annotations[-1].get("ply", 0)) == manual_actions.size():
		undo_count = 2
	for _step in range(undo_count):
		manual_redo_states.append(manual_states.pop_back())
		var old_ply := manual_actions.size()
		if not manual_actions.is_empty():
			manual_redo_actions.append(manual_actions.pop_back())
		if not ai_annotations.is_empty() and int(ai_annotations[-1].get("ply", 0)) == old_ply:
			manual_redo_ai_annotations.append(ai_annotations.pop_back())
	game_state = manual_states[-1].duplicate(true)
	manual_end_method = ""
	_save_human_game()
	selected_square = ""
	_reset_stack_inspection()
	_clear_move_animation()
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
	manual_end_method = "RESIGNATION" if not ai_annotations.is_empty() and str(ai_annotations[-1].get("event", "")) == "resignation" and GameEngine.is_over(game_state) else ""
	_save_human_game()
	selected_square = ""
	_reset_stack_inspection()
	_clear_move_animation()
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
			"computer_color": ai_player if ai_enabled else "",
			"human_color": Rules.opponent(ai_player) if ai_enabled else "",
			"ruleset": str(manual_initial_state.get("rules", {}).get("id", "")),
			"outcome": outcome,
			"completed": not game_state.is_empty() and GameEngine.is_over(game_state),
			"end_method": manual_end_method,
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
	if not is_instance_valid(file_dialog):
		_build_file_dialog()
	file_dialog.current_file = ""
	file_dialog.popup_file_dialog()


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
	reserve_view_owner = ""
	replay_document = document.duplicate(true)
	replay_actions = document.actions.duplicate(true)
	replay_states = [Codec.normalize_state(document.initial_state)]
	replay_error = ""
	replay_end_method = str(document.get("metadata", {}).get("end_method", ""))
	notation_popover_open = false
	expanded_discard_owner = ""
	hamburger_open = false
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
	if replay_end_method == "RESIGNATION" and replay_states.size() == replay_actions.size() + 1:
		state = replay_states[-1].duplicate(true)
		state.winner = Rules.WHITE
		state.is_draw = false
		replay_states[-1] = state
	replay_index = 0
	game_state = replay_states[0].duplicate(true)
	selected_square = ""
	_reset_stack_inspection()
	_clear_move_animation()
	_clear_action_selection()
	queue_redraw()


func _set_replay_index(index: int) -> void:
	if replay_states.is_empty():
		return
	var previous_index := replay_index
	var previous_state := game_state.duplicate(true)
	replay_index = clampi(index, 0, replay_states.size() - 1)
	game_state = replay_states[replay_index].duplicate(true)
	selected_square = ""
	_reset_stack_inspection()
	_clear_move_animation()
	if replay_index == previous_index + 1 and previous_index < replay_actions.size():
		_begin_move_animation(previous_state, replay_actions[previous_index])
	queue_redraw()


func _draw() -> void:
	_draw_table()
	_calculate_board_rect()
	_draw_scene_reserves()
	_draw_board()
	_draw_action_markers()
	_draw_position()
	_draw_move_animation()
	_draw_stack_explosion()
	_draw_game_over_overlay()
	_draw_scene_chrome()
	_draw_context_action_overlay()
	if notation_popover_open:
		_draw_notation_popover()
	if not expanded_discard_owner.is_empty():
		_draw_discard_explosion(expanded_discard_owner)
	if hamburger_open:
		_draw_hamburger_menu()


func _draw_table() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.TABLE_WOOD)
	var plank_height := maxf(74.0, size.y / 11.0)
	for plank in range(int(ceil(size.y / plank_height)) + 1):
		var y := float(plank) * plank_height
		var plank_color := Palette.TABLE_WOOD_LIGHT if plank % 3 == 1 else Palette.TABLE_WOOD_DARK
		draw_rect(Rect2(Vector2(0.0, y), Vector2(size.x, plank_height)), Color(plank_color, 0.18 if plank % 2 == 0 else 0.11))
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.06, 0.035, 0.02, 0.72), 2.0)
	for index in range(86):
		var seed_value := index * 97 + 31
		var y := fmod(float(seed_value * 43), maxf(1.0, size.y))
		var x := fmod(float(seed_value * 67), maxf(1.0, size.x * 0.38)) - size.x * 0.08
		var length := size.x * (0.30 + float(seed_value % 17) / 55.0)
		var grain := Color(0.78, 0.49, 0.25, 0.07) if index % 3 else Color(0.06, 0.025, 0.01, 0.13)
		var points := PackedVector2Array()
		for segment in range(7):
			var t := float(segment) / 6.0
			points.append(Vector2(x + length * t, y + sin(t * PI * 2.0 + float(seed_value)) * (2.0 + float(seed_value % 5))))
		draw_polyline(points, grain, 1.0, true)
	# Sparse knots break the mechanically uniform plank texture. Their low
	# contrast keeps the play area quiet while making the table feel real.
	for knot_index in range(7):
		var knot_seed := knot_index * 113 + 47
		var knot_center := Vector2(
			fmod(float(knot_seed * 71), maxf(1.0, size.x)),
			fmod(float(knot_seed * 41), maxf(1.0, size.y))
		)
		for ring in range(3):
			draw_ellipse(knot_center, 15.0 + float(ring) * 8.0, 4.0 + float(ring) * 2.6, Color(0.04, 0.018, 0.008, 0.10 - float(ring) * 0.018), false, 1.0, true)
	# A restrained vignette keeps the physical play surface centered without
	# turning the table back into a software panel.
	for index in range(7, 0, -1):
		var alpha := 0.018 * float(8 - index)
		draw_circle(size * Vector2(0.50, 0.46), minf(size.x, size.y) * float(index) * 0.14, Color(0.03, 0.025, 0.02, alpha))


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
	if view_mode == "play" and not manual_end_method.is_empty():
		return manual_end_method
	if view_mode == "replay" and replay_index == replay_states.size() - 1 and not replay_end_method.is_empty():
		return replay_end_method
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
	var available_height := maxf(540.0, size.y - 92.0)
	var available_width := maxf(540.0, size.x - 540.0)
	var side := floorf(minf(available_height, available_width))
	var left := floorf((size.x - side) * 0.5)
	var top := floorf((size.y - side) * 0.5 + 12.0)
	board_rect = Rect2(Vector2(left, top), Vector2(side, side))


func _draw_board() -> void:
	var frame := board_rect.grow(24.0)
	# Several soft offset silhouettes approximate the ambient occlusion a heavy
	# wooden board casts onto the table.
	for shadow_step in range(5, 0, -1):
		var spread := float(shadow_step) * 4.0
		var shadow_rect := frame.grow(spread)
		shadow_rect.position += Vector2(3.0, 6.0)
		draw_rect(shadow_rect, Color(0.0, 0.0, 0.0, 0.035 * float(6 - shadow_step)))
	draw_rect(frame.grow(8.0), Palette.TABLE_WOOD_DARK)
	draw_rect(frame.grow(5.0), Palette.TRAY_RIM)
	draw_rect(frame, Palette.FRAME_DARK)
	draw_rect(frame.grow(-4.0), Color("0d1012"))
	draw_rect(frame.grow(-7.0), Color(Palette.FRAME_EDGE, 0.88), false, 2.0)
	draw_rect(frame.grow(-11.0), Color(Palette.BRASS, 0.72), false, 1.4)
	draw_rect(board_rect.grow(8.0), Palette.FRAME_MID)
	# Miter seams make the surround read as four assembled rails rather than a
	# single software rectangle.
	for corner in [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]:
		var inward := board_rect.get_center().direction_to(corner) * -18.0
		draw_line(corner, corner + inward, Color(0.05, 0.035, 0.025, 0.62), 1.5, true)
	draw_line(frame.position + Vector2(5.0, 5.0), Vector2(frame.end.x - 5.0, frame.position.y + 5.0), Color(1.0, 0.82, 0.56, 0.13), 2.0)
	draw_line(Vector2(frame.end.x - 4.0, frame.position.y + 5.0), frame.end - Vector2(4.0, 5.0), Color(0.0, 0.0, 0.0, 0.58), 3.0)
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
	# Thin edge light and shadow keep each square materially present without
	# reintroducing corner markers or a heavy software grid.
	draw_line(rect.position + Vector2(1.0, 1.0), Vector2(rect.end.x - 1.0, rect.position.y + 1.0), Color(base.lightened(0.42), 0.12), 1.0)
	draw_line(rect.position + Vector2(1.0, 1.0), Vector2(rect.position.x + 1.0, rect.end.y - 1.0), Color(base.lightened(0.35), 0.08), 1.0)
	draw_line(Vector2(rect.position.x + 1.0, rect.end.y - 1.0), rect.end - Vector2(1.0, 1.0), Color(base.darkened(0.48), 0.15), 1.0)
	# Broad translucent bands produce a softly mottled finish under the finer
	# fibers instead of an absolutely flat digital fill.
	for band in range(4):
		var band_y := rect.position.y + rect.size.y * (0.11 + float(band) * 0.22)
		var band_height := rect.size.y * (0.09 + float((column * 3 + row + band) % 4) * 0.018)
		var band_color := Color(base.lightened(0.24), 0.025) if band % 2 == 0 else Color(base.darkened(0.24), 0.030)
		draw_rect(Rect2(Vector2(rect.position.x + 2.0, band_y), Vector2(rect.size.x - 4.0, band_height)), band_color)
	for index in range(11):
		var seed_value := column * 61 + row * 37 + index * 19
		var x_offset := float((seed_value * 17) % 79) / 100.0
		var y_offset := float((seed_value * 29) % 83) / 100.0
		var start := rect.position + Vector2(rect.size.x * x_offset, rect.size.y * y_offset)
		var length := rect.size.x * (0.12 + float(seed_value % 17) / 64.0)
		var grain_color := Color(base.lightened(0.38), 0.065) if index % 2 == 0 else Color(base.darkened(0.35), 0.075)
		var points := PackedVector2Array([start])
		for segment in range(1, 4):
			var t := float(segment) / 3.0
			points.append(start + Vector2(length * t, sin(float(seed_value) + t * PI) * 2.2))
		draw_polyline(points, grain_color, 1.0, true)


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
		if marker_kind in ["capture", "enemy_capture"]:
			var capture_radius := board_rect.size.x / BOARD_DIMENSION * 0.40
			var capture_color := Color(0.78, 0.52, 0.25, 0.92) if marker_kind == "enemy_capture" else Palette.CAPTURE
			draw_circle(center, capture_radius * 0.80, Color(capture_color, 0.10))
			draw_arc(center, capture_radius, 0.0, TAU, 30, capture_color, 4.0, true)
		else:
			var move_radius := board_rect.size.x / BOARD_DIMENSION * 0.12
			var move_color := Color(0.78, 0.52, 0.25, 0.80) if marker_kind == "enemy_move" else Color(Palette.MOVE, 0.78)
			draw_circle(center, move_radius, Color(move_color, 0.22))
			draw_arc(center, move_radius * 1.34, 0.0, TAU, 24, move_color, 2.0, true)


func _current_action_markers() -> Dictionary:
	if not selected_square.is_empty() and not game_state.is_empty() and game_state.board.has(selected_square):
		var selected_stack: Array = game_state.board[selected_square]
		var inspecting_enemy := view_mode == "replay" or str(selected_stack[-1].owner) != str(game_state.get("turn", ""))
		if inspecting_enemy:
			var inspection_markers := {}
			for destination_value in GameEngine.movement_destinations(game_state, selected_square):
				var destination := str(destination_value)
				inspection_markers[destination] = "enemy_capture" if game_state.board.has(destination) else "enemy_move"
			return inspection_markers
	if view_mode != "play":
		return {}
	if game_state.is_empty():
		if ai_busy:
			return {}
		var setup_markers := {}
		if setup_black_file < 0:
			for file in range(Rules.board_size()):
				setup_markers["%s9" % Rules.files().substr(file, 1)] = "move"
		else:
			for file in _sovereign_response_files():
				setup_markers["%s1" % Rules.files().substr(file, 1)] = "move"
		return setup_markers
	if GameEngine.is_over(game_state):
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
		if not move_animation.is_empty() and square == str(move_animation.destination):
			continue
		if square == selected_square and stack_inspection_progress > 0.001:
			continue
		Tokens.draw_stack(
			self, center, radius, str(data.owner), data.kinds,
			square == selected_square, square == hovered_square
		)


func _draw_move_animation() -> void:
	if move_animation.is_empty():
		return
	var source := str(move_animation.source)
	var destination := str(move_animation.destination)
	var kinds: Array = move_animation.kinds
	if kinds.is_empty():
		return
	var cell := board_rect.size.x / BOARD_DIMENSION
	var radius := cell * 0.37
	var progress := smoothstep(0.0, 1.0, move_animation_progress)
	var source_center := _square_center(source)
	var destination_center := _square_center(destination)
	var center := source_center.lerp(destination_center, progress)
	# A Griffin reads as a leap while ray pieces slide directly along their line.
	if str(kinds[-1]) == Rules.GRIFFIN:
		center.y -= sin(progress * PI) * cell * 0.24
	var target: Dictionary = move_animation.get("target", {})
	if not target.is_empty() and progress < 0.74:
		Tokens.draw_stack(self, destination_center, radius, str(target.owner), target.kinds)
	var shadow_radius := radius * (0.72 + sin(progress * PI) * 0.10)
	draw_ellipse(center + Vector2(0.0, radius * 0.46), shadow_radius, radius * 0.30, Color(0.0, 0.0, 0.0, 0.30))
	Tokens.draw_stack(self, center, radius, str(move_animation.owner), kinds)
	if progress >= 0.72:
		var impact_progress := clampf((progress - 0.72) / 0.28, 0.0, 1.0)
		draw_arc(destination_center, radius * (0.75 + impact_progress * 0.48), 0.0, TAU, 32, Color(Palette.BRASS_LIGHT, (1.0 - impact_progress) * 0.62), 2.0, true)


func _draw_scene_reserves() -> void:
	reserve_rects.clear()
	discard_rects.clear()
	var side_gap := 54.0
	var left_rect := Rect2(
		Vector2(22.0, board_rect.position.y + 34.0),
		Vector2(maxf(170.0, board_rect.position.x - side_gap - 22.0), board_rect.size.y - 68.0)
	)
	var right_rect := Rect2(
		Vector2(board_rect.end.x + side_gap, board_rect.position.y + 34.0),
		Vector2(maxf(170.0, size.x - board_rect.end.x - side_gap - 22.0), board_rect.size.y - 68.0)
	)
	_draw_scene_reserve_side(Rules.WHITE, left_rect)
	_draw_scene_reserve_side(Rules.BLACK, right_rect)


func _draw_scene_reserve_side(owner: String, rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var active := not game_state.is_empty() and view_mode == "play" and str(game_state.turn) == owner and not _is_ai_turn()
	var discard_height := 86.0
	var reserve_tray := Rect2(rect.position + Vector2(0.0, 34.0), Vector2(rect.size.x, rect.size.y - discard_height - 44.0))
	var discard_tray := Rect2(Vector2(rect.position.x, reserve_tray.end.y + 10.0), Vector2(rect.size.x, discard_height))
	_draw_recessed_tray(reserve_tray)
	_draw_recessed_tray(discard_tray)
	var heading := "%s PIECES" % owner.to_upper()
	if active:
		heading += " · YOUR TURN"
	draw_string(font, rect.position + Vector2(0.0, 18.0), heading, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11, Palette.BRASS_LIGHT if active else Palette.TEXT_MUTED)
	draw_line(rect.position + Vector2(12.0, 29.0), Vector2(rect.end.x - 12.0, rect.position.y + 29.0), Color(Palette.BRASS, 0.40), 1.0)
	var columns := 2
	var rows := int(ceil(float(PIECE_ORDER.size()) / float(columns)))
	var usable_height := rect.size.y - 42.0 - discard_height
	var row_step := usable_height / float(rows)
	var column_step := rect.size.x / float(columns)
	var radius := minf(22.0, minf(column_step * 0.20, row_step * 0.25))
	for index in range(PIECE_ORDER.size()):
		var column := index % columns
		var row := index / columns
		var kind: String = PIECE_ORDER[index]
		var center := rect.position + Vector2(column_step * (float(column) + 0.5), 55.0 + row_step * (float(row) + 0.38))
		var hit_rect := Rect2(center - Vector2(column_step * 0.43, radius * 1.65), Vector2(column_step * 0.86, radius * 3.3))
		reserve_rects["%s|%s" % [owner, kind]] = hit_rect
		if active and selected_piece_kind == kind:
			draw_circle(center - Vector2(0.0, radius * 0.18), radius * 1.45, Color(Palette.SELECTED, 0.13))
		var remaining := _reserve_count_for(owner, kind)
		var capacities := _reserve_pile_capacities(kind)
		var pile_counts := _reserve_pile_counts(kind, remaining)
		if kind == Rules.INFANTRY:
			_draw_sideways_infantry_reserve(center, radius, owner, pile_counts)
		else:
			var pile_gap := radius * 2.2
			for pile_index in range(capacities.size()):
				var pile_x := center.x + (float(pile_index) - float(capacities.size() - 1) * 0.5) * pile_gap
				_draw_reserve_pile(Vector2(pile_x, center.y), radius, owner, kind, int(pile_counts[pile_index]))
		draw_string(font, Vector2(center.x - column_step * 0.45, center.y + radius * 1.85), _display_name(kind), HORIZONTAL_ALIGNMENT_CENTER, column_step * 0.90, 9, Palette.TEXT if active and selected_piece_kind == kind else Palette.TEXT_MUTED)
	var discard_center := Vector2(rect.get_center().x, rect.end.y - 33.0)
	var discard_rect := Rect2(discard_center - Vector2(rect.size.x * 0.40, 31.0), Vector2(rect.size.x * 0.80, 63.0))
	discard_rects[owner] = discard_rect
	_draw_discard_pile(owner, discard_center, minf(23.0, rect.size.x * 0.09))
	draw_string(font, Vector2(discard_rect.position.x, discard_rect.end.y + 1.0), "DISCARDS · %d" % _discard_count(owner), HORIZONTAL_ALIGNMENT_CENTER, discard_rect.size.x, 9, Palette.TEXT_MUTED)


func _draw_recessed_tray(rect: Rect2) -> void:
	for shadow_step in range(4, 0, -1):
		var shadow_rect := rect.grow(9.0 + float(shadow_step) * 2.0)
		shadow_rect.position += Vector2(2.0, 4.0)
		draw_rect(shadow_rect, Color(0.0, 0.0, 0.0, 0.035 * float(5 - shadow_step)))
	draw_rect(rect.grow(7.0), Palette.TABLE_WOOD_DARK)
	draw_rect(rect.grow(5.0), Palette.TRAY_RIM)
	draw_rect(rect.grow(2.0), Color(0.02, 0.018, 0.015, 0.98))
	draw_rect(rect, Palette.TRAY_WELL)
	draw_rect(rect, Color(Palette.FRAME_EDGE, 0.78), false, 1.25)
	draw_line(rect.position + Vector2(2.0, 2.0), Vector2(rect.end.x - 2.0, rect.position.y + 2.0), Color(0.0, 0.0, 0.0, 0.66), 4.0)
	draw_line(rect.position + Vector2(2.0, 2.0), Vector2(rect.position.x + 2.0, rect.end.y - 2.0), Color(0.0, 0.0, 0.0, 0.52), 4.0)
	for index in range(12):
		var y := rect.position.y + 8.0 + fmod(float(index * 37), maxf(1.0, rect.size.y - 16.0))
		var offset := float((index * 23) % 17)
		draw_line(Vector2(rect.position.x + 7.0 + offset, y), Vector2(rect.end.x - 7.0, y + 3.0), Color(0.56, 0.42, 0.28, 0.045), 1.0)
	# A faint pebbled leather grain prevents the well from reading as a flat
	# black UI panel.
	for index in range(34):
		var seed_value := index * 59 + roundi(rect.position.x * 0.13)
		var point := rect.position + Vector2(
			7.0 + fmod(float(seed_value * 31), maxf(1.0, rect.size.x - 14.0)),
			7.0 + fmod(float(seed_value * 47), maxf(1.0, rect.size.y - 14.0))
		)
		draw_circle(point, 0.7 + float(index % 3) * 0.25, Color(0.78, 0.67, 0.49, 0.055))


func _draw_sideways_infantry_reserve(center: Vector2, radius: float, owner: String, pile_counts: Array) -> void:
	var group_gap := radius * 0.30
	var widths: Array[float] = []
	var total_width := 0.0
	for count_value in pile_counts:
		var count := int(count_value)
		var width := radius * (1.12 + 0.24 * float(maxi(0, count - 1)))
		widths.append(width)
		total_width += width
	total_width += group_gap * float(maxi(0, pile_counts.size() - 1))
	var cursor_x := center.x - total_width * 0.5
	for group_index in range(pile_counts.size()):
		var count := int(pile_counts[group_index])
		var width := widths[group_index]
		var group_center := Vector2(cursor_x + width * 0.5, center.y - radius * 0.04)
		_draw_sideways_infantry_group(group_center, radius, owner, count, width)
		var badge_center := group_center + Vector2(width * 0.34, radius * 0.94)
		draw_circle(badge_center, radius * 0.34, Palette.PANEL)
		draw_arc(badge_center, radius * 0.34, 0.0, TAU, 22, Palette.PANEL_LINE, 1.0, true)
		draw_string(ThemeDB.fallback_font, badge_center + Vector2(-radius * 0.32, 3.0), str(count), HORIZONTAL_ALIGNMENT_CENTER, radius * 0.64, 8, Palette.TEXT if count > 0 else Palette.TEXT_MUTED)
		cursor_x += width + group_gap


func _draw_sideways_infantry_group(center: Vector2, radius: float, owner: String, count: int, width: float) -> void:
	var edge := Palette.token_edge(owner)
	var body := Palette.token_body(owner)
	var face := Palette.token_face(owner)
	var stripe := Palette.token_layer_border(owner)
	var ink := Palette.token_ink(owner)
	draw_ellipse(center + Vector2(radius * 0.10, radius * 0.64), width * 0.54, radius * 0.34, Color(0.0, 0.0, 0.0, 0.34))
	if count <= 0:
		draw_ellipse(center, width * 0.42, radius * 0.79, Color(face, 0.055), false, maxf(1.2, radius * 0.07), true)
		return
	var step := radius * 0.24
	var occupied_width := radius * 1.12 + step * float(count - 1)
	var first_x := center.x - occupied_width * 0.5 + radius * 0.54
	for piece_index in range(count):
		var piece_center := Vector2(first_x + step * float(piece_index), center.y)
		draw_ellipse(piece_center + Vector2(radius * 0.04, radius * 0.07), radius * 0.31, radius * 0.91, Color(0.0, 0.0, 0.0, 0.30))
		draw_ellipse(piece_center, radius * 0.29, radius * 0.90, stripe)
		draw_ellipse(piece_center - Vector2(radius * 0.015, 0.0), radius * 0.24, radius * 0.84, body)
		draw_ellipse(piece_center - Vector2(radius * 0.025, 0.0), radius * 0.18, radius * 0.77, Color(1.0, 1.0, 1.0, 0.08), false, maxf(1.0, radius * 0.025), true)
	var end_center := Vector2(first_x + step * float(count - 1), center.y)
	draw_ellipse(end_center, radius * 0.42, radius * 0.90, edge)
	draw_ellipse(end_center - Vector2(radius * 0.025, 0.0), radius * 0.34, radius * 0.78, face)
	for column in [-0.14, 0.0, 0.14]:
		var x: float = end_center.x + radius * float(column)
		draw_line(Vector2(x, end_center.y - radius * 0.31), Vector2(x, end_center.y + radius * 0.31), ink, maxf(1.0, radius * 0.055), true)


func _reserve_count_for(owner: String, kind: String) -> int:
	if not game_state.is_empty():
		return int(game_state.reserves[owner].get(kind, 0))
	var count := int(Rules.piece_definition(kind).get("starting_count", 0))
	return count - 1 if kind == Rules.SOVEREIGN else count


func _discard_count(owner: String) -> int:
	if game_state.is_empty():
		return 0
	var count := 0
	for kind in Rules.piece_types():
		count += int(game_state.discards[owner].get(kind, 0))
	return count


func _discard_kinds(owner: String) -> Array:
	var kinds: Array = []
	if game_state.is_empty():
		return kinds
	for kind in PIECE_ORDER:
		for _index in range(int(game_state.discards[owner].get(kind, 0))):
			kinds.append(kind)
	return kinds


func _draw_discard_pile(owner: String, center: Vector2, radius: float) -> void:
	var kinds := _discard_kinds(owner)
	if kinds.is_empty():
		Tokens.draw_empty_token(self, center, radius, owner)
		return
	var visible: Array = kinds.slice(maxi(0, kinds.size() - 5), kinds.size())
	Tokens.draw_stack(self, center + Vector2(0.0, radius * 0.20), radius, owner, visible)


func _draw_stack_explosion() -> void:
	stack_inspection_hit_rects.clear()
	if selected_square.is_empty() or stack_inspection_progress <= 0.001:
		return
	var position := _position_data()
	if not position.has(selected_square):
		return
	var selected: Dictionary = position[selected_square]
	var kinds: Array = selected.kinds
	if kinds.is_empty():
		return
	var cell := board_rect.size.x / BOARD_DIMENSION
	var anchor := _square_center(selected_square)
	var progress := smoothstep(0.0, 1.0, stack_inspection_progress)
	var label_progress := smoothstep(0.24, 0.82, progress)
	var place_right := anchor.x <= board_rect.get_center().x
	var direction := 1.0 if place_right else -1.0
	var radius := cell * 0.31
	var vertical_step := cell * 0.72
	var spread_height := vertical_step * float(kinds.size() - 1)
	var first_y := clampf(anchor.y - spread_height * 0.5, board_rect.position.y + radius + 5.0, board_rect.end.y - radius - 5.0 - spread_height)
	var expanded_x := clampf(anchor.x + direction * cell * 0.48, board_rect.position.x + radius + 5.0, board_rect.end.x - radius - 5.0)
	var font := ThemeDB.fallback_font
	for index in range(kinds.size() - 1, -1, -1):
		var display_index := kinds.size() - 1 - index
		var stacked_center := anchor + Vector2(0.0, radius * 0.13 * float(index - kinds.size() + 1))
		var expanded_center := Vector2(expanded_x, first_y + vertical_step * float(display_index))
		var center := stacked_center.lerp(expanded_center, progress)
		Tokens.draw_token(self, center, radius, str(selected.owner), str(kinds[index]), true, index == kinds.size() - 1)
		var role := "TOP PIECE" if index == kinds.size() - 1 else "BURIED"
		var piece_name := _display_name(str(kinds[index])).to_upper()
		var label_width := cell * 1.48 * label_progress
		var label_height := cell * 0.32
		var label_x := center.x + direction * (radius + cell * 0.10)
		if not place_right:
			label_x -= label_width
		var label_rect := Rect2(Vector2(label_x, center.y - label_height * 0.5), Vector2(label_width, label_height))
		if label_progress > 0.01:
			var connector_end := Vector2(label_rect.position.x if place_right else label_rect.end.x, center.y)
			draw_line(center + Vector2(direction * radius * 0.76, 0.0), connector_end, Color(Palette.SELECTED, 0.82 * label_progress), 1.5)
			draw_rect(label_rect, Color(Palette.PANEL, 0.88 * label_progress))
			draw_line(Vector2(label_rect.position.x, label_rect.end.y), label_rect.end, Color(Palette.SELECTED, 0.72 * label_progress), 1.0)
			if label_progress > 0.72:
				var text_alpha := smoothstep(0.72, 1.0, label_progress)
				draw_string(font, label_rect.position + Vector2(7.0, label_height * 0.43), piece_name, HORIZONTAL_ALIGNMENT_LEFT, label_rect.size.x - 14.0, 9, Color(Palette.TEXT, text_alpha))
				draw_string(font, label_rect.position + Vector2(7.0, label_height * 0.79), role, HORIZONTAL_ALIGNMENT_LEFT, label_rect.size.x - 14.0, 7, Color(Palette.SELECTED if role == "TOP PIECE" else Palette.TEXT_MUTED, text_alpha))
		stack_inspection_hit_rects.append(Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).merge(label_rect))
	var square_tag_width := cell * 0.78
	var square_tag := Rect2(anchor + Vector2(-square_tag_width * 0.5, cell * 0.34), Vector2(square_tag_width, cell * 0.20))
	draw_rect(square_tag, Color(Palette.PANEL, 0.78 * label_progress))
	draw_string(font, square_tag.position + Vector2(0.0, square_tag.size.y * 0.75), "%s · HEIGHT %d" % [selected_square, kinds.size()], HORIZONTAL_ALIGNMENT_CENTER, square_tag.size.x, 7, Color(Palette.BRASS_LIGHT, label_progress))
	stack_inspection_hit_rects.append(square_tag)


func _draw_scene_chrome() -> void:
	right_control_rects.clear()
	hamburger_control_rects.clear()
	var font := ThemeDB.fallback_font
	hamburger_rect = Rect2(Vector2(18.0, 16.0), Vector2(46.0, 40.0))
	draw_rect(hamburger_rect, Color(Palette.PANEL, 0.90))
	draw_rect(hamburger_rect, Palette.PANEL_LINE, false, 1.0)
	for index in range(3):
		var y := hamburger_rect.position.y + 12.0 + float(index) * 8.0
		draw_line(Vector2(hamburger_rect.position.x + 12.0, y), Vector2(hamburger_rect.end.x - 12.0, y), Palette.TEXT, 2.0)
	draw_string(font, Vector2(76.0, 43.0), "T3RNARY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 25, Palette.TEXT)
	var status_width := minf(430.0, board_rect.size.x * 0.52)
	var status_rect := Rect2(Vector2(board_rect.get_center().x - status_width * 0.5, 15.0), Vector2(status_width, 40.0))
	draw_rect(status_rect, Color(Palette.PANEL, 0.86))
	draw_rect(status_rect, Color(Palette.BRASS, 0.65), false, 1.0)
	var status := _play_status_text() if view_mode == "play" else ("REPLAY · PLY %d / %d" % [replay_index, replay_actions.size()])
	draw_string(font, Vector2(status_rect.position.x, status_rect.position.y + 25.0), status, HORIZONTAL_ALIGNMENT_CENTER, status_rect.size.x, 11, Palette.TEXT)
	if view_mode == "replay":
		_draw_replay_overlay_controls()
	elif not game_state.is_empty():
		var undo_rect := Rect2(Vector2(board_rect.position.x + 14.0, board_rect.end.y - 45.0), Vector2(58.0, 28.0))
		var redo_rect := Rect2(Vector2(undo_rect.end.x + 6.0, undo_rect.position.y), Vector2(58.0, 28.0))
		right_control_rects.undo = undo_rect
		right_control_rects.redo = redo_rect
		_draw_button(undo_rect, "UNDO", false)
		_draw_button(redo_rect, "REDO", false)


func _draw_replay_overlay_controls() -> void:
	var width := minf(420.0, board_rect.size.x * 0.52)
	var rect := Rect2(Vector2(board_rect.get_center().x - width * 0.5, board_rect.end.y - 54.0), Vector2(width, 39.0))
	draw_rect(rect, Color(Palette.PANEL, 0.91))
	draw_rect(rect, Color(Palette.BRASS, 0.62), false, 1.0)
	var names := ["first", "previous", "next", "last"]
	var labels := ["|<", "<", ">", ">|"]
	var button_width := 52.0
	for index in range(2):
		var button := Rect2(Vector2(rect.position.x + 8.0 + float(index) * (button_width + 5.0), rect.position.y + 5.0), Vector2(button_width, 29.0))
		right_control_rects[names[index]] = button
		_draw_button(button, labels[index], false)
	for index in range(2, 4):
		var offset := float(index - 2)
		var button := Rect2(Vector2(rect.end.x - 8.0 - (2.0 - offset) * button_width - (1.0 - offset) * 5.0, rect.position.y + 5.0), Vector2(button_width, 29.0))
		right_control_rects[names[index]] = button
		_draw_button(button, labels[index], false)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(rect.position.x + 120.0, rect.position.y + 24.0), "%d / %d" % [replay_index, replay_actions.size()], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 240.0, 11, Palette.TEXT)


func _draw_context_action_overlay() -> void:
	recall_kind_rects.clear()
	if view_mode != "play" or game_state.is_empty():
		return
	if not pending_artillery_actions.is_empty():
		var rect := Rect2(Vector2(board_rect.get_center().x - 105.0, board_rect.end.y - 94.0), Vector2(210.0, 31.0))
		right_control_rects.no_shoot = rect
		_draw_button(rect, "PLACE WITHOUT SHOOTING", true)
	if selected_piece_kind == Rules.RECALL and selected_recall_kind.is_empty():
		var available: Array = []
		for kind in PIECE_ORDER:
			if kind == Rules.RECALL or int(game_state.discards[game_state.turn].get(kind, 0)) <= 0:
				continue
			for action in _legal_actions():
				if str(action.get("type", "")) == "recall" and str(action.get("piece", "")) == kind:
					available.append(kind)
					break
		var width := 250.0
		var height := 46.0 + 34.0 * float(maxi(1, available.size()))
		var panel := Rect2(board_rect.get_center() - Vector2(width, height) * 0.5, Vector2(width, height))
		_draw_panel(panel)
		var font := ThemeDB.fallback_font
		draw_string(font, panel.position + Vector2(14.0, 28.0), "CHOOSE A PIECE TO RECALL", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 28.0, 10, Palette.BRASS_LIGHT)
		for index in range(available.size()):
			var choice := Rect2(Vector2(panel.position.x + 14.0, panel.position.y + 39.0 + float(index) * 34.0), Vector2(panel.size.x - 28.0, 28.0))
			recall_kind_rects[available[index]] = choice
			_draw_button(choice, "%s ×%d" % [_display_name(available[index]), int(game_state.discards[game_state.turn][available[index]])], false)


func _draw_notation_popover() -> void:
	var width := minf(390.0, board_rect.size.x * 0.42)
	var rect := Rect2(Vector2(board_rect.end.x - width - 15.0, board_rect.position.y + 15.0), Vector2(width, board_rect.size.y - 82.0))
	notation_overlay_rect = rect
	draw_rect(rect, Color(Palette.PANEL, 0.97))
	draw_rect(rect, Palette.BRASS, false, 1.5)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(16.0, 29.0), "GAME NOTATION", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 130.0, 13, Palette.BRASS_LIGHT)
	var copy_rect := Rect2(Vector2(rect.end.x - 105.0, rect.position.y + 9.0), Vector2(58.0, 26.0))
	var close_rect := Rect2(Vector2(rect.end.x - 39.0, rect.position.y + 9.0), Vector2(26.0, 26.0))
	right_control_rects.copy_notation = copy_rect
	right_control_rects.close_notation = close_rect
	_draw_button(copy_rect, "COPIED" if Time.get_ticks_msec() < notation_copy_feedback_until else "COPY", Time.get_ticks_msec() < notation_copy_feedback_until)
	_draw_button(close_rect, "×", false)
	draw_line(Vector2(rect.position.x + 14.0, rect.position.y + 44.0), Vector2(rect.end.x - 14.0, rect.position.y + 44.0), Palette.PANEL_LINE, 1.0)
	var entries := _notation_entries()
	var line_height := 18.0
	var available_lines := maxi(1, int((rect.size.y - 70.0) / line_height))
	var first := maxi(0, entries.size() - available_lines)
	var y := rect.position.y + 67.0
	for index in range(first, entries.size()):
		draw_string(font, Vector2(rect.position.x + 16.0, y), str(entries[index]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32.0, 10, Palette.TEXT)
		y += line_height


func _draw_discard_explosion(owner: String) -> void:
	var kinds := _discard_kinds(owner)
	var columns := 6
	var rows := maxi(1, int(ceil(float(kinds.size()) / float(columns))))
	var token_radius := minf(27.0, board_rect.size.x * 0.025)
	var width := maxf(310.0, float(columns) * token_radius * 2.35 + 32.0)
	var height := maxf(140.0, float(rows) * token_radius * 2.45 + 68.0)
	discard_overlay_rect = Rect2(board_rect.get_center() - Vector2(width, height) * 0.5, Vector2(width, height))
	draw_rect(discard_overlay_rect, Color(Palette.PANEL, 0.98))
	draw_rect(discard_overlay_rect, Palette.BRASS, false, 1.5)
	var font := ThemeDB.fallback_font
	draw_string(font, discard_overlay_rect.position + Vector2(16.0, 28.0), "%s DISCARDS · %d" % [owner.to_upper(), kinds.size()], HORIZONTAL_ALIGNMENT_LEFT, discard_overlay_rect.size.x - 32.0, 12, Palette.BRASS_LIGHT)
	if kinds.is_empty():
		draw_string(font, discard_overlay_rect.position + Vector2(16.0, 68.0), "No pieces have been discarded.", HORIZONTAL_ALIGNMENT_LEFT, discard_overlay_rect.size.x - 32.0, 11, Palette.TEXT_MUTED)
		return
	for index in range(kinds.size()):
		var column := index % columns
		var row := index / columns
		var center := discard_overlay_rect.position + Vector2(30.0 + token_radius + float(column) * token_radius * 2.35, 48.0 + token_radius + float(row) * token_radius * 2.45)
		Tokens.draw_token(self, center, token_radius, owner, str(kinds[index]))


func _draw_hamburger_menu() -> void:
	var width := 245.0
	var items: Array = [
		["play", "NEW PLAY GAME"],
		["replay", "OPEN REPLAY"],
		["notation", "HIDE NOTATION" if notation_popover_open else "SHOW NOTATION"],
		["toggle_ai", "OPPONENT: COMPUTER" if ai_enabled else "OPPONENT: HUMAN"],
	]
	if ai_enabled:
		items.append(["toggle_ai_side", "PLAY AS %s" % Rules.opponent(ai_player).to_upper()])
	var height := 28.0 + float(items.size()) * 37.0
	hamburger_menu_rect = Rect2(Vector2(18.0, 62.0), Vector2(width, height))
	_draw_panel(hamburger_menu_rect)
	hamburger_control_rects.clear()
	for index in range(items.size()):
		var rect := Rect2(Vector2(hamburger_menu_rect.position.x + 12.0, hamburger_menu_rect.position.y + 14.0 + float(index) * 37.0), Vector2(hamburger_menu_rect.size.x - 24.0, 30.0))
		hamburger_control_rects[str(items[index][0])] = rect
		_draw_button(rect, str(items[index][1]), (str(items[index][0]) == view_mode) or (str(items[index][0]) == "notation" and notation_popover_open))


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
	# Leave clearance beneath the reserve-owner header for physical inventory.
	var grid_start := 216.0
	var reference_owner := _reserve_display_owner()
	if view_mode == "play":
		var status := _play_status_text()
		draw_string(font, rect.position + Vector2(18.0, 136.0), status, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.TEXT_MUTED)
	elif view_mode == "replay":
		var replay_name := str(replay_document.get("game_id", "No replay loaded"))
		draw_string(font, rect.position + Vector2(18.0, 136.0), replay_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.TEXT_MUTED)
	reserve_owner_toggle_rect = Rect2(rect.position + Vector2(18.0, 145.0), Vector2(rect.size.x - 36.0, 25.0))
	if game_state.is_empty():
		reserve_owner_toggle_rect = Rect2()
	else:
		var reserve_label := "%s RESERVE" % reference_owner.to_upper()
		if view_mode == "play":
			reserve_label += " · ACTIVE" if reference_owner == str(game_state.turn) else " · VIEW ONLY"
		_draw_button(reserve_owner_toggle_rect, reserve_label, view_mode == "play" and reference_owner == str(game_state.turn))
	for index in range(PIECE_ORDER.size()):
		var column := index % 2
		var row := index / 2
		var center := rect.position + Vector2(18.0 + column_width * (float(column) + 0.5), grid_start + float(row) * 76.0)
		var kind: String = PIECE_ORDER[index]
		var icon_rect := Rect2(center - Vector2(column_width * 0.46, 31.0), Vector2(column_width * 0.92, 67.0))
		if view_mode == "play" and not game_state.is_empty() and reference_owner == str(game_state.turn):
			reserve_rects[kind] = icon_rect
		if selected_piece_kind == kind:
			draw_rect(icon_rect.grow(2.0), Color(Palette.SELECTED, 0.18))
			draw_rect(icon_rect.grow(2.0), Palette.SELECTED, false, 2.0)
		var remaining := _reserve_count(kind)
		var pile_counts := _reserve_pile_counts(kind, remaining)
		var pile_radius := minf(17.0, column_width * 0.20)
		if kind == Rules.INFANTRY:
			_draw_sideways_infantry_reserve(center - Vector2(0.0, 3.0), pile_radius, reference_owner, pile_counts)
		else:
			_draw_reserve_pile(center - Vector2(0.0, 3.0), pile_radius, reference_owner, kind, int(pile_counts[0]))
		var label := _display_name(kind)
		var label_size := 8 if label.length() > 10 else 10
		draw_string(font, center + Vector2(-column_width * 0.46, 31.0), label, HORIZONTAL_ALIGNMENT_CENTER, column_width * 0.92, label_size, Palette.TEXT if selected_piece_kind == kind else Palette.TEXT_MUTED)
	if view_mode == "play":
		var reserve_help := "Click a reserve piece to PLACE." if game_state.is_empty() or reference_owner == str(game_state.turn) else "Opponent reserve · view only."
		draw_string(font, Vector2(rect.position.x + 18.0, rect.end.y - 35.0), reserve_help, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 10, Palette.BRASS_LIGHT)
	elif view_mode == "replay":
		draw_string(font, Vector2(rect.position.x + 18.0, rect.end.y - 35.0), "Use ← and → to review turns.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 10, Palette.BRASS_LIGHT)


func _reserve_count(kind: String) -> int:
	if not game_state.is_empty():
		return int(game_state.reserves[_reserve_display_owner()].get(kind, 0))
	return int(Rules.piece_definition(kind).get("starting_count", 0))


func _reserve_pile_capacities(kind: String) -> Array:
	return [int(Rules.piece_definition(kind).get("starting_count", 0))]


func _reserve_pile_counts(kind: String, remaining: int) -> Array:
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
		if ai_enabled and ai_busy:
			return "Computer is choosing %s's Sovereign position." % ai_player.capitalize()
		if setup_black_file < 0:
			return "Black chooses a Sovereign square on rank 9."
		return "White chooses a highlighted Sovereign square on rank 1."
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
		return Rules.BLACK if setup_black_file < 0 else Rules.WHITE
	return str(game_state.turn)


func _reserve_display_owner() -> String:
	if reserve_view_owner in [Rules.WHITE, Rules.BLACK]:
		return reserve_view_owner
	return _reference_owner()


func _toggle_reserve_owner() -> void:
	if game_state.is_empty():
		return
	reserve_view_owner = Rules.opponent(_reserve_display_owner())
	selected_square = ""
	_reset_stack_inspection()
	_clear_action_selection()
	queue_redraw()


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
		var opponent_row_width := rect.size.x - 36.0
		var side_width := 93.0
		var opponent_rect := Rect2(Vector2(rect.position.x + 18.0, controls_y + 37.0), Vector2(opponent_row_width - side_width - control_gap, 28.0))
		var side_rect := Rect2(Vector2(opponent_rect.end.x + control_gap, controls_y + 37.0), Vector2(side_width, 28.0))
		right_control_rects["toggle_ai"] = opponent_rect
		_draw_button(opponent_rect, "OPPONENT: COMPUTER" if ai_enabled else "OPPONENT: HUMAN", ai_enabled)
		if ai_enabled:
			right_control_rects["toggle_ai_side"] = side_rect
			_draw_button(side_rect, "PLAY: %s" % Rules.opponent(ai_player).to_upper(), true)
		else:
			_draw_button(side_rect, "HOTSEAT", false)
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
		return "%s · COMPUTER THINKING" % ai_player.to_upper()
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
	if not black_square.is_empty():
		entries.append("1B P-V@%s" % black_square)
	if not white_square.is_empty():
		entries.append("1W P-V@%s" % white_square)
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
	if view_mode == "play" and manual_end_method == "RESIGNATION":
		lines.insert(3, "Result: White wins by resignation")
	elif view_mode == "replay" and replay_index == replay_states.size() - 1 and replay_end_method == "RESIGNATION":
		lines.insert(3, "Result: White wins by resignation")
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
			if hamburger_open or notation_popover_open or not expanded_discard_owner.is_empty():
				hamburger_open = false
				notation_popover_open = false
				expanded_discard_owner = ""
				queue_redraw()
				return
			selected_square = ""
			_reset_stack_inspection()
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
	if not move_animation.is_empty():
		return
	if hamburger_rect.has_point(position):
		hamburger_open = not hamburger_open
		queue_redraw()
		return
	if hamburger_open:
		for control in hamburger_control_rects:
			if hamburger_control_rects[control].has_point(position):
				_handle_hamburger_control(str(control))
				return
		hamburger_open = false
		queue_redraw()
		return
	if not expanded_discard_owner.is_empty():
		expanded_discard_owner = ""
		queue_redraw()
		return
	if notation_popover_open:
		for control in ["copy_notation", "close_notation"]:
			if right_control_rects.has(control) and right_control_rects[control].has_point(position):
				_handle_right_control(control)
				return
		if notation_overlay_rect.has_point(position):
			return
		notation_popover_open = false
		queue_redraw()
		return
	if stack_inspection_expanded:
		for hit_rect in stack_inspection_hit_rects:
			if hit_rect.has_point(position):
				_toggle_stack_inspection()
				return
	for owner in discard_rects:
		if discard_rects[owner].has_point(position):
			expanded_discard_owner = str(owner)
			queue_redraw()
			return
	if reserve_owner_toggle_rect.has_point(position):
		_toggle_reserve_owner()
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
	for reserve_key in reserve_rects:
		if reserve_rects[reserve_key].has_point(position):
			var parts := str(reserve_key).split("|")
			if parts.size() == 2 and str(parts[0]) == str(game_state.get("turn", "")):
				reserve_view_owner = str(parts[0])
				_select_reserve_piece(str(parts[1]))
			return
	var square := _square_at(position)
	if square.is_empty():
		return
	if view_mode == "play":
		_handle_play_square(square)
	else:
		var position_data := _position_data()
		if position_data.has(square) and square == selected_square:
			_toggle_stack_inspection()
		else:
			selected_square = square if position_data.has(square) else ""
			_reset_stack_inspection()
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
		"toggle_ai_side":
			if ai_enabled and not ai_busy:
				ai_player = Rules.opponent(ai_player)
				_start_new_game()
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
		"close_notation":
			notation_popover_open = false
			queue_redraw()


func _handle_hamburger_control(control: String) -> void:
	hamburger_open = false
	match control:
		"play":
			_start_new_game()
		"replay":
			view_mode = "replay"
			_open_replay_dialog()
		"notation":
			notation_popover_open = not notation_popover_open
			queue_redraw()
		"toggle_ai":
			_handle_right_control("toggle_ai")
		"toggle_ai_side":
			_handle_right_control("toggle_ai_side")


func _select_reserve_piece(kind: String) -> void:
	if view_mode != "play" or game_state.is_empty() or GameEngine.is_over(game_state) or _is_ai_turn():
		return
	if _reserve_display_owner() != str(game_state.turn):
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
	_reset_stack_inspection()
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
		if setup_black_file < 0 and rank == 9:
			setup_black_file = file
			setup_position = {square: _stack(Rules.BLACK, [Rules.SOVEREIGN])}
			_queue_ai_turn()
		elif setup_black_file >= 0 and rank == 1 and file in _sovereign_response_files():
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
			_reset_stack_inspection()
			queue_redraw()
			return
	var position := _position_data()
	if position.has(square):
		if square == selected_square:
			_toggle_stack_inspection()
			return
		selected_square = square
		_reset_stack_inspection()
		selected_piece_kind = ""
		selected_recall_kind = ""
		var stack: Array = game_state.board[square]
		if stack[-1].owner != game_state.turn:
			pending_artillery_actions.clear()
	else:
		selected_square = ""
		_reset_stack_inspection()
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
