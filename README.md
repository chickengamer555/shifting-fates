# Shifting Fates

A third-person 3D skateboarding game made with Godot 4.7.

After a career-ending wipeout, a skater wakes up in hospital and is visited by God. They
make one wish: to become the best skateboarder in the universe. To earn it, they have to
shift the fates and impress a whole pantheon of gods, one level at a time. Each god hands
out new powers along the way.

## Features

- Momentum-based skating: push, steer, brake, an ollie or a charged spring jump, and a
  free-orbit third-person camera.
- Air tricks (Q plus a direction) and grabs (Ctrl / Alt). The longer you stay in the air,
  the higher your combo, from **Baby** up to **Godly xN**.
- Grinding with a balance minigame: counter the wobble with A and D.
- **Shift** (X): dash and phase out of reality, passing through phaseable walls.
- God-given gifts: grapple hooks (left and right mouse, both to reel in) and a rocket
  booster (middle mouse).
- Paint your own body and board after you lose your physical form.
- Point goals per level. Reach one and a portal opens onto the next area.

See [docs/CONTROLS.md](docs/CONTROLS.md) for the full control list.

## Running

1. Install [Godot 4.7](https://godotengine.org/download) (standard build).
2. Clone this repository and open `project.godot` in Godot.
3. Press F5.

## Project layout

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the folder layout and code
conventions.

## Licensing

- **Code** is under the [MIT License](LICENSE).
- **Art, levels, story and dialogue are All Rights Reserved.** See
  [ASSETS_LICENSE.md](ASSETS_LICENSE.md). You may build and play the game from this
  repository, but you may not reuse or redistribute the assets.
- Third-party material is listed in [THIRD_PARTY.md](THIRD_PARTY.md).

## Credits

Created by chickengamer555. Built with the [Godot Engine](https://godotengine.org).

## Note on levels 2 and 3

The art for levels 2 and 3 uses models from Bryce 3D's built-in library whose license is unconfirmed, so it is not in this repository. Those two levels only load on the author's machine.
