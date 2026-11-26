# Controls

| Action | Key | Input action |
|---|---|---|
| Move / steer (third-person camera looks around with the mouse) | W A S D | `move_forward` `move_left` `move_backward` `move_right` |
| Hard push / start pushing | Shift | `push` |
| Jump (hold for a bigger spring jump) | Space | `jump` |
| Trick (hold with a direction in the air, e.g. Q + W = front flip) | Q | `trick` |
| Brake | Z | `brake` |
| Grind | C | `grind` |
| Shift (dash, phase in and out of the world) | X | `shift_phase` |
| Left grab / right grab | Ctrl / Alt | `grab_left` / `grab_right` |
| Grapple left / right (both: reel in) | Left / right mouse | `grapple_left` / `grapple_right` |
| Rocket boost (hold) | Middle mouse | `rocket_boost` |
| Pause | Esc | `pause` |
| Dev: spectator camera | Tab | `toggle_spectator` |
| Dev: test hub (debug builds; every scene, everything unlocked) | F1 | `toggle_test_hub` |

## Developer test hub

`scenes/dev/test_hub.tscn` lists every playable scene: the main menu (the full game flow),
the opening, the intro, the intro started at its paint step, levels 1 to 3 and the skate test
(`scenes/main.tscn`). Pick one to go there with every ability unlocked. The hub runs on its
own GameState (`unlock_all`) with its own save and paint files (`user://test_hub_save.cfg`,
`user://test_hub_appearance.tres`), so your real save and look are never touched.

- Open it directly, or press **F1** (`toggle_test_hub`) anywhere in a debug build.
- In a chosen scene, **Esc** then **Quit** returns to the hub list (inside the full game flow,
  use F1). Finishing a level goes on to the next one.
- Add a scene by adding one line to `TestHub.ENTRIES` (`scripts/dev/test_hub.gd`).
