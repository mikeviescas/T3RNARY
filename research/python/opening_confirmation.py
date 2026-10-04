"""Confirm the strongest development plans in a direct round robin."""

from __future__ import annotations

import argparse
import itertools
import os
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from stack_chess import Player
from tournament import GameResult, play_game


REPRESENTATIVE_ENTRANTS = (
    "tactical@control",
    "material_control@mobile",
    "spy_rush@staging",
    "artillery_rush@platform",
    "height_rush@double",
    "sovereign_race@dual",
    "sovereign_defense@intercept",
)

DEFAULT_ENTRANTS = REPRESENTATIVE_ENTRANTS


def _play_task(
    task: tuple[str, str, int, int, bool]
) -> tuple[GameResult, dict[str, Counter]]:
    white, black, seed, max_plies, mirror = task
    telemetry: dict[str, Counter] = defaultdict(Counter)
    result = play_game(
        white,
        black,
        seed,
        max_plies,
        telemetry,
        "development",
        mirror_opening=mirror,
    )
    return result, dict(telemetry)


def _record(result: GameResult, records: dict[str, Counter]) -> None:
    names = (result.white_policy, result.black_policy)
    for name in names:
        records[name]["games"] += 1
        records[name]["plies"] += result.plies
        records[name]["limits"] += result.hit_limit
    if result.winner is None:
        for name in names:
            records[name]["draws"] += 1
            records[name]["points"] += 0.5
        return
    winner = names[0] if result.winner is Player.WHITE else names[1]
    loser = names[1] if result.winner is Player.WHITE else names[0]
    records[winner]["wins"] += 1
    records[winner]["points"] += 1.0
    records[loser]["losses"] += 1


def _mean(stats: Counter, total_key: str, count_key: str) -> str:
    count = stats[count_key]
    return f"{stats[total_key] / count:.2f}" if count else "—"


def run_confirmation(
    entrants: tuple[str, ...],
    seeds: int,
    seed_start: int,
    max_plies: int,
    workers: int,
) -> str:
    tasks: list[tuple[str, str, int, int, bool]] = []
    pair_keys: list[tuple[str, str]] = []
    for first, second in itertools.combinations(entrants, 2):
        for offset in range(seeds):
            seed = seed_start + offset
            mirror = bool(offset % 2)
            tasks.append((first, second, seed, max_plies, mirror))
            pair_keys.append((first, second))
            tasks.append((second, first, seed, max_plies, mirror))
            pair_keys.append((first, second))

    records: dict[str, Counter] = defaultdict(Counter)
    pair_records: dict[tuple[str, str], dict[str, Counter]] = defaultdict(
        lambda: defaultdict(Counter)
    )
    telemetry: dict[str, Counter] = defaultdict(Counter)
    with ProcessPoolExecutor(max_workers=workers) as executor:
        outcomes = executor.map(_play_task, tasks, chunksize=4)
        for pair, (result, game_telemetry) in zip(pair_keys, outcomes):
            _record(result, records)
            _record(result, pair_records[pair])
            for name, stats in game_telemetry.items():
                telemetry[name].update(stats)

    ordered = sorted(
        entrants,
        key=lambda name: records[name]["points"] / records[name]["games"],
        reverse=True,
    )
    lines = [
        "# Development-plan confirmation tournament",
        "",
        f"- Entrants: {len(entrants)}",
        f"- Paired seeds per matchup: {seeds}",
        f"- Total games: {len(tasks)}",
        f"- Seed range: {seed_start}-{seed_start + seeds - 1}",
        f"- Maximum plies: {max_plies}",
        f"- Parallel workers: {workers}",
        "- Every matchup is color-swapped; wing orientation is reversed on alternating seeds.",
        "- Self-play is omitted because it does not help rank distinct entrants.",
        "",
        "## Overall results",
        "",
        "| Rank | Entrant | Games | W-L-D | Score | Mean plies | Limits | Material +10 | +20 | +30 | Opening survivors |",
        "|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for rank, name in enumerate(ordered, 1):
        record = records[name]
        stats = telemetry[name]
        materials = [
            _mean(
                stats,
                f"material_advantage_ply_{ply}_total",
                f"material_advantage_ply_{ply}_samples",
            )
            for ply in (10, 20, 30)
        ]
        lines.append(
            f"| {rank} | {name} | {record['games']} | {record['wins']}-{record['losses']}-{record['draws']} "
            f"| {100 * record['points'] / record['games']:.1f}% | {record['plies'] / record['games']:.1f} "
            f"| {record['limits']} | {materials[0]} | {materials[1]} | {materials[2]} "
            f"| {_mean(stats, 'opening_survivors_total', 'opening_survivor_samples')} |"
        )

    lines += [
        "",
        "## Timing and opening behavior",
        "",
        "| Entrant | First threat | First height 3 | First Spy | First artillery | Target profile |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for name in ordered:
        stats = telemetry[name]
        target = (
            100 * stats["opening_target_achieved"] / stats["opening_completed"]
            if stats["opening_completed"] and not name.endswith("@control")
            else None
        )
        lines.append(
            f"| {name} | {_mean(stats, 'first_sovereign_threat_normal_ply_total', 'games_with_first_sovereign_threat')} "
            f"| {_mean(stats, 'first_height_three_normal_ply_total', 'games_with_height_three')} "
            f"| {_mean(stats, 'first_spy_conversion_normal_ply_total', 'games_with_first_spy_conversion')} "
            f"| {_mean(stats, 'first_artillery_shot_normal_ply_total', 'games_with_first_artillery_shot')} "
            f"| {f'{target:.1f}%' if target is not None else 'control'} |"
        )

    lines += ["", "## Matchup scores", ""]
    for first, second in itertools.combinations(entrants, 2):
        pair = pair_records[(first, second)]
        first_score = 100 * pair[first]["points"] / pair[first]["games"]
        lines.append(f"- {first} vs {second}: **{first_score:.1f}%–{100 - first_score:.1f}%**")

    lines += [
        "",
        "## Interpretation limit",
        "",
        "This tournament compares the selected plans directly, eliminating the screening tournament's planned-versus-unplanned asymmetry. It still measures these heuristic policies rather than optimal human play.",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--entrants", nargs="+", default=list(DEFAULT_ENTRANTS))
    parser.add_argument("--seeds", type=int, default=25)
    parser.add_argument("--seed-start", type=int, default=75001)
    parser.add_argument("--max-plies", type=int, default=300)
    parser.add_argument("--workers", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = run_confirmation(
        tuple(args.entrants),
        args.seeds,
        args.seed_start,
        args.max_plies,
        max(1, args.workers),
    )
    if args.output:
        args.output.write_text(report + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
