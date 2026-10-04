# Nomenclature Conversion for Older Artifacts

T3RNARY contract version 2 uses one vocabulary in the rules, both rules
engines, reports, replay files, and notation. The engines do not translate old
identifiers at runtime. Use this guide when reading or explicitly migrating a
contract version 1 archive or an older external report.

## Unit names

| Earlier name and JSON identifier | Current name | Notation | Contract v2 identifier |
|---|---|:---:|---|
| King / `king` | Sovereign | V | `sovereign` |
| Soldier / `soldier` | Infantry | I | `infantry` |
| Cavalry / `cavalry` | Dragoon | D | `dragoon` |
| Knight / `knight` | Chariot | C | `chariot` |
| Griffin / `griffin` | Griffin | G | `griffin` |
| Marshal / `marshal` | Marshal | M | `marshal` |
| Cannon / `cannon` | Ballista | B | `ballista` |
| Trebuchet / `trebuchet` | Trebuchet | T | `trebuchet` |
| Spy / `spy` | Spy | Sp | `spy` |
| Resurrect / `resurrect` | Recall | Rc | `recall` |
| Reinforcement / `reinforcement` | Reinforcement | Rf | `reinforcement` |

## Other serialized names

| Contract v1 or older | Contract v2 |
|---|---|
| action type `resurrect` | action type `recall` |
| `height_three_requires_nonking_move` | `height_three_requires_nonsovereign_move` |
| artillery field `king_target` | `sovereign_target` |
| `forbidden_active_targets` | `forbidden_top_piece_targets` |
| policy family `king_race` | `sovereign_race` |
| policy family `king_defense` | `sovereign_defense` |
| piece catalog `core-pieces-v2` | piece catalog `core-pieces-v3` |

When converting JSON, change both top-level and embedded state
`contract_version` values from `1` to `2`, replace identifiers according to
the tables, and update the catalog id and hash to the current catalog values.
Revalidate or replay the result through a current engine before treating it as
a current archive.

## Stack language

Older prose may describe an “active piece.” Current rules identify a stack by
its TOP piece and call the whole unit a `<piece> Stack`. For example, a
three-piece stack with a Marshal on TOP is a Marshal 3 Stack. Buried pieces do
not determine stack identity, movement, or abilities.
