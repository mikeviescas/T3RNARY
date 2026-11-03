extends SceneTree

const Rules = preload("res://scripts/core/ternary_rules.gd")
const Session = preload("res://scripts/core/ternary_session.gd")


func _init() -> void:
	var session = Session.new()
	session.recording_enabled = false
	root.add_child(session)
	session.start_new_game()
	if not session.choose_sovereign_square("C9") or not session.choose_sovereign_square("G1"):
		_fail("Hot-seat Sovereign setup failed")
		return
	if session.game_state.is_empty() or session.states.size() != 1:
		_fail("Completed setup did not create the initial session state")
		return
	var legal := session.legal_actions()
	if legal.is_empty() or not session.apply_action(legal[0]):
		_fail("Session did not commit a legal opening action")
		return
	if not session.waiting_for_presentation or session.actions.size() != 1:
		_fail("Session did not wait for presentation after committing an action")
		return
	session.presentation_complete()
	if not session.undo() or int(session.game_state.ply) != 0:
		_fail("Session undo did not restore the initial state")
		return
	if not session.redo() or int(session.game_state.ply) != 1:
		_fail("Session redo did not restore the committed action")
		return
	# Opponent ownership is allowed to change without replacing the game. Pick
	# the non-moving color here so this assertion is independent of AI timing.
	var adopted_state: Dictionary = session.game_state.duplicate(true)
	var adopted_action_count: int = session.actions.size()
	var current_player := str(session.game_state.turn)
	session.configure_opponent(true, current_player, false)
	if session.game_state != adopted_state or session.actions.size() != adopted_action_count:
		_fail("Enabling the computer replaced the game in progress")
		return
	session.configure_opponent(false, current_player, false)
	var document := session.replay_document()
	if document.actions.size() != 1 or str(document.metadata.ruleset).is_empty():
		_fail("Session replay document did not preserve its action and ruleset")
		return
	var capture_before := {
		"board": {
			"H1": [{"owner": Rules.WHITE, "kind": Rules.MARSHAL}],
			"I1": [{"owner": Rules.BLACK, "kind": Rules.SOVEREIGN}],
		},
	}
	var capture_after := {"winner": Rules.WHITE, "is_draw": false}
	if session._classify_end_method(capture_before, {"type":"move", "source":"H1", "destination":"I1"}, capture_after) != "SOVEREIGN CAPTURE":
		_fail("Session did not identify a Sovereign-capture ending")
		return
	var conquer_before := {
		"board": {"A8": [{"owner": Rules.WHITE, "kind": Rules.SOVEREIGN}]},
	}
	if session._classify_end_method(conquer_before, {"type":"move", "source":"A8", "destination":"A9"}, capture_after) != "CONQUER":
		_fail("Session did not identify a Conquer ending")
		return

	# Mobile recovery uses a separate active-session snapshot rather than
	# treating the replay archive as mutable application state. It must preserve
	# both an interrupted Sovereign draft and the undo/redo cursor.
	var autosave_path := "user://test_active_session.json"
	_remove_autosave_files(autosave_path)
	var draft_session = Session.new()
	draft_session.recording_enabled = false
	draft_session.autosave_enabled = true
	draft_session.autosave_path = autosave_path
	root.add_child(draft_session)
	draft_session.start_new_game()
	if not draft_session.choose_sovereign_square("C9"):
		_fail("Autosave draft fixture could not choose Black's Sovereign")
		return
	var restored_draft = Session.new()
	restored_draft.recording_enabled = false
	restored_draft.autosave_enabled = true
	restored_draft.autosave_path = autosave_path
	root.add_child(restored_draft)
	if not restored_draft.restore_autosave() or restored_draft.setup_black_file != 2 or restored_draft.setup_white_file != -1:
		_fail("Autosave did not restore an interrupted Sovereign draft")
		return

	session.autosave_enabled = true
	session.autosave_path = autosave_path
	if not session.undo() or session.redo_actions.size() != 1:
		_fail("Autosave fixture could not create redo history")
		return
	var restored_session = Session.new()
	restored_session.recording_enabled = false
	restored_session.autosave_enabled = true
	restored_session.autosave_path = autosave_path
	root.add_child(restored_session)
	if not restored_session.restore_autosave():
		_fail("Autosave did not restore an active game")
		return
	if int(restored_session.game_state.ply) != 0 or restored_session.redo_actions.size() != 1:
		_fail("Autosave did not preserve the active undo/redo cursor")
		return
	if not restored_session.redo() or int(restored_session.game_state.ply) != 1:
		_fail("Restored redo history could not be replayed")
		return

	# A finished recording remains in the replay archive, but it is no longer an
	# active session. Launch must start clean instead of reopening its victory UI.
	restored_session.game_state = restored_session.game_state.duplicate(true)
	restored_session.game_state.winner = Rules.WHITE
	restored_session.game_state.is_draw = false
	restored_session.end_method = "VICTORY"
	if restored_session.save_autosave() != OK:
		_fail("Completed-autosave fixture could not be saved")
		return
	var completed_restore = Session.new()
	completed_restore.recording_enabled = false
	completed_restore.autosave_enabled = true
	completed_restore.autosave_path = autosave_path
	root.add_child(completed_restore)
	if completed_restore.restore_autosave():
		_fail("A completed game was incorrectly restored as the active session")
		return
	_remove_autosave_files(autosave_path)

	# Computer Black owns the first Sovereign choice. This exercises the setup
	# scheduler without paying for a full search turn.
	var ai_session = Session.new()
	ai_session.recording_enabled = false
	root.add_child(ai_session)
	ai_session.configure_opponent(true, Rules.WHITE)
	var deadline := Time.get_ticks_msec() + 2000
	while ai_session.ai_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	if ai_session.setup_black_file != 2 or not ai_session.game_state.is_empty():
		_fail("Computer Black did not choose its Sovereign band before White")
		return
	if not ai_session.choose_sovereign_square("G1"):
		_fail("Human White could not answer the computer's Sovereign choice")
		return
	var white_opening: Dictionary = ai_session.legal_actions()[0]
	if not ai_session.apply_action(white_opening):
		_fail("Human opening action did not enter the computer session")
		return
	ai_session.presentation_complete()
	deadline = Time.get_ticks_msec() + 30000
	while ai_session.actions.size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	if ai_session.actions.size() != 2 or str(ai_session.game_state.turn) != Rules.WHITE:
		_fail("Computer Black did not return a legal opening action")
		return
	ai_session.presentation_complete()

	print("T3RNARY session tests: passed")
	session.queue_free()
	draft_session.queue_free()
	restored_draft.queue_free()
	restored_session.queue_free()
	completed_restore.queue_free()
	ai_session.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)


func _remove_autosave_files(path: String) -> void:
	for suffix_value in ["", ".tmp", ".bak"]:
		var suffix := str(suffix_value)
		var candidate: String = path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
