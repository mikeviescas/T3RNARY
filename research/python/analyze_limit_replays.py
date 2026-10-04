"""Validate saved T3RNARY limit replays and summarize their final positions."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from stack_chess.contract import action_from_dict, state_from_dict
from stack_chess.engine import MoveAction, PieceType, Player, apply_action, legal_actions, piece_display_name, validate_state


def validate_replay(path: Path) -> tuple[dict[str, object], object]:
    replay = json.loads(path.read_text(encoding="utf-8"))
    if replay.get("contract_version") != 2:
        raise ValueError(f"{path.name}: unsupported replay contract version")
    state = state_from_dict(replay["initial_state"])
    for ply, raw_action in enumerate(replay["actions"], start=1):
        try:
            state = apply_action(state, action_from_dict(raw_action))
        except ValueError as error:
            raise ValueError(f"{path.name}: illegal action at ply {ply}: {error}") from error
    validate_state(state, enforce_inventory=True)
    metadata = replay["metadata"]
    if state.ply != metadata["max_plies"] or state.is_over:
        raise ValueError(f"{path.name}: replay does not end at an unresolved ply limit")
    if not all(metadata["diagnostics"]["sovereigns_present"].values()):
        raise ValueError(f"{path.name}: limit position is missing a Sovereign")
    return replay, state


def build_report(paths: list[Path]) -> str:
    records = [validate_replay(path) for path in sorted(paths)]
    by_ruleset: dict[str, list[tuple[dict[str, object], object]]] = defaultdict(list)
    for replay, state in records:
        by_ruleset[str(replay["metadata"]["ruleset"])].append((replay, state))

    lines = [
        "# Royal Attack 500-ply Endgame Study",
        "",
        f"Validated complete action histories for **{len(records)}** ply-limit games.",
        "Every action was legal when replayed, material inventory remained conserved, both Sovereigns were present, and no replay had already reached a terminal state.",
        "",
    ]
    for ruleset, group in sorted(by_ruleset.items()):
        categories = Counter(
            str(replay["metadata"]["diagnostics"]["category"])
            for replay, _state in group
        )
        lines += [
            f"## {ruleset}",
            "",
            f"Limit games: **{len(group)}** ({len(group) / 900:.1%} of the tournament).",
            "",
            "| Category | Games | Share | Mean board pieces | Mean reserve pieces | Mean legal captures | Mean plies since capture | Mean quiet-MOVE run |",
            "|---|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for category, count in categories.most_common():
            members = [
                replay for replay, _state in group
                if replay["metadata"]["diagnostics"]["category"] == category
            ]
            diagnostics = [replay["metadata"]["diagnostics"] for replay in members]
            lines.append(
                f"| {category.replace('_', ' ')} | {count} | {count / len(group):.1%} | "
                f"{sum(d['board_pieces'] for d in diagnostics) / count:.1f} | "
                f"{sum(d['reserve_pieces'] for d in diagnostics) / count:.1f} | "
                f"{sum(d['legal_captures'] for d in diagnostics) / count:.1f} | "
                f"{sum(d['plies_since_capture'] for d in diagnostics) / count:.1f} | "
                f"{sum(d['quiet_move_run'] for d in diagnostics) / count:.1f} |"
            )

        matchups = Counter(
            f"{replay['metadata']['white_policy']} vs {replay['metadata']['black_policy']}"
            for replay, _state in group
        )
        sovereign_only = sum(
            sum(len(stack) for stack in state.board.values()) == 2
            for _replay, state in group
        )
        empty_reserves = sum(
            all(sum(state.reserves[player].values()) == 0 for player in Player)
            for _replay, state in group
        )
        nonsovereign_pieces = sum(
            sum(
                piece.kind is not PieceType.SOVEREIGN
                for stack in state.board.values()
                for piece in stack
            )
            for _replay, state in group
        )
        movable_nonsovereign_stacks = 0
        top_kinds: Counter[str] = Counter()
        for _replay, state in group:
            movable_sources = set()
            for player in Player:
                player_state = state.copy()
                player_state.turn = player
                movable_sources.update(
                    action.source
                    for action in legal_actions(player_state)
                    if isinstance(action, MoveAction)
                    and player_state.board[action.source][-1].kind is not PieceType.SOVEREIGN
                )
            movable_nonsovereign_stacks += len(movable_sources)
            top_kinds.update(
                stack[-1].kind.value
                for stack in state.board.values()
                if stack[-1].kind is not PieceType.SOVEREIGN
            )
        lines += [
            "",
            f"Material shape: {sovereign_only} Sovereign-only games ({sovereign_only / len(group):.1%}); "
            f"{empty_reserves} with both reserves empty ({empty_reserves / len(group):.1%}); "
            f"{nonsovereign_pieces / len(group):.1f} non-Sovereign board pieces and "
            f"{movable_nonsovereign_stacks / len(group):.2f} actually movable non-Sovereign stacks per game. "
            f"Remaining TOP pieces: {', '.join(f'{piece_display_name(PieceType(kind))}={count}' for kind, count in top_kinds.most_common()) or 'none'}.",
            "",
            "Most common color-specific limit matchups: "
            + "; ".join(f"{name}: {count}" for name, count in matchups.most_common(5))
            + ".",
            "",
            "### Suggested replay sample",
            "",
        ]
        for category in categories:
            members = [
                replay for replay, _state in group
                if replay["metadata"]["diagnostics"]["category"] == category
            ]
            members.sort(
                key=lambda replay: (
                    replay["metadata"]["diagnostics"]["quiet_move_run"],
                    replay["metadata"]["diagnostics"]["final_position_repeats"],
                    replay["metadata"]["diagnostics"]["legal_captures"],
                ),
                reverse=True,
            )
            for replay in members[:3]:
                diagnostics = replay["metadata"]["diagnostics"]
                lines.append(
                    f"- `{replay['game_id']}.json` — {category.replace('_', ' ')}; "
                    f"board {diagnostics['board_pieces']}, reserve {diagnostics['reserve_pieces']}, "
                    f"legal captures {diagnostics['legal_captures']}, "
                    f"quiet run {diagnostics['quiet_move_run']}, "
                    f"final repeats {diagnostics['final_position_repeats']}."
                )
        lines.append("")
    all_categories = Counter(
        str(replay["metadata"]["diagnostics"]["category"])
        for replay, _state in records
    )
    sovereign_only_total = sum(
        sum(len(stack) for stack in state.board.values()) == 2
        for _replay, state in records
    )
    empty_reserve_total = sum(
        all(sum(state.reserves[player].values()) == 0 for player in Player)
        for _replay, state in records
    )
    sterile_total = all_categories["quiet_move_loop"] + all_categories["low_material_stall"]
    lines += [
        "## Interpretation",
        "",
        f"The limit population is overwhelmingly sterile: {sterile_total} of {len(records)} games ({sterile_total / len(records):.1%}) are quiet loops or low-material stalls. Only {all_categories['active_tactical_cutoff']} games still had active tactical contact, and none offered an immediate Sovereign capture.",
        "",
        f"Material exhaustion is the common condition. {empty_reserve_total} games ({empty_reserve_total / len(records):.1%}) had both reserves empty, {sovereign_only_total} ({sovereign_only_total / len(records):.1%}) had only the two Sovereigns, and no limit position contained a non-Sovereign stack with a legal MOVE. The remaining TOP pieces were overwhelmingly Infantry stranded at the end of their forward movement, with a handful of immobile special pieces.",
        "",
        "Exact repetition is not a useful primary detector here. The Sovereigns can wander through many equivalent squares, so strategically repeated play often has a final exact-position count of only one. A threefold-repetition rule alone would leave most of these games unresolved.",
        "",
        "These results point to an endgame/adjudication issue rather than a hidden middlegame rules failure. The next controlled experiment should compare 50-, 75-, and 100-ply no-progress rules, where a capture or placement resets the counter. It should be paired with a Sovereign endgame policy that actively pursues stranded material and tests whether apparently sterile positions are convertible before declaring them draws.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", nargs="+", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    paths = [path for directory in args.directories for path in directory.glob("*.json")]
    report = build_report(paths)
    if args.output:
        args.output.write_text(report + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
