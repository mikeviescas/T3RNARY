"""Run color-swapped paired policy tournaments with diagnostic reporting."""

from __future__ import annotations

import argparse
import itertools
import json
import random
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

from stack_chess import (
    CONTROL_RULES,
    DEVELOPMENT_RULES,
    GameState,
    MoveAction,
    PieceType,
    Player,
    RecallAction,
    RULESETS_BY_ID,
    apply_action,
    initial_state,
    is_sovereign_threatened,
    legal_actions,
    piece_display_name,
    ruleset_by_id,
    validate_state,
)
from stack_chess.contract import action_to_dict, state_to_dict
from stack_chess.policies import (
    PIECE_VALUES,
    game_phase,
    opening_target_profile,
    policy_by_name,
)


MOBILE_TOPS = {
    PieceType.INFANTRY,
    PieceType.DRAGOON,
    PieceType.CHARIOT,
    PieceType.GRIFFIN,
    PieceType.MARSHAL,
}
RESERVE_PROTECTED_KINDS = {
    PieceType.INFANTRY,
    PieceType.DRAGOON,
    PieceType.CHARIOT,
    PieceType.GRIFFIN,
    PieceType.MARSHAL,
}
DEFAULT_POLICIES = (
    "tactical",
    "spy_rush",
    "artillery_rush",
    "turtle",
    "neutral_denial",
    "height_rush",
    "reserve_hoarder",
    "evasion",
)

@dataclass(slots=True)
class GameResult:
    white_policy: str
    black_policy: str
    seed: int
    winner: Player | None
    draw: bool
    hit_limit: bool
    plies: int
    development_plies: int
    first_capture: int | None
    max_no_capture: int
    max_no_progress: int
    max_position_repeats: int
    limit_diagnostics: dict[str, object] | None = None
    win_reason: str | None = None


def _limit_diagnostics(
    state: GameState,
    *,
    no_capture: int,
    no_progress: int,
    max_position_repeats: int,
    final_position_repeats: int,
    reversible_moves: int,
) -> dict[str, object]:
    actions = legal_actions(state)
    captures = [action for action in actions if _is_capture_action(state, action)]
    immediate_sovereign_captures = [
        action
        for action in captures
        if isinstance(action, MoveAction)
        and state.board[action.destination][-1].kind is PieceType.SOVEREIGN
    ]
    sovereigns_present = {
        player.value: any(
            stack[-1].owner is player and stack[-1].kind is PieceType.SOVEREIGN
            for stack in state.board.values()
        )
        for player in Player
    }
    threatened_sovereigns = sum(is_sovereign_threatened(state, player) for player in Player)
    board_pieces = sum(len(stack) for stack in state.board.values())
    reserve_pieces = sum(
        sum(state.reserves[player].values()) for player in Player
    )
    nonsovereign_active = sum(
        piece.kind is not PieceType.SOVEREIGN
        for stack in state.board.values()
        for piece in stack
    ) + reserve_pieces
    mobile_stacks = sum(stack[-1].kind in MOBILE_TOPS or stack[-1].kind is PieceType.SOVEREIGN for stack in state.board.values())
    immobile_stacks = len(state.board) - mobile_stacks

    if immediate_sovereign_captures:
        category = "missed_immediate_win"
    elif no_progress >= 100:
        category = "quiet_move_loop"
    elif final_position_repeats >= 3:
        category = "repetition_loop"
    elif captures or threatened_sovereigns:
        category = "active_tactical_cutoff"
    elif nonsovereign_active <= 8:
        category = "low_material_stall"
    elif reserve_pieces == 0:
        category = "reserve_exhaustion"
    elif nonsovereign_active >= 20:
        category = "high_material_policy_stall"
    else:
        category = "positional_stall"

    return {
        "category": category,
        "board_pieces": board_pieces,
        "reserve_pieces": reserve_pieces,
        "board_stacks": len(state.board),
        "mobile_stacks": mobile_stacks,
        "immobile_stacks": immobile_stacks,
        "legal_actions": len(actions),
        "legal_captures": len(captures),
        "immediate_sovereign_captures": len(immediate_sovereign_captures),
        "threatened_sovereigns": threatened_sovereigns,
        "sovereigns_present": sovereigns_present,
        "plies_since_capture": no_capture,
        "quiet_move_run": no_progress,
        "max_position_repeats": max_position_repeats,
        "final_position_repeats": final_position_repeats,
        "reversible_moves": reversible_moves,
    }


def _state_key(state: GameState) -> tuple:
    board = tuple(
        sorted(
            (
                square,
                tuple((piece.owner.value, piece.kind.value) for piece in stack),
            )
            for square, stack in state.board.items()
        )
    )
    reserves = tuple(
        (player.value, tuple(sorted((kind.value, count) for kind, count in state.reserves[player].items() if count)))
        for player in Player
    )
    discards = tuple(
        (player.value, tuple(sorted((kind.value, count) for kind, count in state.discards[player].items() if count)))
        for player in Player
    )
    return state.turn.value, board, reserves, discards


def _griffin_jump(action: MoveAction) -> str | None:
    dimensions = tuple(sorted((abs(action.destination[0] - action.source[0]), abs(action.destination[1] - action.source[1]))))
    if dimensions == (1, 2):
        return "short"
    if dimensions == (2, 3):
        return "long"
    return None


def _enemy_territory(player: Player, rank: int) -> bool:
    return rank >= 6 if player is Player.WHITE else rank <= 2


def _is_spy_conversion(state: GameState, action: object) -> bool:
    if isinstance(action, MoveAction) or getattr(action, "piece", None) is not PieceType.SPY:
        return False
    target = state.board.get(action.destination)
    return bool(target and target[-1].owner is state.turn.opponent)


def _is_capture_action(state: GameState, action: object) -> bool:
    if isinstance(action, MoveAction):
        return action.destination in state.board
    return bool(getattr(action, "effect_target", None) is not None or _is_spy_conversion(state, action))


DECISION_REASONS = (
    "sovereign_capture",
    "infiltration_win",
    "forced_defense",
    "sovereign_threat",
    "spy_conversion",
    "spy_mobilization",
    "artillery_attack",
    "height_build",
    "material_capture",
    "development",
    "quiet_move",
)


def _decision_reason(
    state: GameState,
    action: object,
    result: GameState,
    policy_name: str,
    *,
    own_sovereign_was_threatened: bool,
    enemy_sovereign_was_threatened: bool,
) -> str:
    """Infer one primary reason from policy priority and the action's effect."""
    player = state.turn
    target = state.board.get(action.destination)
    if (
        isinstance(action, MoveAction)
        and target
        and target[-1].kind is PieceType.SOVEREIGN
    ):
        return "sovereign_capture"
    if result.winner is player:
        return "infiltration_win"
    if own_sovereign_was_threatened and not is_sovereign_threatened(result, player):
        return "forced_defense"

    creates_sovereign_threat = (
        not enemy_sovereign_was_threatened
        and is_sovereign_threatened(result, player.opponent)
    )
    # Sovereign Race explicitly searches for a new threat before using its fallback
    # heuristic, so that policy's threat takes precedence over side effects.
    if policy_name == "sovereign_race" and creates_sovereign_threat:
        return "sovereign_threat"
    if _is_spy_conversion(state, action):
        return "spy_conversion"
    if not isinstance(action, MoveAction):
        if (
            target
            and target[-1].owner is player
            and target[-1].kind is PieceType.SPY
            and action.piece in MOBILE_TOPS
        ):
            return "spy_mobilization"
        if (
            action.piece in {PieceType.BALLISTA, PieceType.TREBUCHET}
            and action.effect_target is not None
        ):
            return "artillery_attack"
        if target and target[-1].owner is player and len(target) in {1, 2}:
            return "height_build"
    if isinstance(action, MoveAction) and target:
        return "material_capture"
    if creates_sovereign_threat:
        return "sovereign_threat"
    return "quiet_move" if isinstance(action, MoveAction) else "development"


def play_game(
    white_policy_name: str,
    black_policy_name: str,
    seed: int,
    max_plies: int,
    telemetry: dict[str, Counter],
    opening: str = "standard",
    mirror_opening: bool = False,
    sovereign_files: tuple[int, int] | None = None,
    ruleset_id: str | None = None,
    limit_replays: list[dict[str, object]] | None = None,
) -> GameResult:
    exclude_behavioral_telemetry = (
        white_policy_name == black_policy_name == "evasion"
    )
    game_telemetry: dict[str, Counter] = (
        defaultdict(Counter) if exclude_behavioral_telemetry else telemetry
    )
    policies = {
        Player.WHITE: policy_by_name(white_policy_name, mirror_opening=mirror_opening),
        Player.BLACK: policy_by_name(black_policy_name, mirror_opening=mirror_opening),
    }
    policy_names = {Player.WHITE: white_policy_name, Player.BLACK: black_policy_name}
    rng = random.Random(seed)
    rules = (
        ruleset_by_id(ruleset_id)
        if ruleset_id is not None
        else DEVELOPMENT_RULES if opening == "development" else CONTROL_RULES
    )
    state = initial_state(rules, sovereign_files=sovereign_files)
    replay_initial_state = state_to_dict(state) if limit_replays is not None else None
    replay_actions: list[dict[str, object]] = []
    first_capture: int | None = None
    no_capture = 0
    no_progress = 0
    max_no_capture = 0
    max_no_progress = 0
    positions = Counter({_state_key(state): 1})
    pending_spies: dict[tuple[Player, tuple[int, int]], dict[str, object]] = {}
    first_height_three_seen = {Player.WHITE: False, Player.BLACK: False}
    first_nonsovereign_move_seen = {Player.WHITE: False, Player.BLACK: False}
    first_any_move_seen = {Player.WHITE: False, Player.BLACK: False}
    first_mover: Player | None = None
    first_move_preplacements = 0
    first_spy_conversion_seen = {Player.WHITE: False, Player.BLACK: False}
    first_artillery_shot_seen = {Player.WHITE: False, Player.BLACK: False}
    first_sovereign_threat_seen = {Player.WHITE: False, Player.BLACK: False}
    development_plies = 0
    win_reason: str | None = None
    reversible_moves = 0
    last_move_by_player: dict[Player, tuple[tuple[int, int], tuple[int, int]] | None] = {
        Player.WHITE: None,
        Player.BLACK: None,
    }
    development_piece_ids: dict[Player, set[int]] = {
        Player.WHITE: set(),
        Player.BLACK: set(),
    }

    for _ in range(max_plies):
        if state.is_over:
            break
        player = state.turn
        policy_name = policy_names[player]
        stats = game_telemetry[policy_name]
        phase = game_phase(state, player)
        was_development = state.in_development
        actions = legal_actions(state)
        if not actions:
            raise AssertionError("non-terminal state has no legal actions")

        for key, data in list(pending_spies.items()):
            owner, square = key
            stack = state.board.get(square)
            if not stack or stack[-1].owner is not owner or stack[-1].kind is not PieceType.SPY:
                pending_spies.pop(key)
            elif owner is player and not data["survived_checked"]:
                game_telemetry[str(data["policy"])]["spy_survived_reply"] += 1
                data["survived_checked"] = True

        for stack in state.board.values():
            if stack[-1].owner is player and len(stack) == 3:
                stats[f"h3_exposure_{stack[-1].kind.value}"] += 1

        h3_griffin_actions = []
        for candidate in actions:
            if not isinstance(candidate, MoveAction):
                continue
            stack = state.board[candidate.source]
            if len(stack) == 3 and stack[-1].kind is PieceType.GRIFFIN:
                jump = _griffin_jump(candidate)
                if jump:
                    stats[f"griffin_h3_{jump}_legal"] += 1
                    h3_griffin_actions.append(candidate)
        if h3_griffin_actions:
            stats["griffin_h3_eligible_turns"] += 1

        action = policies[player].choose(state, actions, rng)
        if limit_replays is not None:
            replay_actions.append(action_to_dict(action))
        capture_was_available = any(_is_capture_action(state, candidate) for candidate in actions)
        stats["actions"] += 1
        stats[f"phase_{phase}_actions"] += 1
        before_own_threat = is_sovereign_threatened(state, player)
        before_enemy_threat = is_sovereign_threatened(state, player.opponent)
        capture = False
        progress = not isinstance(action, MoveAction)
        h3_move_top: PieceType | None = None
        h3_move_capture_value = 0.0
        royal_attack = False
        sovereign_capture_action = False
        infiltration_action = False

        if not was_development:
            next_normal_ply = state.ply - development_plies + 1
            if isinstance(action, MoveAction):
                if not first_any_move_seen[player]:
                    first_any_move_seen[player] = True
                    stats["games_with_first_any_move"] += 1
                    stats["first_any_move_normal_ply_total"] += next_normal_ply
                if first_mover is None:
                    first_mover = player
                    stats["first_mover_games"] += 1
                    stats["first_move_global_normal_ply_total"] += next_normal_ply
                    stats["first_move_global_preplacements_total"] += first_move_preplacements
                    stats["first_move_immediate"] += first_move_preplacements == 0
                    stats[f"first_mover_color_{player.value}"] += 1
            else:
                if not first_any_move_seen[player]:
                    stats["optional_placements_before_own_first_move"] += 1
                if first_mover is None:
                    first_move_preplacements += 1

        if was_development:
            development_plies += 1
            stats["development_actions"] += 1
            stats[f"development_piece_{action.piece.value}"] += 1
            stats[f"development_rank_{action.destination[1] + 1}"] += 1
            stats[f"development_file_{action.destination[0]}"] += 1

        if isinstance(action, MoveAction):
            previous_move = last_move_by_player[player]
            if previous_move == (action.destination, action.source):
                reversible_moves += 1
            last_move_by_player[player] = (action.source, action.destination)
            stats["moves"] += 1
            stats[f"phase_{phase}_moves"] += 1
            moving_stack = state.board[action.source]
            if (
                moving_stack[-1].kind is not PieceType.SOVEREIGN
                and not first_nonsovereign_move_seen[player]
            ):
                first_nonsovereign_move_seen[player] = True
                stats["games_with_first_nonsovereign_move"] += 1
                stats["first_nonsovereign_move_normal_ply_total"] += state.ply - development_plies + 1
            target = state.board.get(action.destination)
            sovereign_capture_action = bool(
                target and target[-1].kind is PieceType.SOVEREIGN
            )
            infiltration_action = (
                state.rules.infiltration_victory
                and moving_stack[-1].kind is PieceType.SOVEREIGN
                and action.destination[1]
                == (8 if player is Player.WHITE else 0)
            )
            if len(moving_stack) == 3:
                h3_move_top = moving_stack[-1].kind
                stats[f"h3_moves_{h3_move_top.value}"] += 1
            if target:
                capture = True
                stats["move_captures"] += 1
                move_attrition = (
                    moving_stack[-1].kind is not PieceType.SOVEREIGN
                    and len(moving_stack) < len(target)
                    and state.rules.move_vs_taller == "mutual_bottom_attrition"
                )
                royal_attack = (
                    moving_stack[-1].kind is PieceType.SOVEREIGN
                    and len(target) > len(moving_stack)
                )
                if royal_attack:
                    stats["royal_attacks"] += 1
                    stats[f"royal_target_height_{len(target)}"] += 1
                    stats["royal_removed_pieces"] += len(target)
                    stats["royal_removed_value"] += sum(
                        0.0 if piece.kind is PieceType.SOVEREIGN else PIECE_VALUES[piece.kind]
                        for piece in target
                    )
                    if target[-1].kind is PieceType.SOVEREIGN:
                        stats["royal_sovereign_captures"] += 1
                removed_target = target[:len(moving_stack)] if move_attrition else target
                if move_attrition:
                    stats["move_attrition_events"] += 1
                    for piece in moving_stack:
                        stats[f"own_removed_move_attrition_{piece.kind.value}"] += 1
                for piece in removed_target:
                    stats[f"enemy_removed_move_{piece.kind.value}"] += 1
                if h3_move_top is not None:
                    h3_move_capture_value = sum(
                        0.0 if piece.kind is PieceType.SOVEREIGN else PIECE_VALUES[piece.kind]
                        for piece in removed_target
                    )
                    stats[f"h3_captures_{h3_move_top.value}"] += 1
                    stats[f"h3_capture_value_{h3_move_top.value}"] += h3_move_capture_value
                    if target[-1].kind is PieceType.SOVEREIGN:
                        stats[f"h3_sovereign_captures_{h3_move_top.value}"] += 1
            if len(moving_stack) == 3 and moving_stack[-1].kind is PieceType.GRIFFIN:
                jump = _griffin_jump(action)
                if jump:
                    stats[f"griffin_h3_{jump}_chosen"] += 1
                    if target:
                        stats[f"griffin_h3_{jump}_captures"] += 1
                        if target[-1].kind is PieceType.SOVEREIGN:
                            stats[f"griffin_h3_{jump}_sovereign_captures"] += 1
        else:
            stats["placements"] += 1
            stats[f"phase_{phase}_placements"] += 1
            existing = state.board.get(action.destination)
            if existing is None and 3 <= action.destination[1] <= 5:
                stats["open_neutral_placements"] += 1
            if isinstance(action, RecallAction):
                stats["recalls"] += 1
                stats[f"recall_{action.piece.value}"] += 1
                stats["material_recall_tokens_spent"] += 1
                stats[f"discard_to_board_{action.piece.value}"] += 1
            else:
                stats[f"direct_reserve_to_board_{action.piece.value}"] += 1
            if _is_spy_conversion(state, action):
                capture = True
                stats["spy_conversions"] += 1
                if not first_spy_conversion_seen[player]:
                    first_spy_conversion_seen[player] = True
                    stats["games_with_first_spy_conversion"] += 1
                    stats["first_spy_conversion_normal_ply_total"] += state.ply - development_plies + 1
                stats["spy_target_value_total"] += sum(
                    PIECE_VALUES[piece.kind] for piece in existing
                )
                if _enemy_territory(player, action.destination[1]):
                    stats["spy_enemy_territory_conversions"] += 1
                if len(existing) == 1 and existing[-1].kind is PieceType.INFANTRY:
                    stats["spy_single_infantry_conversions"] += 1
                for piece in existing:
                    stats[f"spy_replacement_reserve_to_board_{piece.kind.value}"] += 1
                    stats[f"enemy_removed_spy_{piece.kind.value}"] += 1
                pending_spies[(player, action.destination)] = {
                    "policy": policy_name,
                    "survived_checked": False,
                }
            elif action.piece is PieceType.SPY:
                stats["spy_nonconversion_placements"] += 1
            if (
                (player, action.destination) in pending_spies
                and action.piece in MOBILE_TOPS
                and existing
                and existing[-1].kind is PieceType.SPY
                and existing[-1].owner is player
            ):
                original_policy = str(pending_spies[(player, action.destination)]["policy"])
                game_telemetry[original_policy]["spy_stacks_mobilized"] += 1
            if action.piece in {PieceType.BALLISTA, PieceType.TREBUCHET}:
                resulting_height = 1 + (len(existing) if existing else 0)
                stats[f"artillery_height_{resulting_height}_placements"] += 1
                if action.effect_target is None:
                    stats["artillery_no_fire"] += 1
                else:
                    capture = True
                    stats["artillery_shots"] += 1
                    if not first_artillery_shot_seen[player]:
                        first_artillery_shot_seen[player] = True
                        stats["games_with_first_artillery_shot"] += 1
                        stats["first_artillery_shot_normal_ply_total"] += state.ply - development_plies + 1
                    artillery_target = state.board[action.effect_target]
                    artillery_attrition = (
                        resulting_height < len(artillery_target)
                        and state.rules.artillery_vs_taller == "target_bottom_attrition"
                    )
                    removed_target = (
                        artillery_target[:resulting_height]
                        if artillery_attrition
                        else artillery_target
                    )
                    if artillery_attrition:
                        stats["artillery_attrition_events"] += 1
                    for piece in removed_target:
                        stats[f"enemy_removed_artillery_{piece.kind.value}"] += 1
                    stats[f"artillery_height_{resulting_height}_shots"] += 1
                    distance = max(
                        abs(action.effect_target[0] - action.destination[0]),
                        abs(action.effect_target[1] - action.destination[1]),
                    )
                    stats[f"artillery_range_{distance}_shots"] += 1

        if capture:
            progress = True
            if first_capture is None:
                first_capture = state.ply + 1
            no_capture = 0
        else:
            no_capture += 1
        if capture_was_available:
            stats["capture_opportunities"] += 1
            if not capture:
                stats["captures_declined"] += 1
        no_progress = 0 if progress else no_progress + 1
        max_no_capture = max(max_no_capture, no_capture)
        max_no_progress = max(max_no_progress, no_progress)

        prior_state = state
        state = apply_action(state, action)
        validate_state(state, enforce_inventory=True)
        if state.winner is player:
            if sovereign_capture_action:
                win_reason = "sovereign_capture"
                stats["wins_sovereign_capture"] += 1
            elif infiltration_action:
                win_reason = "infiltration"
                stats["wins_infiltration"] += 1
                normal_win_ply = state.ply - development_plies
                stats["infiltration_win_normal_ply_total"] += normal_win_ply
                stats[f"infiltration_file_{action.destination[0]}"] += 1
                opposing_reserve = sum(state.reserves[player.opponent].values())
                stats["infiltration_opponent_reserve_total"] += opposing_reserve
                stats["infiltration_with_opponent_reserve"] += opposing_reserve > 0
                stats["infiltration_by_normal_ply_30"] += normal_win_ply <= 30
                stats["infiltration_by_normal_ply_60"] += normal_win_ply <= 60
                stats["infiltration_ending_threatened"] += is_sovereign_threatened(
                    state, player
                )
        if royal_attack and not state.is_over and is_sovereign_threatened(state, player):
            stats["royal_attacks_ending_threatened"] += 1
        if was_development and not state.in_development:
            for opening_player in Player:
                opening_name = policy_names[opening_player]
                opening_stats = game_telemetry[opening_name]
                stacks = [
                    stack
                    for stack in state.board.values()
                    if stack[-1].owner is opening_player
                    and stack[-1].kind is not PieceType.SOVEREIGN
                ]
                profile = tuple(sorted(len(stack) for stack in stacks))
                opening_stats["opening_completed"] += 1
                opening_stats["opening_occupied_stacks_total"] += len(stacks)
                opening_stats[f"opening_profile_{'-'.join(map(str, profile))}"] += 1
                for stack in stacks:
                    for piece in stack:
                        development_piece_ids[opening_player].add(id(piece))
                        opening_stats[f"opening_piece_{piece.kind.value}"] += 1
                base_name, separator, plan_name = opening_name.partition("@")
                target = (
                    opening_target_profile(base_name, plan_name)
                    if separator and plan_name != "control"
                    else None
                )
                if target is not None and profile == target:
                    opening_stats["opening_target_achieved"] += 1
        reason = _decision_reason(
            prior_state,
            action,
            state,
            policy_name.partition("@")[0],
            own_sovereign_was_threatened=before_own_threat,
            enemy_sovereign_was_threatened=before_enemy_threat,
        )
        stats[f"decision_{reason}"] += 1
        if not isinstance(action, MoveAction):
            resulting_stack = state.board.get(action.destination)
            if resulting_stack:
                height = len(resulting_stack)
                stats[f"placement_result_height_{height}"] += 1
                if height == 3:
                    top_kind = resulting_stack[-1].kind
                    stats[f"h3_created_{top_kind.value}"] += 1
                    for foundation_piece in resulting_stack[:-1]:
                        stats[
                            f"h3_foundation_{top_kind.value}_{foundation_piece.kind.value}"
                        ] += 1
                    if resulting_stack[-1].kind in {
                        PieceType.SPY,
                        PieceType.BALLISTA,
                        PieceType.TREBUCHET,
                    }:
                        stats["immobile_height_three_created"] += 1
                    else:
                        stats["mobile_height_three_created"] += 1
            if was_development and resulting_stack:
                stats[f"development_result_height_{len(resulting_stack)}"] += 1
        own_neutral = sum(
            1
            for square, stack in state.board.items()
            if 3 <= square[1] <= 5 and stack[-1].owner is player
        )
        enemy_neutral = sum(
            1
            for square, stack in state.board.items()
            if 3 <= square[1] <= 5 and stack[-1].owner is player.opponent
        )
        stats["neutral_sample_count"] += 1
        stats["own_neutral_stacks_sample_total"] += own_neutral
        stats["enemy_neutral_stacks_sample_total"] += enemy_neutral
        own_height_three = [
            stack
            for stack in state.board.values()
            if stack[-1].owner is player and len(stack) == 3
        ]
        stats["height_three_sample_count"] += 1
        stats["height_three_stacks_sample_total"] += len(own_height_three)
        stats["mobile_height_three_sample_total"] += sum(
            stack[-1].kind
            not in {PieceType.SPY, PieceType.BALLISTA, PieceType.TREBUCHET}
            for stack in own_height_three
        )
        if own_height_three and not first_height_three_seen[player]:
            first_height_three_seen[player] = True
            stats["games_with_height_three"] += 1
            stats["first_height_three_ply_total"] += state.ply
            stats["first_height_three_normal_ply_total"] += state.ply - development_plies
        stats["reserve_sample_count"] += 1
        stats["reserve_pieces_sample_total"] += sum(state.reserves[player].values())
        stats["protected_reserve_sample_total"] += sum(
            state.reserves[player][kind] for kind in RESERVE_PROTECTED_KINDS
        )
        if not before_enemy_threat and is_sovereign_threatened(state, player.opponent):
            stats["new_sovereign_threats"] += 1
            if not first_sovereign_threat_seen[player]:
                first_sovereign_threat_seen[player] = True
                stats["games_with_first_sovereign_threat"] += 1
                stats["first_sovereign_threat_normal_ply_total"] += state.ply - development_plies
            if isinstance(action, MoveAction):
                threat_source = "move"
                threat_piece = prior_state.board[action.source][-1].kind
            elif isinstance(action, RecallAction):
                threat_source = "recall"
                threat_piece = action.piece
            else:
                threat_source = "place"
                threat_piece = action.piece
            stats[f"sovereign_threat_source_{threat_source}"] += 1
            stats[f"sovereign_threat_piece_{threat_piece.value}"] += 1
            if h3_move_top is not None:
                stats[f"h3_sovereign_threats_{h3_move_top.value}"] += 1
            if isinstance(action, MoveAction):
                moved = state.board.get(action.destination)
                if moved and len(moved) == 3 and moved[-1].kind is PieceType.GRIFFIN:
                    jump = _griffin_jump(action)
                    if jump:
                        stats[f"griffin_h3_{jump}_sovereign_threats"] += 1
        positions[_state_key(state)] += 1

        normal_ply = state.ply - development_plies
        if normal_ply in {10, 20, 30, 50}:
            active_values = {}
            for measured_player in Player:
                reserve_value = sum(
                    count * PIECE_VALUES[kind]
                    for kind, count in state.reserves[measured_player].items()
                    if kind is not PieceType.SOVEREIGN
                )
                board_value = sum(
                    PIECE_VALUES[piece.kind]
                    for stack in state.board.values()
                    for piece in stack
                    if piece.owner is measured_player and piece.kind is not PieceType.SOVEREIGN
                )
                active_values[measured_player] = reserve_value + board_value
            for measured_player in Player:
                measured_stats = game_telemetry[policy_names[measured_player]]
                measured_stats[f"material_advantage_ply_{normal_ply}_samples"] += 1
                measured_stats[f"material_advantage_ply_{normal_ply}_total"] += (
                    active_values[measured_player]
                    - active_values[measured_player.opponent]
                )

    hit_limit = not state.is_over
    max_repeats = max(positions.values())
    final_position_repeats = positions[_state_key(state)]
    limit_diagnostics = (
        _limit_diagnostics(
            state,
            no_capture=no_capture,
            no_progress=no_progress,
            max_position_repeats=max_repeats,
            final_position_repeats=final_position_repeats,
            reversible_moves=reversible_moves,
        )
        if hit_limit
        else None
    )
    result = GameResult(
        white_policy=white_policy_name,
        black_policy=black_policy_name,
        seed=seed,
        winner=state.winner,
        draw=state.is_draw,
        hit_limit=hit_limit,
        plies=state.ply,
        development_plies=development_plies,
        first_capture=first_capture,
        max_no_capture=max_no_capture,
        max_no_progress=max_no_progress,
        max_position_repeats=max_repeats,
        limit_diagnostics=limit_diagnostics,
        win_reason=win_reason,
    )
    if hit_limit and limit_replays is not None:
        game_id = (
            f"{rules.id}__{white_policy_name}-vs-{black_policy_name}__seed-{seed}"
            .replace("@", "-")
            .replace("/", "-")
        )
        limit_replays.append(
            {
                "contract_version": 2,
                "game_id": game_id,
                "initial_state": replay_initial_state,
                "actions": replay_actions,
                "metadata": {
                    "white_policy": white_policy_name,
                    "black_policy": black_policy_name,
                    "seed": seed,
                    "ruleset": rules.id,
                    "max_plies": max_plies,
                    "outcome": "ply_limit",
                    "diagnostics": limit_diagnostics,
                },
                "annotations": [
                    {
                        "ply": state.ply,
                        "type": "limit_endgame",
                        "category": limit_diagnostics["category"],
                    }
                ],
            }
        )
    if first_mover is not None:
        first_mover_stats = game_telemetry[policy_names[first_mover]]
        if result.hit_limit:
            first_mover_stats["first_mover_limits"] += 1
        elif result.draw or result.winner is None:
            first_mover_stats["first_mover_draws"] += 1
        elif result.winner is first_mover:
            first_mover_stats["first_mover_wins"] += 1
        else:
            first_mover_stats["first_mover_losses"] += 1
    for policy_name in set(policy_names.values()):
        stats = game_telemetry[policy_name]
        stats["games_observed"] += 1
        stats["game_plies_total"] += result.plies
        stats["max_no_capture_total"] += result.max_no_capture
        stats["max_no_progress_total"] += result.max_no_progress
        stats["largest_no_capture"] = max(stats["largest_no_capture"], result.max_no_capture)
        stats["largest_no_progress"] = max(stats["largest_no_progress"], result.max_no_progress)
        stats["max_position_repeats"] = max(stats["max_position_repeats"], result.max_position_repeats)
        stats["games_200_plus"] += result.plies >= 200
        stats["games_300_plus"] += result.plies >= 300
        stats["games_at_limit"] += result.hit_limit
    for player, policy_name in policy_names.items():
        stats = game_telemetry[policy_name]
        if development_piece_ids[player]:
            surviving_ids = {
                id(piece)
                for stack in state.board.values()
                for piece in stack
                if piece.owner is player
            }
            stats["opening_survivor_samples"] += 1
            stats["opening_survivors_total"] += len(
                development_piece_ids[player] & surviving_ids
            )
        final_neutral = sum(
            1
            for square, stack in state.board.items()
            if 3 <= square[1] <= 5 and stack[-1].owner is player
        )
        stats["final_neutral_stacks_total"] += final_neutral
        stats["final_reserve_pieces_total"] += sum(state.reserves[player].values())
        stats["final_protected_reserve_total"] += sum(
            state.reserves[player][kind] for kind in RESERVE_PROTECTED_KINDS
        )
        for kind in PieceType:
            stats[f"final_reserve_{kind.value}_total"] += state.reserves[player][kind]
            stats[f"final_discard_{kind.value}_total"] += state.discards[player][kind]
            stats[f"final_board_{kind.value}_total"] += sum(
                piece.owner is player and piece.kind is kind
                for stack in state.board.values()
                for piece in stack
            )
        stats["player_games"] += 1
    return result


def _pair_summary(results: list[GameResult], policy_a: str, policy_b: str) -> dict[str, float]:
    wins_a = wins_b = draws = limits = 0
    white_wins = black_wins = 0
    winners_by_seed: dict[int, list[str | None]] = defaultdict(list)
    for result in results:
        if result.hit_limit:
            limits += 1
            winners_by_seed[result.seed].append(None)
        elif result.draw or result.winner is None:
            draws += 1
            winners_by_seed[result.seed].append(None)
        else:
            if result.winner is Player.WHITE:
                white_wins += 1
            else:
                black_wins += 1
            winner_name = result.white_policy if result.winner is Player.WHITE else result.black_policy
            winners_by_seed[result.seed].append(winner_name)
            if winner_name == policy_a:
                wins_a += 1
            else:
                wins_b += 1
    a_sweeps = b_sweeps = splits = unresolved_pairs = 0
    for winners in winners_by_seed.values():
        if len(winners) == 2 and winners[0] == winners[1] == policy_a:
            a_sweeps += 1
        elif len(winners) == 2 and winners[0] == winners[1] == policy_b:
            b_sweeps += 1
        elif len(winners) == 2 and set(winners) == {policy_a, policy_b}:
            splits += 1
        else:
            unresolved_pairs += 1
    games = len(results)
    return {
        "wins_a": wins_a,
        "wins_b": wins_b,
        "draws": draws,
        "limits": limits,
        "score_a": (wins_a + 0.5 * (draws + limits)) / games,
        "mean_plies": sum(result.plies for result in results) / games,
        "mean_normal_plies": sum(
            result.plies - result.development_plies for result in results
        )
        / games,
        "white_wins": white_wins,
        "black_wins": black_wins,
        "a_sweeps": a_sweeps,
        "b_sweeps": b_sweeps,
        "splits": splits,
        "unresolved_pairs": unresolved_pairs,
    }


def _pct(part: float, whole: float) -> str:
    return f"{part / whole:.1%}" if whole else "n/a"


def build_report(
    policies: tuple[str, ...],
    seeds: int,
    seed_start: int,
    max_plies: int,
    paired: dict[tuple[str, str], list[GameResult]],
    self_play: dict[str, list[GameResult]],
    telemetry: dict[str, Counter],
    opening: str = "standard",
    ruleset_id: str | None = None,
) -> str:
    active_rules = (
        ruleset_by_id(ruleset_id)
        if ruleset_id is not None
        else DEVELOPMENT_RULES if opening == "development" else CONTROL_RULES
    )
    counter_policies = {
        "height_interceptor",
        "artillery_battery",
        "hybrid_height",
        "sovereign_race",
    }
    baseline_policies = {
        "tactical",
        "spy_rush",
        "artillery_rush",
        "height_rush",
        "sovereign_race",
    }
    if set(policies) == baseline_policies and seeds >= 25:
        stage_title = "Material-flow and decision baseline tournament"
    elif counter_policies.intersection(policies):
        stage_title = "Stage D height-counter policy tournament"
    elif "reserve_hoarder" in policies or "evasion" in policies:
        stage_title = "Stage C full policy tournament"
    elif seeds >= 25:
        stage_title = "Stage B policy screening tournament"
    else:
        stage_title = "Stage A policy smoke tournament"
    lines = [
        f"# {stage_title}",
        "",
        f"- Policies: {', '.join(policies)}",
        f"- Paired seeds per cross-policy matchup: {seeds}",
        f"- Seed range: {seed_start}-{seed_start + seeds - 1}",
        f"- Maximum plies: {max_plies}",
        f"- Opening: {opening}",
        f"- Ruleset: {active_rules.id}",
        f"- Piece catalog: {active_rules.catalog_id} (`{active_rules.catalog_hash}`)",
        "- Every cross-policy seed is played twice with colors swapped.",
        "",
        "## Cross-policy paired results",
        "",
        "| Matchup | A wins | B wins | White wins | Black wins | Draws | Limits | A score | Mean plies | Mean post-development plies |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for (a, b), results in paired.items():
        summary = _pair_summary(results, a, b)
        lines.append(
            f"| {a} (A) vs {b} (B) | {summary['wins_a']:.0f} | "
            f"{summary['wins_b']:.0f} | {summary['white_wins']:.0f} | "
            f"{summary['black_wins']:.0f} | {summary['draws']:.0f} | "
            f"{summary['limits']:.0f} | {summary['score_a']:.1%} | "
            f"{summary['mean_plies']:.1f} | {summary['mean_normal_plies']:.1f} |"
        )

    lines += [
        "",
        "## Color-swapped pair outcomes",
        "",
        "A sweep means that policy won both color assignments for the same seed.",
        "",
        "| Matchup | A sweeps | B sweeps | Split pairs | Unresolved pairs |",
        "|---|---:|---:|---:|---:|",
    ]
    for (a, b), results in paired.items():
        summary = _pair_summary(results, a, b)
        lines.append(
            f"| {a} (A) vs {b} (B) | {summary['a_sweeps']:.0f} | "
            f"{summary['b_sweeps']:.0f} | {summary['splits']:.0f} | "
            f"{summary['unresolved_pairs']:.0f} |"
        )

    if active_rules.infiltration_victory:
        total_infiltrations = sum(telemetry[name]["wins_infiltration"] for name in policies)
        total_captures = sum(telemetry[name]["wins_sovereign_capture"] for name in policies)
        total_games = sum(len(results) for results in paired.values()) + sum(
            len(results) for results in self_play.values()
        )
        lines += [
            "",
            "## Victory-condition diagnostics",
            "",
            f"Across all {total_games} games, {total_infiltrations} ended by back-row infiltration and {total_captures} ended by Sovereign capture. Infiltration is immediate and has no reserve or survival requirement.",
            "",
            "| Policy | Infiltration wins | Sovereign-capture wins | Mean infiltration ply | Mean opposing reserve | Opponent had reserve | By ply 30 | By ply 60 | Destination threatened |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for name in policies:
            s = telemetry[name]
            wins = s["wins_infiltration"]
            lines.append(
                f"| {name} | {wins} | {s['wins_sovereign_capture']} | "
                f"{s['infiltration_win_normal_ply_total'] / wins:.1f} | "
                f"{s['infiltration_opponent_reserve_total'] / wins:.2f} | "
                f"{_pct(s['infiltration_with_opponent_reserve'], wins)} | "
                f"{_pct(s['infiltration_by_normal_ply_30'], wins)} | "
                f"{_pct(s['infiltration_by_normal_ply_60'], wins)} | "
                f"{_pct(s['infiltration_ending_threatened'], wins)} |"
                if wins
                else f"| {name} | 0 | {s['wins_sovereign_capture']} | n/a | n/a | n/a | n/a | n/a | n/a |"
            )
        lines += [
            "",
            "Back-row destination files: "
            + ", ".join(
                f"{'ABCDEFGHI'[file]}={sum(telemetry[name][f'infiltration_file_{file}'] for name in policies)}"
                for file in range(9)
            )
            + ".",
        ]

    if opening == "development":
        development_kinds = (
            PieceType.INFANTRY,
            PieceType.DRAGOON,
            PieceType.CHARIOT,
            PieceType.GRIFFIN,
            PieceType.MARSHAL,
            PieceType.REINFORCEMENT,
        )
        lines += [
            "",
            "## Development-opening diagnostics",
            "",
            "Sovereigns are fixed at E1/E9 for this first controlled comparison. Each player then makes four kitchen placements; special pieces are unavailable and height three remains locked until that player completes a non-Sovereign MOVE.",
            "",
            "| Policy | Development actions | Infantry | Dragoon | Chariot | Griffin | Marshal | Reinforcement | Height-1 results | Height-2 results | Back rank | Middle rank | Front rank |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for name in policies:
            s = telemetry[name]
            lines.append(
                f"| {name} | {s['development_actions']} | "
                + " | ".join(
                    str(s[f"development_piece_{kind.value}"])
                    for kind in development_kinds
                )
                + f" | {s['development_result_height_1']} | "
                f"{s['development_result_height_2']} | "
                f"{s['development_rank_1'] + s['development_rank_9']} | "
                f"{s['development_rank_2'] + s['development_rank_8']} | "
                f"{s['development_rank_3'] + s['development_rank_7']} |"
            )

        def mean_first(s: Counter, event: str) -> str:
            games = s[f"games_with_first_{event}"]
            return (
                f"{s[f'first_{event}_normal_ply_total'] / games:.1f}"
                if games
                else "n/a"
            )

        lines += [
            "",
            "### Post-development timing",
            "",
            "Ply timing begins with White's first normal turn after development. Means include only player-games in which the event occurred.",
            "",
            "| Policy | First non-Sovereign MOVE | First height 3 | First Spy conversion | First artillery shot | First Sovereign threat |",
            "|---|---:|---:|---:|---:|---:|",
        ]
        for name in policies:
            s = telemetry[name]
            h3_games = s["games_with_height_three"]
            h3_mean = (
                f"{s['first_height_three_normal_ply_total'] / h3_games:.1f}"
                if h3_games
                else "n/a"
            )
            lines.append(
                f"| {name} | {mean_first(s, 'nonsovereign_move')} | {h3_mean} | "
                f"{mean_first(s, 'spy_conversion')} | "
                f"{mean_first(s, 'artillery_shot')} | "
                f"{mean_first(s, 'sovereign_threat')} |"
            )

        total_first_moves = sum(
            telemetry[name]["first_mover_games"] for name in policies
        )
        total_immediate = sum(
            telemetry[name]["first_move_immediate"] for name in policies
        )
        total_preplacements = sum(
            telemetry[name]["first_move_global_preplacements_total"]
            for name in policies
        )
        total_white_first = sum(
            telemetry[name]["first_mover_color_white"] for name in policies
        )
        lines += [
            "",
            "### First-MOVE tension diagnostics",
            "",
            (
                f"Across {total_first_moves} games with a MOVE, the first MOVE was "
                f"immediate in {_pct(total_immediate, total_first_moves)} of games. "
                f"Players made {total_preplacements / total_first_moves:.2f} optional "
                f"placements on average after MOVE became legal but before either "
                f"player moved; White moved first in "
                f"{_pct(total_white_first, total_first_moves)} of games."
            ),
            "",
            "| Policy | Mean own first MOVE ply | Optional placements before own first MOVE | First-mover games | Mean global first-MOVE ply | Mean placements before global first MOVE | Immediate first MOVE | First-mover score |",
            "|---|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for name in policies:
            s = telemetry[name]
            own_move_games = s["games_with_first_any_move"]
            first_mover_games = s["first_mover_games"]
            first_mover_score = (
                s["first_mover_wins"]
                + 0.5 * (s["first_mover_draws"] + s["first_mover_limits"])
            ) / first_mover_games
            lines.append(
                f"| {name} | "
                f"{s['first_any_move_normal_ply_total'] / own_move_games:.1f} | "
                f"{s['optional_placements_before_own_first_move'] / own_move_games:.2f} | "
                f"{first_mover_games} | "
                f"{s['first_move_global_normal_ply_total'] / first_mover_games:.1f} | "
                f"{s['first_move_global_preplacements_total'] / first_mover_games:.2f} | "
                f"{_pct(s['first_move_immediate'], first_mover_games)} | "
                f"{first_mover_score:.1%} |"
            )

    lines += [
        "",
        "## Reserve-retention and capture-choice diagnostics",
        "",
        "Protected reserve pieces are Infantry, Dragoons, Chariots, Griffins, and Marshals.",
        "",
        "| Policy | Mean reserve during turns | Mean protected reserve | Mean final reserve | Mean final protected reserve | Capture opportunities | Captures declined | Decline rate |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        samples = s["reserve_sample_count"]
        opportunities = s["capture_opportunities"]
        lines.append(
            f"| {name} | {s['reserve_pieces_sample_total'] / samples:.2f} | "
            f"{s['protected_reserve_sample_total'] / samples:.2f} | "
            f"{s['final_reserve_pieces_total'] / s['player_games']:.2f} | "
            f"{s['final_protected_reserve_total'] / s['player_games']:.2f} | "
            f"{opportunities} | {s['captures_declined']} | "
            f"{_pct(s['captures_declined'], opportunities)} |"
        )

    reserve_kinds = [kind for kind in PieceType if kind is not PieceType.SOVEREIGN]
    report_initial_state = initial_state(active_rules)
    lines += [
        "",
        "### Mean final reserve by piece",
        "",
        "Values are pieces remaining in reserve per player-game. The starting reserve is shown for comparison; the Sovereign begins on the board.",
        "",
        "| Policy | "
        + " | ".join(piece_display_name(kind) for kind in reserve_kinds)
        + " | Total |",
        "|---|" + "---:|" * (len(reserve_kinds) + 1),
        "| Starting reserve | "
        + " | ".join(
            str(report_initial_state.reserves[Player.WHITE][kind])
            for kind in reserve_kinds
        )
        + f" | {sum(report_initial_state.reserves[Player.WHITE].values())} |",
    ]
    for name in policies:
        s = telemetry[name]
        games = s["player_games"]
        lines.append(
            f"| {name} | "
            + " | ".join(
                f"{s[f'final_reserve_{kind.value}_total'] / games:.2f}"
                for kind in reserve_kinds
            )
            + f" | {s['final_reserve_pieces_total'] / games:.2f} |"
        )

    all_kinds = list(PieceType)
    lines += [
        "",
        "## Material-flow diagnostics",
        "",
        "Direct deployment moves a piece from reserve to board. Spy replacement moves matching pieces from reserve under a converting Spy. Enemy removals are credited to the acting policy.",
        "",
        "| Policy | Direct reserve→board | Spy replacement reserve→board | Recall discard→board | Recall tokens spent | Enemy removed by MOVE | Own lost in MOVE attrition | Enemy removed by Spy | Enemy removed by artillery |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        direct = sum(s[f"direct_reserve_to_board_{kind.value}"] for kind in all_kinds)
        replacements = sum(
            s[f"spy_replacement_reserve_to_board_{kind.value}"] for kind in all_kinds
        )
        recalled = sum(s[f"discard_to_board_{kind.value}"] for kind in all_kinds)
        removed_move = sum(s[f"enemy_removed_move_{kind.value}"] for kind in all_kinds)
        own_move_attrition = sum(
            s[f"own_removed_move_attrition_{kind.value}"] for kind in all_kinds
        )
        removed_spy = sum(s[f"enemy_removed_spy_{kind.value}"] for kind in all_kinds)
        removed_artillery = sum(
            s[f"enemy_removed_artillery_{kind.value}"] for kind in all_kinds
        )
        lines.append(
            f"| {name} | {direct} | {replacements} | {recalled} | "
            f"{s['material_recall_tokens_spent']} | {removed_move} | "
            f"{own_move_attrition} | {removed_spy} | {removed_artillery} |"
        )

    lines += [
        "",
        "### Attrition events",
        "",
        "| Policy | Shorter MOVE attacks | Shorter artillery attacks |",
        "|---|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        lines.append(
            f"| {name} | {s['move_attrition_events']} | "
            f"{s['artillery_attrition_events']} |"
        )

    lines += [
        "",
        "### Royal Attack",
        "",
        "Royal Attacks are Sovereign captures of taller adjacent stacks. A protected attack remains legal; `Ends threatened` means the Sovereign could be captured on the opponent's immediate reply.",
        "",
        "| Policy | Royal Attacks | Height-2 targets | Height-3 targets | Pieces removed | Material value removed | Sovereign captures | Ends threatened |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        lines.append(
            f"| {name} | {s['royal_attacks']} | {s['royal_target_height_2']} | "
            f"{s['royal_target_height_3']} | {s['royal_removed_pieces']} | "
            f"{s['royal_removed_value']:.1f} | {s['royal_sovereign_captures']} | "
            f"{s['royal_attacks_ending_threatened']} |"
        )

    lines += [
        "",
        "### Material flow by piece",
        "",
        "| Policy | Piece | Direct deployment | Spy replacement | Recalled | Enemy removed by MOVE | Own lost in MOVE attrition | Removed by Spy | Removed by artillery |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        for kind in all_kinds:
            values = (
                s[f"direct_reserve_to_board_{kind.value}"],
                s[f"spy_replacement_reserve_to_board_{kind.value}"],
                s[f"discard_to_board_{kind.value}"],
                s[f"enemy_removed_move_{kind.value}"],
                s[f"own_removed_move_attrition_{kind.value}"],
                s[f"enemy_removed_spy_{kind.value}"],
                s[f"enemy_removed_artillery_{kind.value}"],
            )
            if any(values):
                lines.append(
                    f"| {name} | {piece_display_name(kind)} | "
                    + " | ".join(str(value) for value in values)
                    + " |"
                )

    lines += [
        "",
        "### Mean final material location",
        "",
        "Each row should conserve the original 27-piece inventory, apart from rounding.",
        "",
        "| Policy | Reserve | Board | Discard | Total |",
        "|---|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        games = s["player_games"]
        final_reserve = sum(s[f"final_reserve_{kind.value}_total"] for kind in all_kinds) / games
        final_board = sum(s[f"final_board_{kind.value}_total"] for kind in all_kinds) / games
        final_discard = sum(s[f"final_discard_{kind.value}_total"] for kind in all_kinds) / games
        lines.append(
            f"| {name} | {final_reserve:.2f} | {final_board:.2f} | "
            f"{final_discard:.2f} | {final_reserve + final_board + final_discard:.2f} |"
        )

    lines += [
        "",
        "## 3 Stack performance by TOP piece",
        "",
        "Exposure is the number of owner turns for which a 3 Stack was present, grouped by its TOP piece. Capture value uses the provisional material values.",
        "",
        "| Policy | TOP piece | Created | Exposure | Moves | Captures | Capture value | Sovereign threats | Sovereign captures | Common foundations |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    tracked_tops = (
        PieceType.INFANTRY,
        PieceType.DRAGOON,
        PieceType.CHARIOT,
        PieceType.GRIFFIN,
        PieceType.MARSHAL,
        PieceType.SPY,
        PieceType.BALLISTA,
        PieceType.TREBUCHET,
    )
    for name in policies:
        s = telemetry[name]
        for top in tracked_tops:
            created = s[f"h3_created_{top.value}"]
            exposure = s[f"h3_exposure_{top.value}"]
            if not created and not exposure:
                continue
            foundations = sorted(
                (
                    (piece_display_name(kind), s[f"h3_foundation_{top.value}_{kind.value}"])
                    for kind in PieceType
                    if s[f"h3_foundation_{top.value}_{kind.value}"]
                ),
                key=lambda item: item[1],
                reverse=True,
            )[:2]
            foundation_text = ", ".join(
                f"{kind}={count}" for kind, count in foundations
            ) or "-"
            lines.append(
                f"| {name} | {piece_display_name(top)} | {created} | {exposure} | "
                f"{s[f'h3_moves_{top.value}']} | {s[f'h3_captures_{top.value}']} | "
                f"{s[f'h3_capture_value_{top.value}']:.1f} | "
                f"{s[f'h3_sovereign_threats_{top.value}']} | "
                f"{s[f'h3_sovereign_captures_{top.value}']} | {foundation_text} |"
            )

    lines += [
        "",
        "## Neutral-territory diagnostics",
        "",
        "| Policy | Open neutral placements | Mean own neutral stacks during turns | Mean opposing neutral stacks | Mean final neutral stacks |",
        "|---|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        samples = s["neutral_sample_count"]
        lines.append(
            f"| {name} | {s['open_neutral_placements']} | "
            f"{s['own_neutral_stacks_sample_total'] / samples:.2f} | "
            f"{s['enemy_neutral_stacks_sample_total'] / samples:.2f} | "
            f"{s['final_neutral_stacks_total'] / s['player_games']:.2f} |"
        )

    lines += [
        "",
        "## Stack-height construction diagnostics",
        "",
        "| Policy | Height-2 placement results | Height-3 placement results | Mobile height-3 created | Immobile height-3 created | Mean height-3 stacks during turns | Mean mobile height-3 stacks | Mean first height-3 ply |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        samples = s["height_three_sample_count"]
        mean_first = (
            s["first_height_three_ply_total"] / s["games_with_height_three"]
            if s["games_with_height_three"]
            else 0
        )
        lines.append(
            f"| {name} | {s['placement_result_height_2']} | "
            f"{s['placement_result_height_3']} | {s['mobile_height_three_created']} | "
            f"{s['immobile_height_three_created']} | "
            f"{s['height_three_stacks_sample_total'] / samples:.2f} | "
            f"{s['mobile_height_three_sample_total'] / samples:.2f} | "
            f"{mean_first:.1f} |"
        )

    lines += [
        "",
        "## Self-play",
        "",
        "| Policy | White wins | Black wins | Draws | Limits | Mean plies | Mean post-development plies |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for name, results in self_play.items():
        white = sum(result.winner is Player.WHITE for result in results)
        black = sum(result.winner is Player.BLACK for result in results)
        draws = sum(result.draw for result in results)
        limits = sum(result.hit_limit for result in results)
        mean_plies = sum(result.plies for result in results) / len(results)
        mean_normal = sum(
            result.plies - result.development_plies for result in results
        ) / len(results)
        lines.append(
            f"| {name} | {white} | {black} | {draws} | {limits} | "
            f"{mean_plies:.1f} | {mean_normal:.1f} |"
        )

    lines += [
        "",
        "## Inferred primary decision reasons",
        "",
        "Each action receives one mutually exclusive primary reason, inferred from the policy's priority and the immediate board effect. Directed actions are all categories except ordinary development and quiet movement.",
        "",
        "| Policy | Actions | Sovereign capture | Infiltration win | Forced defense | Sovereign threat | Spy conversion | Spy mobilization | Artillery attack | Height build | Material capture | Development | Quiet move | Directed |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        actions = s["actions"]
        directed = sum(
            s[f"decision_{reason}"]
            for reason in DECISION_REASONS
            if reason not in {"development", "quiet_move"}
        )
        lines.append(
            f"| {name} | {actions} | "
            + " | ".join(
                f"{s[f'decision_{reason}']} ({_pct(s[f'decision_{reason}'], actions)})"
                for reason in DECISION_REASONS
            )
            + f" | {_pct(directed, actions)} |"
        )

    lines += [
        "",
        "## Sovereign-threat sources",
        "",
        "Only newly created Sovereign threats are counted.",
        "",
        "| Policy | MOVE | Ordinary PLACE | Recall PLACE | Infantry | Dragoon | Chariot | Griffin | Marshal | Sovereign |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        lines.append(
            f"| {name} | {s['sovereign_threat_source_move']} | "
            f"{s['sovereign_threat_source_place']} | {s['sovereign_threat_source_recall']} | "
            f"{s['sovereign_threat_piece_infantry']} | {s['sovereign_threat_piece_dragoon']} | "
            f"{s['sovereign_threat_piece_chariot']} | {s['sovereign_threat_piece_griffin']} | "
            f"{s['sovereign_threat_piece_marshal']} | {s['sovereign_threat_piece_sovereign']} |"
        )

    lines += [
        "",
        "## Policy behavior",
        "",
        "| Policy | Actions | Opening PLACE | Middle PLACE | Ending PLACE | Spy conversions | Artillery fired | No-fire artillery |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        stats = telemetry[name]
        lines.append(
            f"| {name} | {stats['actions']} | "
            f"{_pct(stats['phase_opening_placements'], stats['phase_opening_actions'])} | "
            f"{_pct(stats['phase_middle_placements'], stats['phase_middle_actions'])} | "
            f"{_pct(stats['phase_ending_placements'], stats['phase_ending_actions'])} | "
            f"{stats['spy_conversions']} | {stats['artillery_shots']} | "
            f"{stats['artillery_no_fire']} |"
        )

    lines += [
        "",
        "## Artillery height and range diagnostics",
        "",
        "| Policy | Shots | Height 1 | Height 2 | Height 3 | Range 1-3 | Range 4-5 | Range 6-9 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        short = sum(s[f"artillery_range_{distance}_shots"] for distance in range(1, 4))
        medium = sum(s[f"artillery_range_{distance}_shots"] for distance in range(4, 6))
        long = sum(s[f"artillery_range_{distance}_shots"] for distance in range(6, 10))
        lines.append(
            f"| {name} | {s['artillery_shots']} | "
            f"{s['artillery_height_1_shots']} | {s['artillery_height_2_shots']} | "
            f"{s['artillery_height_3_shots']} | {short} | {medium} | {long} |"
        )

    lines += [
        "",
        "## Spy diagnostics",
        "",
        "| Policy | Conversions | Non-converting placements | In enemy territory | Single Infantry | Survived reply | Mobilized afterward | Mean target value |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        stats = telemetry[name]
        mean_target = stats["spy_target_value_total"] / stats["spy_conversions"] if stats["spy_conversions"] else 0
        lines.append(
            f"| {name} | {stats['spy_conversions']} | "
            f"{stats['spy_nonconversion_placements']} | "
            f"{stats['spy_enemy_territory_conversions']} | "
            f"{stats['spy_single_infantry_conversions']} | "
            f"{stats['spy_survived_reply']} | {stats['spy_stacks_mobilized']} | "
            f"{mean_target:.2f} |"
        )

    lines += [
        "",
        "## Griffin 3 Stack move diagnostics",
        "",
        "Legal counts are generated legal actions, while chosen counts are actual moves.",
        "",
        "| Policy | Eligible turns | 2x3 legal | 2x3 chosen | 2x3 captures | 2x3 Sovereign threats | 2x3 Sovereign captures |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        lines.append(
            f"| {name} | {s['griffin_h3_eligible_turns']} | "
            f"{s['griffin_h3_long_legal']} | "
            f"{s['griffin_h3_long_chosen']} | "
            f"{s['griffin_h3_long_captures']} | "
            f"{s['griffin_h3_long_sovereign_threats']} | "
            f"{s['griffin_h3_long_sovereign_captures']} |"
        )

    lines += [
        "",
        "## Long-game and avoidance diagnostics",
        "",
        "| Policy | Games observed | Mean max no-capture run | Largest no-capture run | Mean max quiet-MOVE run | Largest quiet-MOVE run | 200+ plies | 300+ plies | At limit | Max position repeats |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        s = telemetry[name]
        games = s["games_observed"]
        lines.append(
            f"| {name} | {games} | {s['max_no_capture_total'] / games:.1f} | "
            f"{s['largest_no_capture']} | {s['max_no_progress_total'] / games:.1f} | "
            f"{s['largest_no_progress']} | {s['games_200_plus']} | "
            f"{s['games_300_plus']} | {s['games_at_limit']} | "
            f"{s['max_position_repeats']} |"
        )

    limit_results = [
        result
        for results in (*paired.values(), *self_play.values())
        for result in results
        if result.hit_limit and result.limit_diagnostics is not None
    ]
    categories: dict[str, list[GameResult]] = defaultdict(list)
    for result in limit_results:
        categories[str(result.limit_diagnostics["category"])].append(result)
    lines += [
        "",
        "### Ply-limit endgame classification",
        "",
        "Classifications describe the final position, not a formal game result. `Active tactical cutoff` means at least one capture or Sovereign threat was present at the limit; `missed immediate win` means the side to move could capture the Sovereign immediately.",
        "",
        "| Category | Games | Mean board pieces | Mean reserve pieces | Mean legal captures | Mean plies since capture | Mean quiet-MOVE run | Mean max repeats | Representative games |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for category, results in sorted(categories.items(), key=lambda item: (-len(item[1]), item[0])):
        count = len(results)
        diagnostics = [result.limit_diagnostics for result in results]
        representatives = ", ".join(
            f"{result.white_policy}–{result.black_policy} s{result.seed}"
            for result in results[:3]
        )
        lines.append(
            f"| {category.replace('_', ' ')} | {count} | "
            f"{sum(int(d['board_pieces']) for d in diagnostics) / count:.1f} | "
            f"{sum(int(d['reserve_pieces']) for d in diagnostics) / count:.1f} | "
            f"{sum(int(d['legal_captures']) for d in diagnostics) / count:.1f} | "
            f"{sum(int(d['plies_since_capture']) for d in diagnostics) / count:.1f} | "
            f"{sum(int(d['quiet_move_run']) for d in diagnostics) / count:.1f} | "
            f"{sum(int(d['max_position_repeats']) for d in diagnostics) / count:.1f} | "
            f"{representatives} |"
        )
    if not limit_results:
        lines.append("| none | 0 | — | — | — | — | — | — | — |")

    missing_sovereign_limits = sum(
        not all(result.limit_diagnostics["sovereigns_present"].values())
        for result in limit_results
    )
    immediate_wins = sum(
        int(result.limit_diagnostics["immediate_sovereign_captures"])
        for result in limit_results
    )
    lines += [
        "",
        f"All {len(limit_results)} ply-limit positions retained both Sovereigns: **{'yes' if missing_sovereign_limits == 0 else 'no'}**. Immediate Sovereign captures available at the limit: **{immediate_wins}**.",
    ]

    lines += [
        "",
        "## Notes",
        "",
        (
            "This is a targeted confirmation tournament. Two hundred color-swapped games per cross-policy matchup provide a substantially stronger comparison, but still measure these specific policies rather than optimal play. Ply-limit games count as half a point for each policy in the paired score."
            if seeds >= 100
            else (
                "This is a screening tournament. Fifty color-swapped games per cross-policy matchup can identify strong candidates for targeted confirmation, but do not establish optimal play or final balance. Ply-limit games count as half a point for each policy in the paired score."
                if seeds >= 25
                else "This is a smoke tournament, so ten cross-policy games per matchup are enough to expose configuration errors and large behavioral differences, but not enough to establish balance. Ply-limit games count as half a point for each policy in the paired score."
            )
        ),
        "",
    ]
    if "evasion" in policies:
        lines += [
            "Evasion self-play remains listed in the self-play table but is excluded from aggregate policy-behavior, reserve, height, and long-game diagnostics because mutual evasion is a deliberately cooperative non-game scenario.",
            "",
        ]
    return "\n".join(lines)


def run_tournament(
    policies: tuple[str, ...],
    seeds: int,
    seed_start: int,
    max_plies: int,
    opening: str = "standard",
    ruleset_id: str | None = None,
    limit_replay_dir: Path | None = None,
) -> tuple[str, dict[str, Counter]]:
    # A named ruleset is authoritative; keep opening for legacy callers.
    if ruleset_id is not None:
        opening = "development" if ruleset_by_id(ruleset_id).development_opening else "standard"
    telemetry: dict[str, Counter] = defaultdict(Counter)
    limit_replays: list[dict[str, object]] | None = [] if limit_replay_dir else None
    paired: dict[tuple[str, str], list[GameResult]] = {}
    for a, b in itertools.combinations(policies, 2):
        results = []
        for offset in range(seeds):
            seed = seed_start + offset
            results.append(
                play_game(
                    a, b, seed, max_plies, telemetry, opening,
                    ruleset_id=ruleset_id,
                    limit_replays=limit_replays,
                )
            )
            results.append(
                play_game(
                    b, a, seed, max_plies, telemetry, opening,
                    ruleset_id=ruleset_id,
                    limit_replays=limit_replays,
                )
            )
        paired[(a, b)] = results

    self_play: dict[str, list[GameResult]] = {}
    for name in policies:
        self_play[name] = [
            play_game(
                name, name, seed_start + offset, max_plies, telemetry, opening,
                ruleset_id=ruleset_id,
                limit_replays=limit_replays,
            )
            for offset in range(seeds)
        ]
    if limit_replay_dir is not None and limit_replays is not None:
        limit_replay_dir.mkdir(parents=True, exist_ok=True)
        for replay in limit_replays:
            path = limit_replay_dir / f"{replay['game_id']}.json"
            path.write_text(json.dumps(replay, indent=2) + "\n", encoding="utf-8")
    return (
        build_report(
            policies, seeds, seed_start, max_plies, paired, self_play,
            telemetry, opening, ruleset_id,
        ),
        telemetry,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policies", nargs="+", default=list(DEFAULT_POLICIES))
    parser.add_argument("--seeds", type=int, default=5)
    parser.add_argument("--seed-start", type=int, default=20001)
    parser.add_argument("--max-plies", type=int, default=500)
    parser.add_argument(
        "--opening", choices=("standard", "development"), default="standard"
    )
    parser.add_argument(
        "--ruleset",
        choices=tuple(RULESETS_BY_ID),
        help="Named shared ruleset; overrides --opening",
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--limit-replay-dir",
        type=Path,
        help="Save every ply-limit game as a replay JSON file in this directory",
    )
    args = parser.parse_args()
    report, _ = run_tournament(
        tuple(args.policies), args.seeds, args.seed_start, args.max_plies,
        args.opening, args.ruleset, args.limit_replay_dir,
    )
    if args.output:
        args.output.write_text(report + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
