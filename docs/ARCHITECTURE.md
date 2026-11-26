# Architecture

Godot 4.7, GDScript, Jolt physics. Statically typed GDScript throughout.

## Folder layout

| Folder | What lives there |
|---|---|
| `autoload/` | Singletons registered in `project.godot`: `GameState` (progress, unlocks, saves), `Settings` (preferences). No `class_name` on autoload scripts (avoids name clashes). |
| `scripts/core/` | Shared constants, e.g. `PhysicsLayers` (layer numbers and bit masks). |
| `scripts/player/` | The skater body, its camera, its visual rig and the shift phase ability. |
| `scripts/abilities/` | `SkaterAbility` base and subclasses: grind, grapple, rocket boost. |
| `scripts/scoring/` | Pure logic: tricks, combo multiplier, rank names, level point goal. No nodes needed to test them. `ScoreKeeper` is the one node: it turns a bound Skater's signals into banked points. |
| `scripts/grind/` | Grind rails and the grind balance minigame logic. |
| `scripts/world/` | Level pieces: portals, invisible barriers, level controller. |
| `scripts/levels/` | Scripts of specific story scenes: the opening, the intro, level 2's god lights. |
| `scripts/flow/` | `GameFlow`: the screen flow (menu, opening, levels) in the boot scene `scenes/game.tscn`. |
| `scripts/dialogue/` | Dialogue data resources and the runner that plays them. |
| `scripts/ui/` | Menus, HUD, dialogue box. |
| `scripts/dev/` | Developer tools (spectator camera). Not part of the shipped game flow. |
| `scenes/<same>/` | Scenes, mirroring the `scripts/` folders. |
| `data/` | Authored content as resources (dialogue sequences, trick tables). |
| `Assets/` | Original art, levels, environments and shaders. **All rights reserved** (see `ASSETS_LICENSE.md`). |

## Conventions

- **Call down, signal up.** Parents call methods on children; children emit signals.
  No `get_node("..")`. Cross-scene references use `%UniqueName` or exported `NodePath`s.
- **Logic separate from presentation.** Scoring, combo, grind balance and grapple-rope
  rules are plain `RefCounted`/`Resource` classes, so they are unit-testable without a scene.
- **Abilities are components.** The `Skater` hosts `SkaterAbility` child nodes and ticks
  them each physics frame (see `scripts/abilities/skater_ability.gd`). It feeds them the
  camera forward and heading (`update_aim`), keeps the horizontal velocity they add, skips
  its own movement while one `is_controlling_movement()`, and also skips gravity,
  `move_and_slide()` and air state while it `places_body_directly()` (grinding). Gated
  abilities name an `unlock_id`; the Skater enables them from GameState.
- **Scoring flow.** A level wires `ScoreKeeper.bind(skater)` and `Hud.bind(skater, keeper)`.
  Air time and grind time both grow the combo multiplier; the Skater never counts a grind
  as air time.
- **Fonts** come from `FontLibrary` (`scripts/ui/font_library.gd`): the licensed fonts in the
  git-ignored `local_fonts/` when present, bundled `third_party/fonts/` otherwise. Never
  preload a `local_fonts/` file: it is absent in a fresh clone.
- **Dialogue** is drawn at the top of the screen with no panel (`DialogueBox`): every god is
  a `GodOrb` (an oscillating ball of light) in the box's orb row, lines are `DialogueText`
  (god lines fade in word by word in Cinzel under the orbs; player lines fade in below them
  in plain, quieter Inter with no tag). `scenes/dev/dialogue_preview_*` step the dialogue on
  a timer for screenshots.
- **HUD** (`Hud`) is one thin strip across the top (score, goal bar, unlocked abilities) plus
  a `ComboPopup` drawn beside the skater (projected through the active camera) only while a
  combo is scoring; it flashes the banked points or "Bailed" and fades. Numbers are always
  Inter: The Jacatra draws its "0" as a logo, so it only ever gets the rank's letters.
- **Main menu** puts the `GodOrb` at top centre with `god_rays.gdshader` light branching
  out of it across the top, the title in Cinzel and four `WishButton`s bottom left.
- **Main menu background** is `MenuLivePan`: the level art scenes rendered live in a
  SubViewport, one at a time, with cameras and bodies stripped and physics paused.
- **Input actions** are declared in `project.godot` (see `docs/CONTROLS.md`).
- **Physics layers:** 1 `world`, 2 `player`, 3 `phaseable` (solid normally, passable while
  shifted), 4 `grind_rail`, 5 `trigger`. In code always use `PhysicsLayers`.
- Style: tabs, lines <= 100 chars, `snake_case` members, `PascalCase` classes, typed vars and
  return types, `signal.emit()` / `signal.connect()`, past-tense signal names.

## Testing

Behaviour is verified with the godot-verify headless matrix, kept outside this repo in a
sibling `harness/` folder (`harness/run.sh` stages a copy of the game and runs it).
