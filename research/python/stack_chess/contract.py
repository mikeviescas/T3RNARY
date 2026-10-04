"""Versioned JSON adapter shared with the Godot simulator."""

from __future__ import annotations

from collections import Counter
from dataclasses import asdict
import hashlib
import json
from typing import Any

from .engine import (
    Action,
    GameState,
    MoveAction,
    Piece,
    PieceType,
    PlaceAction,
    Player,
    RecallAction,
    Ruleset,
    parse_square,
    square_name,
)


CONTRACT_VERSION = 2


def piece_type(value: str) -> PieceType:
    return PieceType(value)


def action_to_dict(action: Action) -> dict[str, Any]:
    if isinstance(action, MoveAction):
        return {
            "type": "move",
            "source": square_name(action.source),
            "destination": square_name(action.destination),
        }
    result: dict[str, Any] = {
        "type": "recall" if isinstance(action, RecallAction) else "place",
        "piece": action.piece.value,
        "destination": square_name(action.destination),
    }
    if action.effect_target is not None:
        result["effect_target"] = square_name(action.effect_target)
    return result


def action_from_dict(raw: dict[str, Any]) -> Action:
    action_type = raw["type"]
    if action_type == "move":
        return MoveAction(parse_square(raw["source"]), parse_square(raw["destination"]))
    if action_type not in {"place", "recall"}:
        raise ValueError(f"unsupported action type: {action_type}")
    action_class = RecallAction if action_type == "recall" else PlaceAction
    target = raw.get("effect_target")
    return action_class(
        piece_type(raw["piece"]),
        parse_square(raw["destination"]),
        parse_square(target) if target is not None else None,
    )


def _inventory(counter: Counter[PieceType]) -> dict[str, int]:
    return {kind.value: counter[kind] for kind in PieceType}


def state_to_dict(state: GameState) -> dict[str, Any]:
    return {
        "contract_version": CONTRACT_VERSION,
        "rules": asdict(state.rules),
        "board": {
            square_name(square): [
                {"owner": piece.owner.value, "kind": piece.kind.value}
                for piece in stack
            ]
            for square, stack in sorted(state.board.items())
        },
        "reserves": {player.value: _inventory(state.reserves[player]) for player in Player},
        "discards": {player.value: _inventory(state.discards[player]) for player in Player},
        "turn": state.turn.value,
        "winner": state.winner.value if state.winner else None,
        "is_draw": state.is_draw,
        "ply": state.ply,
        "development_placements": {player.value: state.development_placements[player] for player in Player},
        "height_three_unlocked": {player.value: state.height_three_unlocked[player] for player in Player},
    }


def state_from_dict(raw: dict[str, Any]) -> GameState:
    if raw.get("contract_version") != CONTRACT_VERSION:
        raise ValueError(
            f"unsupported contract version: {raw.get('contract_version')!r}; "
            f"expected {CONTRACT_VERSION}"
        )
    rule_values = dict(raw["rules"])
    rule_values.pop("id", None)
    state = GameState(
        board={
            parse_square(square): tuple(
                Piece(Player(piece["owner"]), piece_type(piece["kind"]))
                for piece in stack
            )
            for square, stack in raw["board"].items()
        },
        reserves={
            player: Counter({piece_type(kind): count for kind, count in raw.get("reserves", {}).get(player.value, {}).items()})
            for player in Player
        },
        discards={
            player: Counter({piece_type(kind): count for kind, count in raw.get("discards", {}).get(player.value, {}).items()})
            for player in Player
        },
        turn=Player(raw.get("turn", "white")),
        winner=Player(raw["winner"]) if raw.get("winner") else None,
        is_draw=bool(raw.get("is_draw", False)),
        ply=int(raw.get("ply", 0)),
        rules=Ruleset(**rule_values),
        development_placements={
            player: int(raw.get("development_placements", {}).get(player.value, 0))
            for player in Player
        },
        height_three_unlocked={
            player: bool(raw.get("height_three_unlocked", {}).get(player.value, True))
            for player in Player
        },
    )
    return state


def state_checksum(state: GameState) -> str:
    payload = json.dumps(
        state_to_dict(state), sort_keys=True, separators=(",", ":"), ensure_ascii=False
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
