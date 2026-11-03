extends SceneTree

const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")


func _init() -> void:
	var portrait := "--portrait" in OS.get_cmdline_user_args()
	var explode := "--explode" in OS.get_cmdline_user_args()
	var occlusion_test := "--occlusion-test" in OS.get_cmdline_user_args()
	var settings := "--settings" in OS.get_cmdline_user_args()
	var labels := "--labels" in OS.get_cmdline_user_args()
	var opening_feedback := "--opening-feedback" in OS.get_cmdline_user_args()
	var attack_feedback := "--attack-feedback" in OS.get_cmdline_user_args()
	var attack_sample_ms := 660
	var replay_path := ""
	var replay_ply := -1
	var encyclopedia_kind := "sovereign"
	var capture_size := Vector2i(900, 1600) if portrait else Vector2i(2400, 1500)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--encyclopedia-kind="):
			encyclopedia_kind = argument.trim_prefix("--encyclopedia-kind=")
		elif argument.begins_with("--capture-size="):
			var dimensions := argument.trim_prefix("--capture-size=").split("x")
			if dimensions.size() == 2:
				capture_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif argument.begins_with("--attack-sample-ms="):
			attack_sample_ms = int(argument.trim_prefix("--attack-sample-ms="))
		elif argument.begins_with("--replay-path="):
			replay_path = argument.trim_prefix("--replay-path=")
		elif argument.begins_with("--replay-ply="):
			replay_ply = int(argument.trim_prefix("--replay-ply="))
	var encyclopedia := "--encyclopedia" in OS.get_cmdline_user_args() or encyclopedia_kind != "sovereign"
	var viewport := SubViewport.new()
	viewport.size = capture_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var loader = scene.instantiate()
	viewport.add_child(loader)
	var deadline := Time.get_ticks_msec() + 60000
	while loader.get_node_or_null("TabletopRuntime") == null and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	if loader.get_node_or_null("TabletopRuntime") == null:
		printerr("Tabletop POC did not finish loading before capture timeout")
		quit(1)
		return
	if occlusion_test:
		var tabletop = loader.get_node("TabletopRuntime")
		var black_infantry := {"owner":"black", "kind":"infantry"}
		tabletop.game_state.board = {
			"D8": [black_infantry.duplicate(), black_infantry.duplicate(), {"owner":"black", "kind":"marshal"}],
			"E8": [black_infantry.duplicate(), black_infantry.duplicate(), {"owner":"black", "kind":"griffin"}],
			"F8": [black_infantry.duplicate(), black_infantry.duplicate(), {"owner":"black", "kind":"chariot"}],
			"E9": [{"owner":"black", "kind":"griffin"}],
		}
		tabletop._render_game_state()
	if labels:
		var tabletop = loader.get_node("TabletopRuntime")
		for child in tabletop.position_root.get_children():
			if child.has_meta("reserve_kind") and not child.has_meta("reserve_emblem"):
				child.queue_free()
	if opening_feedback:
		var tabletop = loader.get_node("TabletopRuntime")
		var state: Dictionary = GameEngine.initial_state(Rules.development_ruleset(), Vector2i(2, 6))
		tabletop.session.game_state = state.duplicate(true)
		tabletop.game_state = state.duplicate(true)
		tabletop._render_game_state()
	if attack_feedback:
		var tabletop = loader.get_node("TabletopRuntime")
		var before: Dictionary = GameEngine.initial_state(Rules.development_ruleset(), Vector2i(2, 6))
		before.board = {
			"C5": [
				{"owner": Rules.WHITE, "kind": Rules.INFANTRY},
				{"owner": Rules.WHITE, "kind": Rules.CHARIOT},
			],
			"E5": [
				{"owner": Rules.BLACK, "kind": Rules.INFANTRY},
				{"owner": Rules.BLACK, "kind": Rules.DRAGOON},
			],
		}
		before.turn = Rules.WHITE
		before.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
		var action := {"type": "move", "source": "C5", "destination": "E5"}
		var after := GameEngine.apply_action(before, action)
		tabletop.session.game_state = before.duplicate(true)
		tabletop.game_state = before.duplicate(true)
		tabletop._render_game_state()
		tabletop._animate_move(action, after)
	if not replay_path.is_empty() and replay_ply > 0:
		var tabletop = loader.get_node("TabletopRuntime")
		var document = JSON.parse_string(FileAccess.get_file_as_string(replay_path))
		if not document is Dictionary or not tabletop._load_replay_document(document):
			printerr("Could not load replay capture source: " + replay_path)
			quit(1)
			return
		if replay_ply > tabletop.replay_actions.size():
			printerr("Replay ply is out of range: %d" % replay_ply)
			quit(1)
			return
		tabletop.replay_index = replay_ply - 1
		tabletop.game_state = tabletop.replay_states[replay_ply - 1].duplicate(true)
		tabletop._render_game_state()
	# Give imported meshes, generated materials, shadows, and texture filtering
	# time to settle before reading back the render target.
	await create_timer(4.0).timeout
	if opening_feedback:
		var tabletop = loader.get_node("TabletopRuntime")
		tabletop._select_reserve(Rules.INFANTRY)
		tabletop._handle_board_click("E5")
		await create_timer(0.20).timeout
	if attack_feedback:
		# Restart immediately before capture and sample during the contact pulse.
		var tabletop = loader.get_node("TabletopRuntime")
		tabletop._render_game_state()
		var action := {"type": "move", "source": "C5", "destination": "E5"}
		var after := GameEngine.apply_action(tabletop.game_state, action)
		tabletop._animate_move(action, after)
		await create_timer(float(attack_sample_ms) / 1000.0).timeout
	if not replay_path.is_empty() and replay_ply > 0:
		var tabletop = loader.get_node("TabletopRuntime")
		tabletop._render_game_state()
		var action: Dictionary = tabletop.replay_actions[replay_ply - 1]
		var after: Dictionary = tabletop.replay_states[replay_ply]
		tabletop._animate_action(action, after)
		await create_timer(float(attack_sample_ms) / 1000.0).timeout
	if explode:
		var tabletop = loader.get_node("TabletopRuntime")
		for square_value in tabletop.game_state.board:
			var square := str(square_value)
			var stack: Array = tabletop.game_state.board[square]
			if stack.size() > 1 and str(stack[-1].owner) == str(tabletop.game_state.turn):
				tabletop._select_board_stack(square)
				tabletop._toggle_stack_explosion(square)
				break
		await create_timer(0.4).timeout
	if encyclopedia:
		var tabletop = loader.get_node("TabletopRuntime")
		tabletop._toggle_encyclopedia_overlay()
		tabletop._show_encyclopedia_piece(encyclopedia_kind)
		await create_timer(0.25).timeout
	elif settings:
		var tabletop = loader.get_node("TabletopRuntime")
		tabletop._toggle_settings_overlay()
		await create_timer(0.25).timeout
	await process_frame
	await process_frame
	var output := (
		"/tmp/t3rnary-tabletop-poc-portrait.png"
		if portrait
		else "/tmp/t3rnary-tabletop-poc-settings.png" if settings
		else "/tmp/t3rnary-tabletop-poc-encyclopedia.png" if encyclopedia
		else "/tmp/t3rnary-tabletop-poc-occlusion.png" if occlusion_test
		else "/tmp/t3rnary-tabletop-poc-exploded.png" if explode
		else "/tmp/t3rnary-tabletop-poc-labels.png" if labels
		else "/tmp/t3rnary-tabletop-poc-opening-feedback.png" if opening_feedback
		else "/tmp/t3rnary-tabletop-poc-replay-%d-%d.png" % [replay_ply, attack_sample_ms] if not replay_path.is_empty()
		else "/tmp/t3rnary-tabletop-poc-attack-feedback-%d.png" % attack_sample_ms if attack_feedback
		else "/tmp/t3rnary-tabletop-poc.png"
	)
	var error := viewport.get_texture().get_image().save_png(output)
	if error != OK:
		printerr("Could not save tabletop POC screenshot: %s" % error)
		quit(1)
	else:
		print("Saved tabletop POC screenshot: " + output)
		quit(0)
