# T3RNARY

T3RNARY is a 9x9 abstract strategy game built around three-piece stacks,
placement, movement, conversion, and ranged removal.

The current player-facing rules are in
[`docs/T3RNARY_RULES.md`](docs/T3RNARY_RULES.md).

This repository contains two deliberately separate engines:

- `godot/` — the interactive simulator and its authoritative local rules core.
- `research/python/` — the Python simulation laboratory used for batch policy
  tests and statistical analysis.

Both implementations load the same fixed rule data from `godot/data/rules/`
and exchange versioned states and actions through `fixtures/`. Algorithms stay
native to each engine; tunable facts such as movement vectors, ranges, piece
counts, and opening parameters have one source of truth.

## Current milestone

Interactive simulator milestone:

- Godot 4 project shell
- versioned state, action, replay, and ruleset contracts with JSON Schemas
- shared, strictly validated piece catalog and ruleset presets
- pure GDScript legal-action engine
- development-opening rules
- canonical unit identifiers shared by both engines, reports, and replays
- headless engine tests and golden JSON fixtures
- local hot-seat play for both sides, including player-selected Sovereign files
- engine-generated MOVE/ATTACK and PLACE/SHOOT targets
- stack inspection, undo, and full tournament-replay navigation

The simulator now binds the vector tabletop presentation to the live Godot
rules engine. See [`docs/simulator.md`](docs/simulator.md) for controls and
replay-loading behavior.

## Run the GDScript tests

With Godot 4 available on the command line:

```sh
godot --headless --path godot --script res://tests/run_tests.gd
```

## Run the Python reference tests

```sh
PYTHONPATH=research/python python3 -m unittest discover -s research/python/tests
```

Convenience wrappers are also available as `scripts/test_godot.sh` and
`scripts/test_python.sh`. Set `GODOT_BIN` if the Godot executable is not on
your command path.

Run an attrition tournament with the shared development preset:

```sh
PYTHONPATH=research/python python3 research/python/tournament.py \
  --ruleset attrition-development-v2 \
  --policies tactical height_rush material_control
```

Experimental immediate back-row victory is available through
`development-infiltration-v1` and
`attrition-development-infiltration-v1`.

Add `--limit-replay-dir research/replays/long_games/<ruleset>` to preserve every
ply-limit game as a replay JSON file with final-position diagnostics. Validate
and summarize saved limit games with `research/python/analyze_limit_replays.py`.

## Contract policy

The current contract version is `2`. Contract changes must either remain
backward-compatible or increment `contract_version`. See
`docs/data-contract.md`. Older artifacts can be translated explicitly with
`docs/NOMENCLATURE_CONVERSION.md`; runtime aliases are intentionally absent.

## Rule configuration policy

`godot/data/rules/pieces.json` contains fixed board and piece parameters.
`godot/data/rules/rulesets.json` contains named experimental presets. Python
loads these exact files; there is no generated or synchronized copy.

JSON selects parameters and named behavior modes. Resolution algorithms remain
code, and every behavioral change still requires regression tests in both
engines. See `docs/architecture.md` for the boundary.
