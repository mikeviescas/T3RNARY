"""Screen strategic development plans against stable control openings."""

from __future__ import annotations

import argparse
import os
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from stack_chess import Player
from stack_chess.policies import OPENING_PLANS
from tournament import GameResult, play_game


DEFAULT_BASE_POLICIES = (
    "tactical",
    "material_control",
    "spy_rush",
    "artillery_rush",
    "height_rush",
    "sovereign_race",
)


def _record(result: GameResult, candidate: str, record: Counter) -> None:
    record["games"] += 1
    record["plies"] += result.plies
    record["limits"] += result.hit_limit
    if result.winner is None:
        record["draws"] += 1
        record["points"] += 0.5
        return
    winner_name = (
        result.white_policy if result.winner is Player.WHITE else result.black_policy
    )
    if winner_name == candidate:
        record["wins"] += 1
        record["points"] += 1.0
    else:
        record["losses"] += 1


def _mean(stats: Counter, total_key: str, count_key: str) -> str:
    count = stats[count_key]
    return f"{stats[total_key] / count:.2f}" if count else "—"


def _play_task(
    task: tuple[str, str, str, int, int, bool]
) -> tuple[GameResult, Counter]:
    tracked_candidate, white, black, seed, max_plies, mirror = task
    local_telemetry: dict[str, Counter] = defaultdict(Counter)
    result = play_game(
        white,
        black,
        seed,
        max_plies,
        local_telemetry,
        "development",
        mirror_opening=mirror,
    )
    return result, local_telemetry[tracked_candidate]


def run_screen(
    base_policies: tuple[str, ...],
    seeds: int,
    seed_start: int,
    max_plies: int,
    workers: int = 1,
) -> str:
    candidates = [
        f"{base}@{plan}"
        for base in base_policies
        for plan in OPENING_PLANS[base]
    ]
    telemetry: dict[str, Counter] = defaultdict(Counter)
    totals: dict[str, Counter] = defaultdict(Counter)
    matchups: dict[tuple[str, str], Counter] = defaultdict(Counter)

    tasks: list[tuple[str, str, str, int, int, bool]] = []
    task_keys: list[tuple[str, str]] = []
    for candidate in candidates:
        for opponent_base in base_policies:
            opponent = f"{opponent_base}@control"
            for offset in range(seeds):
                seed = seed_start + offset
                mirror = bool(offset % 2)
                tasks.append((candidate, candidate, opponent, seed, max_plies, mirror))
                task_keys.append((candidate, opponent_base))
                tasks.append((candidate, opponent, candidate, seed, max_plies, mirror))
                task_keys.append((candidate, opponent_base))

    if workers == 1:
        outcomes = map(_play_task, tasks)
        executor = None
    else:
        executor = ProcessPoolExecutor(max_workers=workers)
        outcomes = executor.map(_play_task, tasks, chunksize=4)
    try:
        for (candidate, opponent_base), (result, candidate_stats) in zip(
            task_keys, outcomes
        ):
            telemetry[candidate].update(candidate_stats)
            _record(result, candidate, totals[candidate])
            _record(result, candidate, matchups[(candidate, opponent_base)])
    finally:
        if executor is not None:
            executor.shutdown()

    games = len(candidates) * len(base_policies) * seeds * 2
    lines = [
        "# Strategic development-plan screening",
        "",
        f"- Candidate plans: {len(candidates)} ({len(base_policies)} policies × 3 plans)",
        f"- Control opponents: {len(base_policies)} unplanned development policies",
        f"- Paired seeds per candidate/opponent: {seeds}",
        f"- Total games: {games}",
        f"- Seed range: {seed_start}-{seed_start + seeds - 1}",
        f"- Parallel workers: {workers}",
        "- Every matchup is color-swapped; wing orientation is reversed on alternating seeds.",
        "- This is a screening experiment, not a complete plan-versus-plan tournament.",
        "",
        "## Overall candidate results",
        "",
        "| Candidate | Games | W-L-D | Score | Mean plies | Limits | Target profile | Opening survivors | Material +10 | +20 | +30 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    ordered = sorted(
        candidates,
        key=lambda candidate: totals[candidate]["points"] / totals[candidate]["games"],
        reverse=True,
    )
    for candidate in ordered:
        record = totals[candidate]
        stats = telemetry[candidate]
        score = 100.0 * record["points"] / record["games"]
        target = 100.0 * stats["opening_target_achieved"] / max(1, stats["opening_completed"])
        survivors = _mean(stats, "opening_survivors_total", "opening_survivor_samples")
        material = [
            _mean(
                stats,
                f"material_advantage_ply_{ply}_total",
                f"material_advantage_ply_{ply}_samples",
            )
            for ply in (10, 20, 30)
        ]
        lines.append(
            f"| {candidate} | {record['games']} | {record['wins']}-{record['losses']}-{record['draws']} "
            f"| {score:.1f}% | {record['plies'] / record['games']:.1f} | {record['limits']} "
            f"| {target:.1f}% | {survivors} | {material[0]} | {material[1]} | {material[2]} |"
        )

    lines += ["", "## Ranking within each policy", ""]
    for base in base_policies:
        lines += [f"### {base}", "", "| Plan | Score | First threat | First height 3 | First Spy | First artillery |", "|---|---:|---:|---:|---:|---:|"]
        policy_candidates = [candidate for candidate in ordered if candidate.startswith(f"{base}@")]
        for candidate in policy_candidates:
            stats = telemetry[candidate]
            record = totals[candidate]
            lines.append(
                f"| {candidate.partition('@')[2]} | {100 * record['points'] / record['games']:.1f}% "
                f"| {_mean(stats, 'first_sovereign_threat_normal_ply_total', 'games_with_first_sovereign_threat')} "
                f"| {_mean(stats, 'first_height_three_normal_ply_total', 'games_with_height_three')} "
                f"| {_mean(stats, 'first_spy_conversion_normal_ply_total', 'games_with_first_spy_conversion')} "
                f"| {_mean(stats, 'first_artillery_shot_normal_ply_total', 'games_with_first_artillery_shot')} |"
            )
        lines.append("")

    lines += [
        "## Candidate score by control opponent",
        "",
        "| Candidate | " + " | ".join(base_policies) + " |",
        "|---|" + "---:|" * len(base_policies),
    ]
    for candidate in ordered:
        cells = []
        for opponent in base_policies:
            record = matchups[(candidate, opponent)]
            cells.append(f"{100 * record['points'] / record['games']:.1f}%")
        lines.append(f"| {candidate} | " + " | ".join(cells) + " |")

    lines += [
        "",
        "## Interpretation limits",
        "",
        "A candidate plan is being compared with the previous stochastic opening, so its score combines opening quality with the underlying post-development policy. The next tournament should advance only the strongest distinct plans and compare them directly. Material advantage is active non-Sovereign value on board plus reserve, excluding discarded material.",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policies", nargs="+", default=list(DEFAULT_BASE_POLICIES))
    parser.add_argument("--seeds", type=int, default=10)
    parser.add_argument("--seed-start", type=int, default=74001)
    parser.add_argument("--max-plies", type=int, default=300)
    parser.add_argument(
        "--workers", type=int, default=min(8, os.cpu_count() or 1)
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = run_screen(
        tuple(args.policies),
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
