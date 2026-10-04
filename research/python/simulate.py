"""Run reproducible random legal-play simulations against the rules engine."""

from __future__ import annotations

import argparse
import random
from collections import Counter

from stack_chess import apply_action, initial_state, legal_actions, validate_state


def run(games: int, max_plies: int, seed: int) -> Counter[str]:
    rng = random.Random(seed)
    outcomes: Counter[str] = Counter()
    for _ in range(games):
        state = initial_state()
        for _ in range(max_plies):
            if state.is_over:
                break
            actions = legal_actions(state)
            if not actions:
                raise AssertionError("non-terminal state has no legal actions")
            state = apply_action(state, rng.choice(actions))
            validate_state(state, enforce_inventory=True)
        if state.winner:
            outcomes[f"{state.winner.value}_win"] += 1
        elif state.is_draw:
            outcomes["draw"] += 1
        else:
            outcomes["ply_limit"] += 1
    return outcomes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--games", type=int, default=100)
    parser.add_argument("--max-plies", type=int, default=500)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    outcomes = run(args.games, args.max_plies, args.seed)
    print(f"seed={args.seed} games={args.games} max_plies={args.max_plies}")
    for outcome, count in sorted(outcomes.items()):
        print(f"{outcome}: {count}")


if __name__ == "__main__":
    main()
