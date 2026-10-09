"""Fast stochastic action-selection policies for rules pressure testing."""

from __future__ import annotations

import random
import math
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Protocol, Sequence, TypeVar

from .engine import (
    Action,
    BOARD_SIZE,
    GameState,
    MoveAction,
    PieceType,
    Player,
    RecallAction,
    is_sovereign_threatened,
    legal_actions,
    preview_action,
    stack_controls_square,
)


PIECE_VALUES: dict[PieceType, float] = {
    PieceType.INFANTRY: 1.0,
    PieceType.REINFORCEMENT: 1.5,
    PieceType.DRAGOON: 3.0,
    PieceType.CHARIOT: 3.0,
    PieceType.BALLISTA: 3.5,
    PieceType.TREBUCHET: 3.5,
    PieceType.SPY: 4.0,
    PieceType.GRIFFIN: 4.5,
    PieceType.MARSHAL: 5.0,
    PieceType.RECALL: 5.0,
    PieceType.SOVEREIGN: 1000.0,
}

IMMOBILE_TOPS = {PieceType.SPY, PieceType.BALLISTA, PieceType.TREBUCHET}
T = TypeVar("T")


def _removed_target_pieces(state: GameState, action: Action):
    """Return the enemy pieces this action actually removes under its ruleset."""
    if isinstance(action, MoveAction):
        target = state.board.get(action.destination)
        if target is None:
            return ()
        attacker = state.board[action.source]
        attacker_height = len(attacker)
        if (
            attacker[-1].kind is not PieceType.SOVEREIGN
            and
            attacker_height < len(target)
            and state.rules.move_vs_taller == "mutual_bottom_attrition"
        ):
            return target[:attacker_height]
        return target
    if action.effect_target is not None:
        target = state.board[action.effect_target]
        existing = state.board.get(action.destination)
        firing_height = 1 + (len(existing) if existing else 0)
        if (
            firing_height < len(target)
            and state.rules.artillery_vs_taller == "target_bottom_attrition"
        ):
            return target[:firing_height]
        return target
    if action.piece is PieceType.SPY:
        target = state.board.get(action.destination)
        if target and target[-1].owner is state.turn.opponent:
            return target
    return ()


def _own_move_attrition_pieces(state: GameState, action: Action):
    if not isinstance(action, MoveAction):
        return ()
    attacker = state.board[action.source]
    target = state.board.get(action.destination)
    if (
        target
        and attacker[-1].kind is not PieceType.SOVEREIGN
        and len(attacker) < len(target)
        and state.rules.move_vs_taller == "mutual_bottom_attrition"
    ):
        return attacker
    return ()


def _sovereign_square(state: GameState, player: Player) -> tuple[int, int] | None:
    return next(
        (
            square
            for square, stack in state.board.items()
            if stack[-1].owner is player and stack[-1].kind is PieceType.SOVEREIGN
        ),
        None,
    )


def sovereign_attack_profile(state: GameState, attacker: Player) -> tuple[int, int]:
    """Return attacking sources and how many are protected by another stack."""
    sovereign = _sovereign_square(state, attacker.opponent)
    if sovereign is None:
        return 0, 0
    sources = [
        square
        for square, stack in state.board.items()
        if stack[-1].owner is attacker and stack_controls_square(state, square, sovereign)
    ]
    protected = sum(
        any(
            other != source
            and stack[-1].owner is attacker
            and stack_controls_square(state, other, source)
            for other, stack in state.board.items()
        )
        for source in sources
    )
    return len(sources), protected


def valuable_burial_value(state: GameState, action: Action) -> float:
    """Material value made permanently subordinate by a normal TOP placement."""
    if isinstance(action, MoveAction) or action.piece is PieceType.REINFORCEMENT:
        return 0.0
    existing = state.board.get(action.destination)
    if not existing or existing[-1].owner is not state.turn:
        return 0.0
    return sum(
        PIECE_VALUES[piece.kind]
        for piece in existing
        if piece.kind not in {PieceType.INFANTRY, PieceType.REINFORCEMENT}
    )


def is_royal_interposition_trap(state: GameState, action: Action) -> bool:
    """Detect a cheap block that baits an attacker into a safe Royal Attack."""
    if (
        isinstance(action, MoveAction)
        or action.piece not in {PieceType.INFANTRY, PieceType.REINFORCEMENT}
        or not is_sovereign_threatened(state, state.turn)
    ):
        return False
    defender = state.turn
    blocked_square = action.destination
    blocked = preview_action(state, action)
    if is_sovereign_threatened(blocked, defender):
        return False
    for reply in legal_actions(blocked):
        if not isinstance(reply, MoveAction) or reply.destination != blocked_square:
            continue
        after_reply = preview_action(blocked, reply)
        sovereign = _sovereign_square(after_reply, defender)
        if sovereign is None:
            continue
        if len(after_reply.board.get(blocked_square, ())) <= 1:
            continue
        royal_replies = [
            candidate
            for candidate in legal_actions(after_reply)
            if isinstance(candidate, MoveAction)
            and candidate.source == sovereign
            and candidate.destination == blocked_square
        ]
        if any(
            not is_sovereign_threatened(preview_action(after_reply, royal), defender)
            for royal in royal_replies
        ):
            return True
    return False


def action_purpose_count(state: GameState, action: Action, result: GameState) -> int:
    """Count distinct useful jobs performed by one action."""
    player = state.turn
    purposes = 0
    if _removed_target_pieces(state, action):
        purposes += 1
    if is_sovereign_threatened(state, player) and not is_sovereign_threatened(result, player):
        purposes += 1
    if not is_sovereign_threatened(state, player.opponent) and is_sovereign_threatened(result, player.opponent):
        purposes += 1

    destination = action.destination
    own_sovereign = _sovereign_square(result, player)
    if (
        own_sovereign is not None
        and destination in result.board
        and result.board[destination][-1].owner is player
        and stack_controls_square(result, destination, own_sovereign)
    ):
        purposes += 1

    resulting_stack = result.board.get(destination)
    if resulting_stack and resulting_stack[-1].owner is player:
        if len(resulting_stack) == 2 and all(
            piece.kind in {PieceType.INFANTRY, PieceType.REINFORCEMENT}
            for piece in resulting_stack
        ):
            purposes += 1
        if len(resulting_stack) == 3:
            purposes += 1
    return purposes


def _vector_piece_weight(
    state: GameState, piece: PieceType, destination: tuple[int, int]
) -> float:
    """Prefer Chariots on straight Sovereign vectors and Dragoons on diagonals."""
    enemy_sovereign = _sovereign_square(state, state.turn.opponent)
    if enemy_sovereign is None:
        return 1.0
    dx = abs(destination[0] - enemy_sovereign[0])
    dy = abs(destination[1] - enemy_sovereign[1])
    straight = dx == 0 or dy == 0
    diagonal = dx == dy
    if piece is PieceType.CHARIOT:
        return 1.8 if straight else (0.82 if diagonal else 1.0)
    if piece is PieceType.DRAGOON:
        return 1.8 if diagonal else (0.82 if straight else 1.0)
    if piece is PieceType.MARSHAL and (straight or diagonal):
        return 1.2
    return 1.0


def is_free_capture(
    state: GameState, action: Action, result: GameState | None = None
) -> bool:
    """Return whether a capture is safe, favorable, and not MOVE-recapturable."""
    removed = _removed_target_pieces(state, action)
    if not removed:
        return False
    if (
        not isinstance(action, MoveAction)
        and action.piece in {PieceType.BALLISTA, PieceType.TREBUCHET}
    ):
        # A SHOOT may be tactically safe, but it commits a scarce artillery
        # token from reserve and therefore is not an automatic free capture.
        return False
    if result is None:
        result = preview_action(state, action)
    player = state.turn
    if is_sovereign_threatened(result, player):
        return False
    removed_value = sum(
        0.0 if piece.kind is PieceType.SOVEREIGN else PIECE_VALUES[piece.kind]
        for piece in removed
    )
    own_loss_value = sum(
        PIECE_VALUES[piece.kind]
        for piece in _own_move_attrition_pieces(state, action)
    )
    if removed_value < own_loss_value:
        return False
    actor_square = action.destination
    actor = result.board.get(actor_square)
    if not actor or actor[-1].owner is not player:
        return False
    return not any(
        stack[-1].owner is player.opponent
        and stack_controls_square(result, square, actor_square)
        for square, stack in result.board.items()
    )


@dataclass(frozen=True, slots=True)
class OpeningPlan:
    """A soft development objective, not a fixed opening script."""

    name: str
    target_stacks: int
    file_mode: str
    rank_weights: tuple[float, float, float]
    piece_weights: dict[PieceType, float]


MOBILE_DEVELOPMENT_WEIGHTS = {
    PieceType.INFANTRY: 1.0,
    PieceType.REINFORCEMENT: 0.7,
    PieceType.DRAGOON: 1.2,
    PieceType.CHARIOT: 1.2,
    PieceType.GRIFFIN: 1.2,
    PieceType.MARSHAL: 1.2,
}


def _opening_plan(
    name: str,
    target_stacks: int,
    file_mode: str,
    rank_weights: tuple[float, float, float],
    **piece_weights: float,
) -> OpeningPlan:
    weights = dict(MOBILE_DEVELOPMENT_WEIGHTS)
    for kind_name, weight in piece_weights.items():
        weights[PieceType(kind_name)] = weight
    return OpeningPlan(name, target_stacks, file_mode, rank_weights, weights)


# Every plan leaves several near-equal legal choices. The structural target is
# deliberate, while the exact files, ranks, and piece order remain stochastic.
OPENING_PLANS: dict[str, dict[str, OpeningPlan]] = {
    "tactical": {
        "balanced": _opening_plan("balanced", 4, "spread", (1.0, 1.25, 1.55)),
        "central": _opening_plan("central", 3, "center", (0.9, 1.25, 1.7), chariot=1.5, marshal=1.45),
        "wing": _opening_plan("wing", 3, "wing", (0.8, 1.25, 1.8), dragoon=1.55, griffin=1.5),
    },
    "material_control": {
        "wide": _opening_plan("wide", 4, "spread", (0.8, 1.25, 1.85), infantry=1.35, chariot=1.4, dragoon=1.4),
        "central": _opening_plan("central", 3, "center", (0.9, 1.35, 1.7), chariot=1.55, marshal=1.55),
        "mobile": _opening_plan("mobile", 3, "spread", (0.8, 1.2, 1.9), dragoon=1.6, griffin=1.55, marshal=1.5),
    },
    "spy_rush": {
        "wide": _opening_plan("wide", 4, "spread", (0.75, 1.2, 1.95), dragoon=1.5, chariot=1.4),
        "spearhead": _opening_plan("spearhead", 3, "center", (0.65, 1.1, 2.15), marshal=1.55, chariot=1.45),
        "staging": _opening_plan("staging", 3, "spread", (0.85, 1.35, 1.7), griffin=1.55, dragoon=1.45),
    },
    "artillery_rush": {
        "screen": _opening_plan("screen", 4, "spread", (0.7, 1.15, 2.1), infantry=1.6, chariot=1.35),
        "lanes": _opening_plan("lanes", 4, "lanes", (0.8, 1.25, 1.9), infantry=1.4, marshal=1.35),
        "platform": _opening_plan("platform", 3, "center", (0.75, 1.2, 2.0), chariot=1.55, marshal=1.45),
    },
    "height_rush": {
        "double": _opening_plan("double", 2, "spread", (0.9, 1.25, 1.65), marshal=1.55, dragoon=1.5),
        "split": _opening_plan("split", 3, "spread", (0.8, 1.25, 1.8), chariot=1.45, dragoon=1.45),
        "griffin": _opening_plan("griffin", 2, "center", (0.85, 1.25, 1.75), griffin=2.5, marshal=1.45),
    },
    "sovereign_race": {
        "spearhead": _opening_plan("spearhead", 3, "center", (0.6, 1.05, 2.35), marshal=1.7, chariot=1.55),
        "wing": _opening_plan("wing", 3, "wing", (0.6, 1.05, 2.35), dragoon=1.7, griffin=1.65),
        "dual": _opening_plan("dual", 2, "spread", (0.7, 1.15, 2.05), marshal=1.6, dragoon=1.55),
    },
    "sovereign_defense": {
        "intercept": _opening_plan("intercept", 3, "center", (2.0, 1.35, 0.85), chariot=1.65, marshal=1.55, infantry=1.35),
    },
}


class Policy(Protocol):
    name: str

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action: ...


def reserve_ratio(state: GameState, player: Player) -> float:
    return min(1.0, max(0.0, sum(state.reserves[player].values()) / 23.0))


def game_phase(state: GameState, player: Player) -> str:
    ratio = reserve_ratio(state, player)
    if ratio > 0.66:
        return "opening"
    if ratio > 0.25:
        return "middle"
    return "ending"


def _weighted_choice(items: Sequence[T], weights: Sequence[float], rng: random.Random) -> T:
    if not items:
        raise ValueError("cannot choose from an empty sequence")
    return rng.choices(items, weights=[max(0.0001, weight) for weight in weights], k=1)[0]


@dataclass(slots=True)
class UniformPolicy:
    name: str = "uniform"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        del state
        return rng.choice(actions)


@dataclass(slots=True)
class HeuristicPolicy:
    """Phase-aware, tactical, weighted-random policy with no game-tree search."""

    tactical_blunder_rate: float = 0.03
    name: str = "heuristic"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        if not actions:
            raise ValueError("cannot choose without legal actions")

        sovereign_captures = [
            action for action in actions if self._captures_sovereign(state, action)
        ]
        if sovereign_captures:
            return rng.choice(sovereign_captures)
        other_wins = [action for action in actions if self._wins_game(state, action)]
        if other_wins:
            return rng.choice(other_wins)

        candidates = list(actions)
        preview_cache: dict[Action, GameState] = {}

        def preview(action: Action) -> GameState:
            if action not in preview_cache:
                preview_cache[action] = preview_action(state, action)
            return preview_cache[action]

        # A player under immediate threat almost always chooses an action that
        # removes it, but the small error rate keeps rule exploration alive.
        if is_sovereign_threatened(state, state.turn):
            safe = [
                action
                for action in candidates
                if not is_sovereign_threatened(preview(action), state.turn)
            ]
            if safe and rng.random() >= self.tactical_blunder_rate:
                candidates = safe

        # Keep non-converting Spy placements legal, but do not treat an
        # immobile one-copy deployment as a normal strategic choice when the
        # player has another viable action.
        without_idle_spy = [
            action
            for action in candidates
            if not self._is_nonconverting_spy_placement(state, action)
        ]
        if without_idle_spy:
            candidates = without_idle_spy

        moves = [action for action in candidates if isinstance(action, MoveAction)]
        placements = [action for action in candidates if not isinstance(action, MoveAction)]
        chosen_family = self._choose_family(state, moves, placements, rng)

        # Choose a piece type before a destination so pieces with more legal
        # squares are not selected merely because they create more actions.
        grouped: dict[PieceType, list[Action]] = defaultdict(list)
        for action in chosen_family:
            if isinstance(action, MoveAction):
                kind = state.board[action.source][-1].kind
            else:
                kind = action.piece
            grouped[kind].append(action)

        group_kinds = list(grouped)
        base_scored: dict[Action, float] = {}
        group_weights: list[float] = []
        for kind in group_kinds:
            group_actions = grouped[kind]
            for action in group_actions:
                base_scored[action] = self._base_action_weight(state, action)
            # The best opportunity influences piece selection, but the number
            # of destinations does not.
            group_weights.append(max(base_scored[action] for action in group_actions))

        chosen_kind = _weighted_choice(group_kinds, group_weights, rng)
        choices = grouped[chosen_kind]
        final_weights = [
            self._sovereign_context_weight(
                state, base_scored[action], preview(action)
            )
            for action in choices
        ]
        return _weighted_choice(choices, final_weights, rng)

    def _choose_family(
        self,
        state: GameState,
        moves: list[Action],
        placements: list[Action],
        rng: random.Random,
    ) -> list[Action]:
        if not moves:
            return placements
        if not placements:
            return moves
        ratio = reserve_ratio(state, state.turn)
        place_probability = 0.15 + 0.75 * ratio**1.5
        move_tactical = any(self._is_tactical(state, action) for action in moves)
        place_tactical = any(self._is_tactical(state, action) for action in placements)
        move_weight = (1.0 - place_probability) * (2.5 if move_tactical else 1.0)
        place_weight = place_probability * (2.5 if place_tactical else 1.0)
        family = _weighted_choice(
            [moves, placements], [move_weight, place_weight], rng
        )
        return family

    @staticmethod
    def _captures_sovereign(state: GameState, action: Action) -> bool:
        if not isinstance(action, MoveAction):
            return False
        target = state.board.get(action.destination)
        return bool(target and target[-1].kind is PieceType.SOVEREIGN)

    @staticmethod
    def _wins_game(state: GameState, action: Action) -> bool:
        if HeuristicPolicy._captures_sovereign(state, action):
            return True
        if not state.rules.infiltration_victory or not isinstance(action, MoveAction):
            return False
        moving = state.board[action.source]
        enemy_back_rank = 8 if state.turn is Player.WHITE else 0
        return (
            moving[-1].kind is PieceType.SOVEREIGN
            and action.destination[1] == enemy_back_rank
        )

    @staticmethod
    def _is_nonconverting_spy_placement(state: GameState, action: Action) -> bool:
        if isinstance(action, MoveAction) or action.piece is not PieceType.SPY:
            return False
        target = state.board.get(action.destination)
        return not target or target[-1].owner is not state.turn.opponent

    @staticmethod
    def _is_tactical(state: GameState, action: Action) -> bool:
        if isinstance(action, MoveAction):
            return action.destination in state.board
        existing = state.board.get(action.destination)
        return bool(
            action.effect_target is not None
            or (
                action.piece is PieceType.SPY
                and existing
                and existing[-1].owner is state.turn.opponent
            )
        )

    def _base_action_weight(self, state: GameState, action: Action) -> float:
        if isinstance(action, MoveAction):
            return self._move_weight(state, action)
        return self._placement_weight(state, action)

    def _sovereign_context_weight(
        self, state: GameState, weight: float, result: GameState
    ) -> float:
        player = state.turn
        if is_sovereign_threatened(result, player):
            weight *= self.tactical_blunder_rate
        if is_sovereign_threatened(result, player.opponent):
            weight *= 2.5
        return max(0.05, weight)

    def _move_weight(self, state: GameState, action: MoveAction) -> float:
        stack = state.board[action.source]
        top = stack[-1]
        weight = 1.0
        target = state.board.get(action.destination)
        if target:
            captured_value = sum(
                PIECE_VALUES[piece.kind]
                for piece in _removed_target_pieces(state, action)
            )
            lost_value = sum(
                PIECE_VALUES[piece.kind]
                for piece in _own_move_attrition_pieces(state, action)
            )
            weight *= max(0.1, 1.0 + 1.5 * captured_value - lost_value)

        forward_progress = (action.destination[1] - action.source[1]) * top.owner.forward
        if forward_progress > 0:
            weight *= 1.0 + 0.08 * forward_progress
        center_distance = abs(action.destination[0] - 4) + abs(action.destination[1] - 4)
        weight *= 1.0 + 0.025 * (8 - center_distance)
        return weight

    def _placement_weight(self, state: GameState, action: Action) -> float:
        assert not isinstance(action, MoveAction)
        player = state.turn
        phase = game_phase(state, player)
        phase_weights: dict[str, dict[PieceType, float]] = {
            "opening": {
                PieceType.INFANTRY: 1.5,
                PieceType.DRAGOON: 1.3,
                PieceType.CHARIOT: 1.3,
                PieceType.GRIFFIN: 1.0,
                PieceType.MARSHAL: 0.85,
                PieceType.REINFORCEMENT: 1.1,
                PieceType.BALLISTA: 0.65,
                PieceType.TREBUCHET: 0.65,
                PieceType.SPY: 0.6,
            },
            "middle": {
                PieceType.INFANTRY: 1.0,
                PieceType.DRAGOON: 1.0,
                PieceType.CHARIOT: 1.0,
                PieceType.GRIFFIN: 1.2,
                PieceType.MARSHAL: 1.2,
                PieceType.REINFORCEMENT: 1.15,
                PieceType.BALLISTA: 0.9,
                PieceType.TREBUCHET: 0.9,
                PieceType.SPY: 0.9,
            },
            "ending": {
                PieceType.INFANTRY: 0.8,
                PieceType.DRAGOON: 1.1,
                PieceType.CHARIOT: 1.1,
                PieceType.GRIFFIN: 1.2,
                PieceType.MARSHAL: 1.2,
                PieceType.REINFORCEMENT: 1.1,
                PieceType.BALLISTA: 0.6,
                PieceType.TREBUCHET: 0.6,
                PieceType.SPY: 0.6,
            },
        }
        weight = phase_weights[phase].get(action.piece, 1.0)
        existing = state.board.get(action.destination)

        if isinstance(action, RecallAction):
            weight *= 1.0 + 0.12 * PIECE_VALUES[action.piece]

        if action.piece is PieceType.REINFORCEMENT:
            assert existing
            top_kind = existing[-1].kind
            weight *= 0.4 if top_kind in IMMOBILE_TOPS else (1.6 if len(existing) == 2 else 1.35)
        elif action.piece is PieceType.SPY:
            if existing and existing[-1].owner is player.opponent:
                target_value = sum(PIECE_VALUES[piece.kind] for piece in existing)
                weight *= 2.0 + target_value
            else:
                weight *= 0.4
        elif action.piece in {PieceType.BALLISTA, PieceType.TREBUCHET}:
            if action.effect_target is not None:
                target_value = sum(
                    PIECE_VALUES[piece.kind]
                    for piece in _removed_target_pieces(state, action)
                )
                weight *= 2.0 + target_value
            else:
                weight *= 0.3
        elif existing:
            if existing[-1].kind in IMMOBILE_TOPS:
                weight *= 2.5
            else:
                weight *= 1.15
            if len(existing) == 2:
                weight *= 1.25
        else:
            center_distance = abs(action.destination[0] - 4) + abs(action.destination[1] - 4)
            weight *= 1.0 + 0.025 * (8 - center_distance)
        return weight


def _immediate_win_action(state: GameState, action: Action) -> bool:
    if isinstance(action, MoveAction):
        target = state.board.get(action.destination)
        if target and target[-1].kind is PieceType.SOVEREIGN:
            return True
        if state.rules.infiltration_victory:
            moving = state.board[action.source]
            enemy_back_rank = 8 if state.turn is Player.WHITE else 0
            return (
                moving[-1].kind is PieceType.SOVEREIGN
                and action.destination[1] == enemy_back_rank
            )
    return False


def _safe_sovereign_flights(state: GameState, player: Player) -> int:
    """Approximate chess-style king mobility without generating a full turn."""
    sovereign = _sovereign_square(state, player)
    if sovereign is None:
        return 0
    safe = 0
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == dy == 0:
                continue
            destination = sovereign[0] + dx, sovereign[1] + dy
            if not (0 <= destination[0] < BOARD_SIZE and 0 <= destination[1] < BOARD_SIZE):
                continue
            occupant = state.board.get(destination)
            if occupant and occupant[-1].owner is player:
                continue
            if any(
                stack[-1].owner is player.opponent
                and square != destination
                and stack_controls_square(state, square, destination)
                for square, stack in state.board.items()
            ):
                continue
            safe += 1
    return safe


def _position_score(state: GameState, perspective: Player) -> float:
    """Fast leaf evaluation shared by all shallow-search policy variants."""
    if state.winner is perspective:
        return 1_000_000.0
    if state.winner is perspective.opponent:
        return -1_000_000.0
    if state.is_draw:
        return 0.0

    score = 0.0
    for player, sign in ((perspective, 1.0), (perspective.opponent, -1.0)):
        score += sign * 0.82 * sum(
            PIECE_VALUES[kind] * count
            for kind, count in state.reserves[player].items()
            if kind is not PieceType.SOVEREIGN
        )
        for stack in state.board.values():
            if stack[-1].owner is not player:
                continue
            for index, piece in enumerate(stack):
                if piece.kind is PieceType.SOVEREIGN:
                    continue
                # TOP material keeps its full agency. Buried premium material
                # still counts, but is less useful until attrition exposes it.
                agency = 1.0 if index == len(stack) - 1 else 0.58
                score += sign * agency * PIECE_VALUES[piece.kind]

    own_sovereign = _sovereign_square(state, perspective)
    enemy_sovereign = _sovereign_square(state, perspective.opponent)
    if own_sovereign is not None and enemy_sovereign is not None:
        own_progress = own_sovereign[1] if perspective is Player.WHITE else 8 - own_sovereign[1]
        enemy_progress = enemy_sovereign[1] if perspective.opponent is Player.WHITE else 8 - enemy_sovereign[1]
        score += 1.5 * (own_progress - enemy_progress)

    if is_sovereign_threatened(state, perspective):
        score -= 95.0
    if is_sovereign_threatened(state, perspective.opponent):
        score += 95.0

    own_sources, own_protected = sovereign_attack_profile(state, perspective)
    enemy_sources, enemy_protected = sovereign_attack_profile(state, perspective.opponent)
    score += 18.0 * (own_sources - enemy_sources)
    score += 13.0 * (own_protected - enemy_protected)

    own_flights = _safe_sovereign_flights(state, perspective)
    enemy_flights = _safe_sovereign_flights(state, perspective.opponent)
    score += 5.0 * (own_flights - enemy_flights)
    if enemy_flights <= 2:
        score += 12.0 * (3 - enemy_flights)
    if own_flights <= 2:
        score -= 12.0 * (3 - own_flights)
    return score


@dataclass(slots=True)
class TacticalSearchPolicy:
    """Bounded two-ply search wrapped around an existing strategic policy."""

    base: Policy
    max_root_candidates: int = 6
    max_reply_candidates: int = 6
    policy_samples: int = 3
    near_best_margin: float = 5.0
    override_threshold: float = 16.0
    name: str = "tactical_search"
    last_search_info: dict[str, object] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.name = self.base.name
        self.last_search_info = {}

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        if not actions:
            raise ValueError("cannot choose without legal actions")

        sovereign_wins = [
            action
            for action in actions
            if isinstance(action, MoveAction)
            and (target := state.board.get(action.destination)) is not None
            and target[-1].kind is PieceType.SOVEREIGN
        ]
        if sovereign_wins:
            chosen = rng.choice(sovereign_wins)
            self.last_search_info = {
                "searched": False, "overrode": False, "reason": "sovereign_capture",
            }
            return chosen
        other_wins = [action for action in actions if _immediate_win_action(state, action)]
        if other_wins:
            chosen = rng.choice(other_wins)
            self.last_search_info = {
                "searched": False, "overrode": False, "reason": "immediate_win",
            }
            return chosen

        baseline = self.base.choose(state, actions, rng)
        if state.in_development:
            self.last_search_info = {
                "searched": False, "overrode": False, "reason": "opening",
            }
            return baseline

        root = state.turn
        previews = {action: preview_action(state, action) for action in actions}
        safe_actions = [
            action for action in actions
            if not is_sovereign_threatened(previews[action], root)
        ]
        eligible = safe_actions or list(actions)

        policy_choices = {baseline}
        for _ in range(max(0, self.policy_samples - 1)):
            policy_choices.add(self.base.choose(state, actions, rng))
        ranked = sorted(
            eligible,
            key=lambda action: _position_score(previews[action], root),
            reverse=True,
        )
        candidates = [action for action in policy_choices if action in eligible]
        for action in ranked:
            if action not in candidates:
                candidates.append(action)
            if len(candidates) >= self.max_root_candidates:
                break

        scored: dict[Action, float] = {}
        reply_nodes = 0
        quiescence_nodes = 0
        immediate_loss: dict[Action, bool] = {}
        for action in candidates:
            result = previews[action]
            replies = legal_actions(result)
            if not replies:
                scored[action] = _position_score(result, root)
                immediate_loss[action] = result.winner is root.opponent
                continue
            losing_replies = [reply for reply in replies if _immediate_win_action(result, reply)]
            if losing_replies:
                scored[action] = -1_000_000.0
                immediate_loss[action] = True
                reply_nodes += len(losing_replies)
                continue
            immediate_loss[action] = False
            replies = sorted(
                replies,
                key=lambda reply: self._reply_priority(result, reply, root),
                reverse=True,
            )[: self.max_reply_candidates]
            reply_leaves: list[tuple[float, GameState]] = []
            for reply in replies:
                reply_nodes += 1
                leaf = preview_action(result, reply)
                reply_leaves.append((_position_score(leaf, root), leaf))
            if reply_leaves:
                worst_score, worst_leaf = min(reply_leaves, key=lambda item: item[0])
                # Extend only the principal tactical reply, and only when it
                # directly threatens the acting Sovereign. This avoids the
                # horizon problem without expanding every capture branch.
                if is_sovereign_threatened(worst_leaf, root):
                    worst_score, extra_nodes = self._quiescent_score(worst_leaf, root)
                    quiescence_nodes += extra_nodes
                scored[action] = worst_score
            else:
                scored[action] = _position_score(result, root)

        best = max(scored.values())
        near_best = [
            action for action, score in scored.items()
            if score >= best - self.near_best_margin
        ]
        weights = [math.exp((scored[action] - best) / 3.0) for action in near_best]
        baseline_score = scored.get(baseline, _position_score(previews[baseline], root))
        baseline_was_eligible = baseline in scored
        if (
            baseline_was_eligible
            and not immediate_loss.get(baseline, False)
            and best < baseline_score + self.override_threshold
        ):
            chosen = baseline
        else:
            chosen = _weighted_choice(near_best, weights, rng)
        reason = self._override_reason(
            state, baseline, chosen, previews, immediate_loss, baseline_score, scored[chosen]
        )
        self.last_search_info = {
            "searched": True,
            "overrode": chosen != baseline,
            "reason": reason,
            "root_candidates": len(candidates),
            "reply_nodes": reply_nodes,
            "quiescence_nodes": quiescence_nodes,
            "baseline_score": baseline_score,
            "chosen_score": scored[chosen],
        }
        return chosen

    @staticmethod
    def _reply_priority(state: GameState, action: Action, root: Player) -> float:
        if _immediate_win_action(state, action):
            return 1_000_000.0
        priority = 12.0 * sum(
            PIECE_VALUES[piece.kind] for piece in _removed_target_pieces(state, action)
        )
        if not isinstance(action, MoveAction) and action.effect_target is not None:
            priority += 18.0
        root_sovereign = _sovereign_square(state, root)
        if root_sovereign is not None:
            priority += max(
                0.0,
                10.0
                - abs(action.destination[0] - root_sovereign[0])
                - abs(action.destination[1] - root_sovereign[1]),
            )
        return priority

    def _quiescent_score(
        self, state: GameState, root: Player
    ) -> tuple[float, int]:
        if state.is_over:
            return _position_score(state, root), 0
        threatened = is_sovereign_threatened(state, root)
        if not threatened:
            return _position_score(state, root), 0
        forcing = []
        for action in legal_actions(state):
            result = preview_action(state, action)
            if (
                _immediate_win_action(state, action)
                or (threatened and not is_sovereign_threatened(result, root))
            ):
                forcing.append((action, result))
        if not forcing:
            return _position_score(state, root), 0
        forcing.sort(key=lambda item: _position_score(item[1], root), reverse=True)
        selected = forcing[: self.max_reply_candidates]
        return max(_position_score(result, root) for _, result in selected), len(selected)

    @staticmethod
    def _override_reason(
        state: GameState,
        baseline: Action,
        chosen: Action,
        previews: dict[Action, GameState],
        immediate_loss: dict[Action, bool],
        baseline_score: float,
        chosen_score: float,
    ) -> str:
        if chosen == baseline:
            return "confirmed"
        if immediate_loss.get(baseline, False) and not immediate_loss.get(chosen, False):
            return "avoided_immediate_loss"
        if _removed_target_pieces(state, chosen):
            return "preferred_capture"
        if (
            is_sovereign_threatened(previews[chosen], state.turn.opponent)
            and not is_sovereign_threatened(previews[baseline], state.turn.opponent)
        ):
            return "preferred_sovereign_pressure"
        if chosen_score > baseline_score + 20.0:
            return "avoided_tactical_loss"
        return "improved_reply_score"


@dataclass(slots=True)
class PlannedPolicy:
    """Use a development plan, then hand control to a normal game policy."""

    base: Policy
    plan: OpeningPlan
    mirror: bool = False
    name: str = "planned"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        if not state.in_development:
            return self.base.choose(state, actions, rng)

        player = state.turn
        own_stacks = {
            square: stack
            for square, stack in state.board.items()
            if stack[-1].owner is player and stack[-1].kind is not PieceType.SOVEREIGN
        }
        need_new_stack = len(own_stacks) < self.plan.target_stacks
        scored: list[Action] = []
        weights: list[float] = []
        for action in actions:
            if isinstance(action, MoveAction):
                continue
            existing = state.board.get(action.destination)
            is_own_stack = bool(existing and existing[-1].owner is player)
            # Structure is the defining experimental variable. Keep exact
            # squares and pieces soft, but make accidental profile misses rare.
            structure_weight = 1.0 if need_new_stack == (not is_own_stack) else 0.0001

            file, rank = action.destination
            relative_rank = rank if player is Player.WHITE else 8 - rank
            rank_weight = self.plan.rank_weights[relative_rank]
            distance_from_center = abs(file - 4)
            if self.plan.file_mode == "center":
                file_weight = (1.8, 1.55, 1.3, 1.1, 0.9)[distance_from_center]
            elif self.plan.file_mode == "wing":
                oriented_file = 8 - file if self.mirror else file
                file_weight = 0.75 + 0.16 * oriented_file
            elif self.plan.file_mode == "lanes":
                file_weight = 1.55 if file in {1, 4, 7} else 0.9
            else:
                occupied_files = [square[0] for square in own_stacks]
                separation = min((abs(file - other) for other in occupied_files), default=4)
                file_weight = 1.0 + 0.18 * separation

            piece_weight = self.plan.piece_weights.get(action.piece, 0.2)
            if is_own_stack and action.piece is PieceType.REINFORCEMENT:
                piece_weight *= 0.75
            scored.append(action)
            weights.append(structure_weight * rank_weight * file_weight * piece_weight)
        if not scored:
            return self.base.choose(state, actions, rng)
        return _weighted_choice(scored, weights, rng)


def opening_plan_names(policy_name: str) -> tuple[str, ...]:
    return tuple(OPENING_PLANS.get(policy_name, ()))


def opening_target_profile(policy_name: str, plan_name: str) -> tuple[int, ...] | None:
    plan = OPENING_PLANS.get(policy_name, {}).get(plan_name)
    if plan is None:
        return None
    stacked_pieces = 4 - plan.target_stacks
    return tuple(sorted([2] * stacked_pieces + [1] * (plan.target_stacks - stacked_pieces)))


@dataclass(slots=True)
class SpyRushPolicy(HeuristicPolicy):
    name: str = "spy_rush"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._wins_game(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            conversions = [
                action
                for action in actions
                if not isinstance(action, MoveAction)
                and action.piece is PieceType.SPY
                and (target := state.board.get(action.destination)) is not None
                and target[-1].owner is state.turn.opponent
            ]
            if conversions:
                weights = [
                    sum(PIECE_VALUES[piece.kind] for piece in state.board[action.destination])
                    for action in conversions
                ]
                return _weighted_choice(conversions, weights, rng)

            mobile_tops = {
                PieceType.INFANTRY,
                PieceType.DRAGOON,
                PieceType.CHARIOT,
                PieceType.GRIFFIN,
                PieceType.MARSHAL,
            }
            covers = [
                action
                for action in actions
                if not isinstance(action, MoveAction)
                and action.piece in mobile_tops
                and (stack := state.board.get(action.destination)) is not None
                and stack[-1].owner is state.turn
                and stack[-1].kind is PieceType.SPY
            ]
            if covers:
                return _weighted_choice(
                    covers,
                    [PIECE_VALUES[action.piece] for action in covers],
                    rng,
                )
        return super().choose(state, actions, rng)


@dataclass(slots=True)
class ArtilleryRushPolicy(HeuristicPolicy):
    name: str = "artillery_rush"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            shots = [
                action
                for action in actions
                if not isinstance(action, MoveAction)
                and action.piece in {PieceType.BALLISTA, PieceType.TREBUCHET}
                and action.effect_target is not None
            ]
            if shots:
                return _weighted_choice(
                    shots,
                    [
                        sum(
                            PIECE_VALUES[piece.kind]
                            for piece in _removed_target_pieces(state, action)
                        )
                        for action in shots
                    ],
                    rng,
                )
        return super().choose(state, actions, rng)


@dataclass(slots=True)
class TurtlePolicy(HeuristicPolicy):
    name: str = "turtle"

    def _choose_family(
        self,
        state: GameState,
        moves: list[Action],
        placements: list[Action],
        rng: random.Random,
    ) -> list[Action]:
        if not moves:
            return placements
        if not placements:
            return moves
        ratio = reserve_ratio(state, state.turn)
        place_probability = min(0.95, 0.25 + 0.75 * ratio**1.2)
        return _weighted_choice(
            [moves, placements],
            [1.0 - place_probability, place_probability],
            rng,
        )

    @staticmethod
    def _own_territory(player: Player, rank: int) -> bool:
        return rank <= 2 if player is Player.WHITE else rank >= 6

    @staticmethod
    def _sovereign_square(state: GameState, player: Player) -> tuple[int, int]:
        return next(
            square
            for square, stack in state.board.items()
            if stack[-1].owner is player and stack[-1].kind is PieceType.SOVEREIGN
        )

    def _move_weight(self, state: GameState, action: MoveAction) -> float:
        player = state.turn
        sovereign = self._sovereign_square(state, player)
        target = state.board.get(action.destination)
        weight = 0.3 if target else 1.0
        old_distance = abs(action.source[0] - sovereign[0]) + abs(action.source[1] - sovereign[1])
        new_distance = abs(action.destination[0] - sovereign[0]) + abs(action.destination[1] - sovereign[1])
        if new_distance < old_distance:
            weight *= 1.8
        if self._own_territory(player, action.destination[1]):
            weight *= 2.0
        return weight

    def _placement_weight(self, state: GameState, action: Action) -> float:
        assert not isinstance(action, MoveAction)
        player = state.turn
        sovereign = self._sovereign_square(state, player)
        existing = state.board.get(action.destination)
        weight = super()._placement_weight(state, action)
        if self._own_territory(player, action.destination[1]):
            weight *= 4.0
        elif existing is None:
            weight *= 0.25
        distance = abs(action.destination[0] - sovereign[0]) + abs(action.destination[1] - sovereign[1])
        weight *= 1.0 + max(0, 5 - distance) * 0.3
        if action.effect_target is not None:
            weight *= 0.35
        if (
            action.piece is PieceType.SPY
            and existing
            and existing[-1].owner is player.opponent
        ):
            weight *= 0.15
        return weight


@dataclass(slots=True)
class NeutralDenialPolicy(HeuristicPolicy):
    name: str = "neutral_denial"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            neutral_open = [
                action
                for action in actions
                if not isinstance(action, MoveAction)
                and 3 <= action.destination[1] <= 5
                and action.destination not in state.board
                and action.piece is not PieceType.REINFORCEMENT
                and action.piece is not PieceType.SPY
            ]
            if neutral_open:
                by_square: dict[tuple[int, int], list[Action]] = defaultdict(list)
                for action in neutral_open:
                    by_square[action.destination].append(action)
                squares = list(by_square)
                square_weights = [
                    1.0
                    + 0.35 * (4 - abs(square[0] - 4))
                    + 0.2 * (2 - abs(square[1] - 4))
                    for square in squares
                ]
                square = _weighted_choice(squares, square_weights, rng)
                choices = by_square[square]
                return _weighted_choice(
                    choices,
                    [self._base_action_weight(state, action) for action in choices],
                    rng,
                )
        return super().choose(state, actions, rng)


@dataclass(slots=True)
class HeightRushPolicy(HeuristicPolicy):
    name: str = "height_rush"

    @staticmethod
    def _result_is_mobile(action: Action, existing_kind: PieceType) -> bool:
        if isinstance(action, MoveAction):
            return False
        top_kind = existing_kind if action.piece is PieceType.REINFORCEMENT else action.piece
        return top_kind not in IMMOBILE_TOPS and top_kind is not PieceType.REINFORCEMENT

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            if (
                state.rules.height_three_requires_shared_neutral_presence
                and not state.in_development
                and not state.height_three_unlocked[state.turn]
            ):
                gate_openers = [
                    action
                    for action in actions
                    if preview_action(state, action).height_three_unlocked[state.turn]
                ]
                if gate_openers:
                    return _weighted_choice(
                        gate_openers,
                        [self._base_action_weight(state, action) for action in gate_openers],
                        rng,
                    )
            if (
                state.rules.height_three_requires_nonsovereign_move
                and not state.in_development
                and not state.height_three_unlocked[state.turn]
            ):
                unlocsovereign_moves = [
                    action
                    for action in actions
                    if isinstance(action, MoveAction)
                    and state.board[action.source][-1].kind is not PieceType.SOVEREIGN
                ]
                if unlocsovereign_moves:
                    return _weighted_choice(
                        unlocsovereign_moves,
                        [
                            (2.0 if len(state.board[action.source]) == 2 else 1.0)
                            * self._move_weight(state, action)
                            for action in unlocsovereign_moves
                        ],
                        rng,
                    )
            height_three: list[Action] = []
            height_two: list[Action] = []
            for action in actions:
                if isinstance(action, MoveAction):
                    continue
                existing = state.board.get(action.destination)
                if not existing or existing[-1].owner is not state.turn:
                    continue
                if not self._result_is_mobile(action, existing[-1].kind):
                    continue
                if len(existing) == 2:
                    height_three.append(action)
                elif len(existing) == 1:
                    height_two.append(action)
            candidates = height_three or height_two
            if candidates:
                return _weighted_choice(
                    candidates,
                    [
                        PIECE_VALUES[
                            state.board[action.destination][-1].kind
                            if action.piece is PieceType.REINFORCEMENT
                            else action.piece
                        ]
                        for action in candidates
                    ],
                    rng,
                )
        return super().choose(state, actions, rng)


@dataclass(slots=True)
class ReserveHoarderPolicy(HeuristicPolicy):
    name: str = "reserve_hoarder"

    protected_kinds = {
        PieceType.INFANTRY,
        PieceType.DRAGOON,
        PieceType.CHARIOT,
        PieceType.GRIFFIN,
        PieceType.MARSHAL,
    }

    def _preserves_floor(self, state: GameState, action: Action) -> bool:
        if isinstance(action, MoveAction):
            return True
        costs: dict[PieceType, int] = defaultdict(int)
        if not isinstance(action, RecallAction):
            costs[action.piece] += 1
        existing = state.board.get(action.destination)
        if (
            action.piece is PieceType.SPY
            and existing
            and existing[-1].owner is state.turn.opponent
        ):
            for piece in existing:
                costs[piece.kind] += 1
        return all(
            kind not in self.protected_kinds
            or state.reserves[state.turn][kind] - cost >= 1
            for kind, cost in costs.items()
        )

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            preserving = [action for action in actions if self._preserves_floor(state, action)]
            if preserving:
                actions = preserving
        return super().choose(state, actions, rng)


@dataclass(slots=True)
class EvasionPolicy(HeuristicPolicy):
    name: str = "evasion"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if is_sovereign_threatened(state, state.turn):
            return super().choose(state, actions, rng)

        quiet_moves = [
            action
            for action in actions
            if isinstance(action, MoveAction)
            and action.destination not in state.board
            and not is_sovereign_threatened(preview_action(state, action), state.turn)
        ]
        if quiet_moves:
            enemies = [
                square
                for square, stack in state.board.items()
                if stack[-1].owner is state.turn.opponent
            ]
            weights = []
            for action in quiet_moves:
                kind = state.board[action.source][-1].kind
                nearest_enemy = min(
                    (
                        abs(action.destination[0] - square[0])
                        + abs(action.destination[1] - square[1])
                        for square in enemies
                    ),
                    default=8,
                )
                reversible_bonus = 0.35 if kind is PieceType.INFANTRY else 1.0
                weights.append(reversible_bonus * (1.0 + 0.2 * nearest_enemy))
            return _weighted_choice(quiet_moves, weights, rng)

        quiet_placements = [
            action
            for action in actions
            if not isinstance(action, MoveAction)
            and action.effect_target is None
            and not (
                action.piece is PieceType.SPY
                and (target := state.board.get(action.destination)) is not None
                and target[-1].owner is state.turn.opponent
            )
        ]
        if quiet_placements:
            return super().choose(state, quiet_placements, rng)
        return super().choose(state, actions, rng)


def _target_stack(state: GameState, action: Action):
    if isinstance(action, MoveAction):
        return state.board.get(action.destination)
    if action.effect_target is not None:
        return state.board.get(action.effect_target)
    if action.piece is PieceType.SPY:
        target = state.board.get(action.destination)
        if target and target[-1].owner is state.turn.opponent:
            return target
    return None


@dataclass(slots=True)
class HeightInterceptorPolicy(HeuristicPolicy):
    name: str = "height_interceptor"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            height_three_captures = [
                action
                for action in actions
                if (target := _target_stack(state, action)) is not None
                and len(target) == 3
            ]
            if height_three_captures:
                return _weighted_choice(
                    height_three_captures,
                    [sum(PIECE_VALUES[p.kind] for p in _removed_target_pieces(state, a)) for a in height_three_captures],
                    rng,
                )
            height_two_interceptions = [
                action
                for action in actions
                if (target := _target_stack(state, action)) is not None
                and len(target) == 2
            ]
            if height_two_interceptions:
                return _weighted_choice(
                    height_two_interceptions,
                    [sum(PIECE_VALUES[p.kind] for p in _removed_target_pieces(state, a)) for a in height_two_interceptions],
                    rng,
                )
            # Preserve the one-shot Spy rather than spending it on height 1.
            without_premature_spy = [
                action
                for action in actions
                if isinstance(action, MoveAction) or action.piece is not PieceType.SPY
            ]
            if without_premature_spy:
                actions = without_premature_spy
        return super().choose(state, actions, rng)


@dataclass(slots=True)
class SovereignDefensePolicy(HeuristicPolicy):
    """Break prepared launch stacks and prioritize Sovereign-safe counterplay."""

    name: str = "sovereign_defense"

    @staticmethod
    def _safe_actions(state: GameState, actions: Sequence[Action]) -> list[Action]:
        return [
            action
            for action in actions
            if not is_sovereign_threatened(preview_action(state, action), state.turn)
        ]

    @staticmethod
    def _attacsovereign_sources(state: GameState) -> set[tuple[int, int]]:
        """Return enemy stacks with a legal MOVE that captures the Sovereign now."""
        defender = state.turn
        sovereign_square = next(
            square
            for square, stack in state.board.items()
            if stack[-1].owner is defender and stack[-1].kind is PieceType.SOVEREIGN
        )
        attack_state = state.copy()
        attack_state.turn = defender.opponent
        return {
            action.source
            for action in legal_actions(attack_state)
            if isinstance(action, MoveAction) and action.destination == sovereign_square
        }

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)

        player = state.turn
        threatened = is_sovereign_threatened(state, player)
        candidates = self._safe_actions(state, actions) if threatened else list(actions)
        if not candidates:
            return super().choose(state, actions, rng)

        # When the attack has already arrived, remove its source if possible.
        if threatened:
            attacsovereign_sources = self._attacsovereign_sources(state)
            source_removals = [
                action
                for action in candidates
                if (target := _target_stack(state, action)) is not None
                and any(state.board.get(square) is target for square in attacsovereign_sources)
            ]
            if source_removals:
                return _weighted_choice(
                    source_removals,
                    [
                        sum(PIECE_VALUES[piece.kind] for piece in _target_stack(state, action))
                        for action in source_removals
                    ],
                    rng,
                )

        launch_stacks = {
            square
            for square, stack in state.board.items()
            if stack[-1].owner is player.opponent
            and len(stack) >= 2
            and stack[-1].kind not in IMMOBILE_TOPS
        }
        prepared_race = sum(len(state.board[square]) == 2 for square in launch_stacks) >= 2

        # Spy, artillery, or a legal capture can remove the prepared stack
        # before it is promoted into a decisive attack.
        launch_removals = [
            action
            for action in candidates
            if (
                _target_stack(state, action) is not None
                and action.destination in launch_stacks
            )
            or (
                not isinstance(action, MoveAction)
                and action.effect_target in launch_stacks
            )
        ]
        if launch_removals:
            return _weighted_choice(
                launch_removals,
                [
                    1.0
                    + sum(
                        PIECE_VALUES[piece.kind]
                        for piece in (_target_stack(state, action) or ())
                    )
                    for action in launch_removals
                ],
                rng,
            )

        # A counter-threat forces the rusher to defend instead of executing
        # the prepared launch. This is the policy's practical "dispersal."
        counter_threats = [
            action
            for action in candidates
            if is_sovereign_threatened(preview_action(state, action), player.opponent)
        ]
        if counter_threats and (threatened or prepared_race):
            return _weighted_choice(
                counter_threats,
                [self._base_action_weight(state, action) for action in counter_threats],
                rng,
            )

        if prepared_race:
            sovereign_square = next(
                square
                for square, stack in state.board.items()
                if stack[-1].owner is player and stack[-1].kind is PieceType.SOVEREIGN
            )
            blockers = [
                action
                for action in candidates
                if not isinstance(action, MoveAction)
                and max(
                    abs(action.destination[0] - sovereign_square[0]),
                    abs(action.destination[1] - sovereign_square[1]),
                )
                <= 2
                and action.piece not in IMMOBILE_TOPS
            ]
            if blockers:
                return _weighted_choice(
                    blockers,
                    [
                        PIECE_VALUES[action.piece]
                        * (1.5 if action.destination[1] == sovereign_square[1] else 1.0)
                        for action in blockers
                    ],
                    rng,
                )

        return super().choose(state, candidates, rng)


@dataclass(slots=True)
class ArtilleryBatteryPolicy(HeuristicPolicy):
    name: str = "artillery_battery"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            valuable_shots = [
                action
                for action in actions
                if not isinstance(action, MoveAction)
                and action.piece in {PieceType.BALLISTA, PieceType.TREBUCHET}
                and action.effect_target is not None
                and len(state.board[action.effect_target]) >= 2
            ]
            if valuable_shots:
                return _weighted_choice(
                    valuable_shots,
                    [
                        len(_removed_target_pieces(state, action))
                        * sum(PIECE_VALUES[p.kind] for p in _removed_target_pieces(state, action))
                        for action in valuable_shots
                    ],
                    rng,
                )

            own_height_two = sum(
                stack[-1].owner is state.turn and len(stack) == 2
                for stack in state.board.values()
            )
            platform_builders = [
                action
                for action in actions
                if not isinstance(action, MoveAction)
                and (existing := state.board.get(action.destination)) is not None
                and existing[-1].owner is state.turn
                and len(existing) == 1
                and action.piece not in {
                    PieceType.BALLISTA,
                    PieceType.TREBUCHET,
                    PieceType.SPY,
                }
            ]
            if own_height_two < 3 and platform_builders:
                return _weighted_choice(
                    platform_builders,
                    [1.0 + 0.2 * PIECE_VALUES[action.piece] for action in platform_builders],
                    rng,
                )

            # Keep artillery in reserve until it can remove a stack of height 2+.
            preserved = [
                action
                for action in actions
                if isinstance(action, MoveAction)
                or action.piece not in {PieceType.BALLISTA, PieceType.TREBUCHET}
            ]
            if preserved:
                actions = preserved
        return super().choose(state, actions, rng)


@dataclass(slots=True)
class HybridHeightPolicy(HeightRushPolicy):
    name: str = "hybrid_height"
    target_height_three: int = 2

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            tall_captures = [
                action
                for action in actions
                if (target := _target_stack(state, action)) is not None
                and len(target) >= 2
            ]
            if tall_captures:
                return _weighted_choice(
                    tall_captures,
                    [len(_target_stack(state, a)) ** 2 for a in tall_captures],
                    rng,
                )
            own_tall = sum(
                stack[-1].owner is state.turn and len(stack) == 3
                for stack in state.board.values()
            )
            if own_tall < self.target_height_three:
                return super().choose(state, actions, rng)
            preserved = [
                action
                for action in actions
                if isinstance(action, MoveAction)
                or action.piece not in {
                    PieceType.SPY,
                    PieceType.BALLISTA,
                    PieceType.TREBUCHET,
                }
                or action.effect_target is not None
                or _target_stack(state, action) is not None
            ]
            if preserved:
                actions = preserved
        return HeuristicPolicy.choose(self, state, actions, rng)


@dataclass(slots=True)
class SovereignRacePolicy(HeuristicPolicy):
    name: str = "sovereign_race"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            threats: list[Action] = []
            for action in actions:
                result = preview_action(state, action)
                if (
                    not is_sovereign_threatened(result, state.turn)
                    and is_sovereign_threatened(result, state.turn.opponent)
                ):
                    threats.append(action)
            if threats:
                return _weighted_choice(
                    threats,
                    [
                        1.0
                        + (
                            sum(PIECE_VALUES[p.kind] for p in _removed_target_pieces(state, action))
                            if _removed_target_pieces(state, action)
                            else 0.0
                        )
                        for action in threats
                    ],
                    rng,
                )
        return super().choose(state, actions, rng)


@dataclass(slots=True)
class ThreatDevelopmentPolicy(HeuristicPolicy):
    """Develop cheap optionality, then create defended and converging threats."""

    name: str = "threat_development"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        sovereign_captures = [
            action for action in actions if self._captures_sovereign(state, action)
        ]
        if sovereign_captures:
            return rng.choice(sovereign_captures)
        other_wins = [action for action in actions if self._wins_game(state, action)]
        if other_wins:
            return rng.choice(other_wins)

        candidates = list(actions)
        previews: dict[Action, GameState] = {}

        def result(action: Action) -> GameState:
            if action not in previews:
                previews[action] = preview_action(state, action)
            return previews[action]

        if is_sovereign_threatened(state, state.turn):
            safe = [
                action
                for action in candidates
                if not is_sovereign_threatened(result(action), state.turn)
            ]
            if safe:
                candidates = safe

        without_idle_spy = [
            action
            for action in candidates
            if not self._is_nonconverting_spy_placement(state, action)
        ]
        if without_idle_spy:
            candidates = without_idle_spy

        # Clean captures are a priority tier, not merely another weighted
        # preference. The only alternatives retained are protected or
        # converging direct Sovereign threats, which can plausibly be stronger
        # than routine material gain.
        free_captures = [
            action for action in candidates if is_free_capture(state, action, result(action))
        ]
        if free_captures:
            sovereign_overrides: list[Action] = []
            for action in candidates:
                if action in free_captures:
                    continue
                candidate_result = result(action)
                if not is_sovereign_threatened(candidate_result, state.turn.opponent):
                    continue
                sources, protected = sovereign_attack_profile(candidate_result, state.turn)
                if sources >= 2 or protected:
                    sovereign_overrides.append(action)
            candidates = free_captures + sovereign_overrides

        if state.in_development:
            weights = [
                self._development_weight(state, action, result(action))
                * self._development_strategy_weight(state, action, result(action))
                for action in candidates
            ]
        else:
            weights = [
                self._strategic_weight(state, action, result(action))
                * self._strategy_weight(state, action, result(action))
                for action in candidates
            ]
        return _weighted_choice(candidates, weights, rng)

    def _development_strategy_weight(
        self, state: GameState, action: Action, result: GameState
    ) -> float:
        return 1.0

    def _strategy_weight(
        self, state: GameState, action: Action, result: GameState
    ) -> float:
        return 1.0

    def _development_weight(
        self, state: GameState, action: Action, result: GameState
    ) -> float:
        if isinstance(action, MoveAction):
            return 0.0001
        player = state.turn
        own_stacks = [
            stack
            for stack in state.board.values()
            if stack[-1].owner is player and stack[-1].kind is not PieceType.SOVEREIGN
        ]
        required = state.rules.development_placements_per_player
        desired_platforms = max(3, (required + 1) // 2)
        existing = state.board.get(action.destination)
        starts_stack = existing is None
        structure = 8.0 if starts_stack == (len(own_stacks) < desired_platforms) else 0.18
        piece_weights = {
            PieceType.INFANTRY: 12.0,
            PieceType.REINFORCEMENT: 1.4,
            PieceType.DRAGOON: 1.15,
            PieceType.CHARIOT: 1.15,
            PieceType.GRIFFIN: 0.65,
            PieceType.MARSHAL: 0.25,
        }
        weight = structure * piece_weights.get(action.piece, 0.08)
        if existing and len(existing) == 1 and all(
            piece.kind in {PieceType.INFANTRY, PieceType.REINFORCEMENT}
            for piece in existing
        ):
            weight *= 2.0
        buried = valuable_burial_value(state, action)
        if buried:
            weight /= 1.0 + 2.0 * buried
        own_sovereign = _sovereign_square(result, player)
        if own_sovereign is not None and stack_controls_square(result, action.destination, own_sovereign):
            weight *= 1.45
        file, rank = action.destination
        relative_rank = rank if player is Player.WHITE else 8 - rank
        weight *= (0.9, 1.15, 1.4)[relative_rank]
        weight *= 1.0 + 0.06 * (4 - abs(file - 4))
        weight *= _vector_piece_weight(state, action.piece, action.destination)
        return max(0.0001, weight)

    def _strategic_weight(
        self, state: GameState, action: Action, result: GameState
    ) -> float:
        player = state.turn
        enemy = player.opponent
        weight = self._base_action_weight(state, action)
        was_threatened = is_sovereign_threatened(state, player)
        remains_threatened = is_sovereign_threatened(result, player)
        enemy_threatened = is_sovereign_threatened(result, enemy)
        tactical = self._is_tactical(state, action) or enemy_threatened

        if is_free_capture(state, action, result):
            weight *= 25.0

        if remains_threatened:
            weight *= 0.001
        elif was_threatened:
            weight *= 18.0
            if is_royal_interposition_trap(state, action):
                weight *= 5.0

        attack_sources, protected_sources = sovereign_attack_profile(result, player)
        if enemy_threatened:
            weight *= 5.0
            threat_kind = (
                state.board[action.source][-1].kind
                if isinstance(action, MoveAction)
                else action.piece
            )
            weight *= max(0.7, 1.0 + 0.22 * (5.0 - min(5.0, PIECE_VALUES[threat_kind])))
        if attack_sources >= 2:
            weight *= 3.5 + 0.5 * (attack_sources - 2)
        if protected_sources:
            weight *= 2.2 + 0.4 * protected_sources

        if (
            state.rules.height_three_requires_shared_neutral_presence
            and not any(state.height_three_unlocked.values())
            and all(result.height_three_unlocked.values())
            and not tactical
        ):
            weight *= 0.08

        buried = valuable_burial_value(state, action)
        if buried:
            weight /= 1.0 + 1.8 * buried

        if not isinstance(action, MoveAction):
            existing = state.board.get(action.destination)
            if action.piece is PieceType.INFANTRY:
                if existing is None:
                    weight *= 2.0
                elif len(existing) == 1 and all(
                    piece.kind in {PieceType.INFANTRY, PieceType.REINFORCEMENT}
                    for piece in existing
                ):
                    weight *= 2.4
                elif len(existing) == 2:
                    weight *= 0.25
            elif (
                existing
                and len(existing) == 2
                and all(
                    piece.kind in {PieceType.INFANTRY, PieceType.REINFORCEMENT}
                    for piece in existing
                )
                and action.piece in {
                    PieceType.DRAGOON,
                    PieceType.CHARIOT,
                    PieceType.GRIFFIN,
                    PieceType.MARSHAL,
                }
            ):
                weight *= 2.4
            if action.piece is PieceType.MARSHAL and not enemy_threatened:
                weight *= 0.45
            elif action.piece is PieceType.GRIFFIN and not enemy_threatened:
                weight *= 0.75

            own_sovereign = _sovereign_square(result, player)
            if own_sovereign is not None and stack_controls_square(result, action.destination, own_sovereign):
                weight *= 1.35

            weight *= _vector_piece_weight(state, action.piece, action.destination)

            if action.piece in {PieceType.BALLISTA, PieceType.TREBUCHET}:
                if action.effect_target is None:
                    weight *= 0.04
                elif not was_threatened and not enemy_threatened:
                    weight *= 0.45

        purposes = action_purpose_count(state, action, result)
        if purposes >= 2:
            weight *= 1.0 + 0.55 * (purposes - 1)

        return max(0.0001, weight)


@dataclass(slots=True)
class BalancedV2Policy(ThreatDevelopmentPolicy):
    """Shared competent play with no dominant strategic bias."""

    name: str = "balanced_v2"


@dataclass(slots=True)
class HeightV2Policy(ThreatDevelopmentPolicy):
    name: str = "height_v2"

    def _development_strategy_weight(self, state, action, result) -> float:
        stack = result.board.get(action.destination)
        return 2.0 if stack and len(stack) == 2 else 1.0

    def _strategy_weight(self, state, action, result) -> float:
        stack = result.board.get(action.destination)
        if not stack or stack[-1].owner is not state.turn:
            return 1.0
        if len(stack) == 3 and stack[-1].kind not in IMMOBILE_TOPS:
            return 3.0
        if len(stack) == 2:
            return 1.6
        return 1.0


@dataclass(slots=True)
class SpyV2Policy(ThreatDevelopmentPolicy):
    name: str = "spy_v2"

    def _strategy_weight(self, state, action, result) -> float:
        if isinstance(action, MoveAction):
            return 1.0
        existing = state.board.get(action.destination)
        if action.piece is PieceType.SPY and existing and existing[-1].owner is state.turn.opponent:
            value = sum(PIECE_VALUES[piece.kind] for piece in existing)
            return 3.0 + value
        if (
            existing
            and existing[-1].owner is state.turn
            and existing[-1].kind is PieceType.SPY
            and action.piece not in IMMOBILE_TOPS
        ):
            return 4.0
        return 1.0


@dataclass(slots=True)
class MaterialV2Policy(ThreatDevelopmentPolicy):
    name: str = "material_v2"

    def _strategy_weight(self, state, action, result) -> float:
        removed = sum(PIECE_VALUES[p.kind] for p in _removed_target_pieces(state, action))
        lost = sum(PIECE_VALUES[p.kind] for p in _own_move_attrition_pieces(state, action))
        if not removed:
            return 1.0
        return max(0.2, 1.0 + 0.9 * removed - 0.8 * lost)


@dataclass(slots=True)
class SovereignPressureV2Policy(ThreatDevelopmentPolicy):
    name: str = "sovereign_pressure_v2"

    def _strategy_weight(self, state, action, result) -> float:
        sources, protected = sovereign_attack_profile(result, state.turn)
        if not sources:
            return 1.0
        return 2.0 + 1.6 * sources + 1.2 * protected


@dataclass(slots=True)
class ArtilleryReserveV2Policy(ThreatDevelopmentPolicy):
    name: str = "artillery_reserve_v2"

    def _strategy_weight(self, state, action, result) -> float:
        if isinstance(action, MoveAction) or action.piece not in {PieceType.BALLISTA, PieceType.TREBUCHET}:
            return 1.0
        if action.effect_target is None:
            return 0.05
        was_threatened = is_sovereign_threatened(state, state.turn)
        is_safe = not is_sovereign_threatened(result, state.turn)
        removed = sum(PIECE_VALUES[p.kind] for p in _removed_target_pieces(state, action))
        if was_threatened and is_safe:
            return 12.0 + removed
        target = state.board[action.effect_target]
        if len(target) == 3 or is_sovereign_threatened(result, state.turn.opponent):
            return 2.0 + removed
        # Ordinary material shots remain legal, but this overlay should hold
        # its one-copy artillery for a rescue, a tall target, or a direct
        # Sovereign threat instead of spending it for routine tempo.
        return 0.015 * (1.0 + removed)


@dataclass(slots=True)
class MaterialControlPolicy(HeuristicPolicy):
    """Prefer favorable exchanges and durable, independent material pressure."""

    name: str = "material_control"

    def choose(
        self, state: GameState, actions: Sequence[Action], rng: random.Random
    ) -> Action:
        winning = [action for action in actions if self._captures_sovereign(state, action)]
        if winning:
            return rng.choice(winning)
        if not is_sovereign_threatened(state, state.turn):
            favorable: list[Action] = []
            values: list[float] = []
            for action in actions:
                target = None
                attacker_value = 0.0
                if isinstance(action, MoveAction):
                    target = state.board.get(action.destination)
                    attacker_value = sum(
                        PIECE_VALUES[piece.kind] for piece in state.board[action.source]
                    )
                elif action.effect_target is not None:
                    target = state.board.get(action.effect_target)
                    attacker_value = PIECE_VALUES[action.piece]
                elif action.piece is PieceType.SPY:
                    candidate = state.board.get(action.destination)
                    if candidate and candidate[-1].owner is state.turn.opponent:
                        target = candidate
                        attacker_value = PIECE_VALUES[PieceType.SPY]
                if not target or target[-1].kind is PieceType.SOVEREIGN:
                    continue
                removed = _removed_target_pieces(state, action)
                target_value = sum(PIECE_VALUES[piece.kind] for piece in removed)
                own_loss = sum(
                    PIECE_VALUES[piece.kind]
                    for piece in _own_move_attrition_pieces(state, action)
                )
                exchange_cost = own_loss if own_loss else attacker_value
                if target_value >= 0.8 * exchange_cost:
                    favorable.append(action)
                    values.append(1.0 + target_value - 0.35 * exchange_cost)
            if favorable:
                return _weighted_choice(favorable, values, rng)
        return super().choose(state, actions, rng)


def policy_by_name(
    name: str, *, mirror_opening: bool = False, tactical_search: bool = False
) -> Policy:
    base_name, separator, plan_name = name.partition("@")
    name = base_name
    if name == "uniform":
        base: Policy = UniformPolicy()
    elif name == "heuristic":
        base = HeuristicPolicy()
    elif name == "tactical":
        base = HeuristicPolicy(name="tactical")
    elif name == "material_control":
        base = MaterialControlPolicy()
    elif name == "threat_development":
        base = ThreatDevelopmentPolicy()
    elif name == "balanced_v2":
        base = BalancedV2Policy()
    elif name == "height_v2":
        base = HeightV2Policy()
    elif name == "spy_v2":
        base = SpyV2Policy()
    elif name == "material_v2":
        base = MaterialV2Policy()
    elif name == "sovereign_pressure_v2":
        base = SovereignPressureV2Policy()
    elif name == "artillery_reserve_v2":
        base = ArtilleryReserveV2Policy()
    elif name == "spy_rush":
        base = SpyRushPolicy()
    elif name == "artillery_rush":
        base = ArtilleryRushPolicy()
    elif name == "turtle":
        base = TurtlePolicy()
    elif name == "neutral_denial":
        base = NeutralDenialPolicy()
    elif name == "height_rush":
        base = HeightRushPolicy()
    elif name == "reserve_hoarder":
        base = ReserveHoarderPolicy()
    elif name == "evasion":
        base = EvasionPolicy()
    elif name == "height_interceptor":
        base = HeightInterceptorPolicy()
    elif name == "sovereign_defense":
        base = SovereignDefensePolicy()
    elif name == "artillery_battery":
        base = ArtilleryBatteryPolicy()
    elif name == "hybrid_height":
        base = HybridHeightPolicy()
    elif name == "sovereign_race":
        base = SovereignRacePolicy()
    else:
        raise ValueError(f"unknown policy: {name}")

    if separator and plan_name != "control":
        try:
            plan = OPENING_PLANS[base_name][plan_name]
        except KeyError as exc:
            choices = ", ".join(opening_plan_names(base_name)) or "none"
            raise ValueError(
                f"unknown opening plan {plan_name!r} for {base_name}; choices: {choices}"
            ) from exc
        base = PlannedPolicy(
            base=base,
            plan=plan,
            mirror=mirror_opening,
            name=f"{base_name}@{plan_name}",
        )
    if tactical_search:
        return TacticalSearchPolicy(base=base)
    return base
