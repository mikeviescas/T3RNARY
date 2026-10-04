# Architecture

## Boundary

The GDScript engine is a pure state transformer. It does not know about nodes,
scenes, animation, input, or policy scoring.

```text
                         Shared rule data
                     pieces.json + rulesets.json
                         │                 │
                         ▼                 ▼
              Python rules engine   GDScript rules engine
                         │                 │
                         └── parity fixtures ──┘
                                           │
                                           ▼
                                  Visual simulator (Stage 3+)
```

The shared data owns stable and tunable facts: canonical display names and
notation symbols, board geometry, inventories, movement profiles, artillery
parameters, special-piece limits, development settings, and named combat modes. Each engine owns algorithms: legal-action
generation, path tracing, state transitions, combat resolution, terminal
conditions, policy scoring, and presentation.

This is intentionally not a general-purpose rules language. A new behavior
mode must be implemented and tested in both engines before a ruleset selects
it.

## Core files

- `data/rules/pieces.json`: canonical piece catalog and board parameters.
- `data/rules/rulesets.json`: canonical named ruleset presets.
- `ternary_rules.gd`: strict shared-data loader, names, and coordinate helpers.
- `ternary_codec.gd`: canonical JSON normalization.
- `ternary_engine.gd`: initial state, legal actions, action application,
  terminal conditions, and invariant checks.
- `tests/run_tests.gd`: dependency-free headless regression suite.

## Design constraints

- Stacks are always bottom-to-top arrays.
- Legal actions are data, not command objects.
- Applying an action returns a deep-copied new state.
- UI code must request legal actions and never reproduce legality rules.
- Policies may score legal actions but may not manufacture actions.
- Batch tournaments stay in Python; Godot consumes their replay output.
- Both engines load the same files rather than maintaining copied constants.
- A ruleset records the catalog id and SHA-256 hash used to create it.
