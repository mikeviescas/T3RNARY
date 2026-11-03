class_name PieceEncyclopedia
extends RefCounted

const Rules = preload("res://scripts/core/ternary_rules.gd")

const ORDER := [
	Rules.SOVEREIGN, Rules.INFANTRY, Rules.DRAGOON, Rules.CHARIOT,
	Rules.GRIFFIN, Rules.MARSHAL, Rules.SPY, Rules.BALLISTA,
	Rules.TREBUCHET, Rules.REINFORCEMENT, Rules.RECALL,
]

const COPY := {
	"sovereign": {
		"summary": "Moves exactly 1 square in any direction. ROYAL ATTACK captures an adjacent enemy stack of any height. Reaching the opponent's back rank wins by CONQUER. Nothing may be stacked on or beneath it.",
		"ranges": [["1", "1 square in any direction"]],
	},
	"infantry": {
		"summary": "Moves and attacks forward.",
		"ranges": [["1", "1 square"], ["2", "2 squares max"], ["3", "3 squares max"]],
	},
	"dragoon": {
		"summary": "Moves diagonally. Cannot pass through occupied squares.",
		"ranges": [["1", "3 squares max"], ["2", "5 squares max"], ["3", "9 squares max"]],
	},
	"chariot": {
		"summary": "Moves horizontally or vertically. Cannot pass through occupied squares.",
		"ranges": [["1", "3 squares max"], ["2", "5 squares max"], ["3", "9 squares max"]],
	},
	"griffin": {
		"summary": "Moves in an L shape. Can leap over other pieces.",
		"ranges": [["1 & 2", "1×2 or 2×1"], ["3", "1×2 or 2×1 or 3×2 or 2×3"]],
	},
	"marshal": {
		"summary": "Moves horizontally, vertically, or diagonally. Cannot pass through occupied squares.",
		"ranges": [["1", "3 squares max"], ["2", "5 squares max"], ["3", "9 squares max"]],
	},
	"spy": {
		"summary": "Cannot move. PLACE on a non-Sovereign enemy stack of height 1 or 2 anywhere after OPENING. Discard the opponent's stack and replace it with identical tiles from your reserve. PLACE is not legal without every matching reserve tile.",
	},
	"ballista": {
		"summary": "Cannot move. When PLACED, may SHOOT forward, left, or right. Fire cannot pass through pieces or target a Sovereign. Shooting is optional.",
		"range_heading": "Stack Height / SHOOT Range:",
		"range_column": "SHOOT RANGE",
		"ranges": [["1", "3 squares max"], ["2", "5 squares max"], ["3", "9 squares max"]],
	},
	"trebuchet": {
		"summary": "Cannot move. When PLACED, may SHOOT along either forward diagonal. Fire cannot pass through pieces or target a Sovereign. Shooting is optional.",
		"range_heading": "Stack Height / SHOOT Range:",
		"range_column": "SHOOT RANGE",
		"ranges": [["1", "3 squares max"], ["2", "5 squares max"], ["3", "9 squares max"]],
	},
	"reinforcement": {
		"summary": "PLACE underneath any of your 1 or 2 Height non-Sovereign stacks to increase stack height without changing the top tile.",
	},
	"recall": {
		"summary": "To use the Recall tile, exchange it with any tile in your discard that can be legally PLACED and PLACE the exchanged tile according to its rules.",
	},
}


static func kinds() -> Array:
	return ORDER.duplicate()


static func entry(kind: String) -> Dictionary:
	var definition := Rules.piece_definition(kind)
	var copy: Dictionary = COPY.get(kind, {})
	return {
		"kind": kind,
		"name": Rules.piece_display_name(kind),
		"notation": Rules.piece_notation(kind),
		"count": int(definition.get("starting_count", 0)),
		"summary": str(copy.get("summary", "")),
		"ranges": copy.get("ranges", []).duplicate(true),
		"range_heading": str(copy.get("range_heading", "Stack Height / Range:")),
		"range_column": str(copy.get("range_column", "RANGE")),
	}
