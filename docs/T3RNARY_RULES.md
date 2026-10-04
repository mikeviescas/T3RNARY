# T3RNARY

## Working Beta Rules v0.2

T3RNARY is a two-player strategy game played on a 9×9 board. Players develop
their forces from reserve, stack units up to 3 pieces high, and attempt to
defeat the opposing Sovereign or conquer its territory with their Sovereign.

## 1. Winning the Game

A player can win in one of two ways:

1. **CAPTURE:** Remove the opponent's Sovereign by attacking its square with any
   movable unit.
2. **CONQUER:** Claim the opponent's territory by advancing your Sovereign to
   their back row.

## 2. The Board

T3RNARY uses a 9×9 board. Files are labeled A–I and ranks are numbered 1–9.

| Territory | Squares |
|---|---|
| White territory | A1–I3 |
| Neutral territory | A4–I6 |
| Black territory | A7–I9 |

White moves forward toward rank 9. Black moves forward toward rank 1.

## 3. Your Pieces

Each player begins with 27 pieces:

| Piece | Code | Quantity |
|---|:---:|---:|
| Sovereign | V | 1 |
| Infantry | I | 9 |
| Dragoon | D | 3 |
| Chariot | C | 3 |
| Griffin | G | 3 |
| Marshal | M | 2 |
| Ballista | B | 1 |
| Trebuchet | T | 1 |
| Spy | Sp | 1 |
| Recall | Rc | 1 |
| Reinforcement | Rf | 2 |

Pieces waiting to be played are kept in your **reserve**. Captured and removed
pieces are kept face-up in their owner's **discard pile**.

## 4. The Opening Phase

Begin with an empty board.

1. White places their Sovereign anywhere on rank 1.
2. Black places their Sovereign anywhere on rank 9.
3. Starting with White, alternate placing one piece at a time until each player
   has placed 4 more pieces.

All development pieces must be placed in their owner's territory. You may build
stacks during development, but only to height 2.

Spy, Ballista, Trebuchet, and Recall may not be used during development. No
pieces may MOVE until the Opening phase is complete.

## 5. Take a Turn

On your turn, you must take one of the following actions:

- **MOVE** one stack already on the board; or
- **PLACE** one piece from your reserve.

A MOVE becomes an **ATTACK** when it ends on an enemy-occupied square. A PLACE
becomes a **SHOOT** when you place a Ballista or Trebuchet and fire it by
selecting a valid target.

After your action, play passes to your opponent.

## 6. Build Stacks

A stack may contain 1, 2, or 3 pieces. Its **TOP piece** identifies the stack
and determines its movement and abilities. Buried pieces add height and
strength but do not determine the stack's identity.

```text
Marshal          ← TOP piece
Infantry
Reinforcement    ← bottom piece
```

This is a **Marshal 3 Stack**. It is a Marshal Stack because its TOP piece is a
Marshal.

You may not MOVE onto a friendly stack. Build friendly stacks by using PLACE.

Before you build your first stack of height 3, you must have completed a
non-Sovereign MOVE.

## 7. Move and Attack

MOVE a stack according to its TOP piece. Movement ranges are maximums, so a
range-5 stack may move anywhere from 1 to 5 squares.

Except for the Griffin, stacks may not move through occupied squares.

A stack may finish its MOVE on an empty square or an enemy-occupied square.

A MOVE onto an enemy-occupied square is an ATTACK. Compare the attacker's
height to the defender's height.

### Equal or Taller Attacker

Remove the entire defending stack. The attacking stack takes the square.

### Shorter Attacker

Remove the entire attacking stack. Then remove the same number of pieces from
the **bottom** of the defending stack. The surviving pieces of the defender
remain in place.

Example: A height-1 stack attacks a height-3 stack. The attacking stack is
removed, along with the bottom piece of the defending stack. The defender
remains as a height-2 stack.

## 8. Place and Shoot

Once the Opening phase is complete, you may PLACE a normal piece:

- on an empty square in your territory;
- on an empty square in neutral territory; or
- on top of one of your stacks of height 1 or 2 anywhere on the board.

You may not place a normal piece on an empty square in enemy territory, on an
enemy stack, on a stack of height 3, or on a Sovereign.

Spy, Recall, and Reinforcement follow the placement rules in **Special Pieces**.

When you PLACE a Ballista or Trebuchet, it may SHOOT. See
[Artillery: Ballista & Trebuchet](#11-artillery-ballista--trebuchet).

## 9. Movement Pieces

| Unit | 1 Stack | 2 Stack | 3 Stack | Movement |
|---|---:|---:|---:|---|
| Infantry | 1 | 2 | 3 | Straight forward |
| Dragoon | 3 | 5 | 9 | Diagonal |
| Chariot | 3 | 5 | 9 | Horizontal or vertical |
| Marshal | 3 | 5 | 9 | Horizontal, vertical, or diagonal |
| Griffin | 1×2 or 2×1 | 1×2 or 2×1 | 1×2, 2×1, 2×3, or 3×2 | Exact L-shaped leap |

Infantry Stacks can only move and attack straight forward.

Dragoon, Chariot, and Marshal Stacks may not move through occupied squares.

Griffin Stacks leap over occupied squares and must land on the exact
destination. A Griffin 3 Stack may use either the shorter or longer leap.

## 10. Sovereign Stack

A Sovereign Stack can MOVE 1 square in any direction and is always height 1.
Nothing may be placed on or beneath it.

### Royal Attack

A Sovereign Stack may attack any adjacent enemy stack, regardless of height.
Remove the entire defending stack and move the Sovereign Stack onto its square.

### Conquer

A Sovereign can win by landing anywhere on the opponent's back rank.

## 11. Artillery: Ballista & Trebuchet

Ballista and Trebuchet Stacks may not MOVE. When either piece is placed on the
board or on top of a stack, the resulting stack may immediately SHOOT once.

| Artillery | Firing directions |
|---|---|
| Ballista | Forward, left, or right |
| Trebuchet | Either forward diagonal |

Artillery range is 3 at height 1, 5 at height 2, and 9 at height 3. Artillery
may not fire through occupied squares or target a Sovereign.

Against an equal or shorter target, remove the entire target stack. Against a
taller target, remove a number of pieces from the target's bottom equal to the
height of the firing stack. The artillery stack is unaffected.

SHOOT is optional.

## 12. Special Pieces

### Spy

A Spy Stack may not MOVE.

You may PLACE Spy directly onto an enemy height-1 or height-2 stack. To do so,
you must have matching pieces in your reserve for every piece in the target
stack.

Discard the enemy stack. Rebuild it with your matching reserve pieces, then
place Spy on top. You now control the converted stack.

Spy may not convert a stack of height 3 or a Sovereign.

### Recall

Use Recall as a PLACE action to return one of your discarded pieces to play.

Discard the Recall piece, then PLACE the returned piece normally. Any
placement ability of the returned piece takes effect.

### Reinforcement

PLACE Reinforcement underneath one of your non-Sovereign stacks of height 1 or
2. It increases the stack's height without changing its TOP piece or stack
identity.

Reinforcement may not be placed on an empty square, on top of a stack, under a
stack of height 3, or under a Sovereign.

## 13. Example Opening

Here is one way a game could begin:

| Step | White | Black |
|---:|---|---|
| 1 | Places Sovereign on E1 | Places Sovereign on E9 |
| 2 | Places Infantry on E3 | Places Infantry on E7 |
| 3 | Places Dragoon on C2 | Places Chariot on G8 |
| 4 | Places Marshal on D2 | Places Griffin on F8 |
| 5 | Places Infantry on F3 | Places Dragoon on C8 |

Both players have now placed their Sovereign and 4 other pieces. The Opening
phase is complete.

White chooses to MOVE the Infantry 1 Stack from E3 to E4, entering neutral
territory and signaling that the board is open.

---

# Frequently Asked Questions

## Are ATTACK and SHOOT additional actions?

No. ATTACK is the name for a MOVE onto an enemy-occupied square. SHOOT is the
name for a PLACE that fires a Ballista or Trebuchet.

## Can I pass without taking an action?

No. On your turn, you must MOVE or PLACE.

## Do Sovereigns use check or checkmate?

No. A Sovereign Stack may move into danger or remain under attack. A player
wins CAPTURE only by actually removing the opposing Sovereign.

## Can a Sovereign attack a taller stack?

Yes. Royal Attack removes the entire adjacent enemy stack regardless of height.
Normal attrition does not apply to the Sovereign Stack.

## Can Ballista, Trebuchet, or Spy remove a Sovereign?

No. A Sovereign Stack can only be removed by an ATTACK.

## Can I PLACE a piece on a friendly stack in enemy territory?

Yes. Once the Opening phase is complete, you may add a piece to a legal friendly
stack anywhere on the board. You still may not PLACE normally onto an empty
enemy-territory square.

## Can Spy be played without converting an enemy stack?

Yes. Spy may be placed normally, although a Spy Stack may not MOVE.

## Can Spy convert a stack in enemy territory?

Yes. Spy conversion is legal in any territory.

## What happens to pieces converted by Spy?

The enemy pieces go to their owner's discard pile. Matching replacements come
from the Spy player's reserve and keep the target's original bottom-to-top
order. Spy is then placed on top.

## Can a Spy Stack ever move?

Not while Spy is its TOP piece. If the stack is shorter than height 3, another
friendly piece may be placed on top. That piece becomes the new TOP piece and
changes the stack's identity.

## Does artillery lose pieces when firing at a taller stack?

No. Only the target suffers artillery attrition.

## Can artillery fire through a friendly or enemy piece?

No. The first occupied square blocks the rest of that firing line.

## Does Reinforcement make Ballista or Trebuchet fire again?

No. Artillery may SHOOT only when the Ballista or Trebuchet is placed as the
new TOP piece.

## Does Recall activate placement abilities?

Yes. A recalled Ballista or Trebuchet may SHOOT, and a recalled Spy may
convert a legal target if its replacement cost can be paid.

## What happens when attrition removes a stack's bottom piece?

The remaining pieces stay in their original order. The TOP piece still
determines the stack's identity.

## What happens when Infantry reaches the far back row?

An Infantry Stack may not move farther forward. Another friendly piece may still
be placed on top if the stack is shorter than height 3, changing its TOP piece
and stack identity.

---

# Appendix A: T3RNARY Notation

Record each action in order. White always records first. The developing board
supplies stack heights and the identities of buried pieces.

Battlefield units and artillery use one-letter codes. Spy, Recall, and
Reinforcement use two-letter codes.

## Piece Codes

| Piece | Code | Piece | Code |
|---|---|---|---|
| Sovereign | V | Marshal | M |
| Infantry | I | Ballista | B |
| Dragoon | D | Trebuchet | T |
| Chariot | C | Spy | Sp |
| Griffin | G | Recall | Rc |
| Reinforcement | Rf |  |  |

## Action Forms

| Form | Meaning | Example |
|---|---|---|
| `P-<piece>@<square>` | PLACE | `P-V@E1` |
| `M-<piece>:<from>-<to>` | MOVE to an empty square | `M-I:E3-E4` |
| `M-<piece>:<from>x<to>` | ATTACK an enemy square | `M-D:C2xF5` |
| `P-<artillery>@<square>x<target>` | PLACE and SHOOT | `P-B@D3xD6` |

Use `@` for placement, `-` for movement, and `x` when an enemy stack is
attacked, shot, or converted. Add `#` when the action wins the game.

Special PLACE actions use these forms:

- Spy conversion: `P-SpxF7`
- Reinforcement under a stack: `P-Rf@D2`
- Recall a Griffin: `P-Rc(G)@C3`
- Recall a Ballista and SHOOT: `P-Rc(B)@D3xD6`

Record the two Sovereign placements first so the archive preserves their starting
squares. A complete record begins like this:

```text
1W P-V@E1       1B P-V@E9
2W P-I@E3       2B P-I@E7
3W P-D@C2       3B P-C@G8
4W P-M@D2       4B P-G@F8
5W P-I@F3       5B P-D@C8
6W M-I:E3-E4
```

Because every entry includes its source and destination or placement square,
the record can be replayed from an empty board.

---

# Appendix B: Technical Rules Index

This index is the authoritative quick reference for edge cases, simulator
comparison, and AI rules review. The current implemented preset is
`attrition-development-infiltration-v1` using piece catalog `core-pieces-v4`.

## A. Core State

- Board: 9×9; files A–I; ranks 1–9.
- White home ranks: 1–3. Neutral ranks: 4–6. Black home ranks: 7–9.
- White forward: increasing rank. Black forward: decreasing rank.
- Maximum stack height: 3.
- Stack order: bottom-to-TOP. The TOP piece determines stack identity,
  movement, and abilities.
- Removed pieces enter the discard pile belonging to their printed owner.
- Starting inventory per player: Sovereign 1, Spy 1, Ballista 1, Trebuchet 1,
  Dragoon 3, Chariot 3, Griffin 3, Marshal 2, Infantry 9, Recall 1, and
  Reinforcement 2.

## B. Development Sequence

- White Sovereign is placed first on rank 1; Black Sovereign is placed second on rank 9.
- White then makes the first of 8 alternating development placements.
- Each player completes exactly 4 development placements.
- Development placement is restricted to the placing player's home territory.
- Spy, Ballista, Trebuchet, and Recall are prohibited during development.
- MOVE is prohibited until both players complete development.
- Height 3 is locked separately for each player until that player completes a
  non-Sovereign MOVE.

## C. Normal PLACE Destinations

- Empty square: own or neutral territory only.
- Friendly stack: anywhere, provided it is below height 3 and is not a Sovereign.
- Enemy stack: prohibited except for legal Spy conversion.
- Reinforcement: bottom insertion into a friendly non-Sovereign stack only.
- A player must possess the placed piece in reserve, except that Recall moves
  the returned piece from discard.

## D. MOVE Combat

- A MOVE ending on an enemy-occupied square is called an ATTACK.
- Attacker height ≥ defender height: discard full defender; attacker occupies.
- Attacker height < defender height: discard full attacker; discard defender's
  bottom pieces equal to attacker height; surviving defender remains.
- Sovereign Royal Attack overrides height comparison and removes the full defender.
- Capturing a Sovereign ends the game immediately.

## E. CONQUER Victory

- White Sovereign Stack destination rank: 9.
- Black Sovereign Stack destination rank: 1.
- Trigger: completion of a Sovereign Stack MOVE onto the enemy back row.
- Resolution: immediate victory.
- No reserve, safety, or survival-turn condition applies.

## F. Movement Parameters

- Sovereign Stack: omnidirectional, exactly 1 square.
- Infantry Stack: forward ray, maximum range equal to stack height.
- Dragoon Stack: diagonal ray, ranges 3/5/9 by height.
- Chariot Stack: orthogonal ray, ranges 3/5/9 by height.
- Marshal Stack: omnidirectional ray, ranges 3/5/9 by height.
- Griffin 1 and Griffin 2 Stacks: exact 1×2 and 2×1 leaps.
- Griffin 3 Stack: exact 1×2, 2×1, 2×3, and 3×2 leaps.
- Ballista, Trebuchet, and Spy Stacks are immobile.
- Reinforcement may not be a TOP piece.
- Recall never remains on the board.

## G. Artillery Resolution

- A PLACE that selects an artillery target is called a SHOOT.
- Trigger: Ballista or Trebuchet is placed as the new TOP piece, including by
  Recall.
- Firing is optional and selects at most one visible legal enemy target.
- Range by resulting firing-stack height: 3/5/9.
- Ballista directions: forward and sideways. Trebuchet: forward diagonals.
- Occupied squares block fire. Sovereign is not a legal target.
- Firing height ≥ target height: discard full target.
- Firing height < target height: discard target's bottom pieces equal to firing
  height; firing stack is unaffected.

## H. Special-Piece Limits

- Sovereign Stack: may not be stacked, Reinforced, Recalled, converted, or
  targeted by artillery.
- Spy conversion: target maximum height 2; Sovereign prohibited; replacements paid
  from reserve; original target order preserved.
- Recall: Sovereign and Recall are prohibited return pieces.
- Reinforcement: inserted at bottom; may not be a TOP piece; Sovereign
  prohibited.

## I. Turn and Terminal Rules

- Exactly one MOVE or PLACE per turn; passing is prohibited.
- Every MOVE changes the source square and travels at least one square.
- Victory is checked immediately after Sovereign capture or CONQUER.
- If the next player has no legal MOVE or PLACE, the game is a draw.
- No repetition, turn-limit, or no-progress draw is currently defined.

## J. Configuration Identity

- Piece catalog: `core-pieces-v4`.
- Ruleset: `attrition-development-infiltration-v1`.
- MOVE against taller stack: `mutual_bottom_attrition`.
- Artillery against taller stack: `target_bottom_attrition`.
- Development opening: enabled, with 4 post-Sovereign placements per player.
- Height-3 prerequisite: each player must first complete a non-Sovereign MOVE.
- CONQUER victory: enabled.

## K. Unit Names and Serialized Identifiers

The rules, notation, both rules engines, and contract version 2 use the same
canonical names. Older archives can be translated with the
[nomenclature conversion guide](NOMENCLATURE_CONVERSION.md).

| Unit name | Notation | Contract v2 JSON identifier |
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
