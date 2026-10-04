"""Strict loader for the rule data shared by Python and Godot."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


RULE_DATA_ROOT = Path(__file__).resolve().parents[3] / "godot" / "data" / "rules"
CATALOG_PATH = RULE_DATA_ROOT / "pieces.json"
RULESETS_PATH = RULE_DATA_ROOT / "rulesets.json"

PIECE_IDS = {
    "sovereign", "spy", "ballista", "trebuchet", "dragoon", "chariot",
    "griffin", "marshal", "infantry", "recall", "reinforcement",
}
MOVEMENT_MODES = {"immobile", "ray", "leap"}
DIRECTION_MODES = {
    "none", "omnidirectional", "forward", "diagonal", "orthogonal",
}
RANGE_MODES = {"none", "one", "stack_height", "height_table"}
ARTILLERY_DIRECTION_MODES = {"forward_and_sideways", "forward_diagonal"}
MOVE_COMBAT_MODES = {"illegal", "mutual_bottom_attrition"}
ARTILLERY_COMBAT_MODES = {"illegal", "target_bottom_attrition"}


def _load_object(path: Path) -> tuple[dict[str, Any], str]:
    raw = path.read_bytes()
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return parsed, hashlib.sha256(raw).hexdigest()


def _exact_keys(value: dict[str, Any], required: set[str], context: str) -> None:
    actual = set(value)
    if actual != required:
        missing = sorted(required - actual)
        unknown = sorted(actual - required)
        raise ValueError(f"{context} keys differ; missing={missing}, unknown={unknown}")


def _positive_int(value: Any, context: str, *, allow_zero: bool = False) -> None:
    lower = 0 if allow_zero else 1
    if not isinstance(value, int) or isinstance(value, bool) or value < lower:
        raise ValueError(f"{context} must be an integer >= {lower}")


def _validate_catalog(catalog: dict[str, Any]) -> None:
    _exact_keys(
        catalog,
        {"schema_version", "id", "board", "range_by_height", "pieces", "specials"},
        "catalog",
    )
    if catalog["schema_version"] != 1 or not isinstance(catalog["id"], str):
        raise ValueError("unsupported catalog schema or id")

    board = catalog["board"]
    _exact_keys(
        board,
        {"size", "files", "max_stack_height", "home_ranks_per_player", "neutral_ranks"},
        "catalog.board",
    )
    for key in ("size", "max_stack_height", "home_ranks_per_player", "neutral_ranks"):
        _positive_int(board[key], f"catalog.board.{key}")
    if not isinstance(board["files"], str) or len(board["files"]) != board["size"]:
        raise ValueError("catalog.board.files must contain one character per board file")
    if board["home_ranks_per_player"] * 2 + board["neutral_ranks"] != board["size"]:
        raise ValueError("home and neutral ranks must exactly fill the board")

    expected_heights = {str(i) for i in range(1, board["max_stack_height"] + 1)}
    if set(catalog["range_by_height"]) != expected_heights:
        raise ValueError("range_by_height must define every legal stack height")
    for height, distance in catalog["range_by_height"].items():
        _positive_int(distance, f"range_by_height.{height}")

    if set(catalog["pieces"]) != PIECE_IDS:
        raise ValueError("catalog.pieces must define exactly the canonical piece ids")
    for piece_id, definition in catalog["pieces"].items():
        _exact_keys(
            definition,
            {"display_name", "notation", "starting_count", "movement", "artillery"},
            f"piece.{piece_id}",
        )
        if not isinstance(definition["display_name"], str) or not definition["display_name"]:
            raise ValueError(f"piece.{piece_id}.display_name must be a non-empty string")
        if not isinstance(definition["notation"], str) or not definition["notation"]:
            raise ValueError(f"piece.{piece_id}.notation must be a non-empty string")
        _positive_int(definition["starting_count"], f"piece.{piece_id}.starting_count", allow_zero=True)
        movement = definition["movement"]
        required = {"mode", "direction_mode", "range_mode"}
        if movement.get("mode") == "leap":
            required.add("vectors_by_height")
        _exact_keys(movement, required, f"piece.{piece_id}.movement")
        if movement["mode"] not in MOVEMENT_MODES:
            raise ValueError(f"unsupported movement mode for {piece_id}")
        if movement["direction_mode"] not in DIRECTION_MODES:
            raise ValueError(f"unsupported direction mode for {piece_id}")
        if movement["range_mode"] not in RANGE_MODES:
            raise ValueError(f"unsupported range mode for {piece_id}")
        if movement["mode"] == "leap":
            if set(movement["vectors_by_height"]) != expected_heights:
                raise ValueError(f"{piece_id} leap vectors must define every height")
            for vectors in movement["vectors_by_height"].values():
                if not vectors or any(
                    not isinstance(vector, list)
                    or len(vector) != 2
                    or any(not isinstance(component, int) or component <= 0 for component in vector)
                    for vector in vectors
                ):
                    raise ValueError(f"invalid leap vector for {piece_id}")
        artillery = definition["artillery"]
        if artillery is not None:
            _exact_keys(artillery, {"direction_mode", "range_mode", "sovereign_target"}, f"piece.{piece_id}.artillery")
            if artillery["direction_mode"] not in ARTILLERY_DIRECTION_MODES:
                raise ValueError(f"unsupported artillery direction mode for {piece_id}")
            if artillery["range_mode"] != "height_table" or not isinstance(artillery["sovereign_target"], bool):
                raise ValueError(f"invalid artillery parameters for {piece_id}")

    notations = [definition["notation"] for definition in catalog["pieces"].values()]
    if len(notations) != len(set(notations)):
        raise ValueError("piece notation values must be unique")

    specials = catalog["specials"]
    _exact_keys(specials, {"sovereign", "spy", "recall", "reinforcement"}, "catalog.specials")
    _exact_keys(specials["sovereign"], {"royal_attack"}, "specials.sovereign")
    if not isinstance(specials["sovereign"]["royal_attack"], bool):
        raise ValueError("specials.sovereign.royal_attack must be boolean")
    _exact_keys(specials["spy"], {"maximum_target_height", "forbidden_top_piece_targets"}, "specials.spy")
    _positive_int(specials["spy"]["maximum_target_height"], "specials.spy.maximum_target_height")
    _exact_keys(specials["recall"], {"forbidden_piece_kinds"}, "specials.recall")
    _exact_keys(specials["reinforcement"], {"insertion", "forbidden_top_piece_targets"}, "specials.reinforcement")
    for key, values in (
        ("spy.forbidden_top_piece_targets", specials["spy"]["forbidden_top_piece_targets"]),
        ("recall.forbidden_piece_kinds", specials["recall"]["forbidden_piece_kinds"]),
        ("reinforcement.forbidden_top_piece_targets", specials["reinforcement"]["forbidden_top_piece_targets"]),
    ):
        if not isinstance(values, list) or not set(values) <= PIECE_IDS:
            raise ValueError(f"specials.{key} contains an unknown piece id")
    if specials["reinforcement"]["insertion"] != "bottom":
        raise ValueError("only bottom reinforcement insertion is currently implemented")


def _validate_rulesets(
    document: dict[str, Any], catalog: dict[str, Any], catalog_hash: str
) -> None:
    _exact_keys(
        document,
        {"schema_version", "catalog_id", "catalog_hash", "rulesets"},
        "rulesets",
    )
    if document["schema_version"] != 1 or document["catalog_id"] != catalog["id"]:
        raise ValueError("ruleset schema or catalog reference does not match")
    if document["catalog_hash"] != catalog_hash:
        raise ValueError("rulesets reference different piece catalog content")
    if not isinstance(document["rulesets"], dict) or not document["rulesets"]:
        raise ValueError("rulesets.rulesets must be a non-empty object")
    required = {
        "development_opening", "development_placements_per_player",
        "development_home_only", "development_specials_prohibited",
        "height_three_requires_nonsovereign_move", "infiltration_victory", "move_vs_taller",
        "artillery_vs_taller",
    }
    for ruleset_id, values in document["rulesets"].items():
        _exact_keys(values, required, f"ruleset.{ruleset_id}")
        for key in (
            "development_opening", "development_home_only",
            "development_specials_prohibited", "height_three_requires_nonsovereign_move",
            "infiltration_victory",
        ):
            if not isinstance(values[key], bool):
                raise ValueError(f"ruleset.{ruleset_id}.{key} must be boolean")
        _positive_int(
            values["development_placements_per_player"],
            f"ruleset.{ruleset_id}.development_placements_per_player",
            allow_zero=True,
        )
        if values["move_vs_taller"] not in MOVE_COMBAT_MODES:
            raise ValueError(f"unsupported move combat mode in {ruleset_id}")
        if values["artillery_vs_taller"] not in ARTILLERY_COMBAT_MODES:
            raise ValueError(f"unsupported artillery combat mode in {ruleset_id}")


CATALOG, CATALOG_HASH = _load_object(CATALOG_PATH)
RULESET_DOCUMENT, _RULESET_FILE_HASH = _load_object(RULESETS_PATH)
_validate_catalog(CATALOG)
_validate_rulesets(RULESET_DOCUMENT, CATALOG, CATALOG_HASH)


def ruleset_values(ruleset_id: str) -> dict[str, Any]:
    try:
        values = RULESET_DOCUMENT["rulesets"][ruleset_id]
    except KeyError as error:
        raise ValueError(f"unknown ruleset id: {ruleset_id}") from error
    return {
        "id": ruleset_id,
        "catalog_id": CATALOG["id"],
        "catalog_hash": CATALOG_HASH,
        **values,
    }
