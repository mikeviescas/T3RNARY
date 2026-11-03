extends SceneTree

const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")
const ShowcaseState = preload("res://scripts/presentation/tabletop_showcase_state.gd")


func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var loader = packed.instantiate()
	root.add_child(loader)
	var deadline := Time.get_ticks_msec() + 60000
	while loader.get_node_or_null("TabletopRuntime") == null and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	var tabletop = loader.get_node_or_null("TabletopRuntime")
	if tabletop == null:
		printerr("Tabletop interaction test timed out while loading the runtime")
		quit(1)
		return
	tabletop.session.recording_enabled = false
	# Let the loader retire its full-screen input-blocking layer before dispatching
	# the same mouse events a player sends to the finished scene.
	await process_frame
	await process_frame
	await physics_frame
	# Rules reference and warning preferences are in-game overlays, not separate
	# scenes that interrupt or reset the active match.
	tabletop._toggle_encyclopedia_overlay()
	if not tabletop.encyclopedia_overlay.visible:
		printerr("Piece encyclopedia did not open from the tabletop")
		quit(1)
		return
	var encyclopedia_panel := tabletop.encyclopedia_overlay.get_child(0) as Control
	if encyclopedia_panel == null or encyclopedia_panel.size.x > tabletop.encyclopedia_overlay.size.x:
		printerr("Piece encyclopedia panel exceeded its clipped overlay width")
		quit(1)
		return
	tabletop._show_encyclopedia_piece("ballista")
	if "forward, left, or right" not in tabletop.encyclopedia_summary_label.text:
		printerr("Piece encyclopedia did not show the Ballista rules")
		quit(1)
		return
	if not tabletop.encyclopedia_range_table.visible or tabletop.encyclopedia_range_heading.text != "Stack Height / SHOOT Range:":
		printerr("Ballista did not display its SHOOT range table")
		quit(1)
		return
	tabletop._show_encyclopedia_piece("griffin")
	if tabletop.encyclopedia_name_label.text != "Griffin (G)" or not tabletop.encyclopedia_range_table.visible:
		printerr("Mobile Griffin did not show inline notation and its range table")
		quit(1)
		return
	tabletop._handle_mobile_back_request()
	if tabletop.encyclopedia_overlay.visible:
		printerr("Mobile Back did not close the piece encyclopedia")
		quit(1)
		return
	tabletop._toggle_settings_overlay()
	if not tabletop.settings_overlay.visible or not tabletop.blunder_warning_toggle.button_pressed or not tabletop.instructional_feedback_toggle.button_pressed:
		printerr("Settings did not open with Tactical Warnings defaults")
		quit(1)
		return
	var settings_panel := tabletop.settings_overlay.get_child(0) as Control
	if not tabletop.settings_overlay.clip_contents or settings_panel == null or settings_panel.size.x > tabletop.settings_overlay.size.x or settings_panel.size.y > tabletop.settings_overlay.size.y:
		printerr("Settings content was not constrained to the safe-area overlay")
		quit(1)
		return
	tabletop._handle_mobile_back_request()
	# The menu behaves like an overlay: clicking the tabletop dismisses it and
	# does not also activate the board underneath that same click.
	tabletop._toggle_hamburger()
	if not tabletop.hamburger_panel.visible:
		printerr("Hamburger menu did not open")
		quit(1)
		return
	var outside_click := InputEventMouseButton.new()
	outside_click.button_index = MOUSE_BUTTON_LEFT
	outside_click.pressed = true
	outside_click.position = Vector2(640.0, 110.0)
	tabletop._on_tabletop_gui_input(outside_click)
	if tabletop.hamburger_panel.visible:
		printerr("Clicking outside the hamburger menu did not close it")
		quit(1)
		return
	# Phones deliver screen-touch events directly. They must follow the same
	# overlay dismissal path without relying on mouse emulation, which can emit a
	# duplicate click on some platforms.
	tabletop._toggle_hamburger()
	var outside_touch := InputEventScreenTouch.new()
	outside_touch.index = 0
	outside_touch.pressed = true
	outside_touch.position = Vector2(640.0, 110.0)
	tabletop._on_tabletop_gui_input(outside_touch)
	if tabletop.hamburger_panel.visible:
		printerr("A screen touch outside the hamburger menu did not close it")
		quit(1)
		return
	# Android Back unwinds overlays first and exposes the menu at the bare table
	# instead of terminating an active match without warning.
	tabletop._handle_mobile_back_request()
	if not tabletop.hamburger_panel.visible:
		printerr("Mobile Back did not open the session menu from the bare tabletop")
		quit(1)
		return
	tabletop._handle_mobile_back_request()
	if tabletop.hamburger_panel.visible:
		printerr("Mobile Back did not dismiss the open session menu")
		quit(1)
		return

	# Changing aspect ratio during the pre-game Sovereign draft must move the
	# loose inventory with its physical trays. Previously only the tray meshes
	# moved because the empty game_state suppressed the piece rebuild.
	tabletop._set_portrait_layout(true)
	await process_frame
	var portrait_safe_rect: Rect2 = tabletop._safe_viewport_rect()
	var menu_center: Vector2 = tabletop.hamburger_button.position + tabletop.hamburger_button.size * 0.5
	if not portrait_safe_rect.has_point(menu_center):
		printerr("Portrait menu control was placed outside the device safe area")
		quit(1)
		return
	var portrait_white_sovereign := _reserve_token(tabletop.position_root, "white", "sovereign")
	var portrait_black_sovereign := _reserve_token(tabletop.position_root, "black", "sovereign")
	if portrait_white_sovereign == null or portrait_black_sovereign == null:
		printerr("Portrait setup did not render both reserve Sovereigns")
		quit(1)
		return
	var expected_white_reserve: Vector3 = tabletop._reserve_world_position("sovereign", "white")
	if Vector2(portrait_white_sovereign.position.x, portrait_white_sovereign.position.z).distance_to(Vector2(expected_white_reserve.x, expected_white_reserve.z)) > 0.01:
		printerr("White setup inventory remained at its landscape coordinates in portrait mode")
		quit(1)
		return
	var expected_black_reserve: Vector3 = tabletop._reserve_world_position("sovereign", "black")
	if Vector2(portrait_black_sovereign.position.x, portrait_black_sovereign.position.z).distance_to(Vector2(expected_black_reserve.x, expected_black_reserve.z)) > 0.01:
		printerr("Black setup inventory remained at its landscape coordinates in portrait mode")
		quit(1)
		return
	tabletop._set_portrait_layout(false)
	await process_frame

	# The replacement tabletop now begins with the real mirrored Sovereign
	# draft rather than a hard-coded showcase position. Reproduce the natural
	# first gesture: select Black's physical Sovereign in the tray before choosing
	# its rank-9 square. This previously attempted to read game_state.board before
	# setup had created a board dictionary.
	var black_sovereign_world: Vector3 = tabletop._reserve_world_position("sovereign", "black")
	var black_sovereign_screen: Vector2 = tabletop.camera.unproject_position(black_sovereign_world)
	tabletop._handle_pointer_click(black_sovereign_screen)
	if tabletop.selected_reserve_kind != "sovereign":
		printerr("Black's setup Sovereign could not be selected from its tray")
		quit(1)
		return
	tabletop._handle_board_click("C9")
	if tabletop.session.setup_black_file != 2:
		printerr("Tabletop session did not accept Black Sovereign setup")
		quit(1)
		return
	var white_sovereign_world: Vector3 = tabletop._reserve_world_position("sovereign", "white")
	var white_sovereign_screen: Vector2 = tabletop.camera.unproject_position(white_sovereign_world)
	tabletop._handle_pointer_click(white_sovereign_screen)
	if tabletop.selected_reserve_kind != "sovereign":
		printerr("White's setup Sovereign could not be selected from its tray")
		quit(1)
		return
	tabletop._handle_board_click("G1")
	if tabletop.session.game_state.is_empty():
		printerr("Tabletop session did not accept White's mirrored Sovereign response")
		quit(1)
		return
	await process_frame
	if tabletop.game_state.is_empty() or tabletop.game_state.board.size() != 2:
		printerr("Tabletop Sovereign setup did not create a playable rules state")
		quit(1)
		return
	# During OPENING, rejected neutral-territory placement teaches the phase rule
	# in context and highlights both the attempted square and the home territory.
	tabletop._select_reserve("infantry")
	tabletop._handle_board_click("E5")
	if tabletop.last_feedback_reason != "opening_incomplete" or "OPENING" not in tabletop.last_instructional_message:
		printerr("Neutral-territory OPENING rejection did not provide instructional feedback")
		quit(1)
		return
	if tabletop.feedback_root.get_child_count() < 5:
		printerr("OPENING rejection did not highlight the attempted square and home territory")
		quit(1)
		return
	tabletop._clear_instructional_feedback()
	tabletop._clear_selection()
	var crown_screen: Vector2 = tabletop.camera.unproject_position(tabletop._square_position("C9") + Vector3(0.0, 0.44, 0.0))
	if tabletop._stack_square_from_physics(crown_screen) != "C9":
		printerr("The tall Sovereign crown was not selectable across its full height")
		quit(1)
		return

	# Material-language regression: immobile tiles use inverse fields, while the
	# two special tiles use physical dotted perimeter geometry.
	var white_spy: Node3D = tabletop._new_token(false, "spy")
	var black_ballista: Node3D = tabletop._new_token(true, "ballista")
	var white_reinforcement: Node3D = tabletop._new_token(false, "reinforcement")
	var black_recall: Node3D = tabletop._new_token(true, "recall")
	var white_sovereign_model: Node3D = tabletop._new_token(false, "sovereign")
	var black_sovereign_model: Node3D = tabletop._new_token(true, "sovereign")
	var white_field_luminance := _field_luminance(white_spy)
	var black_field_luminance := _field_luminance(black_ballista)
	if white_field_luminance < 0.30 or black_field_luminance < 0.30 or absf(white_field_luminance - black_field_luminance) > 0.01:
		printerr("Immobile token fields did not retain their shared medium-gray finish")
		quit(1)
		return
	if _named_mesh_count(white_reinforcement, "dotted special-piece perimeter") < 20 or _named_mesh_count(black_recall, "dotted special-piece perimeter") < 20:
		printerr("Recall/Reinforcement did not retain their dotted top perimeters")
		quit(1)
		return
	if _named_mesh_count(white_sovereign_model, "opposite-color pinstripe") != 2 or _named_mesh_count(black_sovereign_model, "opposite-color pinstripe") != 2:
		printerr("Sovereigns did not retain both opposite-color pinstripes")
		quit(1)
		return
	if _named_mesh_count(white_sovereign_model, "opposite-color spire tip") != 6 or _named_mesh_count(black_sovereign_model, "opposite-color spire tip") != 6:
		printerr("Sovereigns did not retain all six opposite-color spire tips")
		quit(1)
		return
	white_spy.free()
	black_ballista.free()
	white_reinforcement.free()
	black_recall.free()
	white_sovereign_model.free()
	black_sovereign_model.free()

	# Capture choreography is verified from node motion rather than screenshots.
	# A full capture bumps the defending stack apart and leaves the attacker on
	# the destination. Attrition removes the attacker and the defender's matching
	# number of bottom tiles while compacting the survivors in place.
	var animation_restore_state: Dictionary = tabletop.game_state.duplicate(true)
	var full_capture: Dictionary = GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(2, 6))
	full_capture.board = {
		"C5": [
			{"owner": Rules.WHITE, "kind": Rules.INFANTRY},
			{"owner": Rules.WHITE, "kind": Rules.CHARIOT},
		],
		"E5": [
			{"owner": Rules.BLACK, "kind": Rules.INFANTRY},
			{"owner": Rules.BLACK, "kind": Rules.DRAGOON},
		],
	}
	full_capture.turn = Rules.WHITE
	full_capture.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	var full_action := {"type": "move", "source": "C5", "destination": "E5"}
	var full_after := GameEngine.apply_action(full_capture, full_action)
	tabletop.game_state = full_capture.duplicate(true)
	tabletop._render_game_state()
	var full_attacker: Node3D = tabletop.board_stack_nodes.C5
	var full_defender: Node3D = tabletop.board_stack_nodes.E5
	await tabletop._animate_move(full_action, full_after)
	if full_attacker.position.distance_to(tabletop._square_position("E5")) > 0.01 or not tabletop._stack_tiles(full_defender).is_empty():
		printerr("Full capture choreography did not discard the defender tile-by-tile and settle the attacker")
		quit(1)
		return

	var attrition: Dictionary = GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(2, 6))
	attrition.board = {
		"C5": [{"owner": Rules.WHITE, "kind": Rules.CHARIOT}],
		"E5": [
			{"owner": Rules.BLACK, "kind": Rules.INFANTRY},
			{"owner": Rules.BLACK, "kind": Rules.DRAGOON},
			{"owner": Rules.BLACK, "kind": Rules.MARSHAL},
		],
	}
	attrition.turn = Rules.WHITE
	attrition.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	var attrition_action := {"type": "move", "source": "C5", "destination": "E5"}
	var attrition_after := GameEngine.apply_action(attrition, attrition_action)
	tabletop.game_state = attrition.duplicate(true)
	tabletop._render_game_state()
	var attrition_attacker: Node3D = tabletop.board_stack_nodes.C5
	var attrition_defender: Node3D = tabletop.board_stack_nodes.E5
	await tabletop._animate_move(attrition_action, attrition_after)
	var survivor_tiles: Array[Node3D] = tabletop._stack_tiles(attrition_defender)
	if not tabletop._stack_tiles(attrition_attacker).is_empty() or survivor_tiles.size() != 2:
		printerr("Attrition choreography did not discard the attacker and matching bottom defender tiles")
		quit(1)
		return
	for survivor_index in range(survivor_tiles.size()):
		if absf(survivor_tiles[survivor_index].position.y - float(survivor_index) * 0.150) > 0.01:
			printerr("Attrition choreography did not compact the surviving defender tiles")
			quit(1)
			return
	tabletop.game_state = animation_restore_state
	tabletop._render_game_state()

	# Artillery facing is presentation history rather than a rules-state field.
	# It must stay attached to its physical layer when a later TOP piece makes
	# the complete stack mobile.
	var facing_before := {
		"turn": "white",
		"board": {
			"D3": [{"kind": "infantry", "owner": "white"}],
			"H3": [{"kind": "infantry", "owner": "black"}],
		},
	}
	var shot_action := {"type": "place", "piece": "ballista", "destination": "D3", "effect_target": "H3"}
	var facing_after_shot := facing_before.duplicate(true)
	facing_after_shot.board.D3.append({"kind": "ballista", "owner": "white"})
	facing_after_shot.board.erase("H3")
	var tracked: Dictionary = tabletop._advance_artillery_facings(
		{"D3": [null], "H3": [null]},
		facing_before,
		shot_action,
		facing_after_shot,
	)
	var facing_after_top := facing_after_shot.duplicate(true)
	facing_after_top.board.D3.append({"kind": "marshal", "owner": "white"})
	tracked = tabletop._advance_artillery_facings(
		tracked,
		facing_after_shot,
		{"type": "place", "piece": "marshal", "destination": "D3"},
		facing_after_top,
	)
	var facing_after_move := facing_after_top.duplicate(true)
	facing_after_move.board.E4 = facing_after_move.board.D3
	facing_after_move.board.erase("D3")
	tracked = tabletop._advance_artillery_facings(
		tracked,
		facing_after_top,
		{"type": "move", "source": "D3", "destination": "E4"},
		facing_after_move,
	)
	if not tracked.has("E4") or not is_equal_approx(float(tracked.E4[1]), tabletop._artillery_rotation("ballista", "D3", "H3")):
		printerr("A buried artillery facing did not follow its later-moving stack")
		quit(1)
		return

	# Portrait mode relocates the physical trays above and below the board while
	# preserving the same reserve-selection semantics.
	tabletop.portrait_layout = true
	tabletop._apply_tabletop_layout()
	tabletop._render_game_state()
	var portrait_reserve_position: Vector3 = tabletop._reserve_world_position("infantry", str(tabletop.game_state.turn))
	if tabletop._reserve_kind_at_world_point(portrait_reserve_position) != "infantry":
		printerr("Portrait tray coordinates did not preserve reserve selection")
		quit(1)
		return
	tabletop.portrait_layout = false
	tabletop._apply_tabletop_layout()

	# Continue the existing MOVE/PLACE/SHOOT regression from a real recorded
	# midgame state, now installed through the shared session.
	var showcase := ShowcaseState.build()
	tabletop.session.game_state = showcase.duplicate(true)
	tabletop.session.initial_state = showcase.duplicate(true)
	tabletop.session.states.clear()
	tabletop.session.states.append(showcase.duplicate(true))
	tabletop.session.actions.clear()
	tabletop.session.waiting_for_presentation = false
	tabletop.game_state = showcase.duplicate(true)
	tabletop._render_game_state()

	var initial_state: Dictionary = tabletop.game_state.duplicate(true)
	var initial_ply := int(initial_state.ply)
	var initial_action_count: int = tabletop.session.actions.size()
	tabletop._toggle_opponent()
	if not tabletop.session.ai_enabled or tabletop.game_state != initial_state or tabletop.session.actions.size() != initial_action_count:
		printerr("Switching to a computer opponent reset the tabletop game")
		quit(1)
		return
	tabletop._toggle_opponent()
	var actions: Array = GameEngine.legal_actions(initial_state)
	# Either physical discard caddy can be clicked to fan its captured pieces
	# face-up, then clicked again to return them to their two storage rows.
	var discard_owner := ""
	for owner in ["white", "black"]:
		var discarded_count := 0
		for count in initial_state.discards[owner].values():
			discarded_count += int(count)
		if discarded_count > 0:
			discard_owner = owner
			break
	if discard_owner.is_empty():
		printerr("Tabletop showcase state no longer contains a discard pile")
		quit(1)
		return
	var discard_click: Vector3 = tabletop._tray_local_to_world(0.0, 0.34, tabletop.TRAY_DISCARD_START_Z, discard_owner)
	if tabletop._discard_owner_at_world_point(discard_click) != discard_owner:
		printerr("Discard caddy did not resolve to its owning player")
		quit(1)
		return
	tabletop._handle_world_click(discard_click)
	if tabletop.expanded_discard_owner != discard_owner:
		printerr("Clicking the discard caddy did not explode its pieces")
		quit(1)
		return
	tabletop._handle_world_click(discard_click)
	if not tabletop.expanded_discard_owner.is_empty():
		printerr("Clicking an exploded discard caddy did not collapse it")
		quit(1)
		return
	var recall_actions: Array = actions.filter(func(action: Dictionary) -> bool:
		return str(action.get("type", "")) == "recall"
	)
	if recall_actions.is_empty():
		printerr("Tabletop showcase state no longer exposes a Recall action")
		quit(1)
		return
	tabletop._select_reserve("recall")
	if not tabletop.recall_choice_panel.visible:
		printerr("Selecting Recall did not open the discarded-piece chooser")
		quit(1)
		return
	var recalled_kind := str(recall_actions[0].piece)
	tabletop._select_recall_kind(recalled_kind)
	if tabletop.candidate_actions.is_empty() or str(tabletop.candidate_actions[0].piece) != recalled_kind:
		printerr("Recall chooser did not expose destinations for the selected discarded piece")
		quit(1)
		return
	tabletop._clear_selection()
	var chosen: Dictionary = {}
	for action in actions:
		if str(action.get("type", "")) == "move" and initial_state.board[str(action.source)].size() == 3:
			chosen = action
			break
	if chosen.is_empty():
		for action in actions:
			if str(action.get("type", "")) == "move":
				chosen = action
				break
	if chosen.is_empty():
		printerr("Tabletop interaction test could not find a MOVE action")
		quit(1)
		return

	var source_stack: Array = initial_state.board[str(chosen.source)]
	var source_anchor: Vector3 = tabletop._square_position(str(chosen.source))
	source_anchor.y += float(source_stack.size() - 1) * 0.150 + 0.180
	var source_screen: Vector2 = tabletop.camera.unproject_position(source_anchor)
	if tabletop._stack_square_at_screen(source_screen) != str(chosen.source):
		printerr("The visible TOP tile did not resolve to its complete stack")
		quit(1)
		return
	if tabletop._stack_square_from_physics(source_screen) != str(chosen.source):
		printerr("The physical stack hit area did not resolve the complete 3 Stack")
		quit(1)
		return
	# An enemy stack uses the same select/explode/collapse gestures, but its
	# cyan reach markers are informational and never enter executable actions.
	var opponent_square := ""
	for square_value in initial_state.board:
		var square := str(square_value)
		var stack: Array = initial_state.board[square]
		if str(stack[-1].owner) == str(initial_state.turn) or stack.size() < 2:
			continue
		if not GameEngine.movement_destinations(initial_state, square).is_empty():
			opponent_square = square
			break
	var inspection_state := initial_state.duplicate(true)
	if opponent_square.is_empty():
		# The recorded showcase can legitimately leave every enemy mobile piece
		# boxed in. Add a temporary rules-shaped stack solely to exercise the
		# presentation's inspection path without changing the saved fixture.
		var opponent_owner := "black" if str(initial_state.turn) == "white" else "white"
		for file_code in range("A".unicode_at(0), "I".unicode_at(0) + 1):
			for rank in range(1, 10):
				var candidate_square := "%s%d" % [char(file_code), rank]
				if inspection_state.board.has(candidate_square):
					continue
				inspection_state.board[candidate_square] = [
					{"kind": "infantry", "owner": opponent_owner},
					{"kind": "griffin", "owner": opponent_owner},
				]
				if not GameEngine.movement_destinations(inspection_state, candidate_square).is_empty():
					opponent_square = candidate_square
					break
				inspection_state.board.erase(candidate_square)
			if not opponent_square.is_empty():
				break
	if opponent_square.is_empty():
		printerr("Could not construct a movable enemy stack for inspection")
		quit(1)
		return
	tabletop.game_state = inspection_state
	tabletop._render_game_state()
	tabletop._handle_board_click(opponent_square)
	if not tabletop.candidate_actions.is_empty() or tabletop.inspection_destinations.is_empty() or tabletop.marker_root.get_child_count() < 2:
		printerr("Selecting an opponent stack did not expose inspection-only movement reach")
		quit(1)
		return
	tabletop._handle_board_click(opponent_square)
	if tabletop.exploded_stack_square != opponent_square:
		printerr("A second click did not explode the opponent stack")
		quit(1)
		return
	tabletop._handle_board_click(opponent_square)
	if not tabletop.exploded_stack_square.is_empty() or tabletop.inspection_destinations.is_empty():
		printerr("A third click did not collapse the opponent stack while preserving its reach")
		quit(1)
		return
	tabletop.game_state = initial_state.duplicate(true)
	tabletop._render_game_state()
	await _click_screen(source_screen)
	if tabletop.candidate_actions.is_empty() or tabletop.marker_root.get_child_count() == 0:
		printerr("A dispatched mouse click on %s did not expose legal targets" % str(chosen.source))
		quit(1)
		return
	# A second click fans the selected physical stack apart; a third restores it
	# while preserving selection and legal destinations.
	tabletop._handle_board_click(str(chosen.source))
	if tabletop.exploded_stack_square != str(chosen.source):
		printerr("A second click did not explode the selected stack")
		quit(1)
		return
	tabletop._handle_board_click(str(chosen.source))
	if not tabletop.exploded_stack_square.is_empty() or tabletop.candidate_actions.is_empty():
		printerr("A third click did not collapse the stack while preserving selection")
		quit(1)
		return

	var destination_anchor: Vector3 = tabletop._square_position(str(chosen.destination))
	if initial_state.board.has(str(chosen.destination)):
		var destination_stack: Array = initial_state.board[str(chosen.destination)]
		destination_anchor.y += float(destination_stack.size() - 1) * 0.150 + 0.180
	var destination_screen: Vector2 = tabletop.camera.unproject_position(destination_anchor)
	await _click_screen(destination_screen)
	var action_deadline := Time.get_ticks_msec() + 5000
	while tabletop.animating and Time.get_ticks_msec() < action_deadline:
		await process_frame
	if int(tabletop.game_state.ply) != initial_ply + 1:
		printerr("Click-to-MOVE did not advance the authoritative state")
		quit(1)
		return
	if tabletop.undo_button.disabled:
		printerr("Touch-accessible Undo remained disabled after a legal action")
		quit(1)
		return

	tabletop._undo_state()
	if int(tabletop.game_state.ply) != initial_ply:
		printerr("Tabletop undo did not restore the prior state")
		quit(1)
		return
	if tabletop.redo_button.disabled:
		printerr("Touch-accessible Redo remained disabled after undo")
		quit(1)
		return
	tabletop._redo_state()
	if int(tabletop.game_state.ply) != initial_ply + 1:
		printerr("Tabletop redo did not restore the advanced state")
		quit(1)
		return

	# Exercise the reserve path independently from the MOVE path. The scene's
	# showcase position intentionally remains a real recorded game state, so the
	# test selects whatever legal PLACE the engine exposes rather than baking in
	# presentation-only coordinates.
	tabletop.game_state = initial_state.duplicate(true)
	tabletop.session.game_state = initial_state.duplicate(true)
	tabletop.session.initial_state = initial_state.duplicate(true)
	tabletop.session.states.clear()
	tabletop.session.states.append(initial_state.duplicate(true))
	tabletop.session.actions.clear()
	tabletop.session.redo_states.clear()
	tabletop.session.redo_actions.clear()
	tabletop.session.waiting_for_presentation = false
	tabletop._render_game_state()
	var placement: Dictionary = {}
	var shoot: Dictionary = {}
	for action in actions:
		if str(action.get("type", "")) == "place" and placement.is_empty():
			placement = action
		if str(action.get("type", "")) == "place" and action.has("effect_target"):
			shoot = action
			break
	if placement.is_empty():
		printerr("Tabletop interaction test could not find a PLACE action")
		quit(1)
		return
	tabletop._select_reserve(str(placement.piece))
	if tabletop.candidate_actions.is_empty() or tabletop.marker_root.get_child_count() == 0:
		printerr("Selecting a tabletop reserve piece did not expose legal targets")
		quit(1)
		return
	# A phone tap can land beside a small marker while the intended square is
	# still unambiguous. The touch resolver must snap that near miss only to a
	# currently legal destination.
	var placement_square := str(placement.destination)
	var placement_screen: Vector2 = tabletop.camera.unproject_position(
		tabletop._square_position(placement_square) + Vector3(0.0, 0.05, 0.0)
	)
	if tabletop._action_square_at_screen(placement_screen + Vector2(18.0, 0.0)) != placement_square:
		printerr("A near-miss phone tap did not resolve to its visible legal marker")
		quit(1)
		return
	tabletop._execute_action(placement)
	await _wait_for_animation(tabletop)
	if int(tabletop.game_state.ply) != initial_ply + 1:
		printerr("Tabletop PLACE did not advance the authoritative state")
		quit(1)
		return

	if not shoot.is_empty():
		var expected_shot_rotation: float = tabletop._artillery_rotation(
			str(shoot.piece),
			str(shoot.destination),
			str(shoot.effect_target),
		)
		tabletop.game_state = initial_state.duplicate(true)
		tabletop.session.game_state = initial_state.duplicate(true)
		tabletop.session.initial_state = initial_state.duplicate(true)
		tabletop.session.states.clear()
		tabletop.session.states.append(initial_state.duplicate(true))
		tabletop.session.actions.clear()
		tabletop.session.redo_states.clear()
		tabletop.session.redo_actions.clear()
		tabletop.session.waiting_for_presentation = false
		tabletop._render_game_state()
		tabletop._select_reserve(str(shoot.piece))
		tabletop._handle_board_click(str(shoot.destination))
		if tabletop.pending_actions.is_empty() or tabletop.marker_root.get_child_count() < 2:
			printerr("Tabletop artillery placement did not expose PLACE/SHOOT choices")
			quit(1)
			return
		tabletop._execute_action(shoot)
		await _wait_for_animation(tabletop)
		if int(tabletop.game_state.ply) != initial_ply + 1:
			printerr("Tabletop SHOOT did not advance the authoritative state")
			quit(1)
			return
		var firing_stack: Node3D = tabletop.board_stack_nodes.get(str(shoot.destination))
		var firing_tile := _stack_token_of_kind(firing_stack, str(shoot.piece))
		if firing_tile == null or not is_equal_approx(firing_tile.rotation_degrees.y, expected_shot_rotation):
			printerr("Placed artillery did not face the stack it targeted")
			quit(1)
			return

	# The replacement scene must consume its own version-2 recording, expose
	# compact replay transport, and restrict notation to the displayed ply.
	var replay_document: Dictionary = tabletop.session.replay_document()
	replay_document.game_id = "tabletop-interaction-replay"
	if not tabletop._load_replay_document(replay_document):
		printerr("Tabletop could not load a version-2 replay document")
		quit(1)
		return
	if tabletop.view_mode != "replay" or not tabletop.replay_controls.visible or tabletop.replay_index != 0:
		printerr("Loading a replay did not enter the tabletop replay workspace")
		quit(1)
		return
	if not tabletop.interaction_status.text.is_empty():
		printerr("Replay duplicated its ply count in the engraved status label")
		quit(1)
		return
	var plate_center: Vector2 = tabletop.camera.unproject_position(tabletop.interaction_status.global_position)
	var controls_center: Vector2 = tabletop.replay_controls.position + tabletop.replay_controls.size * 0.5
	if controls_center.distance_to(plate_center) > 2.0:
		printerr("Replay transport was not centered inside the physical status inlay")
		quit(1)
		return
	var initial_notation: String = tabletop._notation_copy_text()
	if "Through recorded ply: 0" not in initial_notation:
		printerr("Replay notation did not stop at the initial position")
		quit(1)
		return
	tabletop._set_replay_index(tabletop.replay_states.size() - 1)
	if tabletop.replay_index != 1 or int(tabletop.game_state.ply) != initial_ply + 1:
		printerr("Replay transport did not restore the recorded action state")
		quit(1)
		return
	var final_notation: String = tabletop._notation_copy_text()
	if "Through recorded ply: 1" not in final_notation or final_notation == initial_notation:
		printerr("Replay notation did not advance with the displayed ply")
		quit(1)
		return
	tabletop._toggle_notation_overlay()
	if not tabletop.notation_overlay.visible or tabletop.notation_text.text != final_notation:
		printerr("Tabletop notation overlay did not display the current replay record")
		quit(1)
		return

	# Finishing a live game must not trap the player behind a New Game modal.
	# Dismissing the victory card promotes the in-memory recording directly to
	# replay mode at its final ply, including outcomes that have no final action
	# such as a computer resignation.
	tabletop.notation_overlay.visible = false
	var completed_state: Dictionary = tabletop.session.game_state.duplicate(true)
	completed_state.winner = "white"
	completed_state.is_draw = false
	tabletop.session.game_state = completed_state.duplicate(true)
	tabletop.session.states[-1] = completed_state.duplicate(true)
	tabletop.session.end_method = "RESIGNATION"
	tabletop.view_mode = "play"
	tabletop.game_state = completed_state.duplicate(true)
	tabletop._update_game_over_overlay()
	if not tabletop.game_over_overlay.visible:
		printerr("A completed tabletop game did not present its victory card")
		quit(1)
		return
	tabletop._enter_completed_game_replay()
	if tabletop.view_mode != "replay" or tabletop.game_over_overlay.visible:
		printerr("Dismissing the victory card did not enter post-game replay")
		quit(1)
		return
	if tabletop.replay_index != tabletop.replay_states.size() - 1 or tabletop.game_state.get("winner") != "white":
		printerr("Post-game replay did not open on the completed final position")
		quit(1)
		return
	if tabletop.replay_index > 0 and tabletop.replay_previous_button.disabled:
		printerr("Post-game replay did not allow stepping back through the game")
		quit(1)
		return

	print("T3RNARY tabletop interaction test: passed")
	loader.queue_free()
	await process_frame
	quit(0)


func _click_screen(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.global_position = position
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _stack_token_of_kind(stack_root: Node3D, kind: String) -> Node3D:
	if stack_root == null:
		return null
	for child in stack_root.get_children():
		if child is Node3D and str(child.get_meta("piece_kind", "")) == kind:
			return child
	return null


func _reserve_token(root_node: Node, owner: String, kind: String) -> Node3D:
	for child in root_node.get_children():
		# A layout rebuild queues the former presentation nodes for deletion and
		# creates their replacements immediately. Ignore those retired siblings if
		# this assertion runs before Godot's deletion queue has drained.
		if child.is_queued_for_deletion():
			continue
		if child is Node3D and str(child.get_meta("reserve_owner", "")) == owner and str(child.get_meta("reserve_kind", "")) == kind:
			return child
	return null


func _wait_for_animation(tabletop) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (tabletop.animating or tabletop.session.waiting_for_presentation) and Time.get_ticks_msec() < deadline:
		await process_frame


func _field_luminance(token: Node) -> float:
	for child in token.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if "recessed engraved field" in mesh.name.to_lower():
			var applied := mesh.get_surface_override_material(0)
			if applied is StandardMaterial3D:
				return (applied as StandardMaterial3D).albedo_color.get_luminance()
	return -1.0


func _named_mesh_count(token: Node, needle: String) -> int:
	var count := 0
	for child in token.find_children("*", "MeshInstance3D", true, false):
		if needle in child.name.to_lower():
			count += 1
	return count
