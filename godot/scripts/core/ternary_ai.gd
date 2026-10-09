class_name TernaryAI
extends RefCounted

const Game = preload("res://scripts/core/ternary_engine.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")

const WIN_SCORE := 1000000000.0
const REPLY_DEPTH := 1
const REPORTED_SEARCH_PLIES := 2
const ROOT_CANDIDATES := 6
const SEARCH_CANDIDATES := 6
const ROOT_ACTIONS_EVALUATED := 36
const SEARCH_ACTIONS_EVALUATED := 24
const FORCING_EXTENSIONS := 2
const FORCING_CANDIDATES := 4
const FORCING_ACTIONS_EVALUATED := 18
const ROOT_EXPOSURE_WEIGHT := 3.0

const PIECE_VALUES := {
	Rules.SOVEREIGN: 1000.0,
	Rules.INFANTRY: 1.0,
	Rules.REINFORCEMENT: 1.25,
	Rules.DRAGOON: 3.0,
	Rules.CHARIOT: 3.0,
	Rules.GRIFFIN: 3.5,
	Rules.MARSHAL: 5.0,
	Rules.BALLISTA: 4.0,
	Rules.TREBUCHET: 4.0,
	Rules.SPY: 4.0,
	Rules.RECALL: 3.0,
}

var last_decision: Dictionary = {}


func choose_action(state: Dictionary) -> Dictionary:
	last_decision = {}
	var actions := Game.legal_actions(state)
	if actions.is_empty():
		return {}
	var player := str(state.turn)
	var wins := _winning_actions(state, actions, player)
	if not wins.is_empty():
		var winning_action: Dictionary = wins[0]
		last_decision = _decision(winning_action, "immediate victory", WIN_SCORE, wins.size())
		return last_decision
	if Game.in_development(state):
		var opening := _choose_opening_action(state, actions)
		last_decision = _decision(opening, "Infantry development", _opening_score(state, opening), actions.size())
		return last_decision

	var candidates := _candidate_actions(state, actions, ROOT_CANDIDATES, ROOT_ACTIONS_EVALUATED)
	var best_action: Dictionary = candidates[0]
	var best_score := -WIN_SCORE
	for action_value in candidates:
		var action: Dictionary = action_value
		var result := Game.apply_action(state, action, false)
		var score := _search(result, player, REPLY_DEPTH, -WIN_SCORE, WIN_SCORE, FORCING_EXTENSIONS)
		score -= ROOT_EXPOSURE_WEIGHT * _action_stack_exposure(result, player, action)
		if score > best_score or (is_equal_approx(score, best_score) and _action_key(action) < _action_key(best_action)):
			best_score = score
			best_action = action
	last_decision = _decision(best_action, _reason_for(state, best_action), best_score, candidates.size())
	return last_decision


func _search(state: Dictionary, perspective: String, depth: int, alpha_value: float, beta_value: float, extensions_left: int) -> float:
	if Game.is_over(state):
		if state.get("winner") == perspective:
			return WIN_SCORE - float(state.get("ply", 0))
		if state.get("winner") == Rules.opponent(perspective):
			return -WIN_SCORE + float(state.get("ply", 0))
		return 0.0
	var candidate_limit := SEARCH_CANDIDATES
	var evaluation_limit := SEARCH_ACTIONS_EVALUATED
	if depth <= 0:
		var player_to_move := str(state.turn)
		# A current attack on the opposing Sovereign is already a one-action win;
		# score it directly instead of expanding another full legal-action set.
		if Game.is_sovereign_threatened(state, Rules.opponent(player_to_move)):
			return (WIN_SCORE - float(state.get("ply", 0)) - 1.0) if player_to_move == perspective else (-WIN_SCORE + float(state.get("ply", 0)) + 1.0)
		if extensions_left <= 0 or not Game.is_sovereign_threatened(state, player_to_move):
			return _evaluate(state, perspective)
		depth = 1
		extensions_left -= 1
		candidate_limit = FORCING_CANDIDATES
		evaluation_limit = FORCING_ACTIONS_EVALUATED
	var actions := Game.legal_actions(state)
	if actions.is_empty():
		return _evaluate(state, perspective)
	var candidates := _candidate_actions(state, actions, candidate_limit, evaluation_limit)
	var maximizing := str(state.turn) == perspective
	var alpha := alpha_value
	var beta := beta_value
	var best := -WIN_SCORE if maximizing else WIN_SCORE
	for action_value in candidates:
		var action: Dictionary = action_value
		var result := Game.apply_action(state, action, false)
		var score := _search(result, perspective, depth - 1, alpha, beta, extensions_left)
		if maximizing:
			best = maxf(best, score)
			alpha = maxf(alpha, best)
		else:
			best = minf(best, score)
			beta = minf(beta, best)
		if beta <= alpha:
			break
	return best
func _candidate_actions(state: Dictionary, actions: Array, limit: int, evaluation_limit: int) -> Array:
	var player := str(state.turn)
	var opponent := Rules.opponent(player)
	var was_threatened := Game.is_sovereign_threatened(state, player)
	var entries: Array = []
	var safe_entries: Array = []
	var scanned_actions: Array = actions if was_threatened else _prefilter_actions(state, actions, evaluation_limit)
	for action_value in scanned_actions:
		var action: Dictionary = action_value
		var entry := _candidate_entry(state, action, player, opponent, was_threatened, was_threatened)
		if entry.is_empty():
			continue
		entries.append(entry)
		if bool(entry.safe):
			safe_entries.append(entry)
	# If every legal action leaves the Sovereign threatened, retain the best
	# practical continuations rather than returning an empty candidate set.
	if entries.is_empty() and was_threatened:
		for action_value in _prefilter_actions(state, actions, evaluation_limit):
			var action: Dictionary = action_value
			var entry := _candidate_entry(state, action, player, opponent, was_threatened, false)
			if not entry.is_empty():
				entries.append(entry)
	if not safe_entries.is_empty():
		entries = safe_entries
	entries.sort_custom(func(a, b):
		if not is_equal_approx(float(a.priority), float(b.priority)):
			return float(a.priority) > float(b.priority)
		return str(a.key) < str(b.key)
	)
	var selected: Array = []
	for entry in entries:
		if bool(entry.forcing):
			selected.append(entry.action)
			if selected.size() >= limit:
				return selected
	for entry in entries:
		if entry.action in selected:
			continue
		selected.append(entry.action)
		if selected.size() >= limit:
			break
	if selected.is_empty() and not actions.is_empty():
		selected.append(actions[0])
	return selected


func _candidate_entry(state: Dictionary, action: Dictionary, player: String, opponent: String, was_threatened: bool, reject_unsafe: bool) -> Dictionary:
	var result := Game.apply_action(state, action, false)
	if result.is_empty():
		return {}
	var safe := not Game.is_sovereign_threatened(result, player)
	if reject_unsafe and not safe:
		return {}
	var material := _material_swing(state, result, player)
	var pressures := Game.is_sovereign_threatened(result, opponent)
	var touches_three := _touches_height_three(state, action)
	var forcing: bool = result.get("winner") == player or pressures or absf(material) > 0.01 or (was_threatened and safe) or touches_three
	return {
		"action": action,
		"safe": safe,
		"forcing": forcing,
		"priority": _action_priority(state, action, result, player),
		"key": _action_key(action),
	}


func _prefilter_actions(state: Dictionary, actions: Array, limit: int) -> Array:
	if actions.size() <= limit:
		return actions
	var forcing: Array = []
	var moves: Array = []
	var placements: Array = []
	for action_value in actions:
		var action: Dictionary = action_value
		var entry := {"action": action, "priority": _static_priority(state, action), "key": _action_key(action)}
		if _is_static_forcing(state, action):
			forcing.append(entry)
		elif str(action.get("type", "")) == "move":
			moves.append(entry)
		else:
			placements.append(entry)
	for bucket in [forcing, moves, placements]:
		bucket.sort_custom(func(a, b):
			if not is_equal_approx(float(a.priority), float(b.priority)):
				return float(a.priority) > float(b.priority)
			return str(a.key) < str(b.key)
		)
	var selected: Array = []
	var selected_keys := {}
	var quota := maxi(1, floori(float(limit) / 3.0))
	for bucket in [forcing, moves, placements]:
		for index in range(mini(quota, bucket.size())):
			var entry: Dictionary = bucket[index]
			selected.append(entry.action)
			selected_keys[entry.key] = true
	var remainder: Array = []
	remainder.append_array(forcing)
	remainder.append_array(moves)
	remainder.append_array(placements)
	remainder.sort_custom(func(a, b):
		if not is_equal_approx(float(a.priority), float(b.priority)):
			return float(a.priority) > float(b.priority)
		return str(a.key) < str(b.key)
	)
	for entry in remainder:
		if selected.size() >= limit:
			break
		if not selected_keys.has(entry.key):
			selected.append(entry.action)
			selected_keys[entry.key] = true
	return selected


func _is_static_forcing(state: Dictionary, action: Dictionary) -> bool:
	if action.get("effect_target") != null:
		return true
	var destination := str(action.get("destination", ""))
	if state.board.has(destination):
		var target: Array = state.board[destination]
		if not target.is_empty() and str(target[-1].owner) != str(state.turn):
			return true
	return false


func _static_priority(state: Dictionary, action: Dictionary) -> float:
	var player := str(state.turn)
	if _captures_sovereign(state, action, player):
		return WIN_SCORE
	var score := 0.0
	var destination := str(action.get("destination", ""))
	if action.get("effect_target") != null:
		var target: Array = state.board.get(str(action.effect_target), [])
		score += 50000.0 + 1000.0 * float(target.size())
	if str(action.get("type", "")) == "move":
		score += 10000.0
		if state.board.has(destination):
			var target: Array = state.board[destination]
			score += 30000.0 + 1000.0 * float(target.size())
		var source: Array = state.board.get(str(action.get("source", "")), [])
		if source.size() == 3:
			score += 600.0
	else:
		var kind := str(action.get("piece", ""))
		if kind == Rules.SPY and state.board.has(destination):
			score += 45000.0
		elif kind == Rules.INFANTRY:
			score += 2500.0
		if state.board.has(destination):
			var existing: Array = state.board[destination]
			score += 1200.0 * float(existing.size())
			if not existing.is_empty() and str(existing[-1].kind) in [Rules.MARSHAL, Rules.GRIFFIN, Rules.DRAGOON, Rules.CHARIOT]:
				score -= 2500.0
	score -= 6000.0 * _static_destination_exposure(state, action, player)
	return score


func _static_destination_exposure(state: Dictionary, action: Dictionary, player: String) -> float:
	var destination := str(action.get("destination", ""))
	if destination.is_empty():
		return 0.0
	var future_value := 0.0
	if str(action.get("type", "")) == "move":
		future_value = _stack_value(state.board.get(str(action.get("source", "")), []))
	else:
		future_value = _stack_value(state.board.get(destination, [])) + _piece_value(str(action.get("piece", "")))
	if future_value <= 0.0:
		return 0.0
	for source_value in state.board:
		var source := str(source_value)
		var attacker: Array = state.board[source]
		if not attacker.is_empty() and str(attacker[-1].owner) == Rules.opponent(player) and Game.stack_controls_square(state, source, destination):
			return future_value
	return 0.0


func _winning_actions(state: Dictionary, actions: Array, player: String) -> Array:
	var wins: Array = []
	for action_value in actions:
		var action: Dictionary = action_value
		if _captures_sovereign(state, action, player) or _is_conquer_move(state, action, player):
			wins.append(action)
	wins.sort_custom(func(a, b):
		var a_capture := _captures_sovereign(state, a, player)
		var b_capture := _captures_sovereign(state, b, player)
		if a_capture != b_capture:
			return a_capture
		return _action_key(a) < _action_key(b)
	)
	return wins


func _is_conquer_move(state: Dictionary, action: Dictionary, player: String) -> bool:
	if not state.rules.get("infiltration_victory", false) or str(action.get("type", "")) != "move":
		return false
	var source := str(action.get("source", ""))
	if not state.board.has(source) or str(state.board[source][-1].kind) != Rules.SOVEREIGN:
		return false
	var rank := Rules.square_to_xy(str(action.get("destination", ""))).y
	return rank == (Rules.board_size() - 1 if player == Rules.WHITE else 0)


func _captures_sovereign(state: Dictionary, action: Dictionary, player: String) -> bool:
	if str(action.get("type", "")) != "move":
		return false
	var destination := str(action.get("destination", ""))
	if not state.board.has(destination):
		return false
	var target: Array = state.board[destination]
	return not target.is_empty() and str(target[-1].owner) == Rules.opponent(player) and str(target[-1].kind) == Rules.SOVEREIGN


func _choose_opening_action(state: Dictionary, actions: Array) -> Dictionary:
	var ranked: Array = actions.duplicate()
	ranked.sort_custom(func(a, b):
		var score_a := _opening_score(state, a)
		var score_b := _opening_score(state, b)
		if not is_equal_approx(score_a, score_b):
			return score_a > score_b
		return _action_key(a) < _action_key(b)
	)
	return ranked[0]


func _opening_score(state: Dictionary, action: Dictionary) -> float:
	var score := 0.0
	var kind := str(action.get("piece", ""))
	if kind == Rules.INFANTRY:
		score += 10000.0
	elif kind in [Rules.DRAGOON, Rules.CHARIOT, Rules.GRIFFIN]:
		score += 500.0
	else:
		score -= 500.0
	var destination := str(action.get("destination", ""))
	var existing: Array = state.board.get(destination, [])
	if kind == Rules.INFANTRY and existing.size() == 1 and str(existing[-1].kind) == Rules.INFANTRY:
		score += 900.0
	elif existing.is_empty():
		var rank := Rules.square_to_xy(destination).y
		var front_rank := Rules.home_ranks() - 1 if state.turn == Rules.WHITE else Rules.board_size() - Rules.home_ranks()
		score += 220.0 - 30.0 * absf(float(rank - front_rank))
	var sovereign := Game.sovereign_square(state, str(state.turn))
	if not sovereign.is_empty():
		var delta: Vector2i = Rules.square_to_xy(destination) - Rules.square_to_xy(sovereign)
		var distance: int = abs(delta.x) + abs(delta.y)
		score += 70.0 - 8.0 * float(abs(distance - 3))
	return score


func _action_priority(state: Dictionary, action: Dictionary, result: Dictionary, player: String) -> float:
	if result.get("winner") == player:
		return WIN_SCORE
	var opponent := Rules.opponent(player)
	var score := 120.0 * _material_swing(state, result, player)
	if Game.is_sovereign_threatened(result, opponent):
		score += 9000.0
		var pressure_sources := Game.sovereign_attack_sources(result, player)
		score += 900.0 * float(maxi(0, pressure_sources.size() - 1))
		for source_value in pressure_sources:
			if Game.is_square_protected(result, player, str(source_value), str(source_value)):
				score += 500.0
	if Game.is_sovereign_threatened(state, player) and not Game.is_sovereign_threatened(result, player):
		score += 12000.0
	if _touches_height_three(state, action):
		score += 700.0
	var action_type := str(action.get("type", ""))
	if action.get("effect_target") != null:
		score += 500.0
	if action_type == "move":
		var source := str(action.get("source", ""))
		var moving: Array = state.board.get(source, [])
		if not moving.is_empty() and str(moving[-1].kind) == Rules.SOVEREIGN:
			score -= 30.0
	else:
		var kind := str(action.get("piece", ""))
		var destination := str(action.get("destination", ""))
		var existing: Array = state.board.get(destination, [])
		if kind == Rules.INFANTRY:
			score += 45.0
		if not existing.is_empty():
			var buried_kind := str(existing[-1].kind)
			if buried_kind in [Rules.MARSHAL, Rules.GRIFFIN, Rules.DRAGOON, Rules.CHARIOT]:
				score -= 180.0 * _piece_value(buried_kind)
	score -= 500.0 * _action_stack_exposure(result, player, action)
	return score + 0.01 * _evaluate(result, player)


func _action_stack_exposure(result: Dictionary, player: String, action: Dictionary) -> float:
	var resulting_square := str(action.get("destination", ""))
	if not result.board.has(resulting_square) or str(result.board[resulting_square][-1].owner) != player:
		return 0.0
	return _stack_exposure_at(result, player, resulting_square)


func _evaluate(state: Dictionary, perspective: String) -> float:
	if Game.is_over(state):
		if state.get("winner") == perspective:
			return WIN_SCORE - float(state.get("ply", 0))
		if state.get("winner") == Rules.opponent(perspective):
			return -WIN_SCORE + float(state.get("ply", 0))
		return 0.0
	var score := 0.0
	for player in [Rules.WHITE, Rules.BLACK]:
		var sign := 1.0 if player == perspective else -1.0
		for kind in Rules.piece_types():
			score += sign * 0.90 * _piece_value(str(kind)) * float(state.reserves[player].get(kind, 0))
		for square_value in state.board:
			var stack: Array = state.board[square_value]
			if stack.is_empty() or str(stack[-1].owner) != player:
				continue
			for index in range(stack.size()):
				var kind := str(stack[index].kind)
				var agency := 1.0 if index == stack.size() - 1 else 0.72
				score += sign * agency * _piece_value(kind)
				if index < stack.size() - 1 and kind in [Rules.MARSHAL, Rules.GRIFFIN, Rules.DRAGOON, Rules.CHARIOT]:
					score -= sign * 0.35 * _piece_value(kind)
			var top_kind := str(stack[-1].kind)
			if top_kind not in [Rules.SOVEREIGN, Rules.SPY, Rules.BALLISTA, Rules.TREBUCHET, Rules.REINFORCEMENT]:
				score += sign * float(stack.size() - 1) * (1.4 if stack.size() < 3 else 2.3)
	var enemy := Rules.opponent(perspective)
	if Game.is_sovereign_threatened(state, perspective):
		score -= 1800.0
	if Game.is_sovereign_threatened(state, enemy):
		var sources := Game.sovereign_attack_sources(state, perspective)
		score += 850.0 + 300.0 * float(maxi(0, sources.size() - 1))
		for source_value in sources:
			if Game.is_square_protected(state, perspective, str(source_value), str(source_value)):
				score += 350.0
	var own_sovereign := Game.sovereign_square(state, perspective)
	var enemy_sovereign := Game.sovereign_square(state, enemy)
	if not own_sovereign.is_empty():
		var own_rank := Rules.square_to_xy(own_sovereign).y
		score += 2.0 * float(own_rank if perspective == Rules.WHITE else 8 - own_rank)
	if not enemy_sovereign.is_empty():
		var enemy_rank := Rules.square_to_xy(enemy_sovereign).y
		score -= 2.0 * float(enemy_rank if enemy == Rules.WHITE else 8 - enemy_rank)
	return score


func _exposure_pressure(state: Dictionary, victim: String) -> float:
	var total := 0.0
	var largest := 0.0
	for target_value in state.board:
		var target := str(target_value)
		var stack: Array = state.board[target]
		if stack.is_empty() or str(stack[-1].owner) != victim or str(stack[-1].kind) == Rules.SOVEREIGN:
			continue
		var exposure := _stack_exposure_at(state, victim, target)
		if exposure > 0.0:
			total += exposure
			largest = maxf(largest, exposure)
	return largest + 0.35 * maxf(0.0, total - largest)


func _stack_exposure_at(state: Dictionary, victim: String, target: String) -> float:
	var defenders: Array = state.board.get(target, [])
	if defenders.is_empty():
		return 0.0
	var best := 0.0
	var protected := Game.is_square_protected(state, victim, target, target)
	for source_value in state.board:
		var source := str(source_value)
		var attackers: Array = state.board[source]
		if attackers.is_empty() or str(attackers[-1].owner) != Rules.opponent(victim):
			continue
		if not Game.stack_controls_square(state, source, target):
			continue
		var attacker_kind := str(attackers[-1].kind)
		if attacker_kind == Rules.SOVEREIGN and protected:
			continue
		var exposure := 0.0
		if attacker_kind == Rules.SOVEREIGN or attackers.size() >= defenders.size():
			exposure = _stack_value(defenders)
			if protected:
				exposure = maxf(exposure * 0.22, exposure - 0.70 * _stack_value(attackers))
		elif state.rules.get("move_vs_taller", "illegal") == "mutual_bottom_attrition":
			var removed: Array = defenders.slice(0, attackers.size())
			exposure = maxf(0.0, _stack_value(removed) - 0.65 * _stack_value(attackers))
		best = maxf(best, exposure)
	return best


func _stack_value(stack: Array) -> float:
	var value := 0.0
	for piece in stack:
		value += _piece_value(str(piece.kind))
	return value


func _material_swing(before: Dictionary, after: Dictionary, player: String) -> float:
	var opponent := Rules.opponent(player)
	return _discard_gain(before, after, opponent) - _discard_gain(before, after, player)


func _discard_gain(before: Dictionary, after: Dictionary, owner: String) -> float:
	var value := 0.0
	for kind in Rules.piece_types():
		var delta := int(after.discards[owner].get(kind, 0)) - int(before.discards[owner].get(kind, 0))
		if delta > 0:
			value += float(delta) * _piece_value(str(kind))
	return value


func _touches_height_three(state: Dictionary, action: Dictionary) -> bool:
	for key in ["source", "destination", "effect_target"]:
		var square := str(action.get(key, ""))
		if not square.is_empty() and state.board.has(square) and state.board[square].size() == 3:
			return true
	return false


func _piece_value(kind: String) -> float:
	return float(PIECE_VALUES.get(kind, 0.0))


func _action_key(action: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [
		str(action.get("type", "")), str(action.get("piece", "")),
		str(action.get("source", "")), str(action.get("destination", "")),
		str(action.get("effect_target", "")),
	]


func _reason_for(state: Dictionary, action: Dictionary) -> String:
	var result := Game.apply_action(state, action, false)
	var player := str(state.turn)
	if result.get("winner") == player:
		return "immediate victory"
	if Game.is_sovereign_threatened(state, player) and not Game.is_sovereign_threatened(result, player):
		return "Sovereign defense"
	if action.get("effect_target") != null:
		var target: Array = state.board.get(str(action.effect_target), [])
		if target.size() == 3:
			return "artillery attrition against a 3 Stack"
		return "artillery attack"
	if _material_swing(state, result, player) > 0.0:
		return "favorable material exchange"
	if Game.is_sovereign_threatened(result, Rules.opponent(player)):
		return "Sovereign pressure"
	if _touches_height_three(state, action):
		return "3-Stack response"
	return "positional development"


func _decision(action: Dictionary, reason: String, score: float, considered: int) -> Dictionary:
	return {
		"action": action.duplicate(true),
		"reason": reason,
		"score": score,
		"candidates_considered": considered,
		"search_depth": REPORTED_SEARCH_PLIES,
	}
