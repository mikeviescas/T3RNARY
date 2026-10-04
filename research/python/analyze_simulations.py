"""Collect descriptive statistics from reproducible random legal games."""

from __future__ import annotations

import argparse
import random
import statistics
from collections import Counter

from stack_chess import (
    MoveAction,
    PieceType,
    PlaceAction,
    Player,
    RecallAction,
    apply_action,
    initial_state,
    is_sovereign_threatened,
    legal_actions,
    piece_display_name,
    validate_state,
)
from stack_chess.policies import game_phase, policy_by_name

def percentile(values: list[int], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def mean(values: list[int]) -> float:
    return statistics.fmean(values) if values else 0.0


def run_analysis(
    games: int, max_plies: int, seed: int, policy_name: str = "uniform"
) -> dict[str, object]:
    rng = random.Random(seed)
    policy = policy_by_name(policy_name)
    totals: Counter[str] = Counter()
    by_player = {player: Counter() for player in Player}
    placed_pieces = {player: Counter() for player in Player}
    winning_pieces: Counter[PieceType] = Counter()
    lengths: list[int] = []
    completed_lengths: list[int] = []
    turns = {player: [] for player in Player}
    legal_counts: list[int] = []
    phase_actions = {
        phase: Counter() for phase in ("opening", "middle", "ending")
    }
    phase_stack_heights = {
        phase: Counter() for phase in ("opening", "middle", "ending")
    }
    phase_reserve_counts = {
        phase: [] for phase in ("opening", "middle", "ending")
    }
    placement_plies = {kind: [] for kind in PieceType}
    first_capture_plies: list[int] = []
    first_threat_plies: list[int] = []

    for _ in range(games):
        state = initial_state()
        game_turns = Counter()
        first_capture: int | None = None
        first_threat: int | None = None
        for _ in range(max_plies):
            if state.is_over:
                break
            actions = legal_actions(state)
            if not actions:
                raise AssertionError("non-terminal state has no legal actions")
            legal_counts.append(len(actions))
            player = state.turn
            phase = game_phase(state, player)
            before_own_threat = is_sovereign_threatened(state, player)
            before_enemy_threat = is_sovereign_threatened(state, player.opponent)
            game_turns[player] += 1
            totals["actions"] += 1
            by_player[player]["actions"] += 1

            action = policy.choose(state, actions, rng)
            phase_actions[phase]["actions"] += 1
            if isinstance(action, MoveAction):
                totals["moves"] += 1
                by_player[player]["moves"] += 1
                phase_actions[phase]["moves"] += 1
                moving_kind = state.board[action.source][-1].kind
                target = state.board.get(action.destination)
                if target:
                    if first_capture is None:
                        first_capture = state.ply + 1
                    totals["move_captures"] += 1
                    totals["captured_stacks"] += 1
                    totals["captured_pieces"] += len(target)
                    by_player[player]["move_captures"] += 1
                    if target[-1].kind is PieceType.SOVEREIGN:
                        winning_pieces[moving_kind] += 1
            else:
                totals["placements"] += 1
                by_player[player]["placements"] += 1
                phase_actions[phase]["placements"] += 1
                placed_pieces[player][action.piece] += 1
                placement_plies[action.piece].append(state.ply + 1)
                existing = state.board.get(action.destination)

                if isinstance(action, RecallAction):
                    totals["recalls"] += 1
                    by_player[player]["recalls"] += 1
                else:
                    totals["reserve_placements"] += 1

                if action.piece is PieceType.REINFORCEMENT:
                    totals["reinforcements"] += 1
                    totals["placements_under_stack"] += 1
                elif (
                    action.piece is PieceType.SPY
                    and existing
                    and existing[-1].owner is player.opponent
                ):
                    if first_capture is None:
                        first_capture = state.ply + 1
                    totals["spy_conversions"] += 1
                    totals["captured_stacks"] += 1
                    totals["captured_pieces"] += len(existing)
                elif existing:
                    totals["placements_on_stack"] += 1
                else:
                    totals["placements_on_open_square"] += 1

                if action.piece in {PieceType.BALLISTA, PieceType.TREBUCHET}:
                    if action.effect_target is None:
                        totals["artillery_no_fire"] += 1
                    else:
                        target = state.board[action.effect_target]
                        if first_capture is None:
                            first_capture = state.ply + 1
                        totals["artillery_shots"] += 1
                        totals["captured_stacks"] += 1
                        totals["captured_pieces"] += len(target)

            state = apply_action(state, action)
            validate_state(state, enforce_inventory=True)
            after_own_threat = is_sovereign_threatened(state, player)
            after_enemy_threat = is_sovereign_threatened(state, player.opponent)
            if before_own_threat:
                totals["turns_started_in_threat"] += 1
                if after_own_threat:
                    totals["threats_ignored"] += 1
                else:
                    totals["threats_answered"] += 1
            if after_enemy_threat and not before_enemy_threat:
                totals["new_sovereign_threats"] += 1
                if first_threat is None:
                    first_threat = state.ply
            phase_reserve_counts[phase].append(sum(state.reserves[player].values()))
            phase_stack_heights[phase].update(len(stack) for stack in state.board.values())

        lengths.append(state.ply)
        if first_capture is not None:
            first_capture_plies.append(first_capture)
        if first_threat is not None:
            first_threat_plies.append(first_threat)
        for player in Player:
            turns[player].append(game_turns[player])
        if state.winner:
            totals[f"{state.winner.value}_wins"] += 1
            completed_lengths.append(state.ply)
        elif state.is_draw:
            totals["draws"] += 1
            completed_lengths.append(state.ply)
        else:
            totals["ply_limit_games"] += 1

    return {
        "games": games,
        "max_plies": max_plies,
        "seed": seed,
        "policy": policy.name,
        "totals": totals,
        "by_player": by_player,
        "placed_pieces": placed_pieces,
        "winning_pieces": winning_pieces,
        "lengths": lengths,
        "completed_lengths": completed_lengths,
        "turns": turns,
        "legal_counts": legal_counts,
        "phase_actions": phase_actions,
        "phase_stack_heights": phase_stack_heights,
        "phase_reserve_counts": phase_reserve_counts,
        "placement_plies": placement_plies,
        "first_capture_plies": first_capture_plies,
        "first_threat_plies": first_threat_plies,
    }


def print_report(report: dict[str, object]) -> None:
    games = int(report["games"])
    totals: Counter[str] = report["totals"]  # type: ignore[assignment]
    by_player: dict[Player, Counter[str]] = report["by_player"]  # type: ignore[assignment]
    placed_pieces: dict[Player, Counter[PieceType]] = report["placed_pieces"]  # type: ignore[assignment]
    winning_pieces: Counter[PieceType] = report["winning_pieces"]  # type: ignore[assignment]
    lengths: list[int] = report["lengths"]  # type: ignore[assignment]
    completed: list[int] = report["completed_lengths"]  # type: ignore[assignment]
    turns: dict[Player, list[int]] = report["turns"]  # type: ignore[assignment]
    legal_counts: list[int] = report["legal_counts"]  # type: ignore[assignment]
    phase_actions: dict[str, Counter[str]] = report["phase_actions"]  # type: ignore[assignment]
    phase_stack_heights: dict[str, Counter[int]] = report["phase_stack_heights"]  # type: ignore[assignment]
    phase_reserve_counts: dict[str, list[int]] = report["phase_reserve_counts"]  # type: ignore[assignment]
    placement_plies: dict[PieceType, list[int]] = report["placement_plies"]  # type: ignore[assignment]
    first_capture_plies: list[int] = report["first_capture_plies"]  # type: ignore[assignment]
    first_threat_plies: list[int] = report["first_threat_plies"]  # type: ignore[assignment]

    print(
        f"policy={report['policy']} seed={report['seed']} games={games} "
        f"max_plies={report['max_plies']}"
    )
    print("\nOUTCOMES")
    print(f"White wins: {totals['white_wins']}")
    print(f"Black wins: {totals['black_wins']}")
    print(f"Draws: {totals['draws']}")
    print(f"Reached ply limit: {totals['ply_limit_games']}")

    print("\nGAME LENGTH (one ply = one player's turn)")
    print(
        f"All games: mean {mean(lengths):.2f}, median {statistics.median(lengths):.1f}, "
        f"min {min(lengths)}, Q1 {percentile(lengths, .25):.1f}, "
        f"Q3 {percentile(lengths, .75):.1f}, max {max(lengths)}"
    )
    if completed:
        print(
            f"Completed games only: mean {mean(completed):.2f}, "
            f"median {statistics.median(completed):.1f}, min {min(completed)}, "
            f"max {max(completed)}"
        )
    for player in Player:
        values = turns[player]
        print(
            f"{player.value.title()} turns/game: mean {mean(values):.2f}, "
            f"median {statistics.median(values):.1f}, min {min(values)}, max {max(values)}"
        )

    print("\nACTION MIX BY RESERVE-BASED PHASE")
    for phase in ("opening", "middle", "ending"):
        counts = phase_actions[phase]
        if not counts["actions"]:
            continue
        heights = phase_stack_heights[phase]
        height_total = sum(heights.values())
        height_text = ", ".join(
            f"h{height}={heights[height] / height_total:.1%}" for height in (1, 2, 3)
        )
        print(
            f"{phase.title()}: {counts['actions']} turns; "
            f"MOVE {counts['moves'] / counts['actions']:.1%}, "
            f"PLACE {counts['placements'] / counts['actions']:.1%}; "
            f"mean reserve {mean(phase_reserve_counts[phase]):.2f}; "
            f"stack mix {height_text}"
        )

    actions = totals["actions"]
    print("\nACTION MIX")
    print(f"Total turns: {actions} ({actions / games:.2f} per game)")
    print(
        f"MOVE: {totals['moves']} ({totals['moves'] / actions:.1%}; "
        f"{totals['moves'] / games:.2f}/game)"
    )
    print(
        f"PLACE: {totals['placements']} ({totals['placements'] / actions:.1%}; "
        f"{totals['placements'] / games:.2f}/game)"
    )
    for player in Player:
        counts = by_player[player]
        print(
            f"{player.value.title()}: {counts['moves']} MOVE, "
            f"{counts['placements']} PLACE "
            f"({counts['moves'] / counts['actions']:.1%} / "
            f"{counts['placements'] / counts['actions']:.1%})"
        )

    print("\nPLACEMENT DETAILS")
    print(f"From reserve: {totals['reserve_placements']}")
    print(f"Via Recall: {totals['recalls']}")
    print(f"Onto open squares: {totals['placements_on_open_square']}")
    print(f"Onto friendly stacks: {totals['placements_on_stack']}")
    print(f"Reinforcements under stacks: {totals['placements_under_stack']}")
    print(f"Spy conversions: {totals['spy_conversions']}")
    print(f"Artillery fired: {totals['artillery_shots']}")
    print(f"Artillery placed without firing: {totals['artillery_no_fire']}")
    for player in Player:
        details = ", ".join(
            f"{piece_display_name(kind)}={count}"
            for kind, count in sorted(
                placed_pieces[player].items(), key=lambda item: item[0].value
            )
        )
        print(f"{player.value.title()} placed pieces: {details}")
    timing = ", ".join(
        f"{piece_display_name(kind)}={mean(values):.1f}"
        for kind, values in placement_plies.items()
        if values
    )
    print(f"Mean placement ply by piece: {timing}")

    print("\nREMOVALS")
    print(f"Move captures: {totals['move_captures']}")
    print(f"All removed stacks: {totals['captured_stacks']}")
    print(f"All removed pieces: {totals['captured_pieces']}")
    if winning_pieces:
        details = ", ".join(
            f"{piece_display_name(kind)}={count}"
            for kind, count in sorted(winning_pieces.items(), key=lambda item: item[0].value)
        )
        print(f"Winning Sovereign captures by TOP piece: {details}")

    print("\nTACTICAL TIMING AND SOVEREIGN SAFETY")
    if first_capture_plies:
        print(
            f"First capture: mean ply {mean(first_capture_plies):.2f}, "
            f"median {statistics.median(first_capture_plies):.1f}; "
            f"occurred in {len(first_capture_plies)}/{games} games"
        )
    if first_threat_plies:
        print(
            f"First newly created Sovereign threat: mean ply {mean(first_threat_plies):.2f}, "
            f"median {statistics.median(first_threat_plies):.1f}; "
            f"occurred in {len(first_threat_plies)}/{games} games"
        )
    print(f"Turns begun under Sovereign threat: {totals['turns_started_in_threat']}")
    print(f"Threats answered immediately: {totals['threats_answered']}")
    print(f"Threats ignored or left active: {totals['threats_ignored']}")
    print(f"New Sovereign threats created: {totals['new_sovereign_threats']}")

    print("\nLEGAL-ACTION AVAILABILITY")
    print(
        f"Per turn: mean {mean(legal_counts):.2f}, "
        f"median {statistics.median(legal_counts):.1f}, "
        f"min {min(legal_counts)}, max {max(legal_counts)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--games", type=int, default=100)
    parser.add_argument("--max-plies", type=int, default=500)
    parser.add_argument("--seed", type=int, default=20261001)
    parser.add_argument("--policy", choices=("uniform", "heuristic"), default="uniform")
    args = parser.parse_args()
    print_report(run_analysis(args.games, args.max_plies, args.seed, args.policy))


if __name__ == "__main__":
    main()
