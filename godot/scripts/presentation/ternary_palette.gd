class_name TernaryPalette
extends RefCounted

# Table and interface
const BACKGROUND := Color("111419")
const BACKGROUND_WARM := Color("1b1714")
const PANEL := Color("191d22")
const PANEL_RAISED := Color("232830")
const PANEL_LINE := Color("454b53")
const TEXT := Color("eee8dc")
const TEXT_MUTED := Color("aaa59c")
const BRASS := Color("c89b4b")
const BRASS_LIGHT := Color("f0ca78")
const COPPER := Color("9e5d38")

# Board materials
const FRAME_DARK := Color("17191b")
const FRAME_MID := Color("292725")
const FRAME_EDGE := Color("6e5233")
const LIGHT_SQUARE := Color("c9a871")
const DARK_SQUARE := Color("5d4938")
const NEUTRAL_LIGHT_SQUARE := Color("cfb681")
const NEUTRAL_DARK_SQUARE := Color("786653")
const GRID_LINE := Color(0.10, 0.075, 0.055, 0.72)
const NEUTRAL_BOUNDARY := Color("332d27")

# Token materials. Piece identity never changes these colors.
const WHITE_BODY := Color("e9dfcc")
const WHITE_FACE := Color("f8f0df")
const WHITE_EDGE := Color("a99d89")
const WHITE_INK := Color("25282b")
const BLACK_BODY := Color("24282d")
const BLACK_FACE := Color("353b41")
const BLACK_EDGE := Color("0c0e11")
const BLACK_INK := Color("f2e7d2")
const WHITE_TOKEN_PINSTRIPE := Color("3b3f45")
const BLACK_TOKEN_PINSTRIPE := Color("c5c9cd")

# Interaction
const SELECTED := Color("f1c85f")
const MOVE := Color("65d0d5")
const CAPTURE := Color("e46b55")
const PLACE := Color("7bd18d")
const SPY := Color("b487e8")


static func token_body(owner: String) -> Color:
	return WHITE_BODY if owner == "white" else BLACK_BODY


static func token_face(owner: String) -> Color:
	return WHITE_FACE if owner == "white" else BLACK_FACE


static func token_edge(owner: String) -> Color:
	return WHITE_EDGE if owner == "white" else BLACK_EDGE


static func token_ink(owner: String) -> Color:
	return WHITE_INK if owner == "white" else BLACK_INK


static func token_layer_border(owner: String) -> Color:
	# Purpose-painted graphite and silver-gray sit between the tile materials and
	# literal black/white, preserving separation without a harsh graphic outline.
	return WHITE_TOKEN_PINSTRIPE if owner == "white" else BLACK_TOKEN_PINSTRIPE
