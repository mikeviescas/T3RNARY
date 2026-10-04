# Rules Status

This implementation reflects the currently discussed beta rules, including
the structured development opening.

## Implemented

- 9x9 board and three territories
- variable first-rank Sovereign positions
- Sovereign plus four additional alternating kitchen placements per player
- no MOVE during development
- Spy, Ballista, Trebuchet, and Recall prohibited during development
- first non-Sovereign MOVE unlocks height-three stacking for that player
- stack-height capture restrictions
- Infantry, Dragoon, Chariot, Marshal, and Griffin movement
- Griffin 1 and Griffin 2 Stacks use 1x2/2x1 leaps
- Griffin 3 Stacks use 2x3/3x2 leaps, replacing the shorter leap
- artillery range 3/5/9 by resulting stack height
- Spy conversion with replacement material paid from reserve
- converted enemy material goes to discard
- Recall cannot target a Sovereign
- Reinforcement is inserted beneath a friendly non-Sovereign stack
- immediate victory on Sovereign removal
- Royal Attack: the Sovereign may capture any adjacent enemy stack regardless of
  height, removes the entire stack, and occupies its square; protected attacks
  remain legal and can expose the Sovereign to capture on the reply
- optional Infiltration victory: the game ends immediately when a Sovereign
  completes a MOVE onto any square of the opponent's back row; there is no
  reserve or survival requirement
- draw when the next player has no legal action
- shared JSON configuration for board geometry, inventory, movement, artillery,
  special-piece limits, development presets, and named combat modes
- optional MOVE attrition: a shorter attacker is discarded and removes an
  equal number of pieces from the bottom of the taller defending stack
- optional artillery attrition: a shorter firing stack removes an equal number
  of bottom target pieces while the firing stack remains unaffected

## Data compatibility

Both engines use the same canonical unit identifiers and contract version 2.
They do not maintain runtime aliases for superseded names. Translate older
artifacts explicitly with the
[nomenclature conversion guide](NOMENCLATURE_CONVERSION.md).

## Still a design variable

Spy conversion in enemy territory remains legal. It is preserved for testing
rather than silently changed in the simulator foundation.

`control-v3` and `development-v3` retain the original restriction against
ordinary pieces attacking taller stacks. `attrition-control-v2` and
`attrition-development-v2` enable both implemented attrition rules, allowing
direct baseline comparisons without modifying engine code.

`development-infiltration-v1` and
`attrition-development-infiltration-v1` add the experimental Infiltration win
condition to those two development presets without changing their other rules.
