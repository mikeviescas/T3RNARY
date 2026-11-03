class_name TabletopShowcaseState
extends RefCounted

const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")

# Ply 50 of human-1792117482-351-WG-BC. Keeping the recorded actions here lets
# the rules engine, rather than presentation code, determine every stack,
# reserve count, and discard count shown in the tabletop proof of concept.
const ACTIONS := [
	{"type":"place", "piece":"infantry", "destination":"C3"},
	{"type":"place", "piece":"infantry", "destination":"B7"},
	{"type":"place", "piece":"infantry", "destination":"G3"},
	{"type":"place", "piece":"infantry", "destination":"D7"},
	{"type":"place", "piece":"chariot", "destination":"C3"},
	{"type":"place", "piece":"infantry", "destination":"A7"},
	{"type":"place", "piece":"dragoon", "destination":"G3"},
	{"type":"place", "piece":"dragoon", "destination":"A7"},
	{"type":"place", "piece":"infantry", "destination":"A3"},
	{"type":"move", "source":"A7", "destination":"D4"},
	{"type":"place", "piece":"infantry", "destination":"F2"},
	{"type":"move", "source":"B7", "destination":"B6"},
	{"type":"move", "source":"C3", "destination":"D3"},
	{"type":"place", "piece":"dragoon", "destination":"B6"},
	{"type":"move", "source":"D3", "destination":"D4"},
	{"type":"place", "piece":"trebuchet", "destination":"B6", "effect_target":"D4"},
	{"type":"place", "piece":"infantry", "destination":"A3"},
	{"type":"move", "source":"D7", "destination":"D6"},
	{"type":"place", "piece":"chariot", "destination":"A3"},
	{"type":"move", "source":"D6", "destination":"D5"},
	{"type":"move", "source":"A3", "destination":"A9"},
	{"type":"move", "source":"C9", "destination":"C8"},
	{"type":"move", "source":"A9", "destination":"A7"},
	{"type":"move", "source":"D5", "destination":"D4"},
	{"type":"place", "piece":"trebuchet", "destination":"F2", "effect_target":"D4"},
	{"type":"place", "piece":"infantry", "destination":"B4"},
	{"type":"place", "piece":"marshal", "destination":"F2"},
	{"type":"place", "piece":"chariot", "destination":"B4"},
	{"type":"move", "source":"F2", "destination":"F8"},
	{"type":"place", "piece":"infantry", "destination":"D8"},
	{"type":"move", "source":"A7", "destination":"A8"},
	{"type":"move", "source":"C8", "destination":"B7"},
	{"type":"move", "source":"A8", "destination":"D8"},
	{"type":"move", "source":"B4", "destination":"A4"},
	{"type":"move", "source":"F8", "destination":"E7"},
	{"type":"move", "source":"B7", "destination":"C6"},
	{"type":"place", "piece":"dragoon", "destination":"F3"},
	{"type":"move", "source":"C6", "destination":"B5"},
	{"type":"move", "source":"E7", "destination":"E2"},
	{"type":"move", "source":"B5", "destination":"C5"},
	{"type":"move", "source":"G3", "destination":"F2"},
	{"type":"move", "source":"C5", "destination":"B4"},
	{"type":"move", "source":"D8", "destination":"D4"},
	{"type":"move", "source":"B4", "destination":"B3"},
	{"type":"move", "source":"D4", "destination":"D3"},
	{"type":"move", "source":"B3", "destination":"B4"},
	{"type":"place", "piece":"spy", "destination":"A4"},
	{"type":"place", "piece":"infantry", "destination":"A5"},
	{"type":"place", "piece":"infantry", "destination":"B3"},
	{"type":"move", "source":"B4", "destination":"A3"},
]


static func build() -> Dictionary:
	var state := GameEngine.initial_state(Rules.current_beta_ruleset(), Vector2i(6, 2))
	for action in ACTIONS:
		var next_state := GameEngine.apply_action(state, action, false)
		if next_state.is_empty():
			push_error("Tabletop showcase replay failed at ply %d" % (int(state.ply) + 1))
			return {}
		state = next_state
	return state
