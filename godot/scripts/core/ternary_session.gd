class_name TernarySession
extends Node

const Codec = preload("res://scripts/core/ternary_codec.gd")
const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const OpponentAI = preload("res://scripts/core/ternary_ai.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")

const AUTOSAVE_SCHEMA_VERSION := 1
const DEFAULT_AUTOSAVE_PATH := "user://active_session.json"

signal state_changed(reason: String)
signal setup_changed()
signal action_committed(before: Dictionary, action: Dictionary, after: Dictionary, decision: Dictionary)
signal ai_busy_changed(busy: bool)
signal session_error(message: String)

var game_state := {}
var initial_state := {}
var states: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var redo_states: Array[Dictionary] = []
var redo_actions: Array[Dictionary] = []
var redo_annotations: Array[Dictionary] = []
var annotations: Array[Dictionary] = []
var end_method := ""

var setup_black_file := -1
var setup_white_file := -1

var ai_enabled := false
var ai_player := Rules.BLACK
var ai_busy := false
var ai_thread: Thread
var ai_request_checksum := ""
var waiting_for_presentation := false

var recording_enabled := true
var game_id := ""
var recording_path := ""
var autosave_enabled := false
var autosave_path := DEFAULT_AUTOSAVE_PATH


func _process(_delta: float) -> void:
	if ai_thread != null and ai_thread.is_started() and not ai_thread.is_alive():
		var decision = ai_thread.wait_to_finish()
		ai_thread = null
		_complete_ai_turn(decision)


func _exit_tree() -> void:
	if ai_thread != null and ai_thread.is_started():
		ai_thread.wait_to_finish()
		ai_thread = null


func configure_opponent(enabled: bool, human_color := Rules.WHITE, restart := true) -> void:
	ai_enabled = enabled
	ai_player = Rules.opponent(human_color)
	if restart:
		start_new_game()
	else:
		# Opponent ownership is a session control, not part of the rules state.
		# A computer can therefore adopt its side of an existing setup or game.
		_queue_ai_turn()


func start_new_game() -> void:
	game_state = {}
	initial_state = {}
	states.clear()
	actions.clear()
	redo_states.clear()
	redo_actions.clear()
	redo_annotations.clear()
	annotations.clear()
	end_method = ""
	setup_black_file = -1
	setup_white_file = -1
	waiting_for_presentation = false
	game_id = ""
	recording_path = ""
	_set_ai_busy(false)
	setup_changed.emit()
	state_changed.emit("new_game")
	save_autosave()
	_queue_ai_turn()


func is_setup_complete() -> bool:
	return not game_state.is_empty()


func setup_board() -> Dictionary:
	var board := {}
	if setup_black_file >= 0:
		board["%s9" % Rules.files().substr(setup_black_file, 1)] = [
			{"owner": Rules.BLACK, "kind": Rules.SOVEREIGN},
		]
	if setup_white_file >= 0:
		board["%s1" % Rules.files().substr(setup_white_file, 1)] = [
			{"owner": Rules.WHITE, "kind": Rules.SOVEREIGN},
		]
	return board


func setup_prompt() -> String:
	if setup_black_file < 0:
		return "Black chooses a Sovereign square on rank 9."
	if setup_white_file < 0:
		return "White chooses a mirrored Sovereign square on rank 1."
	return ""


func choose_sovereign_square(square: String) -> bool:
	if is_setup_complete() or square.length() < 2:
		return false
	var file := Rules.files().find(square.substr(0, 1).to_upper())
	var rank := int(square.substr(1))
	if file < 0:
		return false
	if setup_black_file < 0:
		if rank != 9 or (ai_enabled and ai_player == Rules.BLACK):
			return false
		setup_black_file = file
		save_autosave()
		setup_changed.emit()
		_queue_ai_turn()
		return true
	if setup_white_file < 0:
		if rank != 1 or file not in sovereign_response_files() or (ai_enabled and ai_player == Rules.WHITE):
			return false
		_finish_setup(file)
		return true
	return false


func sovereign_response_files() -> Array[int]:
	if setup_black_file < 0:
		return []
	var reflected := Rules.board_size() - 1 - setup_black_file
	return [setup_black_file] if reflected == setup_black_file else [setup_black_file, reflected]


func legal_actions() -> Array:
	if game_state.is_empty() or waiting_for_presentation:
		return []
	return GameEngine.legal_actions(game_state)


func apply_action(action: Dictionary, decision := {}) -> bool:
	if game_state.is_empty() or waiting_for_presentation or GameEngine.is_over(game_state):
		return false
	if not Codec.actions_contain(GameEngine.legal_actions(game_state), action):
		return false
	var before := game_state.duplicate(true)
	var normalized := Codec.normalize_action(action)
	var next_state := GameEngine.apply_action(game_state, normalized)
	if next_state.is_empty():
		return false
	game_state = next_state
	end_method = _classify_end_method(before, normalized, game_state)
	actions.append(normalized)
	states.append(game_state.duplicate(true))
	if not decision.is_empty():
		var annotation: Dictionary = decision.duplicate(true)
		annotation["ply"] = actions.size()
		annotation.erase("action")
		annotations.append(annotation)
	redo_states.clear()
	redo_actions.clear()
	redo_annotations.clear()
	waiting_for_presentation = true
	_save_recording()
	save_autosave()
	action_committed.emit(before, normalized, game_state.duplicate(true), decision.duplicate(true))
	return true


func presentation_complete() -> void:
	waiting_for_presentation = false
	save_autosave()
	state_changed.emit("action")
	_queue_ai_turn()


func undo() -> bool:
	if states.size() <= 1 or ai_busy or waiting_for_presentation:
		return false
	var undo_count := 1
	if ai_enabled and states.size() > 2 and not annotations.is_empty() and int(annotations[-1].get("ply", 0)) == actions.size():
		undo_count = 2
	for _step in range(undo_count):
		if states.size() <= 1:
			break
		redo_states.append(states.pop_back())
		var old_ply := actions.size()
		if not actions.is_empty():
			redo_actions.append(actions.pop_back())
		if not annotations.is_empty() and int(annotations[-1].get("ply", 0)) == old_ply:
			redo_annotations.append(annotations.pop_back())
	game_state = states[-1].duplicate(true)
	end_method = ""
	_save_recording()
	save_autosave()
	state_changed.emit("undo")
	return true


func redo() -> bool:
	if redo_states.is_empty() or redo_actions.is_empty() or ai_busy or waiting_for_presentation:
		return false
	var redo_count := mini(2, redo_actions.size()) if ai_enabled else 1
	for _step in range(redo_count):
		actions.append(redo_actions.pop_back())
		states.append(redo_states.pop_back())
		var restored_ply := actions.size()
		if not redo_annotations.is_empty() and int(redo_annotations[-1].get("ply", 0)) == restored_ply:
			annotations.append(redo_annotations.pop_back())
	game_state = states[-1].duplicate(true)
	end_method = ""
	if GameEngine.is_over(game_state) and actions.size() > 0 and states.size() > 1:
		end_method = _classify_end_method(states[-2], actions[-1], game_state)
	_save_recording()
	save_autosave()
	state_changed.emit("redo")
	return true


func _finish_setup(white_file: int) -> void:
	setup_white_file = white_file
	game_state = GameEngine.initial_state(
		Rules.current_beta_ruleset(),
		Vector2i(setup_white_file, setup_black_file),
	)
	initial_state = game_state.duplicate(true)
	states.clear()
	states.append(game_state.duplicate(true))
	_begin_recording()
	save_autosave()
	setup_changed.emit()
	state_changed.emit("setup_complete")
	_queue_ai_turn()


func _queue_ai_turn() -> void:
	if waiting_for_presentation or ai_busy or not ai_enabled:
		return
	if game_state.is_empty():
		var computer_setup_turn := (
			(ai_player == Rules.BLACK and setup_black_file < 0)
			or (ai_player == Rules.WHITE and setup_black_file >= 0 and setup_white_file < 0)
		)
		if computer_setup_turn:
			_set_ai_busy(true)
			call_deferred("_perform_ai_setup")
		return
	if GameEngine.is_over(game_state) or str(game_state.turn) != ai_player:
		return
	_set_ai_busy(true)
	ai_request_checksum = Codec.state_checksum(game_state)
	ai_thread = Thread.new()
	var snapshot := game_state.duplicate(true)
	if ai_thread.start(_compute_ai_decision.bind(snapshot)) != OK:
		ai_thread = null
		var decision := _compute_ai_decision(snapshot)
		_complete_ai_turn(decision)


func _perform_ai_setup() -> void:
	var ai := OpponentAI.new()
	if ai_player == Rules.BLACK and setup_black_file < 0:
		setup_black_file = ai.choose_sovereign_file()
		_set_ai_busy(false)
		save_autosave()
		setup_changed.emit()
		return
	if ai_player == Rules.WHITE and setup_black_file >= 0 and setup_white_file < 0:
		var response := ai.choose_sovereign_response_file(setup_black_file)
		_set_ai_busy(false)
		_finish_setup(response)
		return
	_set_ai_busy(false)


func _compute_ai_decision(snapshot: Dictionary) -> Dictionary:
	return OpponentAI.new().choose_action(snapshot)


func _complete_ai_turn(decision: Variant) -> void:
	if not decision is Dictionary or game_state.is_empty() or Codec.state_checksum(game_state) != ai_request_checksum:
		_set_ai_busy(false)
		return
	_set_ai_busy(false)
	if bool(decision.get("resign", false)):
		_apply_ai_resignation(decision)
		return
	if not decision.has("action") or not apply_action(decision.action, decision):
		session_error.emit("The computer could not produce a legal action.")


func _apply_ai_resignation(decision: Dictionary) -> void:
	if game_state.is_empty() or str(game_state.turn) != ai_player:
		return
	game_state = game_state.duplicate(true)
	game_state.winner = Rules.opponent(ai_player)
	game_state.is_draw = false
	end_method = "RESIGNATION"
	var annotation: Dictionary = decision.duplicate(true)
	annotation["event"] = "resignation"
	annotation["ply"] = actions.size()
	annotations.append(annotation)
	if not states.is_empty():
		states[-1] = game_state.duplicate(true)
	_save_recording()
	save_autosave()
	state_changed.emit("resignation")


func _classify_end_method(before: Dictionary, action: Dictionary, after: Dictionary) -> String:
	if after.is_empty() or not GameEngine.is_over(after):
		return ""
	if bool(after.get("is_draw", false)):
		return "NO LEGAL ACTIONS"
	if str(action.get("type", "")) != "move":
		return "VICTORY"
	var destination := str(action.get("destination", ""))
	var target: Array = before.get("board", {}).get(destination, [])
	if not target.is_empty() and str(target[-1].get("kind", "")) == Rules.SOVEREIGN:
		return "SOVEREIGN CAPTURE"
	var source: Array = before.get("board", {}).get(str(action.get("source", "")), [])
	if not source.is_empty() and str(source[-1].get("kind", "")) == Rules.SOVEREIGN:
		var destination_rank := Rules.square_to_xy(destination).y
		var winner := str(after.get("winner", ""))
		if destination_rank == (Rules.board_size() - 1 if winner == Rules.WHITE else 0):
			return "CONQUER"
	return "VICTORY"


func _set_ai_busy(value: bool) -> void:
	if ai_busy == value:
		return
	ai_busy = value
	ai_busy_changed.emit(ai_busy)


func autosave_document() -> Dictionary:
	return {
		"schema_version": AUTOSAVE_SCHEMA_VERSION,
		"contract_version": Rules.CONTRACT_VERSION,
		"setup_black_file": setup_black_file,
		"setup_white_file": setup_white_file,
		"initial_state": initial_state.duplicate(true),
		"game_state": game_state.duplicate(true),
		"actions": actions.duplicate(true),
		"redo_actions": redo_actions.duplicate(true),
		"annotations": annotations.duplicate(true),
		"redo_annotations": redo_annotations.duplicate(true),
		"end_method": end_method,
		"ai_enabled": ai_enabled,
		"ai_player": ai_player,
		"game_id": game_id,
		"recording_path": recording_path,
		"updated_unix": int(Time.get_unix_time_from_system()),
	}


func save_autosave() -> Error:
	if not autosave_enabled:
		return OK
	var temporary_path := autosave_path + ".tmp"
	var backup_path := autosave_path + ".bak"
	var error := Codec.save_json(temporary_path, autosave_document())
	if error != OK:
		session_error.emit("The active game could not be saved.")
		return error
	var absolute_path := ProjectSettings.globalize_path(autosave_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(autosave_path):
		error = DirAccess.rename_absolute(absolute_path, absolute_backup)
		if error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			session_error.emit("The active game could not be saved.")
			return error
	error = DirAccess.rename_absolute(absolute_temporary, absolute_path)
	if error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		session_error.emit("The active game could not be saved.")
		return error
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	return OK


func restore_autosave() -> bool:
	if not autosave_enabled:
		return false
	var document = Codec.load_json(autosave_path) if FileAccess.file_exists(autosave_path) else null
	if document is Dictionary:
		if _autosave_document_is_complete(document):
			return false
		if restore_session_document(document):
			return true
	var backup_path := autosave_path + ".bak"
	document = Codec.load_json(backup_path) if FileAccess.file_exists(backup_path) else null
	if document is Dictionary:
		if _autosave_document_is_complete(document):
			return false
		if restore_session_document(document):
			save_autosave()
			return true
	return false


func _autosave_document_is_complete(document: Dictionary) -> bool:
	var saved_state = document.get("game_state", {})
	return saved_state is Dictionary and not saved_state.is_empty() and GameEngine.is_over(saved_state)


func restore_session_document(document: Dictionary) -> bool:
	if int(document.get("schema_version", 0)) != AUTOSAVE_SCHEMA_VERSION:
		return false
	var restored_black_file := int(document.get("setup_black_file", -1))
	var restored_white_file := int(document.get("setup_white_file", -1))
	if restored_black_file < -1 or restored_black_file >= Rules.board_size():
		return false
	if restored_white_file < -1 or restored_white_file >= Rules.board_size():
		return false
	if restored_white_file >= 0 and restored_black_file < 0:
		return false

	var restored_initial_raw = document.get("initial_state", {})
	var restored_game_raw = document.get("game_state", {})
	if not restored_initial_raw is Dictionary or not restored_game_raw is Dictionary:
		return false
	var restored_initial: Dictionary = {}
	var restored_game: Dictionary = {}
	var restored_states: Array[Dictionary] = []
	var restored_actions: Array[Dictionary] = []
	if not restored_initial_raw.is_empty():
		if restored_black_file < 0 or restored_white_file < 0:
			return false
		restored_initial = Codec.normalize_state(restored_initial_raw)
		var cursor := restored_initial.duplicate(true)
		restored_states.append(cursor.duplicate(true))
		for raw_action in document.get("actions", []):
			if not raw_action is Dictionary:
				return false
			var action := Codec.normalize_action(raw_action)
			if not Codec.actions_contain(GameEngine.legal_actions(cursor), action):
				return false
			cursor = GameEngine.apply_action(cursor, action)
			if cursor.is_empty():
				return false
			restored_actions.append(action)
			restored_states.append(cursor.duplicate(true))
		restored_game = cursor.duplicate(true)
		var restored_end_method := str(document.get("end_method", ""))
		if restored_end_method == "RESIGNATION" and not restored_game_raw.is_empty():
			var resignation_state := Codec.normalize_state(restored_game_raw)
			if int(resignation_state.get("ply", -1)) != int(restored_game.get("ply", -2)):
				return false
			restored_game = resignation_state
			restored_states[-1] = restored_game.duplicate(true)
	elif not restored_game_raw.is_empty() or not document.get("actions", []).is_empty():
		return false

	var restored_redo_actions: Array[Dictionary] = []
	for raw_redo in document.get("redo_actions", []):
		if not raw_redo is Dictionary:
			return false
		restored_redo_actions.append(Codec.normalize_action(raw_redo))
	var restored_redo_states: Array[Dictionary] = []
	restored_redo_states.resize(restored_redo_actions.size())
	var redo_cursor := restored_game.duplicate(true)
	for index in range(restored_redo_actions.size() - 1, -1, -1):
		var redo_action: Dictionary = restored_redo_actions[index]
		if redo_cursor.is_empty() or not Codec.actions_contain(GameEngine.legal_actions(redo_cursor), redo_action):
			return false
		redo_cursor = GameEngine.apply_action(redo_cursor, redo_action)
		if redo_cursor.is_empty():
			return false
		restored_redo_states[index] = redo_cursor.duplicate(true)

	setup_black_file = restored_black_file
	setup_white_file = restored_white_file
	initial_state = restored_initial
	game_state = restored_game
	states = restored_states
	actions = restored_actions
	redo_actions = restored_redo_actions
	redo_states = restored_redo_states
	annotations.clear()
	for annotation in document.get("annotations", []):
		if annotation is Dictionary:
			annotations.append(annotation.duplicate(true))
	redo_annotations.clear()
	for annotation in document.get("redo_annotations", []):
		if annotation is Dictionary:
			redo_annotations.append(annotation.duplicate(true))
	end_method = str(document.get("end_method", ""))
	ai_enabled = bool(document.get("ai_enabled", false))
	ai_player = str(document.get("ai_player", Rules.BLACK))
	if ai_player not in [Rules.WHITE, Rules.BLACK]:
		ai_player = Rules.BLACK
	game_id = str(document.get("game_id", ""))
	recording_path = str(document.get("recording_path", ""))
	waiting_for_presentation = false
	_set_ai_busy(false)
	setup_changed.emit()
	state_changed.emit("restore")
	_queue_ai_turn()
	return true


func _begin_recording() -> void:
	if not recording_enabled or initial_state.is_empty():
		return
	var stamp := int(Time.get_unix_time_from_system())
	var fraction := Time.get_ticks_msec() % 1000
	game_id = "human-%d-%03d-W%s-B%s" % [
		stamp,
		fraction,
		Rules.files().substr(setup_white_file, 1),
		Rules.files().substr(setup_black_file, 1),
	]
	var directory := ProjectSettings.globalize_path("res://../research/replays/human")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		directory = ProjectSettings.globalize_path("user://human_games")
		DirAccess.make_dir_recursive_absolute(directory)
	recording_path = directory.path_join(game_id + ".json")
	_save_recording()


func replay_document() -> Dictionary:
	var outcome := "in_progress"
	if not game_state.is_empty() and bool(game_state.get("is_draw", false)):
		outcome = "draw"
	elif not game_state.is_empty() and game_state.get("winner") != null:
		outcome = "%s_win" % str(game_state.winner)
	return {
		"contract_version": Rules.CONTRACT_VERSION,
		"game_id": game_id,
		"initial_state": initial_state.duplicate(true),
		"actions": actions.duplicate(true),
		"metadata": {
			"source": "human_vs_ai" if ai_enabled else "human_hotseat",
			"computer_color": ai_player if ai_enabled else "",
			"human_color": Rules.opponent(ai_player) if ai_enabled else "",
			"ruleset": str(initial_state.get("rules", {}).get("id", "")),
			"outcome": outcome,
			"completed": not game_state.is_empty() and GameEngine.is_over(game_state),
			"end_method": end_method,
			"plies": actions.size(),
			"updated_unix": int(Time.get_unix_time_from_system()),
		},
		"annotations": annotations.duplicate(true),
	}


func _save_recording() -> void:
	if not recording_enabled or recording_path.is_empty() or initial_state.is_empty():
		return
	if Codec.save_json(recording_path, replay_document()) != OK:
		session_error.emit("The game could not be recorded.")
