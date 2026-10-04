extends SceneTree

const Rules = preload("res://scripts/core/ternary_rules.gd")
const Codec = preload("res://scripts/core/ternary_codec.gd")
const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const VisualIcons = preload("res://scripts/presentation/piece_icon_renderer.gd")
const VisualPalette = preload("res://scripts/presentation/ternary_palette.gd")
const VisualPrototype = preload("res://scripts/presentation/visual_prototype.gd")

var failures := 0
var checks := 0


func _init() -> void:
	_test_initial_development_state()
	_test_shared_rule_configuration()
	_test_development_sequence_and_height_unlock()
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
	_test_golden_fixture()
	_test_visual_system_contract()
	_test_visual_prototype_uses_live_move_rules()
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
	expect(VisualPalette.BLACK_TERRITORY != VisualPalette.NEUTRAL_TERRITORY and VisualPalette.NEUTRAL_TERRITORY != VisualPalette.WHITE_TERRITORY, "three territories have distinct material colors")
	expect(VisualPalette.token_body("white") != VisualPalette.token_body("black"), "player token materials remain distinct")


func _test_visual_prototype_uses_live_move_rules() -> void:
	var prototype := VisualPrototype.new()
	prototype._build_sample_position()
	var marshal_markers: Dictionary = prototype.legal_move_markers("E5")
	expect(not marshal_markers.is_empty(), "selected Marshal stack receives generated move markers")
	expect(marshal_markers.get("E8") == "capture", "occupied legal destination receives capture marker")
	expect(not marshal_markers.has("C6"), "prototype no longer displays hardcoded illegal capture")
	var chariot_markers: Dictionary = prototype.legal_move_markers("B4")
	expect(not chariot_markers.is_empty(), "markers update for another selected mobile stack")
	var spy_markers: Dictionary = prototype.legal_move_markers("H4")
	expect(spy_markers.is_empty(), "Spy Stack correctly receives no move markers")
	var height_two_griffin: Dictionary = prototype.legal_move_markers("D7")
	expect(height_two_griffin.has("C5") and height_two_griffin.has("B6"), "height-two Griffin receives 1x2 and 2x1 moves")
	expect(not height_two_griffin.has("B4") and not height_two_griffin.has("G5"), "height-two Griffin does not receive 2x3 or 3x2 moves")
	var height_three_griffin: Dictionary = prototype.legal_move_markers("C6")
	expect(height_three_griffin.has("A3") and height_three_griffin.has("E9"), "height-three Griffin receives 2x3 and 3x2 moves")
	expect(height_three_griffin.has("B4") and height_three_griffin.has("D4"), "height-three Griffin retains 1x2 and 2x1 moves")
	expect(not height_three_griffin.has("G3") and not height_three_griffin.has("F2"), "height-three Griffin does not receive obsolete 3x4 or 4x3 moves")
	prototype.free()


func _test_simulator_manual_play_and_replay() -> void:
	var prototype := VisualPrototype.new()
	prototype._start_new_game()
	expect(prototype.game_state.is_empty(), "new manual game begins with Sovereign placement")
	expect(prototype._reference_owner() == Rules.WHITE, "reference tokens begin with the White setup player")
	prototype._handle_play_square("B1")
	expect(prototype._reference_owner() == Rules.BLACK, "reference tokens switch to Black for Black Sovereign placement")
	prototype._handle_play_square("H9")
	expect(not prototype.game_state.is_empty(), "two Sovereign choices initialize the live game")
	expect(prototype._reference_owner() == Rules.WHITE, "reference tokens match White on the first normal turn")
	expect(prototype.game_state.board.has("B1") and prototype.game_state.board.has("H9"), "manual setup preserves both chosen Sovereign files")
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
	expect(prototype._reserve_pile_counts(Rules.INFANTRY, 9) == [5, 4], "full Infantry reserve is displayed as five- and four-piece piles")
	expect(prototype._reserve_pile_counts(Rules.INFANTRY, 7) == [5, 2], "Infantry four-pile dwindles before the five-pile")
	expect(prototype._reserve_pile_counts(Rules.INFANTRY, 3) == [3, 0], "empty Infantry pile remains represented after its pieces are spent")
	prototype._undo_manual_action()
	expect(prototype.game_state.ply == 0 and prototype.game_state.turn == Rules.WHITE, "manual UNDO restores the preceding state")
	expect(prototype.manual_redo_actions.size() == 1, "manual UNDO retains the action for REDO")
	prototype._redo_manual_action()
	expect(prototype.game_state.ply == 1 and prototype.game_state.turn == Rules.BLACK, "manual REDO restores the later state")
	expect(prototype.manual_actions.size() == 1 and prototype.manual_redo_actions.is_empty(), "manual REDO restores action history")
	var human_document := prototype._human_replay_document()
	expect(human_document.metadata.source == "human_hotseat", "human games identify their source for analysis")
	expect(human_document.actions.size() == 1 and human_document.metadata.plies == 1, "human game recording contains the replayable action history")
	prototype._load_replay_document(human_document)
	expect(prototype.replay_states.size() == 2 and prototype.replay_states[-1].ply == 1, "recorded human games load directly in replay review")
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
	prototype._set_replay_index(prototype.replay_states.size() - 1)
	expect(prototype.game_state.ply == replay_action_list.size(), "replay navigation reaches the final recorded ply")
	prototype.free()
