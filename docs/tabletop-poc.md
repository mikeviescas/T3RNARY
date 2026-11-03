# 3D Tabletop Simulator

`godot/scenes/main.tscn` is the production physical-tabletop simulator and the
project's default application scene. It replaces the original drawn simulator
with play, computer-opponent, replay, notation,
recording, and special-piece interaction parity and is the project launch scene.
The drawn scene remains in the repository as a rollback reference until this
replacement milestone is accepted, after which it can be archived.

The tabletop and original presentation share the same rules, AI, codec, and now
the reusable `ternary_session.gd` game-session controller. The session owns the
Sovereign draft, authoritative state, human and computer turns, resignation,
undo/redo history, annotations, and human-game recording. Presentation code no
longer needs to reproduce those behaviors.

The scene establishes the proposed production pipeline:

- Separately generated table, board, player-tray, and token geometry
- glTF (`.glb`) assets imported by Godot
- responsive perspective tabletop camera
- real-time lights and cast shadows
- procedural wood and leather material studies
- vertical stacks, horizontal Infantry rolls, and loose discard piles
- existing piece symbols applied to physical token faces

## Mobile interaction baseline

The production tabletop now has a first mobile-ready interaction layer while
retaining its desktop controls:

- Native `InputEventScreenTouch` taps use the same authoritative selection and
  action path as mouse input. Synthetic mouse events from touch are disabled so
  one physical tap cannot be interpreted twice.
- Stack and reserve hit regions have extra touch tolerance without enlarging
  the rendered pieces or legal-destination squares.
- The hamburger, menu actions, notation controls, Recall choices, replay
  transport, and game-over actions use phone-friendly minimum touch sizes.
- Undo and Redo are available from the hamburger menu and track the actual
  session history; keyboard shortcuts remain available on desktop.
- Overlay placement is calculated from the platform safe area. Portrait
  notation expands into a nearly full-screen reader, while landscape notation
  remains a side panel.
- Android Back closes the foremost overlay, chooser, expanded inspection, or
  selection. From a bare tabletop it opens the session menu rather than
  unexpectedly terminating an active game.
- Rejected OPENING actions give a short deny cue and, when Instructional
  Feedback is enabled, outline the current player's home territory, mark the
  attempted square, and explain the remaining placement requirement directly
  on the table. The explanation is reformatted for portrait screens.

The first mobile-quality phase also gives the application an independent active
session save at `user://active_session.json`. It is updated after setup choices,
committed actions, animation handoff, undo/redo, resignation, and explicit
opponent changes, and again when the application pauses, loses focus, or closes.
Writes rotate through temporary and backup files so an interrupted write does
not destroy the last recoverable position. Startup validates and reconstructs
the action history before restoring it, including an unfinished Sovereign draft,
computer ownership, and the undo/redo cursor. Human-game replay files remain a
separate immutable record.

The mobile runtime is capped at 60 frames per second and uses Godot's low-
processor mode while the turn-based table is idle. This prevents high-refresh
phones from spending battery rendering an unchanged position while preserving
full-rate movement and input response. Export presets and broader selectable
device-quality profiles remain part of later mobile phases.

Run the Godot project normally to open the tabletop simulator. The scene
displays a branded loading screen while Godot imports and
instantiates the premium model set; first launch is slower than subsequent runs.
Material and shader resources are shared across repeated token instances so the
current scene reaches the interactive table in roughly seven seconds on the
development machine instead of the earlier thirty-second startup.

Godot's embedded **Game** dock is a fixed editor panel, not the POC's window.
To test resizing, use the Game dock's three-dot menu and choose the option to
make the game view floating on the next play, then run the scene again. The POC
opens a standalone window sized to the current display, remains drag-resizable,
and supports F11 fullscreen.

## Interactive replacement milestone

The tabletop now opens at the real mirrored Sovereign draft and starts a current
beta-rules game. Use the compact controls above the table to start a new game,
switch between human and computer opponents, or choose the human player's color.
Computer search runs off the rendering thread and hands each chosen action back
to the tabletop animation before continuing.

On a fresh launch with no recoverable session, the computer controls Black and
the local player controls White by default. A restored game retains its saved
opponent and color choices, and the hamburger controls can still switch an
active position between human and computer ownership without restarting it.

The hamburger closes when the player clicks anywhere else on the tabletop.
Changing between Human and Computer transfers control of the existing position;
it does not restart the game. If the newly assigned computer side is already to
act, it immediately continues from that position.

- Click the current player's board stack to show legal MOVE/ATTACK targets.
- Click an opponent stack to show its movement reach without making those
  markers playable. Click the selected stack again to fan its physical tiles
  apart, and a third time to collapse it.
- Click a reserve piece to show legal PLACE targets.
- Click either discard caddy to fan every captured tile face-up for inspection;
  click the caddy again to return the pieces to their storage rows.
- Recall opens a compact chooser for the eligible discarded piece, then shows
  the legal return squares for that piece. Recalled artillery retains its
  ordinary optional SHOOT step.
- An artillery placement with a legal shot displays gold SHOOT targets. Click
  the muted ochre placement marker again to place without firing. After a shot,
  the Ballista or Trebuchet remains physically aimed along the firing line;
  that facing follows a later-moving stack and is reconstructed in replay.
- MOVE lifts and carries the full stack. On an ATTACK, ordinary pieces slide to
  side contact while a Griffin retains a short hop. The stacks bump and recoil
  with an impact cue; a fully defeated stack is knocked clear and its tiles
  peel individually toward discard before the attacker settles into the square.
  During attrition, the attacker and the matching bottom defender tiles fly to
  their respective discard caddies while the surviving upper tiles compact
  back onto the destination square.
- PLACE moves a physical tile from the reserve to the board. SHOOT draws a
  brief firing line and resolves the target through the rules engine.
- Use Ctrl/Cmd-Z to undo and Ctrl/Cmd-Shift-Z to redo. In computer games the
  session treats the human/computer pair as one undo step.
- Completed setup and every subsequent action are automatically recorded using
  the same version-2 replay document used by the original simulator.
- The hamburger menu contains New Game, Open Replay, Game Notation, opponent,
  and player-color controls without occupying permanent space around the board.
- Open Replay uses the native list-style file picker. Compact first, previous,
  next, and last controls replace the turn inscription inside the polished
  metal status inlay, and forward single-ply steps animate through the same
  physical movement path as live play.
- Game Notation opens as a dismissible table overlay with a copy button. During
  replay it displays and copies only through the currently visible ply.
- Capture, Conquer, resignation, and terminal draws produce a full-table game
  over presentation with the winner and end method. Closing it or choosing
  Review Game immediately opens the completed in-memory game at its final replay
  ply, so the player can step backward without finding and reopening the file.

The 3D scene rebuilds its board, reserve, and discard presentation from the
authoritative post-action state after every animation. Focused regressions cover
session setup, threaded AI response, recording data, target selection, Recall,
MOVE, PLACE, optional SHOOT selection, undo, redo, and end-method tracking in
`godot/tests/test_ternary_session.gd` and
`godot/tests/test_tabletop_interaction.gd`.

`godot/scenes/tile_design_study.tscn` is the companion close-up study for the
nesting play tile. Open it directly and run the current scene to compare the
white and black finishes, side profile, underside socket, exploded seating
pair, legal one-to-three tile stacks, and a horizontal Infantry reserve roll.

## Nesting tile proportions

The current proof-of-concept uses the approved 28:22:10 proportions:

- 28 mm-equivalent lower skirt diameter
- 22 mm-equivalent upper crown diameter
- 10 mm-equivalent overall height
- approximately equal-height lower skirt and upper crown
- a recessed underside socket with clearance around the next tile's crown
- a flat circular bearing surface outside the protected icon and pinstripe

The nesting pitch is approximately half a tile height. Consequently, one,
two, and three tile stacks read as roughly 10, 15, and 20 mm-equivalent rather
than 10, 20, and 30 mm. The underside socket remains visible in the study so
the physical relationship can be evaluated before production tolerances are
specified.

## Premium material study

The token proof-of-concept now uses polished white marble and black obsidian
texture assets rather than flat plastic colors. Stone response is handled by a
real-time Godot material with restrained mineral detail, low roughness, and
strong edge highlights. The circular line and ordinary unit symbols are
separate shallow metal-inlay geometry seated inside a machined face recess;
they are not texture planes or stickers.

The Sovereign is now a standalone open crown on a matching player-colored stone
plinth, approximately the physical height of a nested 3 Stack. White uses white
marble throughout; Black uses polished obsidian throughout. Broad triangular
prongs echo the original Sovereign icon. Its silhouette makes clear that it is
royal, cannot accept another tile, and is not an ordinary stacking piece.
Each Sovereign carries two narrow opposite-color inlays: one at the base of the
crown and one around the lower edge of the plinth. Its six rounded spire tips
also use the opposite color so the crown remains readable against either rank.

Spy, Trebuchet, and Ballista use inverse face wells to identify the three
immobile pieces. Both sides use the same medium-gray field; White uses a white
mark and Black uses a black mark. Reinforcement and Recall retain
ordinary face colors but replace the continuous circular inlay with a raised dotted perimeter,
marking them as special tiles that do not remain visible on the battlefield.
All unit types have dedicated models in both player colors; the tabletop no
longer relies on temporary icon planes for ordinary pieces.

Each reserve tray carries ten flattened token-top emblems in two columns of
five for the non-Infantry pieces. The Sovereign position is gold. The other
positions use contrasting pale or dark gray relief so an empty storage
location remains identifiable without resembling a playable piece. Infantry
is shown separately as a horizontal roll.

## Rebuilding the geometry

After changing the Blender construction script, regenerate the assets with:

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background \
  --python tools/blender/build_tabletop_poc.py
```

The script writes `table_surface.glb`, `board.glb`, `player_tray.glb`, and the
two token models to `godot/assets/poc/`. Godot imports them automatically. The
POC assembles these assets under a named **Landscape Composition** node so every
component can be inspected and repositioned independently.

## Scope of this study

The POC has progressed into the functional replacement simulator and project
launch scene. It is now intended to validate the complete play-and-review
workflow before archival of the drawn simulator. It deliberately uses exaggerated
procedural grain so material direction and object boundaries remain obvious.
Production materials should replace these studies with restrained, tileable
PBR texture sets after the geometry and composition are approved.
