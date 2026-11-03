extends SceneTree

const Rules = preload("res://scripts/core/ternary_rules.gd")
const Codec = preload("res://scripts/core/ternary_codec.gd")
const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const OpponentAI = preload("res://scripts/core/ternary_ai.gd")
const TacticalWarnings = preload("res://scripts/core/ternary_tactical_warnings.gd")
const PieceEncyclopedia = preload("res://scripts/presentation/piece_encyclopedia.gd")
const VisualIcons = preload("res://scripts/presentation/piece_icon_renderer.gd")
const VisualPalette = preload("res://scripts/presentation/ternary_palette.gd")
const VisualPrototype = preload("res://scripts/presentation/visual_prototype.gd")

var failures := 0
var checks := 0


func _init() -> void:
	_test_initial_development_state()
	_test_shared_rule_configuration()
	_test_development_sequence_and_height_unlock()
	_test_shared_neutral_height_unlock()
	_test_white_open_placement_regressions()
	_test_movement_and_capture_rules()
	_test_move_attrition()
	_test_royal_attack()
	_test_infiltration_victory()
	_test_griffin_height_three_moves()
	_test_artillery_range_and_sovereign_immunity()
	_test_artillery_attrition()
	_test_spy_conversion_material_flow()
	_test_reinforcement_position()
	_test_recall_excludes_sovereign()
	_test_immediate_sovereign_capture()
	_test_tactical_warnings()
	_test_piece_encyclopedia()
	_test_opponent_ai()
	_test_golden_fixture()
	_test_visual_system_contract()
	_test_tabletop_poc_asset_separation()
	_test_simulator_manual_play_and_replay()
	if failures == 0:
		print("T3RNARY rules tests: %d checks passed" % checks)
		quit(0)
	else:
		printerr("T3RNARY rules tests: %d of %d checks failed" % [failures, checks])
		quit(1)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _test_tabletop_poc_asset_separation() -> void:
	expect(ResourceLoader.exists("res://scenes/main.tscn", "PackedScene"), "physical tabletop is the main application scene")
	expect(ResourceLoader.exists("res://scenes/legacy/legacy_visual_simulator.tscn", "PackedScene"), "retired visual simulator remains available as a legacy reference scene")
	expect(ResourceLoader.exists("res://scenes/tile_design_study.tscn", "PackedScene"), "nesting tile study remains available as an inspectable scene")
	expect(ResourceLoader.exists("res://assets/poc/table_surface.glb", "PackedScene"), "3D POC table is a separate reusable asset")
	expect(ResourceLoader.exists("res://assets/poc/board.glb", "PackedScene"), "3D POC board is a separate reusable asset")
	expect(ResourceLoader.exists("res://assets/poc/player_tray.glb", "PackedScene"), "3D POC player tray is a separate reusable asset")
	expect(ResourceLoader.exists("res://assets/poc/token_white.glb", "PackedScene"), "white nesting tile is a separate reusable asset")
	expect(ResourceLoader.exists("res://assets/poc/token_black.glb", "PackedScene"), "black nesting tile is a separate reusable asset")
	expect(ResourceLoader.exists("res://assets/poc/token_white_sovereign.glb", "PackedScene"), "white Sovereign has dedicated reverse-engraved geometry")
	expect(ResourceLoader.exists("res://assets/poc/token_black_sovereign.glb", "PackedScene"), "black Sovereign has dedicated reverse-engraved geometry")
	expect(ResourceLoader.exists("res://assets/poc/textures/white_marble_albedo.png", "Texture2D"), "white marble surface texture is available")
	expect(ResourceLoader.exists("res://assets/poc/textures/black_obsidian_albedo.png", "Texture2D"), "black obsidian surface texture is available")


func has(actions: Array, action: Dictionary) -> bool:
	return Codec.actions_contain(actions, action)


func empty_state(board: Dictionary, turn := Rules.WHITE) -> Dictionary:
	return Codec.normalize_state({
		"contract_version": 2,
		"rules": Rules.control_ruleset(),
		"board": board,
		"reserves": {"white": {}, "black": {}},
		"discards": {"white": {}, "black": {}},
		"turn": turn,
	})


func p(owner: String, kind: String) -> Dictionary:
	return {"owner": owner, "kind": kind}


func _test_tactical_warnings() -> void:
	var checked := empty_state({
		"E1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"E3": [p(Rules.BLACK, Rules.CHARIOT)],
		"I9": [p(Rules.BLACK, Rules.SOVEREIGN)],
	}, Rules.WHITE)
	var check_warning := TacticalWarnings.position_warning(checked)
	expect(str(check_warning.get("kind", "")) == "check", "tactical advisor reports a capturable Sovereign with a safe reply as check")

	var forced := empty_state({
		"A1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"A3": [p(Rules.BLACK, Rules.CHARIOT)],
		"C1": [p(Rules.BLACK, Rules.CHARIOT)],
		"C3": [p(Rules.BLACK, Rules.MARSHAL)],
		"I9": [p(Rules.BLACK, Rules.SOVEREIGN)],
	}, Rules.WHITE)
	var forced_warning := TacticalWarnings.position_warning(forced)
	expect(str(forced_warning.get("kind", "")) == "checkmate", "tactical advisor distinguishes a Sovereign with no safe legal reply")

	var blunder := empty_state({
		"E1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"E2": [p(Rules.WHITE, Rules.CHARIOT)],
		"E4": [p(Rules.BLACK, Rules.CHARIOT)],
		"I9": [p(Rules.BLACK, Rules.SOVEREIGN)],
	}, Rules.WHITE)
	var blunder_warning := TacticalWarnings.action_warning(blunder, {
		"type": "move", "source": "E2", "destination": "D2",
	})
	expect(str(blunder_warning.get("kind", "")) == "major_blunder", "tactical advisor warns before an avoidable move exposes the Sovereign")
	var safe_warning := TacticalWarnings.action_warning(blunder, {
		"type": "move", "source": "E2", "destination": "E3",
	})
	expect(safe_warning.is_empty(), "tactical advisor does not interrupt a move that keeps the Sovereign protected")


func _test_piece_encyclopedia() -> void:
	var encyclopedia_kinds := PieceEncyclopedia.kinds()
	expect(encyclopedia_kinds.size() == Rules.piece_types().size(), "piece encyclopedia covers every rules-catalog piece")
	for kind_value in Rules.piece_types():
		var kind := str(kind_value)
		var entry := PieceEncyclopedia.entry(kind)
		expect(kind in encyclopedia_kinds, "piece encyclopedia includes %s" % kind)
		expect(not entry.has("role"), "piece encyclopedia omits the retired role section for %s" % kind)
		expect(not str(entry.get("summary", "")).is_empty(), "piece encyclopedia provides a concise rules summary for %s" % kind)
		expect(not entry.has("movement") and not entry.has("rules"), "piece encyclopedia omits the retired movement/rules sections for %s" % kind)
	var mobile_kinds := [Rules.SOVEREIGN, Rules.INFANTRY, Rules.DRAGOON, Rules.CHARIOT, Rules.GRIFFIN, Rules.MARSHAL]
	for kind_value in mobile_kinds:
		expect(not PieceEncyclopedia.entry(str(kind_value)).get("ranges", []).is_empty(), "mobile piece %s includes a stack-height range table" % str(kind_value))
	for kind_value in [Rules.BALLISTA, Rules.TREBUCHET]:
		var artillery_entry := PieceEncyclopedia.entry(str(kind_value))
		expect(not artillery_entry.get("ranges", []).is_empty(), "artillery piece %s includes a SHOOT range table" % str(kind_value))
		expect(str(artillery_entry.get("range_column", "")) == "SHOOT RANGE", "artillery piece %s labels its range as SHOOT range" % str(kind_value))
	for kind_value in [Rules.SPY, Rules.REINFORCEMENT, Rules.RECALL]:
		expect(PieceEncyclopedia.entry(str(kind_value)).get("ranges", []).is_empty(), "immobile piece %s omits the movement range table" % str(kind_value))


func swap_colors_and_rotate(state: Dictionary) -> Dictionary:
	var mirrored := state.duplicate(true)
	var board := {}
	for square_value in state.board:
		var position := Rules.square_to_xy(str(square_value))
		var destination := Rules.square(Rules.board_size() - 1 - position.x, Rules.board_size() - 1 - position.y)
		var stack: Array = []
		for piece in state.board[square_value]:
			stack.append(p(Rules.opponent(str(piece.owner)), str(piece.kind)))
		board[destination] = stack
	mirrored.board = board
	mirrored.reserves = {
		Rules.WHITE: state.reserves[Rules.BLACK].duplicate(true),
		Rules.BLACK: state.reserves[Rules.WHITE].duplicate(true),
	}
	mirrored.discards = {
		Rules.WHITE: state.discards[Rules.BLACK].duplicate(true),
		Rules.BLACK: state.discards[Rules.WHITE].duplicate(true),
	}
	mirrored.development_placements = {
		Rules.WHITE: state.development_placements[Rules.BLACK],
		Rules.BLACK: state.development_placements[Rules.WHITE],
	}
	mirrored.height_three_unlocked = {
		Rules.WHITE: state.height_three_unlocked[Rules.BLACK],
		Rules.BLACK: state.height_three_unlocked[Rules.WHITE],
	}
	mirrored.turn = Rules.opponent(str(state.turn))
	if state.get("winner") != null:
		mirrored.winner = Rules.opponent(str(state.winner))
	return mirrored


func _test_opponent_ai() -> void:
	var ai = OpponentAI.new()
	var opening := GameEngine.initial_state(Rules.current_beta_ruleset())
	opening = GameEngine.apply_action(opening, {"type":"place", "piece":"infantry", "destination":"D2"})
	var first: Dictionary = ai.choose_action(opening)
	var second: Dictionary = ai.choose_action(opening)
	expect(not first.is_empty() and str(first.action.get("piece", "")) == Rules.INFANTRY, "computer begins with Infantry development")
	expect(Codec.normalize_action(first.action) == Codec.normalize_action(second.action), "computer decisions are deterministic")
	expect(first.has("diagnostics") and first.diagnostics.has("spy_conversion_exposure_after"), "computer decisions expose tactical diagnostics for recorded games")

	var winning := empty_state({
		"I1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"H1": [p(Rules.BLACK, Rules.SOVEREIGN)],
	}, Rules.BLACK)
	winning.rules = Rules.current_beta_ruleset()
	winning.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	var win_decision: Dictionary = ai.choose_action(winning)
	expect(str(win_decision.action.get("type", "")) == "move" and str(win_decision.action.get("source", "")) == "H1" and str(win_decision.action.get("destination", "")) == "I1", "computer never declines an immediate Sovereign capture")
	expect(str(win_decision.reason) == "immediate victory", "computer records the reason for a winning move")

	var artillery := empty_state({
		"A1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"E3": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"E6": [p(Rules.WHITE, Rules.REINFORCEMENT), p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.MARSHAL)],
		"B6": [p(Rules.BLACK, Rules.INFANTRY), p(Rules.BLACK, Rules.INFANTRY)],
	}, Rules.BLACK)
	artillery.rules = Rules.current_beta_ruleset()
	artillery.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	artillery.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	artillery.reserves.black.ballista = 1
	var artillery_decision: Dictionary = ai.choose_action(artillery)
	expect(str(artillery_decision.action.get("effect_target", "")) == "E6", "computer recognizes artillery attrition against an enemy 3 Stack")
	expect(str(artillery_decision.reason) == "Sovereign defense", "computer records the defensive reason for an emergency artillery shot")

	var sealed := empty_state({
		"F1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"B8": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"A6": [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.MARSHAL), p(Rules.WHITE, Rules.SPY)],
		"A7": [p(Rules.BLACK, Rules.INFANTRY), p(Rules.BLACK, Rules.CHARIOT)],
	}, Rules.BLACK)
	sealed.rules = Rules.current_beta_ruleset()
	sealed.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	sealed.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	sealed.reserves.white.recall = 1
	sealed.reserves.black.recall = 1
	sealed.discards.black.ballista = 1
	var release_action := {"type":"recall", "piece":"ballista", "destination":"B6", "effect_target":"A6"}
	expect(has(GameEngine.legal_actions(sealed), release_action), "frozen-Spy regression includes the logged recalled-Ballista attrition")
	expect(ai._sealed_stack_action_penalty(sealed, release_action, Rules.BLACK) >= 30.0, "nonlethal artillery strongly penalizes reopening a sealed 3 Stack")
	var sealed_decision: Dictionary = ai.choose_action(sealed)
	expect(Codec.normalize_action(sealed_decision.action) != Codec.normalize_action(release_action), "computer leaves the harmless full Spy Stack sealed")
	var release_result := GameEngine.simulate_action(sealed, release_action)
	expect(ai._special_option_commitment_penalty(sealed, release_action, release_result, Rules.BLACK) >= 10.0, "computer preserves Recall artillery instead of spending it on an inert target")

	for sealed_kind in [Rules.SPY, Rules.BALLISTA, Rules.TREBUCHET]:
		var capture_state := empty_state({
			"A1": [p(Rules.BLACK, Rules.SOVEREIGN)],
			"E3": [p(Rules.BLACK, Rules.INFANTRY), p(Rules.BLACK, Rules.CHARIOT), p(Rules.BLACK, Rules.MARSHAL)],
			"E6": [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.DRAGOON), p(Rules.WHITE, sealed_kind)],
		}, Rules.BLACK)
		capture_state.rules = Rules.current_beta_ruleset()
		capture_state.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
		capture_state.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
		capture_state.reserves.white.recall = 1
		var capture_action := {"type":"move", "source":"E3", "destination":"E6"}
		expect(ai._sealed_stack_action_penalty(capture_state, capture_action, Rules.BLACK) >= 20.0, "%s 3 Stack capture recognizes the opponent's available Recall" % Rules.piece_display_name(sealed_kind))
		capture_state.board.D4 = [p(Rules.BLACK, Rules.SOVEREIGN)]
		capture_state.board.erase("A1")
		var royal_action := {"type":"move", "source":"D4", "destination":"E5"}
		capture_state.board.E5 = capture_state.board.E6
		capture_state.board.erase("E6")
		expect(ai._sealed_stack_action_penalty(capture_state, royal_action, Rules.BLACK) > ai._sealed_stack_action_penalty(capture_state, {"type":"move", "source":"E3", "destination":"E5"}, Rules.BLACK), "Royal Attack receives an additional sealed-stack penalty")

	var varied_opening := GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(3, 5))
	var varied_sequence := [
		{"type":"place", "piece":"infantry", "destination":"D3"},
		{"type":"place", "piece":"infantry", "destination":"C7"},
		{"type":"place", "piece":"infantry", "destination":"H3"},
		{"type":"place", "piece":"infantry", "destination":"E7"},
		{"type":"place", "piece":"chariot", "destination":"D3"},
		{"type":"place", "piece":"infantry", "destination":"A7"},
		{"type":"place", "piece":"dragoon", "destination":"H3"},
	]
	for action in varied_sequence:
		varied_opening = GameEngine.apply_action(varied_opening, action)
	var fourth_black: Dictionary = ai.choose_action(varied_opening)
	expect(str(fourth_black.action.get("piece", "")) in [Rules.DRAGOON, Rules.CHARIOT, Rules.GRIFFIN], "computer develops a standard mobile TOP before committing a Marshal")
	expect(ai._is_developing_placement(varied_opening, fourth_black.action, Rules.BLACK), "computer's fourth opening placement creates useful mobility")

	var vector_opening := GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(6, 2))
	vector_opening = GameEngine.apply_action(vector_opening, {"type":"place", "piece":"infantry", "destination":"H3"})
	var direct_foundation := {"type":"place", "piece":"infantry", "destination":"C7"}
	var decorative_foundation := {"type":"place", "piece":"infantry", "destination":"B7"}
	expect(ai._opening_score(vector_opening, direct_foundation) > ai._opening_score(vector_opening, decorative_foundation), "opening Infantry favors the direct Chariot corridor in front of the Sovereign")
	var vector_decision: Dictionary = ai.choose_action(vector_opening)
	expect(str(vector_decision.action.get("piece", "")) == Rules.INFANTRY and ai._foundation_geometry_score(vector_opening, Rules.BLACK, str(vector_decision.action.get("destination", ""))) >= 235.0, "computer stages its first foundation on a meaningful Sovereign vector")

	var development_choice := empty_state({
		"A1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"C9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"D7": [p(Rules.BLACK, Rules.INFANTRY)],
		"F7": [p(Rules.BLACK, Rules.INFANTRY)],
		"H3": [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.CHARIOT)],
	}, Rules.BLACK)
	development_choice.rules = Rules.current_beta_ruleset()
	development_choice.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	development_choice.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	development_choice.reserves.black.chariot = 1
	development_choice.reserves.black.dragoon = 1
	development_choice.reserves.black.marshal = 1
	development_choice.reserves.black.infantry = 2
	var quiet_infantry := {"type":"move", "source":"D7", "destination":"D6"}
	var quiet_result := GameEngine.simulate_action(development_choice, quiet_infantry)
	expect(ai._quiet_infantry_move_penalty(development_choice, quiet_infantry, quiet_result, Rules.BLACK) >= 25.0, "midgame quiet Infantry advancement receives a strong tempo penalty")
	var develop_chariot := {"type":"place", "piece":"chariot", "destination":"D7"}
	var develop_result := GameEngine.simulate_action(development_choice, develop_chariot)
	expect(ai._development_action_bonus(development_choice, develop_chariot, develop_result, Rules.BLACK) >= 15.0, "midgame mobile TOP placement receives development urgency")
	var development_decision: Dictionary = ai.choose_action(development_choice)
	expect(str(development_decision.action.get("piece", "")) in [Rules.DRAGOON, Rules.CHARIOT, Rules.MARSHAL] and str(development_decision.action.get("destination", "")) in ["D7", "F7"], "computer develops reserve power instead of marching an idle Infantry")

	var take_pressure := empty_state({
		"A1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"I9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"E7": [p(Rules.BLACK, Rules.INFANTRY), p(Rules.BLACK, Rules.CHARIOT)],
		"E4": [p(Rules.WHITE, Rules.INFANTRY)],
	}, Rules.BLACK)
	var attrit_pressure := take_pressure.duplicate(true)
	attrit_pressure.board.E4 = [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.MARSHAL)]
	expect(ai._development_threat_score(take_pressure, Rules.BLACK, "E7") > ai._development_threat_score(attrit_pressure, Rules.BLACK, "E7"), "TOP evaluation prioritizes full-take threats over attrition threats")

	var active_board := empty_state({
		"A1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"E7": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"A3": [p(Rules.WHITE, Rules.INFANTRY)],
		"C3": [p(Rules.WHITE, Rules.INFANTRY)],
		"G3": [p(Rules.WHITE, Rules.INFANTRY)],
		"B7": [p(Rules.BLACK, Rules.INFANTRY)],
		"H7": [p(Rules.BLACK, Rules.INFANTRY)],
	}, Rules.BLACK)
	active_board.rules = Rules.current_beta_ruleset()
	active_board.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	active_board.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	active_board.reserves.black.infantry = 1
	var premature_advance := {"type":"move", "source":"E7", "destination":"E6"}
	var premature_result := GameEngine.simulate_action(active_board, premature_advance)
	expect(ai._premature_conquer_advance_penalty(active_board, premature_advance, premature_result, Rules.BLACK) >= 20.0, "active-board Sovereign advance is not rewarded as generic Conquer progress")
	var sparse_endgame := active_board.duplicate(true)
	for square in ["A3", "C3", "G3", "B7", "H7"]:
		sparse_endgame.board.erase(square)
	sparse_endgame.reserves.black.infantry = 0
	var endgame_result := GameEngine.simulate_action(sparse_endgame, premature_advance)
	expect(ai._premature_conquer_advance_penalty(sparse_endgame, premature_advance, endgame_result, Rules.BLACK) == 0.0 and ai._conquer_progress_score(sparse_endgame, Rules.BLACK) > 0.0, "Conquer progress becomes strategically relevant on a clear endgame board")

	var spy_exposure := empty_state({
		"I1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"A9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"B7": [p(Rules.BLACK, Rules.INFANTRY)],
	}, Rules.BLACK)
	spy_exposure.rules = Rules.current_beta_ruleset()
	spy_exposure.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	spy_exposure.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	spy_exposure.reserves.black.marshal = 1
	spy_exposure.reserves.white.spy = 1
	spy_exposure.reserves.white.infantry = 1
	spy_exposure.reserves.white.marshal = 1
	var exposed_marshal_action := {"type":"place", "piece":"marshal", "destination":"B7"}
	var exposed_marshal_result := GameEngine.simulate_action(spy_exposure, exposed_marshal_action)
	expect(GameEngine.can_spy_convert(exposed_marshal_result, Rules.WHITE, "B7"), "shared engine helper recognizes a legal reserve-matched Spy conversion")
	expect(ai._spy_conversion_exposure_at(exposed_marshal_result, Rules.BLACK, "B7") > 0.0, "AI values exact Spy conversion exposure")
	expect(ai._premium_commitment_penalty(spy_exposure, exposed_marshal_action, exposed_marshal_result, Rules.BLACK) > 0.0, "AI preserves a Marshal when deployment has no tactical justification")

	var dominant := empty_state({
		"I1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"A9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"E5": [p(Rules.BLACK, Rules.INFANTRY), p(Rules.BLACK, Rules.CHARIOT), p(Rules.BLACK, Rules.MARSHAL)],
		"E6": [p(Rules.WHITE, Rules.INFANTRY)],
	}, Rules.BLACK)
	dominant.rules = Rules.current_beta_ruleset()
	dominant.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	dominant.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	expect(ai._has_critical_tactical_action(dominant, Rules.BLACK), "search extension recognizes a 3-Stack tactical capture")
	expect(ai._dominant_stack_pressure(dominant, Rules.BLACK) > 0.0, "evaluation measures immediate dominant-stack pressure")

	var premium_escape := empty_state({
		"I1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"A9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"E4": [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.CHARIOT)],
		"E5": [p(Rules.BLACK, Rules.INFANTRY), p(Rules.BLACK, Rules.MARSHAL)],
	}, Rules.BLACK)
	premium_escape.rules = Rules.current_beta_ruleset()
	premium_escape.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	premium_escape.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	var marshal_escape := {"type":"move", "source":"E5", "destination":"F5"}
	var marshal_escape_result := GameEngine.simulate_action(premium_escape, marshal_escape)
	expect(not marshal_escape_result.is_empty() and ai._saves_exposed_premium(premium_escape, marshal_escape, marshal_escape_result, Rules.BLACK), "candidate diversity preserves a safe Marshal escape from an attacked square")

	# Frozen checkpoint from human-1792033284-450-WD-BF immediately before
	# Black's logged 10B Infantry-on-Infantry placement.
	var logged_checkpoint := GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(3, 5))
	var logged_actions := [
		{"type":"place", "piece":"infantry", "destination":"B3"},
		{"type":"place", "piece":"infantry", "destination":"E7"},
		{"type":"place", "piece":"infantry", "destination":"F3"},
		{"type":"place", "piece":"infantry", "destination":"E7"},
		{"type":"place", "piece":"dragoon", "destination":"B3"},
		{"type":"place", "piece":"infantry", "destination":"G7"},
		{"type":"place", "piece":"chariot", "destination":"F3"},
		{"type":"place", "piece":"infantry", "destination":"G7"},
		{"type":"move", "source":"B3", "destination":"A4"},
		{"type":"place", "piece":"ballista", "destination":"A5", "effect_target":"A4"},
		{"type":"place", "piece":"griffin", "destination":"A4"},
		{"type":"place", "piece":"trebuchet", "destination":"B5", "effect_target":"A4"},
		{"type":"place", "piece":"infantry", "destination":"C6"},
		{"type":"place", "piece":"spy", "destination":"F3"},
		{"type":"place", "piece":"dragoon", "destination":"C6"},
		{"type":"move", "source":"F9", "destination":"F8"},
		{"type":"place", "piece":"infantry", "destination":"A4"},
		{"type":"place", "piece":"infantry", "destination":"E7"},
		{"type":"place", "piece":"marshal", "destination":"A4"},
	]
	for action in logged_actions:
		logged_checkpoint = GameEngine.apply_action(logged_checkpoint, action)
	var legacy_ai = OpponentAI.new(false)
	var legacy_checkpoint_decision: Dictionary = legacy_ai.choose_action(logged_checkpoint)
	var improved_checkpoint_decision: Dictionary = ai.choose_action(logged_checkpoint)
	expect(str(legacy_checkpoint_decision.action.get("piece", "")) == Rules.INFANTRY and str(legacy_checkpoint_decision.action.get("destination", "")) in ["E7", "G7"], "frozen checkpoint reproduces the legacy Infantry-on-Infantry choice")
	expect(not (str(improved_checkpoint_decision.action.get("piece", "")) == Rules.INFANTRY and str(improved_checkpoint_decision.action.get("destination", "")) in ["E7", "G7"]), "improved AI rejects the logged redundant Infantry stack at the frozen checkpoint")
	expect(ai._mobile_stack_count(GameEngine.simulate_action(logged_checkpoint, improved_checkpoint_decision.action), Rules.BLACK) > ai._mobile_stack_count(logged_checkpoint, Rules.BLACK), "improved checkpoint action develops Black mobility")
	var swapped_checkpoint := swap_colors_and_rotate(logged_checkpoint)
	var swapped_decision: Dictionary = ai.choose_action(swapped_checkpoint)
	expect(ai._mobile_stack_count(GameEngine.simulate_action(swapped_checkpoint, swapped_decision.action), Rules.WHITE) > ai._mobile_stack_count(swapped_checkpoint, Rules.WHITE), "color-swapped checkpoint produces the same mobility-first correction for White")

	var hanging := empty_state({
		"I1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"A9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"B7": [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.BALLISTA), p(Rules.WHITE, Rules.CHARIOT)],
		"B6": [p(Rules.BLACK, Rules.TREBUCHET)],
	}, Rules.BLACK)
	hanging.rules = Rules.current_beta_ruleset()
	hanging.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	hanging.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	hanging.reserves.black.marshal = 1
	hanging.reserves.black.infantry = 1
	var marshal_donation := {"type":"place", "piece":"marshal", "destination":"B6"}
	var exposed_result := GameEngine.apply_action(hanging, marshal_donation, false)
	expect(ai._exposure_pressure(exposed_result, Rules.BLACK) >= 9.0, "computer values every piece in an exposed Trebuchet-Marshal Stack")
	var hanging_decision: Dictionary = ai.choose_action(hanging)
	expect(Codec.normalize_action(hanging_decision.action) != Codec.normalize_action(marshal_donation), "computer declines the logged Marshal-on-Trebuchet donation")

	var defense := empty_state({
		"I1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"A9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"D6": [p(Rules.WHITE, Rules.DRAGOON)],
	}, Rules.BLACK)
	defense.rules = Rules.current_beta_ruleset()
	defense.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	defense.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	defense.reserves.black.infantry = 1
	defense.reserves.black.chariot = 1
	var infantry_block := {"type":"place", "piece":"infantry", "destination":"B8"}
	var chariot_block := {"type":"place", "piece":"chariot", "destination":"B8"}
	var infantry_result := GameEngine.apply_action(defense, infantry_block, false)
	var chariot_result := GameEngine.apply_action(defense, chariot_block, false)
	expect(ai._action_priority(defense, infantry_block, infantry_result, Rules.BLACK) > ai._action_priority(defense, chariot_block, chariot_result, Rules.BLACK), "equal defensive blocks prefer the lower-cost available material")
	expect(ai._is_interposition(defense, infantry_block, infantry_result, Rules.BLACK), "AI recognizes a safe tile placed between an attacker and the Sovereign as an interposition")
	var interposition_decision: Dictionary = ai.choose_action(defense)
	expect(str(interposition_decision.action.get("type", "")) == "place" and str(interposition_decision.action.get("piece", "")) == Rules.INFANTRY and str(interposition_decision.action.get("destination", "")) == "B8", "computer interposes cheap Infantry beside the Sovereign to preserve a Royal Attack counter")
	expect(str(interposition_decision.reason) == "Sovereign interposition", "computer records an interposition as the reason for its defense")

	var no_infantry_defense := defense.duplicate(true)
	no_infantry_defense.reserves.black.infantry = 0
	no_infantry_defense.reserves.black.marshal = 1
	var alternate_interposition: Dictionary = ai.choose_action(no_infantry_defense)
	expect(str(alternate_interposition.action.get("type", "")) == "place" and str(alternate_interposition.action.get("piece", "")) == Rules.CHARIOT and str(alternate_interposition.action.get("destination", "")) == "B8", "computer interposes the cheapest effective non-Infantry tile beside the Sovereign when Infantry is unavailable")

	var pincer_defense := empty_state({
		"I1": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"A9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"D6": [p(Rules.WHITE, Rules.DRAGOON)],
		"A6": [p(Rules.WHITE, Rules.CHARIOT)],
	}, Rules.BLACK)
	pincer_defense.rules = Rules.current_beta_ruleset()
	pincer_defense.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	pincer_defense.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	pincer_defense.reserves.black.infantry = 1
	expect(GameEngine.is_sovereign_threatened(pincer_defense, Rules.BLACK), "pincer fixture attacks the Sovereign along two independent lines")
	expect(not ai._has_safe_interposition(pincer_defense, GameEngine.legal_actions(pincer_defense), Rules.BLACK), "AI does not call a one-line block a defense against a pincer")
	var pincer_decision: Dictionary = ai.choose_action(pincer_defense)
	expect(str(pincer_decision.action.get("type", "")) == "move" and str(pincer_decision.action.get("source", "")) == "A9", "computer moves the Sovereign when no single interposition answers the pincer")

	var forced_loss := empty_state({
		"I5": [p(Rules.WHITE, Rules.SOVEREIGN)],
		"B9": [p(Rules.BLACK, Rules.SOVEREIGN)],
		"B6": [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.BALLISTA), p(Rules.WHITE, Rules.CHARIOT)],
		"B8": [p(Rules.WHITE, Rules.DRAGOON), p(Rules.WHITE, Rules.MARSHAL)],
	}, Rules.BLACK)
	forced_loss.rules = Rules.current_beta_ruleset()
	forced_loss.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	forced_loss.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	var forced_score := ai._search(forced_loss, Rules.BLACK, 0, -1000000000.0, 1000000000.0, 2)
	expect(forced_score < -500000000.0, "forcing extension sees through a protected Marshal threat to the eventual Sovereign capture")
	var resignation_decision: Dictionary = ai.choose_action(forced_loss)
	expect(bool(resignation_decision.get("resign", false)), "computer resigns when every Black action permits immediate White victory")
	expect(int(resignation_decision.get("candidates_considered", 0)) == GameEngine.legal_actions(forced_loss).size(), "resignation proves the loss across every legal Black action")
	var white_forced_loss := swap_colors_and_rotate(forced_loss)
	var white_resignation: Dictionary = ai.choose_action(white_forced_loss)
	expect(bool(white_resignation.get("resign", false)) and str(white_resignation.reason).contains("Black victory"), "forced-loss resignation works when the computer plays White")

	# Frozen human-1792092814 position before White's losing 9W block. Black's
	# protected Marshal can consume any I2 blocker, while H1 is a safe escape.
	var protected_attack := GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(8, 0))
	var protected_attack_sequence := [
		{"type":"place", "piece":"infantry", "destination":"H3"},
		{"type":"place", "piece":"infantry", "destination":"C7"},
		{"type":"place", "piece":"infantry", "destination":"G3"},
		{"type":"place", "piece":"infantry", "destination":"I7"},
		{"type":"place", "piece":"infantry", "destination":"I3"},
		{"type":"place", "piece":"dragoon", "destination":"C7"},
		{"type":"place", "piece":"dragoon", "destination":"G3"},
		{"type":"place", "piece":"chariot", "destination":"I7"},
		{"type":"place", "piece":"chariot", "destination":"H3"},
		{"type":"place", "piece":"spy", "destination":"I3"},
		{"type":"place", "piece":"infantry", "destination":"A1"},
		{"type":"move", "source":"I7", "destination":"I6"},
		{"type":"place", "piece":"chariot", "destination":"A1"},
		{"type":"place", "piece":"marshal", "destination":"I3"},
	]
	for action in protected_attack_sequence:
		protected_attack = GameEngine.apply_action(protected_attack, action)
	expect(GameEngine.is_sovereign_threatened(protected_attack, Rules.WHITE), "protected-attack fixture reproduces the I3 Marshal threat")
	var protected_defense: Dictionary = ai.choose_action(protected_attack)
	expect(str(protected_defense.action.get("type", "")) == "move" and str(protected_defense.action.get("source", "")) == "I1" and str(protected_defense.action.get("destination", "")) == "H1", "computer White escapes instead of feeding a blocker to the protected attacker")
	var losing_block := GameEngine.simulate_action(protected_attack, {"type":"place", "piece":"dragoon", "destination":"I2"})
	var mating_capture := GameEngine.simulate_action(losing_block, {"type":"move", "source":"I3", "destination":"I2"})
	expect(ai._all_actions_allow_immediate_opponent_win(mating_capture, GameEngine.legal_actions(mating_capture), Rules.WHITE), "search proves the protected capture leaves every White reply losing")
	expect(ai._search(mating_capture, Rules.WHITE, 0, -1000000000.0, 1000000000.0, 1) < -500000000.0, "tactical search scores the protected capture as a forced loss")

	var prototype := VisualPrototype.new()
	prototype.view_mode = "play"
	prototype.ai_enabled = true
	prototype.human_recording_enabled = false
	prototype.game_state = winning.duplicate(true)
	prototype.manual_initial_state = winning.duplicate(true)
	prototype.manual_states = [winning.duplicate(true)]
	prototype._perform_ai_turn()
	expect(prototype.manual_actions.size() == 1 and prototype.game_state.winner == Rules.BLACK, "simulator applies the computer's turn through the shared rules engine")
	expect(prototype.ai_annotations.size() == 1 and prototype.ai_annotations[0].has("reason"), "simulator records an auditable computer decision annotation")
	expect(prototype._game_end_method() == "SOVEREIGN CAPTURE", "game-over presentation identifies a Sovereign-capture victory")
	prototype.free()

	var resignation_prototype := VisualPrototype.new()
	resignation_prototype.view_mode = "play"
	resignation_prototype.ai_enabled = true
	resignation_prototype.human_recording_enabled = false
	resignation_prototype.game_state = forced_loss.duplicate(true)
	resignation_prototype.manual_initial_state = forced_loss.duplicate(true)
	resignation_prototype.manual_states = [forced_loss.duplicate(true)]
	resignation_prototype._perform_ai_turn()
	expect(resignation_prototype.game_state.winner == Rules.WHITE and resignation_prototype.manual_actions.is_empty(), "Black resignation awards White victory without inventing a board action")
	expect(resignation_prototype._game_end_method() == "RESIGNATION", "game-over presentation identifies resignation")
	expect(not resignation_prototype.ai_annotations.is_empty() and str(resignation_prototype.ai_annotations[-1].get("event", "")) == "resignation", "replay metadata records the resignation event")
	var resignation_document: Dictionary = resignation_prototype._human_replay_document()
	expect(str(resignation_document.metadata.get("end_method", "")) == "RESIGNATION", "recorded game metadata preserves the resignation result")
	var resignation_replay := VisualPrototype.new()
	resignation_replay._load_replay_document(resignation_document)
	resignation_replay._set_replay_index(resignation_replay.replay_states.size() - 1)
	expect(resignation_replay.game_state.winner == Rules.WHITE and resignation_replay._game_end_method() == "RESIGNATION", "replay review restores a resignation without a fictional action")
	resignation_replay.free()
	resignation_prototype.free()

	var white_resignation_prototype := VisualPrototype.new()
	white_resignation_prototype.view_mode = "play"
	white_resignation_prototype.ai_enabled = true
	white_resignation_prototype.ai_player = Rules.WHITE
	white_resignation_prototype.human_recording_enabled = false
	white_resignation_prototype.game_state = white_forced_loss.duplicate(true)
	white_resignation_prototype.manual_initial_state = white_forced_loss.duplicate(true)
	white_resignation_prototype.manual_states = [white_forced_loss.duplicate(true)]
	white_resignation_prototype._perform_ai_turn()
	expect(white_resignation_prototype.game_state.winner == Rules.BLACK and white_resignation_prototype._game_end_method() == "RESIGNATION", "computer White resignation correctly awards Black the game")
	white_resignation_prototype.free()

	var setup_prototype := VisualPrototype.new()
	setup_prototype.view_mode = "play"
	setup_prototype.ai_enabled = true
	setup_prototype.human_recording_enabled = false
	setup_prototype._queue_ai_turn()
	expect(setup_prototype.ai_busy, "computer Black Sovereign choice is queued before White responds")
	setup_prototype._perform_ai_sovereign_setup()
	expect(setup_prototype.game_state.is_empty() and setup_prototype.setup_black_file == 2 and setup_prototype.setup_position.has("C9"), "computer chooses Black's mirrored-distance band before White")
	setup_prototype._handle_play_square("D1")
	expect(setup_prototype.game_state.is_empty(), "White may not choose a non-mirrored Sovereign response")
	setup_prototype._handle_play_square("G1")
	expect(not setup_prototype.game_state.is_empty() and setup_prototype.game_state.board.has("C9") and setup_prototype.game_state.board.has("G1"), "White chooses the same-distance square on either side")
	expect(setup_prototype.game_state.turn == Rules.WHITE, "White receives the first normal action after computer Sovereign setup")
	setup_prototype.free()

	var white_setup := VisualPrototype.new()
	white_setup.view_mode = "play"
	white_setup.ai_enabled = true
	white_setup.ai_player = Rules.WHITE
	white_setup.human_recording_enabled = false
	white_setup._handle_play_square("B9")
	expect(white_setup.ai_busy and white_setup.setup_black_file == 1, "human Black chooses the Sovereign band before computer White responds")
	white_setup._perform_ai_sovereign_setup()
	expect(not white_setup.game_state.is_empty() and white_setup.game_state.board.has("B9") and white_setup.game_state.board.has("H1"), "computer White chooses a legal mirrored Sovereign response")
	expect(white_setup.game_state.turn == Rules.WHITE and str(ai.choose_action(white_setup.game_state).action.get("piece", "")) == Rules.INFANTRY, "the shared opponent AI can make White's first action")
	var white_setup_document := white_setup._human_replay_document()
	expect(white_setup_document.metadata.computer_color == Rules.WHITE and white_setup_document.metadata.human_color == Rules.BLACK, "human-vs-computer replay metadata records both assigned colors")
	white_setup.ai_enabled = false
	white_setup.free()

	var side_toggle := VisualPrototype.new()
	side_toggle.ai_enabled = true
	side_toggle.human_recording_enabled = false
	side_toggle._handle_right_control("toggle_ai_side")
	expect(side_toggle.ai_player == Rules.WHITE and side_toggle.game_state.is_empty() and not side_toggle.ai_busy, "PLAY color control starts a fresh human-Black game with computer White")
	side_toggle.free()

	var hotseat_setup := VisualPrototype.new()
	hotseat_setup.view_mode = "play"
	hotseat_setup.human_recording_enabled = false
	hotseat_setup._handle_play_square("B9")
	expect(hotseat_setup.setup_black_file == 1 and hotseat_setup.setup_position.has("B9"), "hot-seat setup gives Black the first Sovereign choice")
	hotseat_setup._handle_play_square("B1")
	expect(not hotseat_setup.game_state.is_empty() and hotseat_setup.game_state.board.has("B1") and hotseat_setup.game_state.board.has("B9"), "hot-seat White may choose the same-side mirrored distance")
	hotseat_setup.free()

	# Regression for the first open-play handoff reported from the simulator.
	var transition := GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(8, 0))
	var development := [
		{"type":"place", "piece":"infantry", "destination":"H2"},
		{"type":"place", "piece":"infantry", "destination":"B7"},
		{"type":"place", "piece":"infantry", "destination":"H2"},
		{"type":"place", "piece":"infantry", "destination":"B7"},
		{"type":"place", "piece":"infantry", "destination":"A3"},
		{"type":"place", "piece":"infantry", "destination":"A7"},
		{"type":"place", "piece":"infantry", "destination":"E3"},
		{"type":"place", "piece":"infantry", "destination":"A7"},
	]
	for action in development:
		transition = GameEngine.apply_action(transition, action)
	transition = GameEngine.apply_action(transition, {"type":"move", "source":"A3", "destination":"A4"})
	var started := Time.get_ticks_msec()
	var transition_decision: Dictionary = ai.choose_action(transition)
	var elapsed := Time.get_ticks_msec() - started
	expect(not transition_decision.is_empty(), "computer responds after the first post-development MOVE")
	expect(elapsed < 3000, "first open-play computer response remains within the interactive search budget (%d ms)" % elapsed)


func _test_shared_rule_configuration() -> void:
	expect(Rules.configuration_errors().is_empty(), "shared rule JSON passes strict validation")
	expect(Rules.catalog_id() == "core-pieces-v4", "piece catalog id loads")
	expect(Rules.special_rules("sovereign").royal_attack, "Royal Attack comes from shared catalog")
	expect(Rules.catalog_hash().length() == 64, "piece catalog has a reproducible SHA-256 identity")
	expect(Rules.starting_inventory().infantry == 9, "starting inventory comes from shared catalog")
	expect(Rules.piece_notation(Rules.SOVEREIGN) == "V", "Sovereign notation comes from shared catalog")
	expect(Rules.piece_notation(Rules.SPY) == "Sp", "special-unit notation comes from shared catalog")
	var griffin: Dictionary = Rules.piece_definition(Rules.GRIFFIN)
	expect(griffin.movement.vectors_by_height["1"] == [[1.0, 2.0], [2.0, 1.0]], "height-one Griffin vectors come from shared catalog")
	expect(griffin.movement.vectors_by_height["3"] == [[1.0, 2.0], [2.0, 1.0], [2.0, 3.0], [3.0, 2.0]], "height-three Griffin vectors come from shared catalog")
	var ruleset := Rules.development_ruleset()
	expect(ruleset.id == "development-v3" and ruleset.catalog_hash == Rules.catalog_hash(), "ruleset records its shared catalog identity")
	expect(Rules.attrition_control_ruleset().move_vs_taller == "mutual_bottom_attrition", "MOVE attrition ruleset loads")
	expect(Rules.attrition_development_ruleset().artillery_vs_taller == "target_bottom_attrition", "artillery attrition ruleset loads")
	expect(not Rules.development_ruleset().infiltration_victory, "baseline keeps capture-only victory")
	expect(Rules.development_infiltration_ruleset().infiltration_victory, "infiltration ruleset loads")
	expect(Rules.current_beta_ruleset().id == "attrition-neutral-gate-opening-4-v1", "current beta uses the four-PLACE shared-neutral-gate ruleset")


func _test_initial_development_state() -> void:
	var state := GameEngine.initial_state(Rules.development_ruleset(), Vector2i(0, 8))
	expect(state.board.has("A1") and state.board.has("I9"), "variable back-rank Sovereigns")
	expect(GameEngine.in_development(state), "development begins active")
	var actions := GameEngine.legal_actions(state)
	expect(not actions.is_empty(), "development has legal placements")
	expect(not actions.any(func(a): return a.type == "move"), "no moves during development")
	expect(not actions.any(func(a): return a.get("piece") in ["spy", "ballista", "trebuchet", "recall"]), "specials prohibited during development")
	expect(GameEngine.validate_state(state, true).is_empty(), "initial inventory validates")


func _test_development_sequence_and_height_unlock() -> void:
	var state := GameEngine.initial_state()
	var sequence := [
		{"type":"place", "piece":"infantry", "destination":"A1"},
		{"type":"place", "piece":"infantry", "destination":"A9"},
		{"type":"place", "piece":"chariot", "destination":"A1"},
		{"type":"place", "piece":"chariot", "destination":"A9"},
		{"type":"place", "piece":"infantry", "destination":"A2"},
		{"type":"place", "piece":"infantry", "destination":"A8"},
		{"type":"place", "piece":"griffin", "destination":"B2"},
		{"type":"place", "piece":"griffin", "destination":"B8"},
	]
	for action in sequence:
		expect(has(GameEngine.legal_actions(state), action), "development action is legal")
		state = GameEngine.apply_action(state, action)
	expect(not GameEngine.in_development(state), "development ends after four extra placements each")
	expect(not has(GameEngine.legal_actions(state), {"type":"place", "piece":"marshal", "destination":"A1"}), "height three locked before non-Sovereign move")
	state = GameEngine.apply_action(state, {"type":"move", "source":"A2", "destination":"A3"})
	state.turn = Rules.WHITE
	expect(state.height_three_unlocked.white, "non-Sovereign move unlocks height three")
	expect(has(GameEngine.legal_actions(state), {"type":"place", "piece":"marshal", "destination":"A1"}), "height three placement becomes legal")


func _test_shared_neutral_height_unlock() -> void:
	var state := GameEngine.initial_state(Rules.current_beta_ruleset())
	state.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	state.board.A1 = [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.CHARIOT)]
	state.board.A9 = [p(Rules.BLACK, Rules.INFANTRY), p(Rules.BLACK, Rules.CHARIOT)]
	state.reserves.white.infantry -= 1
	state.reserves.white.chariot -= 1
	state.reserves.black.infantry -= 1
	state.reserves.black.chariot -= 1
	expect(not state.height_three_unlocked.white and not state.height_three_unlocked.black, "shared neutral gate begins locked")
	expect(not has(GameEngine.legal_actions(state), {"type":"place", "piece":"marshal", "destination":"A1"}), "shared neutral gate blocks height three")
	state = GameEngine.apply_action(state, {"type":"place", "piece":"infantry", "destination":"B1"})
	expect(not state.height_three_unlocked.white and not state.height_three_unlocked.black, "home-territory material does not open shared neutral gate")
	state = GameEngine.apply_action(state, {"type":"place", "piece":"infantry", "destination":"D4"})
	expect(state.height_three_unlocked.white and state.height_three_unlocked.black, "neutral material opens height three for both players")
	expect(state.turn == Rules.WHITE, "gate opener's opponent receives first height-three opportunity")
	expect(has(GameEngine.legal_actions(state), {"type":"place", "piece":"marshal", "destination":"A1"}), "height three is legal after shared gate opens")


func _test_white_open_placement_regressions() -> void:
	var state := GameEngine.initial_state(Rules.current_beta_ruleset())
	state.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	state.height_three_unlocked = {Rules.WHITE: true, Rules.BLACK: true}
	state.board.B2 = [p(Rules.WHITE, Rules.INFANTRY)]
	state.board.C2 = [p(Rules.WHITE, Rules.INFANTRY), p(Rules.WHITE, Rules.DRAGOON)]
	state.board.E8 = [p(Rules.BLACK, Rules.INFANTRY), p(Rules.BLACK, Rules.INFANTRY)]
	state.reserves.white.infantry -= 2
	state.reserves.white.dragoon -= 1
	state.reserves.black.infantry -= 2
	var actions := GameEngine.legal_actions(state)
	expect(has(actions, {"type":"place", "piece":"spy", "destination":"E8"}), "White Spy may convert a legal enemy-territory stack after the opening")
	expect(has(actions, {"type":"place", "piece":"ballista", "destination":"B2"}), "White Ballista may stack on a friendly 1 Stack")
	expect(has(actions, {"type":"place", "piece":"ballista", "destination":"C2"}), "White Ballista may make a 3 Stack after the shared gate opens")
	var prototype := VisualPrototype.new()
	prototype.view_mode = "play"
	prototype.game_state = state.duplicate(true)
	prototype._select_reserve_piece(Rules.BALLISTA)
	expect(prototype.selected_piece_kind == Rules.BALLISTA, "White can select the Ballista in the simulator")
	prototype._handle_play_square("C2")
	expect(prototype.game_state.board.C2.size() == 3 and prototype.game_state.board.C2[-1].kind == Rules.BALLISTA, "White can complete a Ballista 3 Stack through the simulator")
	prototype.game_state = state.duplicate(true)
	prototype._select_reserve_piece(Rules.SPY)
	expect(prototype.selected_piece_kind == Rules.SPY, "White can select the Spy in the simulator")
	prototype._handle_play_square("E8")
	expect(prototype.game_state.board.E8.size() == 3 and prototype.game_state.board.E8[-1].owner == Rules.WHITE and prototype.game_state.board.E8[-1].kind == Rules.SPY, "White can complete enemy-territory Spy conversion through the simulator")
	prototype.free()


func _test_movement_and_capture_rules() -> void:
	var state := empty_state({
		"E4": [p("white", "reinforcement"), p("white", "infantry")],
		"E6": [p("black", "infantry")],
	})
	var actions := GameEngine.legal_actions(state)
	expect(has(actions, {"type":"move", "source":"E4", "destination":"E5"}), "Infantry 2 Stack moves one")
	expect(has(actions, {"type":"move", "source":"E4", "destination":"E6"}), "Infantry 2 Stack captures at range two")
	state.board.E6.append(p("black", "chariot"))
	expect(has(GameEngine.legal_actions(state), {"type":"move", "source":"E4", "destination":"E6"}), "equal-height capture legal")
	state.board.E6.append(p("black", "marshal"))
	expect(not has(GameEngine.legal_actions(state), {"type":"move", "source":"E4", "destination":"E6"}), "shorter stack cannot capture taller stack")


func _test_move_attrition() -> void:
	var state := empty_state({
		"A1": [p("white", "infantry")],
		"A2": [p("black", "reinforcement"), p("black", "infantry"), p("black", "marshal")],
	})
	state.rules = Rules.attrition_control_ruleset()
	var action := {"type":"move", "source":"A1", "destination":"A2"}
	expect(has(GameEngine.legal_actions(state), action), "shorter MOVE attack is legal under attrition rules")
	state = GameEngine.apply_action(state, action)
	expect(not state.board.has("A1"), "attrition discards the attacking stack")
	expect(state.board.A2.size() == 2 and state.board.A2[0].kind == "infantry" and state.board.A2[-1].kind == "marshal", "MOVE attrition removes defenders from the bottom")
	expect(state.discards.white.infantry == 1 and state.discards.black.reinforcement == 1, "MOVE attrition accounts for both players' losses")

	state = empty_state({
		"A1": [p("white", "reinforcement"), p("white", "infantry")],
		"A2": [p("black", "infantry"), p("black", "marshal")],
	})
	state.rules = Rules.attrition_control_ruleset()
	state = GameEngine.apply_action(state, action)
	expect(state.board.A2[-1].owner == "white" and state.board.A2.size() == 2, "equal-height MOVE still captures and occupies")
	expect(state.discards.white.infantry == 0 and state.discards.black.infantry == 1 and state.discards.black.marshal == 1, "equal-height capture only discards defenders")


func _test_royal_attack() -> void:
	var state := empty_state({
		"E4": [p("white", "sovereign")],
		"E5": [p("black", "reinforcement"), p("black", "infantry"), p("black", "marshal")],
		"E7": [p("black", "marshal")],
	})
	state.rules = Rules.attrition_control_ruleset()
	var action := {"type":"move", "source":"E4", "destination":"E5"}
	expect(has(GameEngine.legal_actions(state), action), "Sovereign may Royal Attack a taller adjacent stack")
	state = GameEngine.apply_action(state, action)
	expect(state.board.E5.size() == 1 and state.board.E5[-1].kind == "sovereign", "Royal Attack removes the entire stack and occupies")
	expect(state.discards.black.reinforcement == 1 and state.discards.black.infantry == 1 and state.discards.black.marshal == 1, "Royal Attack discards every defender")
	expect(state.discards.white.sovereign == 0, "Royal Attack never applies self-attrition")
	expect(GameEngine.is_sovereign_threatened(state, Rules.WHITE), "protected Royal Attack is legal but leaves Sovereign threatened")


func _test_infiltration_victory() -> void:
	var state := empty_state({
		"E8": [p("white", "sovereign")],
		"E1": [p("black", "sovereign")],
	})
	state.rules = Rules.development_infiltration_ruleset()
	state.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	var action := {"type":"move", "source":"E8", "destination":"E9"}
	expect(has(GameEngine.legal_actions(state), action), "Sovereign may move onto the enemy back row")
	state = GameEngine.apply_action(state, action)
	expect(state.winner == Rules.WHITE and GameEngine.is_over(state), "back-row infiltration wins immediately")

	state = empty_state({"E8": [p("white", "sovereign")], "E1": [p("black", "sovereign")]})
	state = GameEngine.apply_action(state, action)
	expect(state.winner == null, "capture-only rules do not award back-row victory")

	state = empty_state({
		"E8": [p("white", "infantry")],
		"E1": [p("white", "sovereign")],
		"A9": [p("black", "sovereign")],
	})
	state.rules = Rules.ruleset("attrition-neutral-gate-opening-4-v1")
	state.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
	state = GameEngine.apply_action(state, action)
	expect(state.winner == null, "only a Sovereign can win by back-row infiltration")


func _test_griffin_height_three_moves() -> void:
	var state := empty_state({"E5": [p("white","infantry"), p("white","chariot"), p("white","griffin")]})
	var actions := GameEngine.legal_actions(state)
	expect(has(actions, {"type":"move", "source":"E5", "destination":"H7"}), "height-three Griffin has 3x2 leap")
	expect(has(actions, {"type":"move", "source":"E5", "destination":"G8"}), "height-three Griffin has 2x3 leap")
	expect(has(actions, {"type":"move", "source":"E5", "destination":"F7"}), "height-three Griffin retains the 1x2 leap")
	expect(has(actions, {"type":"move", "source":"E5", "destination":"G6"}), "height-three Griffin retains the 2x1 leap")
	expect(not has(actions, {"type":"move", "source":"E5", "destination":"H9"}), "height-three Griffin has no obsolete 3x4 leap")


func _test_artillery_range_and_sovereign_immunity() -> void:
	var state := empty_state({
		"E7": [p("black","infantry")],
		"F4": [p("black","infantry")],
		"H4": [p("black","infantry")],
		"D4": [p("black","sovereign")],
	})
	state.reserves.white.ballista = 1
	var actions := GameEngine.legal_actions(state)
	expect(has(actions, {"type":"place", "piece":"ballista", "destination":"E4"}), "artillery may decline to fire")
	expect(has(actions, {"type":"place", "piece":"ballista", "destination":"E4", "effect_target":"E7"}), "height-one artillery reaches three squares")
	expect(has(actions, {"type":"place", "piece":"ballista", "destination":"E4", "effect_target":"F4"}), "Ballista fires sideways")
	expect(not has(actions, {"type":"place", "piece":"ballista", "destination":"E4", "effect_target":"H4"}), "artillery cannot fire through a stack")
	expect(not has(actions, {"type":"place", "piece":"ballista", "destination":"E4", "effect_target":"D4"}), "artillery cannot target Sovereign")


func _test_artillery_attrition() -> void:
	var state := empty_state({
		"E6": [p("black", "reinforcement"), p("black", "infantry"), p("black", "marshal")],
	})
	state.rules = Rules.attrition_control_ruleset()
	state.reserves.white.ballista = 1
	var action := {"type":"place", "piece":"ballista", "destination":"E4", "effect_target":"E6"}
	expect(has(GameEngine.legal_actions(state), action), "shorter artillery may target a taller stack")
	state = GameEngine.apply_action(state, action)
	expect(state.board.E4.size() == 1 and state.board.E4[-1].kind == "ballista", "firing artillery stack is unaffected")
	expect(state.board.E6.size() == 2 and state.board.E6[0].kind == "infantry" and state.board.E6[-1].kind == "marshal", "artillery attrition removes target pieces from the bottom")
	expect(state.discards.white.ballista == 0 and state.discards.black.reinforcement == 1, "artillery attrition only discards target material")


func _test_spy_conversion_material_flow() -> void:
	var state := empty_state({"E5": [p("black","reinforcement"), p("black","marshal")]})
	state.reserves.white.spy = 1
	state.reserves.white.reinforcement = 1
	state.reserves.white.marshal = 1
	var action := {"type":"place", "piece":"spy", "destination":"E5"}
	expect(has(GameEngine.legal_actions(state), action), "Spy may convert affordable height-two enemy stack")
	state = GameEngine.apply_action(state, action)
	expect(state.board.E5.size() == 3 and state.board.E5[-1].kind == "spy", "Spy creates owned replacement stack in original order")
	expect(state.discards.black.reinforcement == 1 and state.discards.black.marshal == 1, "converted enemy material goes to discard")
	expect(state.reserves.white.marshal == 0, "replacement material comes from converting player's reserve")


func _test_reinforcement_position() -> void:
	var normalized := Codec.normalize_action({"type":"place", "piece":"reinforcement", "destination":"A4"})
	expect(normalized.piece == "reinforcement", "Reinforcement uses its canonical identifier")
	var state := empty_state({"A4": [p("white","marshal")]})
	state.reserves.white.reinforcement = 1
	state = GameEngine.apply_action(state, normalized)
	expect(state.board.A4[0].kind == "reinforcement" and state.board.A4[-1].kind == "marshal", "Reinforcement is inserted underneath the TOP piece")


func _test_recall_excludes_sovereign() -> void:
	var state := empty_state({"A4": [p("white","marshal")]})
	state.reserves.white.recall = 1
	state.discards.white.sovereign = 1
	state.discards.white.reinforcement = 1
	var actions := GameEngine.legal_actions(state)
	expect(not actions.any(func(a): return a.type == "recall" and a.piece == "sovereign"), "Sovereign is not a legal Recall target")
	expect(has(actions, {"type":"recall", "piece":"reinforcement", "destination":"A4"}), "non-Sovereign discarded piece may be Recalled")


func _test_immediate_sovereign_capture() -> void:
	var state := empty_state({"E8": [p("white","marshal")], "E9": [p("black","sovereign")]})
	state = GameEngine.apply_action(state, {"type":"move", "source":"E8", "destination":"E9"})
	expect(state.winner == "white" and GameEngine.is_over(state), "Sovereign capture ends game immediately")
	expect(GameEngine.legal_actions(state).is_empty(), "finished game has no legal actions")


func _test_golden_fixture() -> void:
	var fixture = Codec.load_json("res://../fixtures/development_opening.json")
	expect(fixture != null, "golden fixture loads")
	if fixture == null:
		return
	var state := Codec.normalize_state(fixture.initial_state)
	for step in fixture.steps:
		expect(has(GameEngine.legal_actions(state), step.action), "fixture action is legal: %s" % JSON.stringify(step.action))
		state = GameEngine.apply_action(state, step.action)
		expect(state.ply == int(step.expected.ply), "fixture expected ply")
		expect(state.turn == step.expected.turn, "fixture expected turn")
	expect(not GameEngine.in_development(state), "fixture exits development")
	expect(GameEngine.validate_state(state, true).is_empty(), "fixture preserves inventory")
	expect(Codec.state_checksum(state).length() == 64, "state checksum is SHA-256")


func _test_visual_system_contract() -> void:
	var kinds := VisualIcons.supported_kinds()
	expect(kinds.size() == 11, "visual system covers all eleven piece types")
	expect("reinforcement" in kinds and "sovereign" in kinds, "visual system includes Reinforcement and Sovereign")
	expect(VisualPalette.NEUTRAL_LIGHT_SQUARE != VisualPalette.LIGHT_SQUARE and VisualPalette.NEUTRAL_DARK_SQUARE != VisualPalette.DARK_SQUARE, "both neutral square colors use a faded brown finish")
	expect(VisualPalette.token_body("white") != VisualPalette.token_body("black"), "player token materials remain distinct")
	expect(VisualPalette.token_layer_border("white") == VisualPalette.WHITE_TOKEN_PINSTRIPE, "White tiles use a graphite painted pinstripe")
	expect(VisualPalette.token_layer_border("black") == VisualPalette.BLACK_TOKEN_PINSTRIPE, "Black tiles use a silver-gray painted pinstripe")


func _test_simulator_manual_play_and_replay() -> void:
	var replay_picker := VisualPrototype.new()
	replay_picker._build_file_dialog()
	expect(replay_picker.file_dialog.display_mode == FileDialog.DISPLAY_LIST, "replay picker defaults to filename list mode")
	expect(replay_picker.file_dialog.use_native_dialog, "replay picker uses the native detailed list with modification timestamps")
	var original_dialog = replay_picker.file_dialog
	replay_picker._build_file_dialog()
	expect(replay_picker.file_dialog == original_dialog, "replay picker reuses one connected dialog instead of rebuilding its lifecycle")
	replay_picker.free()

	var prototype := VisualPrototype.new()
	prototype._start_new_game()
	expect(prototype.game_state.is_empty(), "new manual game begins with Sovereign placement")
	expect(prototype._reference_owner() == Rules.BLACK, "reference tokens begin with Black's Sovereign choice")
	prototype._handle_play_square("B9")
	expect(prototype._reference_owner() == Rules.WHITE, "reference tokens switch to White for the mirrored response")
	prototype._handle_play_square("H1")
	expect(not prototype.game_state.is_empty(), "two Sovereign choices initialize the live game")
	expect(prototype.game_state.rules.id == "attrition-neutral-gate-opening-4-v1", "new simulator games use the current four-PLACE beta rules")
	expect(prototype._reference_owner() == Rules.WHITE, "reference tokens match White on the first normal turn")
	expect(prototype.game_state.board.has("H1") and prototype.game_state.board.has("B9"), "manual setup preserves both chosen Sovereign files")
	prototype._handle_play_square("H1")
	expect(prototype.selected_square == "H1" and not prototype.stack_inspection_expanded, "first stack click selects without opening the inspector")
	prototype._handle_play_square("H1")
	expect(prototype.selected_square == "H1" and prototype.stack_inspection_expanded and prototype.stack_inspection_target == 1.0, "second click explodes the selected stack in place")
	prototype._handle_play_square("H1")
	expect(prototype.selected_square == "H1" and not prototype.stack_inspection_expanded and prototype.stack_inspection_target == 0.0, "third click collapses the stack while preserving selection")
	for animation_case in [
		{"owner": Rules.WHITE, "source": "B2", "destination": "B3", "board": {"A1": [p(Rules.WHITE, Rules.SOVEREIGN)], "I9": [p(Rules.BLACK, Rules.SOVEREIGN)], "B2": [p(Rules.WHITE, Rules.INFANTRY)]}},
		{"owner": Rules.BLACK, "source": "H8", "destination": "H7", "board": {"A1": [p(Rules.WHITE, Rules.SOVEREIGN)], "I9": [p(Rules.BLACK, Rules.SOVEREIGN)], "H8": [p(Rules.BLACK, Rules.INFANTRY)]}},
	]:
		var animation_state := empty_state(animation_case.board, str(animation_case.owner))
		animation_state.rules = Rules.current_beta_ruleset()
		animation_state.development_placements = {Rules.WHITE: 4, Rules.BLACK: 4}
		var animation_prototype := VisualPrototype.new()
		animation_prototype.human_recording_enabled = false
		animation_prototype.game_state = animation_state.duplicate(true)
		animation_prototype.manual_initial_state = animation_state.duplicate(true)
		animation_prototype.manual_states = [animation_state.duplicate(true)]
		animation_prototype._apply_manual_action({"type": "move", "source": animation_case.source, "destination": animation_case.destination})
		expect(not animation_prototype.move_animation.is_empty() and str(animation_prototype.move_animation.owner) == str(animation_case.owner), "%s movement starts a visible stack animation" % str(animation_case.owner).capitalize())
		expect(str(animation_prototype.move_animation.source) == str(animation_case.source) and str(animation_prototype.move_animation.destination) == str(animation_case.destination), "%s movement animation retains its board-space path" % str(animation_case.owner).capitalize())
		animation_prototype._process(1.0)
		expect(animation_prototype.move_animation.is_empty(), "%s movement animation settles into the destination state" % str(animation_case.owner).capitalize())
		animation_prototype.free()
	prototype.game_state.reserves.white.infantry = 7
	prototype.game_state.reserves.black.infantry = 3
	expect(prototype._reserve_display_owner() == Rules.WHITE and prototype._reserve_count(Rules.INFANTRY) == 7, "reserve panel follows the active player by default")
	prototype._toggle_reserve_owner()
	expect(prototype._reserve_display_owner() == Rules.BLACK and prototype._reserve_count(Rules.INFANTRY) == 3, "reserve toggle displays the opponent's remaining pieces")
	prototype._select_reserve_piece(Rules.INFANTRY)
	expect(prototype.selected_piece_kind.is_empty(), "opponent reserve remains view-only")
	prototype._toggle_reserve_owner()
	prototype.game_state.reserves.white.infantry = 9
	prototype.game_state.reserves.black.infantry = 9
	prototype._select_reserve_piece(Rules.INFANTRY)
	var placement: Dictionary = {}
	for action in GameEngine.legal_actions(prototype.game_state):
		if action.type == "place" and action.piece == Rules.INFANTRY and action.get("effect_target") == null:
			placement = action
			break
	expect(not placement.is_empty(), "manual interface exposes a legal Infantry placement")
	prototype._handle_play_square(str(placement.destination))
	expect(prototype.game_state.ply == 1 and prototype.game_state.turn == Rules.BLACK, "manual board click applies the selected legal action")
	expect(prototype._reference_owner() == Rules.BLACK, "reference tokens follow the active player after an action")
	expect(prototype._reserve_pile_counts(Rules.INFANTRY, 9) == [9], "full Infantry reserve is displayed as one physical roll")
	expect(prototype._reserve_pile_counts(Rules.INFANTRY, 7) == [7], "Infantry roll dwindles continuously as pieces are spent")
	expect(prototype._reserve_pile_counts(Rules.INFANTRY, 0) == [0], "spent Infantry roll remains represented as empty")
	prototype._undo_manual_action()
	expect(prototype.game_state.ply == 0 and prototype.game_state.turn == Rules.WHITE, "manual UNDO restores the preceding state")
	expect(prototype.manual_redo_actions.size() == 1, "manual UNDO retains the action for REDO")
	prototype._redo_manual_action()
	expect(prototype.game_state.ply == 1 and prototype.game_state.turn == Rules.BLACK, "manual REDO restores the later state")
	expect(prototype.manual_actions.size() == 1 and prototype.manual_redo_actions.is_empty(), "manual REDO restores action history")
	var live_notation: Array = prototype._notation_entries()
	expect(live_notation.size() == 3, "live notation includes both Sovereign placements and the current action history")
	expect(str(live_notation[0]) == "1B P-V@B9" and str(live_notation[1]) == "1W P-V@H1", "notation preserves the actual Black-then-White Sovereign draft order")
	expect(str(live_notation[2]).begins_with("2W P-I@"), "PLACE notation uses the shared Infantry symbol and destination")
	expect(prototype._notation_copy_text().contains("Through recorded ply: 1"), "copied notation identifies the current live-game ply")
	var human_document := prototype._human_replay_document()
	expect(human_document.metadata.source == "human_hotseat", "human games identify their source for analysis")
	expect(human_document.actions.size() == 1 and human_document.metadata.plies == 1, "human game recording contains the replayable action history")
	prototype._load_replay_document(human_document)
	expect(prototype.replay_states.size() == 2 and prototype.replay_states[-1].ply == 1, "recorded human games load directly in replay review")
	expect(prototype._notation_entries().size() == 2, "replay notation at the initial position excludes future actions")
	prototype._set_replay_index(1)
	expect(prototype._notation_entries().size() == 3, "replay notation advances only through the current replay ply")
	prototype.view_mode = "play"
	prototype._undo_manual_action()
	expect(prototype.game_state.ply == 0, "manual history can still move backward after REDO")

	var fixture = Codec.load_json("res://../fixtures/development_opening.json")
	var replay_action_list: Array = []
	for step in fixture.steps:
		replay_action_list.append(step.action)
	prototype._load_replay_document({
		"game_id": "test-replay",
		"initial_state": fixture.initial_state,
		"actions": replay_action_list,
	})
	expect(prototype.replay_states.size() == replay_action_list.size() + 1, "replay review reconstructs every recorded board state")
	expect(prototype._notation_action_count() == 0, "newly loaded replay notation begins at recorded ply zero")
	prototype._set_replay_index(prototype.replay_states.size() - 1)
	expect(prototype.game_state.ply == replay_action_list.size(), "replay navigation reaches the final recorded ply")
	expect(prototype._notation_action_count() == replay_action_list.size(), "replay notation copy is bounded by the current replay position")
	prototype.free()
