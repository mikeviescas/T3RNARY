class_name TernaryEngine
extends RefCounted

const Rules = preload("res://scripts/core/ternary_rules.gd")
const Codec = preload("res://scripts/core/ternary_codec.gd")


static func initial_state(rules: Dictionary = {}, sovereign_files := Vector2i(4, 4)) -> Dictionary:
	if rules.is_empty():
		rules = Rules.development_ruleset()
	if sovereign_files.x < 0 or sovereign_files.x >= Rules.board_size() or sovereign_files.y < 0 or sovereign_files.y >= Rules.board_size():
		push_error("Sovereign files must be between 0 and 8")
		return {}
	var state := {
		"contract_version": Rules.CONTRACT_VERSION,
		"rules": rules.duplicate(true),
		"board": {},
		"reserves": {
			Rules.WHITE: Rules.starting_inventory(),
			Rules.BLACK: Rules.starting_inventory(),
		},
		"discards": {
			Rules.WHITE: Rules.empty_inventory(),
			Rules.BLACK: Rules.empty_inventory(),
		},
		"turn": Rules.WHITE,
		"winner": null,
		"is_draw": false,
		"ply": 0,
		"development_placements": {Rules.WHITE: 0, Rules.BLACK: 0},
		"height_three_unlocked": {Rules.WHITE: true, Rules.BLACK: true},
	}
	if rules.get("development_opening", false):
		_add_setup_piece(state, Rules.WHITE, Rules.SOVEREIGN, Rules.square(sovereign_files.x, 0))
		_add_setup_piece(state, Rules.BLACK, Rules.SOVEREIGN, Rules.square(sovereign_files.y, 8))
		var initially_unlocked: bool = not bool(rules.get("height_three_requires_nonsovereign_move", false))
		state.height_three_unlocked = {Rules.WHITE: initially_unlocked, Rules.BLACK: initially_unlocked}
	else:
		for entry in [[Rules.WHITE, Rules.SOVEREIGN, "E1"], [Rules.WHITE, Rules.INFANTRY, "D2"], [Rules.WHITE, Rules.INFANTRY, "E2"], [Rules.WHITE, Rules.INFANTRY, "F2"], [Rules.BLACK, Rules.SOVEREIGN, "E9"], [Rules.BLACK, Rules.INFANTRY, "D8"], [Rules.BLACK, Rules.INFANTRY, "E8"], [Rules.BLACK, Rules.INFANTRY, "F8"]]:
			_add_setup_piece(state, entry[0], entry[1], entry[2])
	return state


static func _add_setup_piece(state: Dictionary, player: String, kind: String, destination: String) -> void:
	state.board[destination] = [_piece(player, kind)]
	state.reserves[player][kind] -= 1


static func _piece(owner: String, kind: String) -> Dictionary:
	return {"owner": owner, "kind": kind}


static func is_over(state: Dictionary) -> bool:
	return state.get("winner") != null or state.get("is_draw", false)


static func in_development(state: Dictionary) -> bool:
	if not state.rules.get("development_opening", false):
		return false
	var required := int(state.rules.get("development_placements_per_player", 4))
	return int(state.development_placements[Rules.WHITE]) < required or int(state.development_placements[Rules.BLACK]) < required


static func legal_actions(state: Dictionary) -> Array:
	if is_over(state):
		return []
	var actions: Array = []
	var player: String = state.turn
	if not in_development(state):
		for source in state.board:
			var stack: Array = state.board[source]
			if stack[-1].owner == player:
				for destination in _movement_destinations(state, source):
					actions.append({"type": "move", "source": source, "destination": destination})
	for kind in Rules.piece_types():
		if int(state.reserves[player].get(kind, 0)) <= 0:
			continue
		if in_development(state) and state.rules.get("development_specials_prohibited", true) and kind in [Rules.SPY, Rules.BALLISTA, Rules.TREBUCHET, Rules.RECALL]:
			continue
		if kind == Rules.RECALL:
			_append_recall_actions(state, player, actions)
			continue
		for destination in _placement_destinations(state, player, kind, false):
			if _resulting_height(state, player, kind, destination) == Rules.max_stack_height() and not state.height_three_unlocked[player]:
				continue
			_append_placed_piece_actions(state, player, kind, destination, false, actions)
	return actions


static func _append_recall_actions(state: Dictionary, player: String, actions: Array) -> void:
	for kind in Rules.piece_types():
		if int(state.discards[player].get(kind, 0)) <= 0 or kind in Rules.special_rules("recall").forbidden_piece_kinds:
			continue
		for destination in _placement_destinations(state, player, kind, true):
			if _resulting_height(state, player, kind, destination) == Rules.max_stack_height() and not state.height_three_unlocked[player]:
				continue
			_append_placed_piece_actions(state, player, kind, destination, true, actions)


static func _movement_destinations(state: Dictionary, source: String) -> Array:
	var stack: Array = state.board[source]
	var top: Dictionary = stack[-1]
	var kind: String = top.kind
	var player: String = top.owner
	var height := stack.size()
	var movement: Dictionary = Rules.piece_definition(kind).movement
	if movement.mode == "immobile":
		return []
	var origin := Rules.square_to_xy(source)
	if movement.mode == "leap":
		var dimensions: Array = movement.vectors_by_height[str(height)]
		var griffin_moves: Array = []
		for dimension in dimensions:
			for sx in [-1, 1]:
				for sy in [-1, 1]:
					var target: Vector2i = origin + Vector2i(int(dimension[0]) * sx, int(dimension[1]) * sy)
					if Rules.on_board(target) and _can_land(state, player, kind, height, target):
						griffin_moves.append(Rules.square(target.x, target.y))
		return griffin_moves
	var directions := _directions(str(movement.direction_mode), player)
	var max_range := _movement_range(str(movement.range_mode), height)
	var moves: Array = []
	for direction in directions:
		for destination in _ray(state, origin, direction, max_range):
			var target_stack = state.board.get(destination)
			if target_stack == null:
				moves.append(destination)
			elif target_stack[-1].owner == Rules.opponent(player) and _can_attack_stack(state, kind, height, target_stack):
				moves.append(destination)
	return moves


static func _ray(state: Dictionary, origin: Vector2i, direction: Vector2i, max_range: int) -> Array:
	var result: Array = []
	for distance in range(1, max_range + 1):
		var target := origin + direction * distance
		if not Rules.on_board(target):
			break
		var destination := Rules.square(target.x, target.y)
		result.append(destination)
		if state.board.has(destination):
			break
	return result


static func _can_land(state: Dictionary, player: String, kind: String, height: int, target: Vector2i) -> bool:
	var stack = state.board.get(Rules.square(target.x, target.y))
	return stack == null or (stack[-1].owner == Rules.opponent(player) and _can_attack_stack(state, kind, height, stack))


static func _directions(direction_mode: String, player: String) -> Array:
	match direction_mode:
		"forward":
			return [Vector2i(0, Rules.forward(player))]
		"diagonal":
			return [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
		"orthogonal":
			return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		"omnidirectional":
			var result: Array = []
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if dx != 0 or dy != 0:
						result.append(Vector2i(dx, dy))
			return result
	push_error("Unsupported direction mode: %s" % direction_mode)
	return []


static func _movement_range(range_mode: String, height: int) -> int:
	match range_mode:
		"one":
			return 1
		"stack_height":
			return height
		"height_table":
			return Rules.range_for_height(height)
	push_error("Unsupported range mode: %s" % range_mode)
	return 0


static func _can_resolve_against_height(attacker: int, defender: int, mode: String) -> bool:
	if attacker >= defender:
		return true
	if mode == "illegal":
		return false
	if mode in ["mutual_bottom_attrition", "target_bottom_attrition"]:
		return true
	push_error("Unsupported combat mode: %s" % mode)
	return false


static func _can_attack_stack(state: Dictionary, kind: String, attacker_height: int, defender: Array) -> bool:
	if kind == Rules.SOVEREIGN and bool(Rules.special_rules("sovereign").get("royal_attack", false)):
		return true
	return _can_resolve_against_height(attacker_height, defender.size(), str(state.rules.get("move_vs_taller", "illegal")))


static func _placement_destinations(state: Dictionary, player: String, kind: String, recalled: bool) -> Array:
	var result: Array = []
	var development := in_development(state)
	if kind == Rules.REINFORCEMENT:
		for destination in state.board:
			var stack: Array = state.board[destination]
			if stack[-1].owner == player and stack.size() < Rules.max_stack_height() and stack[-1].kind != Rules.SOVEREIGN and (not development or _in_home(player, Rules.square_to_xy(destination).y)):
				result.append(destination)
		return result
	for rank in range(Rules.board_size()):
		var allowed := _in_home(player, rank) if development and state.rules.get("development_home_only", true) else _open_place_allowed(player, rank)
		if not allowed:
			continue
		for file in range(Rules.board_size()):
			var destination := Rules.square(file, rank)
			if not state.board.has(destination):
				result.append(destination)
	if kind != Rules.SOVEREIGN:
		for destination in state.board:
			var stack: Array = state.board[destination]
			if stack[-1].owner == player and stack[-1].kind != Rules.SOVEREIGN and stack.size() < Rules.max_stack_height() and (not development or _in_home(player, Rules.square_to_xy(destination).y)):
				result.append(destination)
	if kind == Rules.SPY:
		for destination in state.board:
			var stack: Array = state.board[destination]
			if stack[-1].owner == Rules.opponent(player) and _spy_can_convert(state, player, stack, not recalled):
				result.append(destination)
	return result


static func _open_place_allowed(player: String, rank: int) -> bool:
	return rank < Rules.home_ranks() + Rules.neutral_ranks() if player == Rules.WHITE else rank >= Rules.home_ranks()


static func _in_home(player: String, rank: int) -> bool:
	return rank < Rules.home_ranks() if player == Rules.WHITE else rank >= Rules.board_size() - Rules.home_ranks()


static func _spy_can_convert(state: Dictionary, player: String, target: Array, placing_spy_from_reserve: bool) -> bool:
	var spy_rules := Rules.special_rules("spy")
	if target.size() > int(spy_rules.maximum_target_height) or target[-1].kind in spy_rules.forbidden_top_piece_targets:
		return false
	var required := {}
	for piece in target:
		required[piece.kind] = int(required.get(piece.kind, 0)) + 1
	if placing_spy_from_reserve:
		required[Rules.SPY] = int(required.get(Rules.SPY, 0)) + 1
	for kind in required:
		if int(state.reserves[player].get(kind, 0)) < int(required[kind]):
			return false
	return true


static func _resulting_height(state: Dictionary, player: String, kind: String, destination: String) -> int:
	var existing = state.board.get(destination)
	if existing == null:
		return 1
	if kind == Rules.SPY and existing[-1].owner == Rules.opponent(player):
		return existing.size() + 1
	return existing.size() + 1


static func _append_placed_piece_actions(state: Dictionary, player: String, kind: String, destination: String, recalled: bool, actions: Array) -> void:
	var action_type := "recall" if recalled else "place"
	var base := {"type": action_type, "piece": kind, "destination": destination}
	actions.append(base)
	if Rules.piece_definition(kind).artillery == null:
		return
	var placed := state.duplicate(true)
	_apply_basic_placement(placed, player, kind, destination, null)
	var height: int = placed.board[destination].size()
	for target in _artillery_targets(placed, player, kind, destination, height):
		var firing := base.duplicate(true)
		firing["effect_target"] = target
		actions.append(firing)


static func _artillery_targets(state: Dictionary, player: String, kind: String, source: String, height: int) -> Array:
	var artillery: Dictionary = Rules.piece_definition(kind).artillery
	var directions: Array
	if artillery.direction_mode == "forward_and_sideways":
		directions = [Vector2i(0, Rules.forward(player)), Vector2i(-1, 0), Vector2i(1, 0)]
	else:
		directions = [Vector2i(-1, Rules.forward(player)), Vector2i(1, Rules.forward(player))]
	var targets: Array = []
	var origin := Rules.square_to_xy(source)
	for direction in directions:
		for destination in _ray(state, origin, direction, Rules.range_for_height(height)):
			var target = state.board.get(destination)
			if target != null and target[-1].owner == Rules.opponent(player) and _can_resolve_against_height(height, target.size(), str(state.rules.get("artillery_vs_taller", "illegal"))) and (bool(artillery.sovereign_target) or target[-1].kind != Rules.SOVEREIGN):
				targets.append(destination)
	return targets


static func apply_action(state: Dictionary, raw_action: Dictionary, adjudicate_draw := true) -> Dictionary:
	var action := Codec.normalize_action(raw_action)
	if is_over(state):
		push_error("The game is already over")
		return {}
	if not Codec.actions_contain(legal_actions(state), action):
		push_error("Illegal action: %s" % JSON.stringify(action))
		return {}
	var result := state.duplicate(true)
	var player: String = state.turn
	var was_development := in_development(state)
	match action.type:
		"move":
			var moving: Array = result.board[action.source]
			result.board.erase(action.source)
			if result.board.has(action.destination):
				var captured: Array = result.board[action.destination]
				if moving[-1].kind != Rules.SOVEREIGN and moving.size() < captured.size() and state.rules.get("move_vs_taller", "illegal") == "mutual_bottom_attrition":
					var removed_defenders: Array = captured.slice(0, moving.size())
					result.board[action.destination] = captured.slice(moving.size())
					_discard_stack(result, moving)
					_discard_stack(result, removed_defenders)
				else:
					result.board.erase(action.destination)
					_discard_stack(result, captured)
					for piece in captured:
						if piece.kind == Rules.SOVEREIGN:
							result.winner = player
					result.board[action.destination] = moving
			else:
				result.board[action.destination] = moving
			if moving[-1].kind != Rules.SOVEREIGN:
				result.height_three_unlocked[player] = true
			elif state.rules.get("infiltration_victory", false):
				var destination_rank := Rules.square_to_xy(action.destination).y
				if destination_rank == (Rules.board_size() - 1 if player == Rules.WHITE else 0):
					result.winner = player
		"recall":
			result.reserves[player][Rules.RECALL] -= 1
			result.discards[player][Rules.RECALL] += 1
			result.discards[player][action.piece] -= 1
			_apply_basic_placement(result, player, action.piece, action.destination, action.get("effect_target"))
		"place":
			result.reserves[player][action.piece] -= 1
			_apply_basic_placement(result, player, action.piece, action.destination, action.get("effect_target"))
	if was_development:
		result.development_placements[player] += 1
	result.ply += 1
	if result.winner == null:
		result.turn = Rules.opponent(player)
		if adjudicate_draw and legal_actions(result).is_empty():
			result.is_draw = true
	return result


static func _apply_basic_placement(state: Dictionary, player: String, kind: String, destination: String, effect_target: Variant) -> void:
	var existing = state.board.get(destination)
	if kind == Rules.REINFORCEMENT:
		var reinforced: Array = [_piece(player, kind)]
		reinforced.append_array(existing)
		state.board[destination] = reinforced
	elif kind == Rules.SPY and existing != null and existing[-1].owner == Rules.opponent(player):
		_discard_stack(state, existing)
		var replacements: Array = []
		for old_piece in existing:
			state.reserves[player][old_piece.kind] -= 1
			replacements.append(_piece(player, old_piece.kind))
		replacements.append(_piece(player, kind))
		state.board[destination] = replacements
	elif existing != null:
		existing.append(_piece(player, kind))
		state.board[destination] = existing
	else:
		state.board[destination] = [_piece(player, kind)]
	if effect_target != null:
		var target: Array = state.board[effect_target]
		var firing_height: int = state.board[destination].size()
		if firing_height < target.size() and state.rules.get("artillery_vs_taller", "illegal") == "target_bottom_attrition":
			var removed: Array = target.slice(0, firing_height)
			state.board[effect_target] = target.slice(firing_height)
			_discard_stack(state, removed)
		else:
			state.board.erase(effect_target)
			_discard_stack(state, target)


static func _discard_stack(state: Dictionary, stack: Array) -> void:
	for piece in stack:
		state.discards[piece.owner][piece.kind] += 1


static func is_sovereign_threatened(state: Dictionary, player: String) -> bool:
	var sovereign_square := ""
	for destination in state.board:
		var stack: Array = state.board[destination]
		if stack[-1].owner == player and stack[-1].kind == Rules.SOVEREIGN:
			sovereign_square = destination
			break
	if sovereign_square.is_empty():
		return false
	for source in state.board:
		var stack: Array = state.board[source]
		if stack[-1].owner == Rules.opponent(player) and sovereign_square in _movement_destinations(state, source):
			return true
	return false


static func validate_state(state: Dictionary, enforce_inventory := false) -> Array:
	var errors: Array = []
	if int(state.get("contract_version", 0)) != Rules.CONTRACT_VERSION:
		errors.append("Unsupported contract version")
	for destination in state.board:
		var position := Rules.square_to_xy(destination)
		var stack: Array = state.board[destination]
		if not Rules.on_board(position):
			errors.append("Off-board square: %s" % destination)
		if stack.size() < 1 or stack.size() > Rules.max_stack_height():
			errors.append("Invalid stack height at %s" % destination)
		var owner = stack[0].owner if not stack.is_empty() else ""
		for piece in stack:
			if piece.owner != owner:
				errors.append("Mixed ownership at %s" % destination)
			if piece.kind not in Rules.piece_types():
				errors.append("Unknown piece kind at %s: %s" % [destination, piece.kind])
			if piece.kind == Rules.SOVEREIGN and stack.size() != 1:
				errors.append("Stacked Sovereign at %s" % destination)
			if piece.kind == Rules.RECALL:
				errors.append("Recall may not remain on board at %s" % destination)
		if not stack.is_empty() and stack[-1].kind == Rules.REINFORCEMENT:
			errors.append("Reinforcement may not be the TOP piece at %s" % destination)
	for player in [Rules.WHITE, Rules.BLACK]:
		for inventory_name in ["reserves", "discards"]:
			for kind in state[inventory_name][player]:
				if kind not in Rules.piece_types():
					errors.append("Unknown %s piece kind for %s: %s" % [inventory_name, player, kind])
			for kind in Rules.piece_types():
				if int(state[inventory_name][player].get(kind, 0)) < 0:
					errors.append("Negative %s count for %s" % [kind, player])
		if enforce_inventory:
			var actual := Rules.empty_inventory()
			for kind in Rules.piece_types():
				actual[kind] = int(state.reserves[player].get(kind, 0)) + int(state.discards[player].get(kind, 0))
			for destination in state.board:
				for piece in state.board[destination]:
					if piece.owner == player:
						actual[piece.kind] += 1
			for kind in Rules.piece_types():
				if actual[kind] != Rules.starting_inventory()[kind]:
					errors.append("Piece inventory mismatch for %s %s: %s" % [player, kind, actual[kind]])
	return errors
