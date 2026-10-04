# T3RNARY Data Contract v2

The contract is the boundary between the Godot simulator, Python research
tools, saved positions, and replay files. JSON uses lowercase snake-case enum
values and chess-style uppercase board coordinates.

## Compatibility

- Every top-level state or replay contains `contract_version`.
- Version 2 uses the current names as canonical serialized identifiers.
- Both engines reject superseded identifiers rather than translating them at
  runtime.
- Convert version 1 artifacts with the
  [nomenclature conversion guide](NOMENCLATURE_CONVERSION.md).

## Piece

```json
{"owner": "white", "kind": "marshal"}
```

Owners are `white` or `black`. Piece kinds are `sovereign`, `spy`, `ballista`,
`trebuchet`, `dragoon`, `chariot`, `griffin`, `marshal`, `infantry`, `recall`,
and `reinforcement`.

These are the stable version 2 identifiers used by the engines and players:

| Player-facing name | Notation | JSON identifier |
|---|:---:|---|
| Sovereign | V | `sovereign` |
| Infantry | I | `infantry` |
| Dragoon | D | `dragoon` |
| Chariot | C | `chariot` |
| Griffin | G | `griffin` |
| Marshal | M | `marshal` |
| Ballista | B | `ballista` |
| Trebuchet | T | `trebuchet` |
| Spy | Sp | `spy` |
| Recall | Rc | `recall` |
| Reinforcement | Rf | `reinforcement` |

Display names and notation symbols are stored with each unit in the shared
piece catalog. Report and replay notation generators should read that metadata
rather than maintain a second name table.

## Stack and board

The board is an object keyed by coordinates. Stack arrays are ordered from
bottom to TOP. The last piece is the TOP piece and determines the stack's
identity, movement, and abilities. The example below is a Marshal 2 Stack.

```json
{
  "A4": [
    {"owner": "white", "kind": "reinforcement"},
    {"owner": "white", "kind": "marshal"}
  ]
}
```

## Actions

MOVE:

```json
{"type": "move", "source": "A4", "destination": "A7"}
```

PLACE:

```json
{"type": "place", "piece": "ballista", "destination": "E4"}
```

An artillery placement that fires includes `effect_target`:

```json
{"type": "place", "piece": "ballista", "destination": "E4", "effect_target": "E7"}
```

RECALL uses the `recall` action type and records the piece brought
back, not the Recall tile consumed:

```json
{"type": "recall", "piece": "griffin", "destination": "C3"}
```

## Game state

Required state fields:

- `contract_version`
- `rules`
- `board`
- `reserves` and `discards`, each keyed by player then piece kind
- `turn`
- `winner` (`null`, `white`, or `black`)
- `is_draw`
- `ply`
- `development_placements`, keyed by player
- `height_three_unlocked`, keyed by player

The rules object is embedded so a position remains interpretable if defaults
change later. Records include `id`, `catalog_id`, and `catalog_hash`; the hash
identifies the exact bytes of the shared piece catalog.

The runtime configuration files are separate from this state contract:

- `godot/data/rules/pieces.json` is the canonical piece catalog.
- `godot/data/rules/rulesets.json` is the canonical preset collection.

Python deliberately reads those same files from the Godot project. There is no
second generated copy to drift out of sync.

The current named presets are:

- `control-v3` and `development-v3`: ordinary attacks against taller stacks are
  illegal.
- `attrition-control-v2` and `attrition-development-v2`: shorter MOVE attacks
  use mutual bottom attrition, while shorter artillery attacks remove only
  bottom target pieces.

All four current presets use catalog `core-pieces-v4`, whose Royal Attack rule
lets a Sovereign capture and replace any adjacent enemy stack regardless of
height. The normal threat system still applies after the capture.

The experimental `development-infiltration-v1` and
`attrition-development-infiltration-v1` presets set `infiltration_victory` to
true. Entering the opponent's back row with the Sovereign then wins immediately.

## Replay

A replay contains an initial state and an ordered action list:

```json
{
  "contract_version": 2,
  "game_id": "example-id",
  "created_utc": "2026-10-02T20:00:00Z",
  "initial_state": {},
  "actions": [],
  "metadata": {
    "white_policy": "human",
    "black_policy": "human",
    "tags": ["opening-lab"]
  }
}
```

Derived board states are not required in a replay. Consumers rebuild them by
applying each action through the rules engine. Optional annotations and cached
state hashes may be added without changing the version.
