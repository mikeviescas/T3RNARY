"""Analyze kitchen formations produced by development-opening policies."""

from __future__ import annotations

import argparse
import itertools
import random
from collections import Counter, defaultdict
from pathlib import Path

from stack_chess import DEVELOPMENT_RULES, Player, apply_action, initial_state, legal_actions
from stack_chess.engine import FILES
from stack_chess.policies import policy_by_name


def normalized_formation(state, player: Player) -> tuple:
    entries = []
    for (file, rank), stack in state.board.items():
        if stack[-1].owner is not player or stack[-1].kind.value == "sovereign":
            continue
        depth = rank + 1 if player is Player.WHITE else 9 - rank
        entries.append(
            (FILES[file], depth, tuple(piece.kind.value for piece in stack))
        )
    return tuple(sorted(entries))


def formation_text(formation: tuple) -> str:
    return ", ".join(
        f"{file}{depth}=" + "/".join(kind.replace("reinforcement", "FP") for kind in stack)
        for file, depth, stack in formation
    )


def play_development(white_name: str, black_name: str, seed: int):
    state = initial_state(DEVELOPMENT_RULES)
    policies = {
        Player.WHITE: policy_by_name(white_name),
        Player.BLACK: policy_by_name(black_name),
    }
    rng = random.Random(seed)
    while state.in_development:
        actions = legal_actions(state)
        action = policies[state.turn].choose(state, actions, rng)
        state = apply_action(state, action)
    return {
        white_name: [(Player.WHITE, normalized_formation(state, Player.WHITE))],
        black_name: [(Player.BLACK, normalized_formation(state, Player.BLACK))],
    }


def collect(policies: tuple[str, ...], seeds: int, seed_start: int):
    formations: dict[str, Counter] = defaultdict(Counter)
    stack_counts: dict[str, Counter] = defaultdict(Counter)
    occupied_counts: dict[str, Counter] = defaultdict(Counter)
    files: dict[str, Counter] = defaultdict(Counter)

    games = []
    for a, b in itertools.combinations(policies, 2):
        for offset in range(seeds):
            seed = seed_start + offset
            games.append((a, b, seed))
            games.append((b, a, seed))
    for name in policies:
        for offset in range(seeds):
            games.append((name, name, seed_start + offset))

    for white, black, seed in games:
        state = initial_state(DEVELOPMENT_RULES)
        policy_map = {
            Player.WHITE: policy_by_name(white),
            Player.BLACK: policy_by_name(black),
        }
        name_map = {Player.WHITE: white, Player.BLACK: black}
        rng = random.Random(seed)
        while state.in_development:
            action = policy_map[state.turn].choose(state, legal_actions(state), rng)
            state = apply_action(state, action)
        for player in Player:
            name = name_map[player]
            formation = normalized_formation(state, player)
            formations[name][formation] += 1
            heights = tuple(sorted(len(stack) for _, _, stack in formation))
            stack_counts[name][heights] += 1
            occupied_counts[name][len(formation)] += 1
            for file, _, _ in formation:
                files[name][file] += 1
    return formations, stack_counts, occupied_counts, files


def build_report(policies: tuple[str, ...], seeds: int, seed_start: int) -> str:
    formations, stack_counts, occupied_counts, files = collect(
        policies, seeds, seed_start
    )
    lines = [
        "# Development-opening position analysis",
        "",
        f"- Policies: {', '.join(policies)}",
        f"- Paired seeds: {seeds}",
        f"- Seed range: {seed_start}-{seed_start + seeds - 1}",
        "- Squares are normalized from each player's perspective: rank 1 is the back rank and rank 3 is the front kitchen rank.",
        "- Stack order is bottom-to-top.",
        "",
        "## Formation diversity",
        "",
        "| Policy | Player-openings | Unique formations | Most common formation frequency | Mean occupied non-Sovereign squares |",
        "|---|---:|---:|---:|---:|",
    ]
    for name in policies:
        total = sum(formations[name].values())
        mean_occupied = sum(
            count * frequency for count, frequency in occupied_counts[name].items()
        ) / total
        lines.append(
            f"| {name} | {total} | {len(formations[name])} | "
            f"{formations[name].most_common(1)[0][1]} ({formations[name].most_common(1)[0][1] / total:.1%}) | "
            f"{mean_occupied:.2f} |"
        )

    lines += ["", "## Stack profiles", ""]
    for name in policies:
        total = sum(stack_counts[name].values())
        profiles = ", ".join(
            f"{'-'.join(map(str, profile))}: {count} ({count / total:.1%})"
            for profile, count in stack_counts[name].most_common()
        )
        lines.append(f"- **{name}:** {profiles}")

    lines += [
        "",
        "## Occupied files",
        "",
        "Counts represent occupied non-Sovereign stack locations after development, not individual pieces.",
        "",
        "| Policy | A | B | C | D | E | F | G | H | I |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in policies:
        lines.append(
            f"| {name} | " + " | ".join(str(files[name][file]) for file in FILES) + " |"
        )

    for name in policies:
        lines += ["", f"## Most common {name} formations", ""]
        for formation, count in formations[name].most_common(10):
            lines.append(
                f"- {count} ({count / sum(formations[name].values()):.1%}): "
                f"{formation_text(formation)}"
            )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--policies",
        nargs="+",
        default=["tactical", "spy_rush", "artillery_rush", "height_rush", "sovereign_race"],
    )
    parser.add_argument("--seeds", type=int, default=25)
    parser.add_argument("--seed-start", type=int, default=72001)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = build_report(tuple(args.policies), args.seeds, args.seed_start)
    if args.output:
        args.output.write_text(report + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
