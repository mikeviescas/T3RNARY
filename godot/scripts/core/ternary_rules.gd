class_name TernaryRules
extends RefCounted

const CONTRACT_VERSION := 2
const CATALOG_PATH := "res://data/rules/pieces.json"
const RULESETS_PATH := "res://data/rules/rulesets.json"

const WHITE := "white"
const BLACK := "black"

const SOVEREIGN := "sovereign"
const SPY := "spy"
const BALLISTA := "ballista"
const TREBUCHET := "trebuchet"
const DRAGOON := "dragoon"
const CHARIOT := "chariot"
const GRIFFIN := "griffin"
const MARSHAL := "marshal"
const INFANTRY := "infantry"
const RECALL := "recall"
const REINFORCEMENT := "reinforcement"

const CANONICAL_PIECE_TYPES := [
	SOVEREIGN, SPY, BALLISTA, TREBUCHET, DRAGOON, CHARIOT,
	GRIFFIN, MARSHAL, INFANTRY, RECALL, REINFORCEMENT,
]

static var _catalog: Dictionary = {}
static var _ruleset_document: Dictionary = {}
static var _catalog_hash := ""
static var _configuration_errors: Array = []


static func _load_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_configuration_errors.append("Could not open %s" % path)
		return {}
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		_configuration_errors.append("%s must contain a JSON object" % path)
		return {}
	if path == CATALOG_PATH:
		_catalog_hash = text.sha256_text()
	return parsed


static func _check_exact_keys(value: Dictionary, required: Array, context: String) -> void:
	for key in required:
		if not value.has(key):
			_configuration_errors.append("%s is missing %s" % [context, key])
	for key in value:
		if key not in required:
			_configuration_errors.append("%s has unknown key %s" % [context, key])


static func _validate_catalog() -> void:
	_check_exact_keys(_catalog, ["schema_version", "id", "board", "range_by_height", "pieces", "specials"], "catalog")
	if _catalog.is_empty():
		return
	if int(_catalog.get("schema_version", 0)) != 1:
		_configuration_errors.append("Unsupported catalog schema version")
	var board: Dictionary = _catalog.get("board", {})
	_check_exact_keys(board, ["size", "files", "max_stack_height", "home_ranks_per_player", "neutral_ranks"], "catalog.board")
	if str(board.get("files", "")).length() != int(board.get("size", 0)):
		_configuration_errors.append("Board files must match board size")
	if int(board.get("home_ranks_per_player", 0)) * 2 + int(board.get("neutral_ranks", 0)) != int(board.get("size", 0)):
		_configuration_errors.append("Home and neutral ranks must fill the board")
	var heights: Array = []
	for height in range(1, int(board.get("max_stack_height", 0)) + 1):
		heights.append(str(height))
	_check_exact_keys(_catalog.get("range_by_height", {}), heights, "catalog.range_by_height")
	_check_exact_keys(_catalog.get("pieces", {}), CANONICAL_PIECE_TYPES, "catalog.pieces")
	for piece_id in _catalog.get("pieces", {}):
		var definition: Dictionary = _catalog.pieces[piece_id]
		_check_exact_keys(definition, ["display_name", "notation", "starting_count", "movement", "artillery"], "piece.%s" % piece_id)
		if str(definition.get("display_name", "")).is_empty():
			_configuration_errors.append("Missing display name for %s" % piece_id)
		if str(definition.get("notation", "")).is_empty():
			_configuration_errors.append("Missing notation for %s" % piece_id)
		var movement: Dictionary = definition.get("movement", {})
		var movement_keys := ["mode", "direction_mode", "range_mode"]
		if movement.get("mode") == "leap":
			movement_keys.append("vectors_by_height")
		_check_exact_keys(movement, movement_keys, "piece.%s.movement" % piece_id)
		if movement.get("mode") not in ["immobile", "ray", "leap"]:
			_configuration_errors.append("Unsupported movement mode for %s" % piece_id)
		if movement.get("direction_mode") not in ["none", "omnidirectional", "forward", "diagonal", "orthogonal"]:
			_configuration_errors.append("Unsupported direction mode for %s" % piece_id)
		if movement.get("range_mode") not in ["none", "one", "stack_height", "height_table"]:
			_configuration_errors.append("Unsupported range mode for %s" % piece_id)
		if movement.get("mode") == "leap":
			_check_exact_keys(movement.get("vectors_by_height", {}), heights, "piece.%s.vectors_by_height" % piece_id)
		var artillery = definition.get("artillery")
		if artillery != null:
			_check_exact_keys(artillery, ["direction_mode", "range_mode", "sovereign_target"], "piece.%s.artillery" % piece_id)
			if artillery.get("direction_mode") not in ["forward_and_sideways", "forward_diagonal"]:
				_configuration_errors.append("Unsupported artillery direction mode for %s" % piece_id)
	var specials: Dictionary = _catalog.get("specials", {})
	var notations := {}
	for piece_id in _catalog.get("pieces", {}):
		var notation := str(_catalog.pieces[piece_id].get("notation", ""))
		if notations.has(notation):
			_configuration_errors.append("Duplicate piece notation: %s" % notation)
		notations[notation] = true
	_check_exact_keys(specials, ["sovereign", "spy", "recall", "reinforcement"], "catalog.specials")
	_check_exact_keys(specials.get("sovereign", {}), ["royal_attack"], "specials.sovereign")
	if not specials.get("sovereign", {}).get("royal_attack") is bool:
		_configuration_errors.append("specials.sovereign.royal_attack must be boolean")
	_check_exact_keys(specials.get("spy", {}), ["maximum_target_height", "forbidden_top_piece_targets"], "specials.spy")
	_check_exact_keys(specials.get("recall", {}), ["forbidden_piece_kinds"], "specials.recall")
	_check_exact_keys(specials.get("reinforcement", {}), ["insertion", "forbidden_top_piece_targets"], "specials.reinforcement")
	if specials.get("reinforcement", {}).get("insertion") != "bottom":
		_configuration_errors.append("Only bottom reinforcement insertion is implemented")


static func _validate_rulesets() -> void:
	_check_exact_keys(_ruleset_document, ["schema_version", "catalog_id", "catalog_hash", "rulesets"], "rulesets")
	if _ruleset_document.is_empty():
		return
	if int(_ruleset_document.get("schema_version", 0)) != 1:
		_configuration_errors.append("Unsupported ruleset schema version")
	if _ruleset_document.get("catalog_id") != _catalog.get("id"):
		_configuration_errors.append("Rulesets reference a different catalog")
	if _ruleset_document.get("catalog_hash") != _catalog_hash:
		_configuration_errors.append("Rulesets reference different piece catalog content")
	var keys := [
		"development_opening", "development_placements_per_player",
		"development_home_only", "development_specials_prohibited",
		"height_three_requires_nonsovereign_move", "infiltration_victory", "move_vs_taller",
		"artillery_vs_taller",
	]
	for ruleset_id in _ruleset_document.get("rulesets", {}):
		var values: Dictionary = _ruleset_document.rulesets[ruleset_id]
		_check_exact_keys(values, keys, "ruleset.%s" % ruleset_id)
		for key in ["development_opening", "development_home_only", "development_specials_prohibited", "height_three_requires_nonsovereign_move", "infiltration_victory"]:
			if not values.get(key) is bool:
				_configuration_errors.append("%s must be boolean in %s" % [key, ruleset_id])
		if values.get("move_vs_taller") not in ["illegal", "mutual_bottom_attrition"]:
			_configuration_errors.append("Unsupported move combat mode in %s" % ruleset_id)
		if values.get("artillery_vs_taller") not in ["illegal", "target_bottom_attrition"]:
			_configuration_errors.append("Unsupported artillery combat mode in %s" % ruleset_id)


static func _ensure_loaded() -> void:
	if not _catalog.is_empty() or not _configuration_errors.is_empty():
		return
	_catalog = _load_json_object(CATALOG_PATH)
	_ruleset_document = _load_json_object(RULESETS_PATH)
	_validate_catalog()
	_validate_rulesets()
	for error in _configuration_errors:
		push_error(error)


static func configuration_errors() -> Array:
	_ensure_loaded()
	return _configuration_errors.duplicate()


static func catalog_id() -> String:
	_ensure_loaded()
	return str(_catalog.get("id", ""))


static func catalog_hash() -> String:
	_ensure_loaded()
	return _catalog_hash


static func board_size() -> int:
	_ensure_loaded()
	return int(_catalog.board.size)


static func max_stack_height() -> int:
	_ensure_loaded()
	return int(_catalog.board.max_stack_height)


static func home_ranks() -> int:
	_ensure_loaded()
	return int(_catalog.board.home_ranks_per_player)


static func neutral_ranks() -> int:
	_ensure_loaded()
	return int(_catalog.board.neutral_ranks)


static func files() -> String:
	_ensure_loaded()
	return str(_catalog.board.files)


static func piece_types() -> Array:
	_ensure_loaded()
	return _catalog.pieces.keys()


static func piece_definition(kind: String) -> Dictionary:
	_ensure_loaded()
	return _catalog.pieces.get(kind, {})


static func piece_display_name(kind: String) -> String:
	return str(piece_definition(kind).get("display_name", kind))


static func piece_notation(kind: String) -> String:
	return str(piece_definition(kind).get("notation", ""))


static func special_rules(name: String) -> Dictionary:
	_ensure_loaded()
	return _catalog.specials.get(name, {})


static func range_for_height(height: int) -> int:
	_ensure_loaded()
	return int(_catalog.range_by_height.get(str(height), 0))


static func ruleset(ruleset_id: String) -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = _ruleset_document.get("rulesets", {}).get(ruleset_id, {}).duplicate(true)
	if result.is_empty():
		push_error("Unknown ruleset id: %s" % ruleset_id)
		return {}
	result["id"] = ruleset_id
	result["catalog_id"] = catalog_id()
	result["catalog_hash"] = catalog_hash()
	return result


static func control_ruleset() -> Dictionary:
	return ruleset("control-v3")


static func development_ruleset() -> Dictionary:
	return ruleset("development-v3")


static func attrition_control_ruleset() -> Dictionary:
	return ruleset("attrition-control-v2")


static func attrition_development_ruleset() -> Dictionary:
	return ruleset("attrition-development-v2")


static func development_infiltration_ruleset() -> Dictionary:
	return ruleset("development-infiltration-v1")


static func attrition_development_infiltration_ruleset() -> Dictionary:
	return ruleset("attrition-development-infiltration-v1")


static func opponent(player: String) -> String:
	return BLACK if player == WHITE else WHITE


static func forward(player: String) -> int:
	return 1 if player == WHITE else -1


static func empty_inventory() -> Dictionary:
	var result := {}
	for piece in piece_types():
		result[piece] = 0
	return result


static func starting_inventory() -> Dictionary:
	var result := {}
	for piece in piece_types():
		result[piece] = int(piece_definition(piece).starting_count)
	return result


static func square(file_index: int, rank_index: int) -> String:
	return files().substr(file_index, 1) + str(rank_index + 1)


static func square_to_xy(name: String) -> Vector2i:
	var normalized := name.strip_edges().to_upper()
	if normalized.length() != 2:
		return Vector2i(-1, -1)
	return Vector2i(files().find(normalized.substr(0, 1)), normalized.substr(1, 1).to_int() - 1)


static func on_board(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < board_size() and position.y >= 0 and position.y < board_size()
