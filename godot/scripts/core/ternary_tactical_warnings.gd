class_name TernaryTacticalWarnings
extends RefCounted

const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")


static func position_warning(state: Dictionary) -> Dictionary:
	if state.is_empty() or GameEngine.is_over(state):
		return {}
	var player := str(state.get("turn", ""))
	if player.is_empty() or not GameEngine.is_sovereign_threatened(state, player):
		return {}
	if not _has_safe_reply(state, player):
		return {
			"kind": "checkmate",
			"player": player,
			"message": "%s in CHECKMATE danger" % player.capitalize(),
		}
	return {
		"kind": "check",
		"player": player,
		"message": "%s in CHECK" % player.capitalize(),
	}


static func action_warning(state: Dictionary, action: Dictionary) -> Dictionary:
	if state.is_empty() or GameEngine.is_over(state):
		return {}
	var player := str(state.get("turn", ""))
	var result := GameEngine.simulate_action(state, action)
	if result.is_empty() or result.get("winner") == player or bool(result.get("is_draw", false)):
		return {}
	if not GameEngine.is_sovereign_threatened(result, player):
		return {}

	# Warn only when this action is meaningfully avoidable. If every legal action
	# leaves the Sovereign exposed, the position warning reports the forced loss
	# without nagging the player for making the only kind of move available.
	for alternative_value in GameEngine.legal_actions(state):
		var alternative: Dictionary = alternative_value
		var alternative_result := GameEngine.simulate_action(state, alternative)
		if alternative_result.is_empty():
			continue
		if (
			alternative_result.get("winner") == player
			or bool(alternative_result.get("is_draw", false))
			or not GameEngine.is_sovereign_threatened(alternative_result, player)
		):
			return {
				"kind": "major_blunder",
				"player": player,
				"message": "This leaves your Sovereign open to immediate capture.",
			}
	return {}


static func _has_safe_reply(state: Dictionary, player: String) -> bool:
	for action_value in GameEngine.legal_actions(state):
		var result := GameEngine.simulate_action(state, action_value)
		if result.is_empty():
			continue
		if (
			result.get("winner") == player
			or bool(result.get("is_draw", false))
			or not GameEngine.is_sovereign_threatened(result, player)
		):
			return true
	return false
