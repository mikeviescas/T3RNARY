"""Run full games for the Sovereign-file configurations selected by screening."""

from __future__ import annotations

import argparse
import json
import os
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from stack_chess.engine import FILES
from sovereign_placement_screen import (
    DEFAULT_OPPONENTS,
    SOVEREIGN_RACE,
    _mean,
    _play_task,
    _record_sovereign_race,
    _score,
)


def run_confirmation(
    shortlist: list[dict[str, object]],
    opponents: tuple[str, ...],
    seeds: int,
    seed_start: int,
    max_plies: int,
    workers: int,
) -> str:
    placements = [
        (FILES.index(str(item["white_file"])), FILES.index(str(item["black_file"])))
        for item in shortlist
    ]
    tasks: list[tuple[str, str, int, int, bool, tuple[int, int]]] = []
    keys: list[tuple[tuple[int, int], str]] = []
    for sovereign_files in placements:
        for opponent in opponents:
            for offset in range(seeds):
                seed = seed_start + offset
                mirror = bool(offset % 2)
                tasks.append((SOVEREIGN_RACE, opponent, seed, max_plies, mirror, sovereign_files))
                keys.append((sovereign_files, opponent))
                tasks.append((opponent, SOVEREIGN_RACE, seed, max_plies, mirror, sovereign_files))
                keys.append((sovereign_files, opponent))

    records: dict[tuple[int, int], Counter] = defaultdict(Counter)
    matchups: dict[tuple[tuple[int, int], str], Counter] = defaultdict(Counter)
    telemetry: dict[tuple[int, int], Counter] = defaultdict(Counter)
    with ProcessPoolExecutor(max_workers=workers) as executor:
        outcomes = executor.map(_play_task, tasks, chunksize=4)
        for (sovereign_files, opponent), (result, game_stats) in zip(keys, outcomes):
            _record_sovereign_race(result, records[sovereign_files])
            _record_sovereign_race(result, matchups[(sovereign_files, opponent)])
            telemetry[sovereign_files].update(game_stats[SOVEREIGN_RACE])
            telemetry[sovereign_files]["opponent_forced_defenses"] += game_stats[
                opponent
            ]["decision_forced_defense"]

    ordered = sorted(placements, key=lambda pair: _score(records[pair]))
    lines = [
        "# Sovereign-placement full-game confirmation",
        "",
        f"- Selected Sovereign-file combinations: {len(placements)}",
        f"- Opponents: {', '.join(opponents)}",
        f"- Paired seeds per combination/opponent: {seeds}",
        f"- Total games: {len(tasks)}",
        f"- Maximum plies: {max_plies}",
        f"- Parallel workers: {workers}",
        "",
        "## Overall results",
        "",
        "| Sovereigns | Games | W-L-D | KR score | KR as White | KR as Black | Mean plies | First threat | Material +30 | +50 | Opponent forced defenses |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for pair in ordered:
        record = records[pair]
        stats = telemetry[pair]
        lines.append(
            f"| {FILES[pair[0]]}1/{FILES[pair[1]]}9 | {record['games']} "
            f"| {record['wins']}-{record['losses']}-{record['draws']} "
            f"| {100 * _score(record):.1f}% "
            f"| {100 * record['white_points'] / record['white_games']:.1f}% "
            f"| {100 * record['black_points'] / record['black_games']:.1f}% "
            f"| {record['plies'] / record['games']:.1f} "
            f"| {_mean(stats, 'first_sovereign_threat_normal_ply_total', 'games_with_first_sovereign_threat')} "
            f"| {_mean(stats, 'material_advantage_ply_30_total', 'material_advantage_ply_30_samples')} "
            f"| {_mean(stats, 'material_advantage_ply_50_total', 'material_advantage_ply_50_samples')} "
            f"| {stats['opponent_forced_defenses']} |"
        )

    lines += ["", "## Results by opponent", "", "| Sovereigns | " + " | ".join(opponents) + " |", "|---|" + "---:|" * len(opponents)]
    for pair in ordered:
        cells = [
            f"{100 * _score(matchups[(pair, opponent)]):.1f}%"
            for opponent in opponents
        ]
        lines.append(f"| {FILES[pair[0]]}1/{FILES[pair[1]]}9 | " + " | ".join(cells) + " |")

    lines += [
        "",
        "## Comparison range",
        "",
        f"Sovereign Race's best selected placement scored {100 * _score(records[ordered[-1]]):.1f}%; its worst scored {100 * _score(records[ordered[0]]):.1f}%, a spread of {100 * (_score(records[ordered[-1]]) - _score(records[ordered[0]])):.1f} percentage points.",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shortlist", type=Path, default=Path("SOVEREIGN_PLACEMENT_SHORTLIST.json"))
    parser.add_argument("--opponents", nargs="+", default=list(DEFAULT_OPPONENTS))
    parser.add_argument("--seeds", type=int, default=25)
    parser.add_argument("--seed-start", type=int, default=80001)
    parser.add_argument("--max-plies", type=int, default=300)
    parser.add_argument("--workers", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--output", type=Path, default=Path("SOVEREIGN_PLACEMENT_CONFIRMATION_REPORT.md"))
    args = parser.parse_args()
    shortlist = json.loads(args.shortlist.read_text(encoding="utf-8"))
    report = run_confirmation(
        shortlist,
        tuple(args.opponents),
        args.seeds,
        args.seed_start,
        args.max_plies,
        max(1, args.workers),
    )
    args.output.write_text(report + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
