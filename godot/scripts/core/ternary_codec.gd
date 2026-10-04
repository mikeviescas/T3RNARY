class_name TernaryCodec
extends RefCounted

const Rules = preload("res://scripts/core/ternary_rules.gd")


static func normalize_piece(piece: Dictionary) -> Dictionary:
	return {
		"owner": str(piece.get("owner", "")),
		"kind": str(piece.get("kind", "")),
	}


static func normalize_inventory(raw: Dictionary) -> Dictionary:
	var result := Rules.empty_inventory()
	for key in raw:
		var piece_kind := str(key)
		result[piece_kind] = int(raw[key])
	return result


static func normalize_action(action: Dictionary) -> Dictionary:
	var result := {"type": str(action.get("type", ""))}
	if result.type == "move":
		result["source"] = str(action.get("source", "")).to_upper()
		result["destination"] = str(action.get("destination", "")).to_upper()
	else:
		result["piece"] = str(action.get("piece", ""))
		result["destination"] = str(action.get("destination", "")).to_upper()
		if action.get("effect_target") != null:
			result["effect_target"] = str(action.effect_target).to_upper()
	return result


static func normalize_state(raw: Dictionary) -> Dictionary:
	var board := {}
	for square in raw.get("board", {}):
		var stack: Array = []
		for piece in raw.board[square]:
			stack.append(normalize_piece(piece))
		board[str(square).to_upper()] = stack
	var rules: Dictionary = raw.get("rules", Rules.development_ruleset()).duplicate(true)
	var state := {
		"contract_version": int(raw.get("contract_version", 0)),
		"rules": rules,
		"board": board,
		"reserves": {},
		"discards": {},
		"turn": str(raw.get("turn", Rules.WHITE)),
		"winner": raw.get("winner"),
		"is_draw": bool(raw.get("is_draw", false)),
		"ply": int(raw.get("ply", 0)),
		"development_placements": raw.get("development_placements", {
			Rules.WHITE: 0, Rules.BLACK: 0,
		}).duplicate(true),
		"height_three_unlocked": raw.get("height_three_unlocked", {
			Rules.WHITE: true, Rules.BLACK: true,
		}).duplicate(true),
	}
	for player in [Rules.WHITE, Rules.BLACK]:
		state.reserves[player] = normalize_inventory(raw.get("reserves", {}).get(player, {}))
		state.discards[player] = normalize_inventory(raw.get("discards", {}).get(player, {}))
	return state


static func action_key(action: Dictionary) -> String:
	return JSON.stringify(normalize_action(action), "", true)


static func actions_contain(actions: Array, candidate: Dictionary) -> bool:
	var candidate_key := action_key(candidate)
	for action in actions:
		if action_key(action) == candidate_key:
			return true
	return false


static func load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open JSON file: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("Invalid JSON file: %s" % path)
	return parsed


static func save_json(path: String, document: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write JSON file: %s" % path)
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document, "\t", false) + "\n")
	return OK


static func stable_state_json(state: Dictionary) -> String:
	return JSON.stringify(normalize_state(state), "", true)


static func state_checksum(state: Dictionary) -> String:
	return stable_state_json(state).sha256_text()
