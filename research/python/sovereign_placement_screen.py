"""Screen all 81 back-rank Sovereign-file combinations at a short horizon."""

from __future__ import annotations

import argparse
import json
import os
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from stack_chess import Player
from stack_chess.engine import FILES
from tournament import GameResult, play_game


SOVEREIGN_RACE = "sovereign_race@dual"
DEFAULT_OPPONENTS = (
    "height_rush@double",
    "material_control@mobile",
    "sovereign_defense@intercept",
)


def _play_task(
    task: tuple[str, str, int, int, bool, tuple[int, int]]
) -> tuple[GameResult, dict[str, Counter]]:
    white, black, seed, max_plies, mirror, sovereign_files = task
    telemetry: dict[str, Counter] = defaultdict(Counter)
    result = play_game(
        white,
        black,
        seed,
        max_plies,
        telemetry,
        "development",
        mirror_opening=mirror,
        sovereign_files=sovereign_files,
    )
    return result, dict(telemetry)


def _record_sovereign_race(result: GameResult, record: Counter) -> None:
    record["games"] += 1
    record["plies"] += result.plies
    record["limits"] += result.hit_limit
    kr_is_white = result.white_policy == SOVEREIGN_RACE
    color = "white" if kr_is_white else "black"
    record[f"{color}_games"] += 1
    if result.winner is None:
        record["draws"] += 1
        record["points"] += 0.5
        record[f"{color}_points"] += 0.5
        return
    kr_won = (result.winner is Player.WHITE) == kr_is_white
    if kr_won:
        record["wins"] += 1
        record["points"] += 1.0
        record[f"{color}_points"] += 1.0
    else:
        record["losses"] += 1


def _score(record: Counter) -> float:
    return record["points"] / record["games"] if record["games"] else 0.0


def _mean(stats: Counter, total: str, samples: str) -> str:
    return f"{stats[total] / stats[samples]:.2f}" if stats[samples] else "—"


def _first_threat(stats: Counter) -> float:
    games = stats["games_with_first_sovereign_threat"]
    return stats["first_sovereign_threat_normal_ply_total"] / games if games else 999.0


def _select_shortlist(
    records: dict[tuple[int, int], Counter],
    telemetry: dict[tuple[int, int], Counter],
) -> list[dict[str, object]]:
    by_win_rate = sorted(
        records, key=lambda pair: records[pair]["wins"] / records[pair]["games"]
    )
    by_threat_time = sorted(records, key=lambda pair: _first_threat(telemetry[pair]))
    reasons: dict[tuple[int, int], set[str]] = defaultdict(set)
    selected: list[tuple[int, int]] = []

    def add(pair: tuple[int, int], reason: str) -> None:
        reasons[pair].add(reason)
        if pair not in selected:
            selected.append(pair)

    for pair in by_win_rate[:2]:
        add(pair, "lowest short-horizon Sovereign Race win rate")
    for pair in by_win_rate[-2:]:
        add(pair, "highest short-horizon Sovereign Race win rate")
    add(by_threat_time[0], "fastest first Sovereign threat")
    add(by_threat_time[-1], "slowest first Sovereign threat")
    archetypes = {
        (0, 0): "same corner",
        (0, 8): "opposite corners",
        (4, 4): "same center",
        (0, 4): "White corner / Black center",
        (4, 0): "White center / Black corner",
        (3, 5): "central offset",
    }
    for pair, reason in archetypes.items():
        add(pair, reason)

    median_order = sorted(
        records,
        key=lambda pair: abs(
            records[pair]["wins"] / records[pair]["games"] - 0.5
        ),
    )
    for pair in median_order:
        if len(selected) >= 12:
            break
        add(pair, "near-even reference")

    return [
        {
            "white_file": FILES[pair[0]],
            "black_file": FILES[pair[1]],
            "score": round(100 * _score(records[pair]), 2),
            "win_rate": round(
                100 * records[pair]["wins"] / records[pair]["games"], 2
            ),
            "first_threat": (
                None
                if _first_threat(telemetry[pair]) == 999.0
                else round(_first_threat(telemetry[pair]), 2)
            ),
            "reasons": sorted(reasons[pair]),
        }
        for pair in selected[:12]
    ]


def run_screen(
    opponents: tuple[str, ...],
    seeds: int,
    seed_start: int,
    post_development_plies: int,
    workers: int,
) -> tuple[str, list[dict[str, object]]]:
    max_plies = 8 + post_development_plies
    tasks: list[tuple[str, str, int, int, bool, tuple[int, int]]] = []
    keys: list[tuple[tuple[int, int], str]] = []
    for white_file in range(9):
        for black_file in range(9):
            sovereign_files = (white_file, black_file)
            for opponent in opponents:
                for offset in range(seeds):
                    seed = seed_start + offset
                    mirror = bool(offset % 2)
                    tasks.append((SOVEREIGN_RACE, opponent, seed, max_plies, mirror, sovereign_files))
                    keys.append((sovereign_files, opponent))
                    tasks.append((opponent, SOVEREIGN_RACE, seed, max_plies, mirror, sovereign_files))
                    keys.append((sovereign_files, opponent))

    records: dict[tuple[int, int], Counter] = defaultdict(Counter)
    matchup_records: dict[tuple[tuple[int, int], str], Counter] = defaultdict(Counter)
    telemetry: dict[tuple[int, int], Counter] = defaultdict(Counter)
    with ProcessPoolExecutor(max_workers=workers) as executor:
        outcomes = executor.map(_play_task, tasks, chunksize=8)
        for (sovereign_files, opponent), (result, game_stats) in zip(keys, outcomes):
            _record_sovereign_race(result, records[sovereign_files])
            _record_sovereign_race(result, matchup_records[(sovereign_files, opponent)])
            telemetry[sovereign_files].update(game_stats[SOVEREIGN_RACE])
            opponent_stats = game_stats[opponent]
            telemetry[sovereign_files]["opponent_forced_defenses"] += opponent_stats[
                "decision_forced_defense"
            ]

    shortlist = _select_shortlist(records, telemetry)
    lines = [
        "# Sovereign-placement 50-ply screening",
        "",
        "- Sovereign-file combinations: 81",
        f"- Opponents: {', '.join(opponents)}",
        f"- Paired seeds per combination/opponent: {seeds}",
        f"- Total games: {len(tasks)}",
        f"- Horizon: {post_development_plies} post-development plies plus 8 development plies",
        f"- Parallel workers: {workers}",
        "- Color swapping keeps each board configuration fixed while Sovereign Race plays both colors.",
        "",
        "## Sovereign Race decisive-win heatmap",
        "",
        "Rows are the White Sovereign file; columns are the Black Sovereign file. Each cell is Sovereign Race's completed win rate by the 50-ply horizon across both colors and all listed opponents; unfinished games are not counted as wins.",
        "",
        "| W\\B | " + " | ".join(FILES) + " |",
        "|---|" + "---:|" * 9,
    ]
    for white_file, white_name in enumerate(FILES):
        cells = [
            f"{100 * records[(white_file, black_file)]['wins'] / records[(white_file, black_file)]['games']:.1f}%"
            for black_file in range(9)
        ]
        lines.append(f"| {white_name} | " + " | ".join(cells) + " |")

    lines += [
        "",
        "## All configurations ranked",
        "",
        "| Sovereigns | Games | W-L-D | Score | KR as White | KR as Black | First threat | Material +30 | +50 | Opponent forced defenses |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    ordered = sorted(records, key=lambda pair: _score(records[pair]))
    for pair in ordered:
        record = records[pair]
        stats = telemetry[pair]
        lines.append(
            f"| {FILES[pair[0]]}1/{FILES[pair[1]]}9 | {record['games']} "
            f"| {record['wins']}-{record['losses']}-{record['draws']} "
            f"| {100 * _score(record):.1f}% "
            f"| {100 * record['white_points'] / record['white_games']:.1f}% "
            f"| {100 * record['black_points'] / record['black_games']:.1f}% "
            f"| {_mean(stats, 'first_sovereign_threat_normal_ply_total', 'games_with_first_sovereign_threat')} "
            f"| {_mean(stats, 'material_advantage_ply_30_total', 'material_advantage_ply_30_samples')} "
            f"| {_mean(stats, 'material_advantage_ply_50_total', 'material_advantage_ply_50_samples')} "
            f"| {stats['opponent_forced_defenses']} |"
        )

    lines += ["", "## Selected configurations for full games", "", "| Sovereigns | Decisive KR wins | First threat | Selection reason |", "|---|---:|---:|---|"]
    for item in shortlist:
        lines.append(
            f"| {item['white_file']}1/{item['black_file']}9 | {item['win_rate']:.1f}% "
            f"| {item['first_threat'] if item['first_threat'] is not None else '—'} "
            f"| {', '.join(item['reasons'])} |"
        )

    lines += ["", "## Scores by opponent", "", "| Sovereigns | " + " | ".join(opponents) + " |", "|---|" + "---:|" * len(opponents)]
    for pair in ordered:
        cells = [
            f"{100 * _score(matchup_records[(pair, opponent)]):.1f}%"
            for opponent in opponents
        ]
        lines.append(f"| {FILES[pair[0]]}1/{FILES[pair[1]]}9 | " + " | ".join(cells) + " |")
    return "\n".join(lines), shortlist


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--opponents", nargs="+", default=list(DEFAULT_OPPONENTS))
    parser.add_argument("--seeds", type=int, default=10)
    parser.add_argument("--seed-start", type=int, default=79001)
    parser.add_argument("--post-development-plies", type=int, default=50)
    parser.add_argument("--workers", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--output", type=Path, default=Path("SOVEREIGN_PLACEMENT_SCREEN_REPORT.md"))
    parser.add_argument("--shortlist", type=Path, default=Path("SOVEREIGN_PLACEMENT_SHORTLIST.json"))
    args = parser.parse_args()
    report, shortlist = run_screen(
        tuple(args.opponents),
        args.seeds,
        args.seed_start,
        args.post_development_plies,
        max(1, args.workers),
    )
    args.output.write_text(report + "\n", encoding="utf-8")
    args.shortlist.write_text(json.dumps(shortlist, indent=2) + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
