"""Deterministic rules engine for T3RNARY.

Stacks are stored bottom-to-top. Actions are immutable values, which makes them
safe to enumerate, compare, log, and later score with heuristics.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from enum import Enum
from typing import Iterable, TypeAlias

from .rules_config import CATALOG, CATALOG_HASH, ruleset_values

FILES = CATALOG["board"]["files"]
BOARD_SIZE = CATALOG["board"]["size"]
MAX_STACK_HEIGHT = CATALOG["board"]["max_stack_height"]
HOME_RANKS = CATALOG["board"]["home_ranks_per_player"]
NEUTRAL_RANKS = CATALOG["board"]["neutral_ranks"]
Square: TypeAlias = tuple[int, int]  # zero-based file, rank


class Player(str, Enum):
    WHITE = "white"
    BLACK = "black"

    @property
    def opponent(self) -> "Player":
        return Player.BLACK if self is Player.WHITE else Player.WHITE

    @property
    def forward(self) -> int:
        return 1 if self is Player.WHITE else -1


class PieceType(str, Enum):
    SOVEREIGN = "sovereign"
    SPY = "spy"
    BALLISTA = "ballista"
    TREBUCHET = "trebuchet"
    DRAGOON = "dragoon"
    CHARIOT = "chariot"
    GRIFFIN = "griffin"
    MARSHAL = "marshal"
    INFANTRY = "infantry"
    RECALL = "recall"
    REINFORCEMENT = "reinforcement"


PIECE_CONFIG = {
    PieceType(piece_id): definition for piece_id, definition in CATALOG["pieces"].items()
}
STARTING_COUNTS = Counter(
    {kind: definition["starting_count"] for kind, definition in PIECE_CONFIG.items()}
)


def piece_display_name(kind: PieceType) -> str:
    return str(PIECE_CONFIG[kind]["display_name"])


def piece_notation(kind: PieceType) -> str:
    return str(PIECE_CONFIG[kind]["notation"])


@dataclass(frozen=True, slots=True)
class Piece:
    owner: Player
    kind: PieceType


Stack: TypeAlias = tuple[Piece, ...]


@dataclass(frozen=True, slots=True)
class MoveAction:
    source: Square
    destination: Square


@dataclass(frozen=True, slots=True)
class PlaceAction:
    piece: PieceType
    destination: Square
    effect_target: Square | None = None


@dataclass(frozen=True, slots=True)
class RecallAction:
    piece: PieceType
    destination: Square
    effect_target: Square | None = None


Action: TypeAlias = MoveAction | PlaceAction | RecallAction


@dataclass(frozen=True, slots=True)
class Ruleset:
    id: str = "control-v3"
    catalog_id: str = CATALOG["id"]
    catalog_hash: str = CATALOG_HASH
    development_opening: bool = False
    development_placements_per_player: int = 4
    development_home_only: bool = True
    development_specials_prohibited: bool = True
    height_three_requires_nonsovereign_move: bool = False
    height_three_requires_shared_neutral_presence: bool = False
    infiltration_victory: bool = False
    move_vs_taller: str = "illegal"
    artillery_vs_taller: str = "illegal"


CONTROL_RULES = Ruleset(**ruleset_values("control-v3"))
DEVELOPMENT_RULES = Ruleset(**ruleset_values("development-v3"))
ATTRITION_CONTROL_RULES = Ruleset(**ruleset_values("attrition-control-v2"))
ATTRITION_DEVELOPMENT_RULES = Ruleset(**ruleset_values("attrition-development-v2"))
DEVELOPMENT_INFILTRATION_RULES = Ruleset(**ruleset_values("development-infiltration-v1"))
ATTRITION_DEVELOPMENT_INFILTRATION_RULES = Ruleset(**ruleset_values("attrition-development-infiltration-v1"))
NEUTRAL_GATE_OPENING_4_RULES = Ruleset(**ruleset_values("attrition-neutral-gate-opening-4-v1"))
NEUTRAL_GATE_OPENING_5_RULES = Ruleset(**ruleset_values("attrition-neutral-gate-opening-5-v1"))
NEUTRAL_GATE_OPENING_6_RULES = Ruleset(**ruleset_values("attrition-neutral-gate-opening-6-v1"))
NEUTRAL_GATE_OPENING_7_RULES = Ruleset(**ruleset_values("attrition-neutral-gate-opening-7-v1"))
RULESETS_BY_ID = {
    rules.id: rules
    for rules in (
        CONTROL_RULES,
        DEVELOPMENT_RULES,
        ATTRITION_CONTROL_RULES,
        ATTRITION_DEVELOPMENT_RULES,
        DEVELOPMENT_INFILTRATION_RULES,
        ATTRITION_DEVELOPMENT_INFILTRATION_RULES,
        NEUTRAL_GATE_OPENING_4_RULES,
        NEUTRAL_GATE_OPENING_5_RULES,
        NEUTRAL_GATE_OPENING_6_RULES,
        NEUTRAL_GATE_OPENING_7_RULES,
    )
}


def ruleset_by_id(ruleset_id: str) -> Ruleset:
    try:
        return RULESETS_BY_ID[ruleset_id]
    except KeyError as error:
        raise ValueError(f"unknown ruleset id: {ruleset_id}") from error


@dataclass(slots=True)
class GameState:
    board: dict[Square, Stack] = field(default_factory=dict)
    reserves: dict[Player, Counter[PieceType]] = field(
        default_factory=lambda: {Player.WHITE: Counter(), Player.BLACK: Counter()}
    )
    discards: dict[Player, Counter[PieceType]] = field(
        default_factory=lambda: {Player.WHITE: Counter(), Player.BLACK: Counter()}
    )
    turn: Player = Player.WHITE
    winner: Player | None = None
    is_draw: bool = False
    ply: int = 0
    rules: Ruleset = field(default_factory=Ruleset)
    development_placements: dict[Player, int] = field(
        default_factory=lambda: {Player.WHITE: 0, Player.BLACK: 0}
    )
    height_three_unlocked: dict[Player, bool] = field(
        default_factory=lambda: {Player.WHITE: True, Player.BLACK: True}
    )

    @property
    def is_over(self) -> bool:
        return self.winner is not None or self.is_draw

    @property
    def in_development(self) -> bool:
        return self.rules.development_opening and any(
            self.development_placements[player]
            < self.rules.development_placements_per_player
            for player in Player
        )

    def copy(self) -> "GameState":
        return GameState(
            board=dict(self.board),
            reserves={p: Counter(c) for p, c in self.reserves.items()},
            discards={p: Counter(c) for p, c in self.discards.items()},
            turn=self.turn,
            winner=self.winner,
            is_draw=self.is_draw,
            ply=self.ply,
            rules=self.rules,
            development_placements=dict(self.development_placements),
            height_three_unlocked=dict(self.height_three_unlocked),
        )


def parse_square(name: str) -> Square:
    name = name.strip().upper()
    if len(name) != 2 or name[0] not in FILES or name[1] not in "123456789":
        raise ValueError(f"invalid square: {name!r}")
    return FILES.index(name[0]), int(name[1]) - 1


def square_name(square: Square) -> str:
    return f"{FILES[square[0]]}{square[1] + 1}"


def _on_board(square: Square) -> bool:
    return 0 <= square[0] < BOARD_SIZE and 0 <= square[1] < BOARD_SIZE


def initial_state(
    rules: Ruleset = CONTROL_RULES,
    sovereign_files: tuple[int, int] | None = None,
) -> GameState:
    state = GameState(rules=rules)
    for player in Player:
        state.reserves[player] = Counter(STARTING_COUNTS)
    if rules.development_opening:
        white_sovereign_file, black_sovereign_file = sovereign_files or (4, 4)
        if not (0 <= white_sovereign_file < BOARD_SIZE and 0 <= black_sovereign_file < BOARD_SIZE):
            raise ValueError("Sovereign files must be between 0 and 8")
        setup = {
            Player.WHITE: ((f"{FILES[white_sovereign_file]}1", PieceType.SOVEREIGN),),
            Player.BLACK: ((f"{FILES[black_sovereign_file]}9", PieceType.SOVEREIGN),),
        }
        initially_unlocked = not (
            rules.height_three_requires_nonsovereign_move
            or rules.height_three_requires_shared_neutral_presence
        )
        state.height_three_unlocked = {
            Player.WHITE: initially_unlocked,
            Player.BLACK: initially_unlocked,
        }
    else:
        setup = {
            Player.WHITE: (("E1", PieceType.SOVEREIGN), ("D2", PieceType.INFANTRY),
                           ("E2", PieceType.INFANTRY), ("F2", PieceType.INFANTRY)),
            Player.BLACK: (("E9", PieceType.SOVEREIGN), ("D8", PieceType.INFANTRY),
                           ("E8", PieceType.INFANTRY), ("F8", PieceType.INFANTRY)),
        }
    for player, placements in setup.items():
        for name, kind in placements:
            state.board[parse_square(name)] = (Piece(player, kind),)
            state.reserves[player][kind] -= 1
    validate_state(state, enforce_inventory=True)
    return state


def _territory_allows_open_place(player: Player, rank: int) -> bool:
    return (
        rank < HOME_RANKS + NEUTRAL_RANKS
        if player is Player.WHITE
        else rank >= HOME_RANKS
    )


def _in_home_territory(player: Player, rank: int) -> bool:
    return rank < HOME_RANKS if player is Player.WHITE else rank >= BOARD_SIZE - HOME_RANKS


def _range_for_height(height: int) -> int:
    return int(CATALOG["range_by_height"][str(height)])


def _directions(direction_mode: str, player: Player) -> list[Square]:
    if direction_mode == "forward":
        return [(0, player.forward)]
    if direction_mode == "diagonal":
        return [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    if direction_mode == "orthogonal":
        return [(1, 0), (-1, 0), (0, 1), (0, -1)]
    if direction_mode == "omnidirectional":
        return [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
    raise ValueError(f"unsupported direction mode: {direction_mode}")


def _movement_range(range_mode: str, height: int) -> int:
    if range_mode == "one":
        return 1
    if range_mode == "stack_height":
        return height
    if range_mode == "height_table":
        return _range_for_height(height)
    raise ValueError(f"unsupported range mode: {range_mode}")


def _can_resolve_against_height(attacker: int, defender: int, mode: str) -> bool:
    if attacker >= defender:
        return True
    if mode == "illegal":
        return False
    if mode in {"mutual_bottom_attrition", "target_bottom_attrition"}:
        return True
    raise ValueError(f"unsupported combat mode: {mode}")


def _can_attack_stack(
    state: GameState, kind: PieceType, attacker_height: int, defender: Stack
) -> bool:
    if kind is PieceType.SOVEREIGN and CATALOG["specials"]["sovereign"]["royal_attack"]:
        return True
    return _can_resolve_against_height(
        attacker_height, len(defender), state.rules.move_vs_taller
    )


def _ray_destinations(
    state: GameState, source: Square, directions: Iterable[Square], max_range: int
) -> Iterable[Square]:
    for dx, dy in directions:
        for distance in range(1, max_range + 1):
            destination = source[0] + dx * distance, source[1] + dy * distance
            if not _on_board(destination):
                break
            yield destination
            if destination in state.board:
                break


def _can_land(
    state: GameState, player: Player, kind: PieceType, height: int, destination: Square
) -> bool:
    target = state.board.get(destination)
    if target is None:
        return True
    return target[-1].owner is player.opponent and _can_attack_stack(
        state, kind, height, target
    )


def _movement_destinations(state: GameState, source: Square) -> Iterable[Square]:
    stack = state.board[source]
    top = stack[-1]
    height = len(stack)
    player = top.owner
    movement = PIECE_CONFIG[top.kind]["movement"]
    if movement["mode"] == "immobile":
        return

    if movement["mode"] == "leap":
        dimensions = movement["vectors_by_height"][str(height)]
        for ax, ay in dimensions:
            for sx in (-1, 1):
                for sy in (-1, 1):
                    destination = source[0] + sx * ax, source[1] + sy * ay
                    if _on_board(destination) and _can_land(state, player, top.kind, height, destination):
                        yield destination
        return

    if movement["mode"] != "ray":  # pragma: no cover - validated configuration
        raise AssertionError(f"unhandled movement mode: {movement['mode']}")
    directions = _directions(movement["direction_mode"], player)
    max_range = _movement_range(movement["range_mode"], height)

    for destination in _ray_destinations(state, source, directions, max_range):
        target = state.board.get(destination)
        if target is None:
            yield destination
        elif target[-1].owner is player.opponent and _can_attack_stack(
            state, top.kind, height, target
        ):
            yield destination


def _artillery_targets(
    state: GameState, player: Player, kind: PieceType, source: Square, height: int
) -> list[Square]:
    artillery = PIECE_CONFIG[kind]["artillery"]
    if artillery is None:
        return []
    forward = player.forward
    directions = {
        "forward_and_sideways": [(0, forward), (-1, 0), (1, 0)],
        "forward_diagonal": [(-1, forward), (1, forward)],
    }[artillery["direction_mode"]]
    targets: list[Square] = []
    for destination in _ray_destinations(state, source, directions, _range_for_height(height)):
        target = state.board.get(destination)
        if target is None:
            continue
        if (
            target[-1].owner is player.opponent
            and _can_resolve_against_height(
                height, len(target), state.rules.artillery_vs_taller
            )
            and (artillery["sovereign_target"] or target[-1].kind is not PieceType.SOVEREIGN)
        ):
            targets.append(destination)
    return targets


def _spy_can_convert(
    state: GameState,
    player: Player,
    target: Stack,
    *,
    placing_spy_from_reserve: bool,
) -> bool:
    spy_rules = CATALOG["specials"]["spy"]
    if (
        len(target) > spy_rules["maximum_target_height"]
        or target[-1].kind.value in spy_rules["forbidden_top_piece_targets"]
    ):
        return False
    required = Counter(piece.kind for piece in target)
    if placing_spy_from_reserve:
        required[PieceType.SPY] += 1
    return all(state.reserves[player][kind] >= count for kind, count in required.items())


def _placement_destinations(
    state: GameState,
    player: Player,
    kind: PieceType,
    *,
    recalled: bool = False,
) -> Iterable[Square]:
    development = state.in_development
    if kind is PieceType.REINFORCEMENT:
        for square, stack in state.board.items():
            if (
                stack[-1].owner is player
                and len(stack) < MAX_STACK_HEIGHT
                and stack[-1].kind is not PieceType.SOVEREIGN
                and (not development or _in_home_territory(player, square[1]))
            ):
                yield square
        return

    for rank in range(BOARD_SIZE):
        allowed = (
            _in_home_territory(player, rank)
            if development and state.rules.development_home_only
            else _territory_allows_open_place(player, rank)
        )
        if not allowed:
            continue
        for file in range(BOARD_SIZE):
            square = file, rank
            if square not in state.board:
                yield square

    if kind is not PieceType.SOVEREIGN:
        for square, stack in state.board.items():
            if (
                stack[-1].owner is player
                and stack[-1].kind is not PieceType.SOVEREIGN
                and len(stack) < MAX_STACK_HEIGHT
                and (not development or _in_home_territory(player, square[1]))
            ):
                yield square

    if kind is PieceType.SPY:
        for square, stack in state.board.items():
            if stack[-1].owner is player.opponent and _spy_can_convert(
                state,
                player,
                stack,
                placing_spy_from_reserve=not recalled,
            ):
                yield square


def _board_after_basic_placement(
    state: GameState, player: Player, kind: PieceType, destination: Square
) -> tuple[dict[Square, Stack], int]:
    board = dict(state.board)
    existing = board.get(destination)
    piece = Piece(player, kind)
    if kind is PieceType.REINFORCEMENT:
        assert existing is not None
        board[destination] = (piece,) + existing
    elif kind is PieceType.SPY and existing and existing[-1].owner is player.opponent:
        replacements = tuple(Piece(player, p.kind) for p in existing)
        board[destination] = replacements + (piece,)
    elif existing:
        board[destination] = existing + (piece,)
    else:
        board[destination] = (piece,)
    return board, len(board[destination])


def _actions_for_placed_piece(
    state: GameState,
    player: Player,
    kind: PieceType,
    destination: Square,
    recalled: bool,
) -> Iterable[Action]:
    action_type = RecallAction if recalled else PlaceAction
    if PIECE_CONFIG[kind]["artillery"] is None:
        yield action_type(kind, destination)
        return
    board, height = _board_after_basic_placement(state, player, kind, destination)
    placed_state = state.copy()
    placed_state.board = board
    yield action_type(kind, destination)  # Firing is optional.
    for target in _artillery_targets(placed_state, player, kind, destination, height):
        yield action_type(kind, destination, target)


def legal_actions(state: GameState) -> list[Action]:
    if state.is_over:
        return []
    player = state.turn
    actions: list[Action] = []

    if not state.in_development:
        for source, stack in state.board.items():
            if stack[-1].owner is player:
                actions.extend(MoveAction(source, destination) for destination in _movement_destinations(state, source))

    for kind in PieceType:
        if state.reserves[player][kind] <= 0:
            continue
        if (
            state.in_development
            and state.rules.development_specials_prohibited
            and kind
            in {
                PieceType.SPY,
                PieceType.BALLISTA,
                PieceType.TREBUCHET,
                PieceType.RECALL,
            }
        ):
            continue
        if kind is PieceType.RECALL:
            for recalled_kind, count in state.discards[player].items():
                if (
                    count <= 0
                    or recalled_kind.value
                    in CATALOG["specials"]["recall"]["forbidden_piece_kinds"]
                ):
                    continue
                for destination in _placement_destinations(
                    state, player, recalled_kind, recalled=True
                ):
                    _, resulting_height = _board_after_basic_placement(
                        state, player, recalled_kind, destination
                    )
                    if resulting_height == MAX_STACK_HEIGHT and not state.height_three_unlocked[player]:
                        continue
                    actions.extend(
                        _actions_for_placed_piece(
                            state, player, recalled_kind, destination, recalled=True
                        )
                    )
            continue
        for destination in _placement_destinations(state, player, kind):
            _, resulting_height = _board_after_basic_placement(
                state, player, kind, destination
            )
            if resulting_height == MAX_STACK_HEIGHT and not state.height_three_unlocked[player]:
                continue
            actions.extend(_actions_for_placed_piece(state, player, kind, destination, recalled=False))
    return actions


def _discard_stack(state: GameState, stack: Stack) -> None:
    for piece in stack:
        state.discards[piece.owner][piece.kind] += 1


def _apply_placement(
    state: GameState,
    player: Player,
    kind: PieceType,
    destination: Square,
    effect_target: Square | None,
) -> None:
    existing = state.board.get(destination)
    if kind is PieceType.REINFORCEMENT:
        assert existing is not None
        state.board[destination] = (Piece(player, kind),) + existing
    elif kind is PieceType.SPY and existing and existing[-1].owner is player.opponent:
        _discard_stack(state, existing)
        replacements: list[Piece] = []
        for old_piece in existing:  # Preserve bottom-to-top order.
            state.reserves[player][old_piece.kind] -= 1
            replacements.append(Piece(player, old_piece.kind))
        state.board[destination] = tuple(replacements) + (Piece(player, kind),)
    elif existing:
        state.board[destination] = existing + (Piece(player, kind),)
    else:
        state.board[destination] = (Piece(player, kind),)

    if effect_target is not None:
        target = state.board[effect_target]
        firing_height = len(state.board[destination])
        if (
            firing_height < len(target)
            and state.rules.artillery_vs_taller == "target_bottom_attrition"
        ):
            removed = target[:firing_height]
            state.board[effect_target] = target[firing_height:]
            _discard_stack(state, removed)
        else:
            _discard_stack(state, state.board.pop(effect_target))


def _apply_legal_action(
    state: GameState, action: Action, *, adjudicate_draw: bool
) -> GameState:
    result = state.copy()
    player = state.turn
    was_development = state.in_development
    if isinstance(action, MoveAction):
        moving = result.board.pop(action.source)
        captured = result.board.get(action.destination)
        if captured:
            if (
                moving[-1].kind is not PieceType.SOVEREIGN
                and len(moving) < len(captured)
                and state.rules.move_vs_taller == "mutual_bottom_attrition"
            ):
                removed_defenders = captured[:len(moving)]
                result.board[action.destination] = captured[len(moving):]
                _discard_stack(result, moving)
                _discard_stack(result, removed_defenders)
            else:
                result.board.pop(action.destination)
                _discard_stack(result, captured)
                if any(piece.kind is PieceType.SOVEREIGN for piece in captured):
                    result.winner = player
                result.board[action.destination] = moving
        else:
            result.board[action.destination] = moving
        if (
            state.rules.height_three_requires_nonsovereign_move
            and moving[-1].kind is not PieceType.SOVEREIGN
        ):
            result.height_three_unlocked[player] = True
        if (
            state.rules.infiltration_victory
            and moving[-1].kind is PieceType.SOVEREIGN
            and action.destination[1]
            == (BOARD_SIZE - 1 if player is Player.WHITE else 0)
        ):
            result.winner = player
    elif isinstance(action, RecallAction):
        result.reserves[player][PieceType.RECALL] -= 1
        result.discards[player][PieceType.RECALL] += 1
        result.discards[player][action.piece] -= 1
        _apply_placement(result, player, action.piece, action.destination, action.effect_target)
    else:
        result.reserves[player][action.piece] -= 1
        _apply_placement(result, player, action.piece, action.destination, action.effect_target)

    if was_development:
        result.development_placements[player] += 1

    if (
        not was_development
        and state.rules.height_three_requires_shared_neutral_presence
        and any(3 <= square[1] <= 5 for square in result.board)
    ):
        result.height_three_unlocked = {
            Player.WHITE: True,
            Player.BLACK: True,
        }

    result.ply += 1
    if result.winner is None:
        result.turn = player.opponent
        if adjudicate_draw and not legal_actions(result):
            result.is_draw = True
    return result


def apply_action(state: GameState, action: Action) -> GameState:
    if state.is_over:
        raise ValueError("the game is already over")
    if action not in legal_actions(state):
        raise ValueError(f"illegal action: {action!r}")
    return _apply_legal_action(state, action, adjudicate_draw=True)


def preview_action(state: GameState, action: Action) -> GameState:
    """Apply an already-generated legal action without draw adjudication.

    This is intended for inexpensive one-ply policy evaluation. Callers must
    pass an action returned by ``legal_actions(state)``.
    """
    if state.is_over:
        raise ValueError("the game is already over")
    return _apply_legal_action(state, action, adjudicate_draw=False)


def is_sovereign_threatened(state: GameState, player: Player) -> bool:
    """Return whether an enemy stack could capture ``player``'s Sovereign by MOVE."""
    sovereign_square = next(
        (
            square
            for square, stack in state.board.items()
            if stack[-1].owner is player and stack[-1].kind is PieceType.SOVEREIGN
        ),
        None,
    )
    if sovereign_square is None:
        return False
    return any(
        sovereign_square in _movement_destinations(state, source)
        for source, stack in state.board.items()
        if stack[-1].owner is player.opponent
    )


def stack_controls_square(state: GameState, source: Square, target: Square) -> bool:
    """Return whether a mobile stack projects its movement line onto ``target``.

    Unlike a legal MOVE query, this treats a friendly occupied target as
    controlled. That distinction lets policies recognize protected attackers,
    batteries, and unsafe Royal Attacks without changing the game rules.
    """
    if source == target or source not in state.board or not _on_board(target):
        return False
    stack = state.board[source]
    top = stack[-1]
    height = len(stack)
    movement = PIECE_CONFIG[top.kind]["movement"]
    if movement["mode"] == "immobile":
        return False
    dx = target[0] - source[0]
    dy = target[1] - source[1]
    if movement["mode"] == "leap":
        return (abs(dx), abs(dy)) in {
            tuple(vector)
            for vector in movement["vectors_by_height"][str(height)]
        }
    directions = _directions(movement["direction_mode"], top.owner)
    direction = next(
        (
            (step_x, step_y, distance)
            for step_x, step_y in directions
            for distance in range(1, _movement_range(movement["range_mode"], height) + 1)
            if (step_x * distance, step_y * distance) == (dx, dy)
        ),
        None,
    )
    if direction is None:
        return False
    step_x, step_y, distance = direction
    return all(
        (source[0] + step_x * step, source[1] + step_y * step) not in state.board
        for step in range(1, distance)
    )


def validate_state(state: GameState, enforce_inventory: bool = False) -> None:
    """Raise ValueError if a core rules invariant is broken."""
    for square, stack in state.board.items():
        if not _on_board(square):
            raise ValueError(f"off-board square: {square}")
        if not 1 <= len(stack) <= MAX_STACK_HEIGHT:
            raise ValueError(f"invalid stack height at {square_name(square)}")
        owners = {piece.owner for piece in stack}
        if len(owners) != 1:
            raise ValueError(f"mixed ownership at {square_name(square)}")
        if any(piece.kind is PieceType.SOVEREIGN for piece in stack) and len(stack) != 1:
            raise ValueError(f"stacked Sovereign at {square_name(square)}")
        if any(piece.kind is PieceType.RECALL for piece in stack):
            raise ValueError(f"Recall may not remain on board at {square_name(square)}")
        if stack[-1].kind is PieceType.REINFORCEMENT:
            raise ValueError(
                f"Reinforcement may not be the TOP piece at {square_name(square)}"
            )
    for player in Player:
        for collection in (state.reserves[player], state.discards[player]):
            if any(count < 0 for count in collection.values()):
                raise ValueError(f"negative piece count for {player.value}")
        if enforce_inventory:
            actual = Counter(state.reserves[player]) + Counter(state.discards[player])
            for stack in state.board.values():
                actual.update(piece.kind for piece in stack if piece.owner is player)
            if +actual != +STARTING_COUNTS:
                raise ValueError(
                    f"piece inventory mismatch for {player.value}: {+actual}"
                )
