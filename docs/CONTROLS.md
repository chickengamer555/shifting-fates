# Controls

| Action | Key | Input action |
|---|---|---|
| Move / steer (third-person camera looks around with the mouse) | W A S D | `move_forward` `move_left` `move_backward` `move_right` |
| Hard push / start pushing | Shift | `push` |
| Jump (hold for a bigger spring jump) | Space | `jump` |
| Flip trick (in the air, Q with a direction in either order: W front flip, S back flip, A kickflip, D heelflip; two keys combine, e.g. Q + W + A = Front Kickflip). Hold the keys to keep repeating it while there is air | Q | `trick` |
| Spin (in the air: hold Q and move the mouse left / right; A / D alone also turn). Scored on landing: 180, 360, 540... | Q + mouse | `trick` |
| Board trick (in the air, the board spins under you: E Pop Shove-it, E + S Frontside Shove-it, E + W 360 Shove-it, E + A Varial Kickflip, E + D Varial Heelflip, E + W + A 360 Flip, E + W + D Laser Flip, E + S + A Hardflip, E + S + D Inward Heelflip). Hold to repeat | E | `board_trick` |
| Brake | Z | `brake` |
| Grind | C | `grind` |
| Shift (dash, phase in and out of the world) | X | `shift_phase` |
| Grab, front hand / back hand (in the air; hold for more points). Add a direction for another grab: Ctrl Melon, Ctrl + W Nosegrab, Ctrl + S Method, Ctrl + A Mute, Ctrl + D Seatbelt; Alt Indy, Alt + W Crail, Alt + S Tailgrab, Alt + A Stalefish, Alt + D Roast Beef | Ctrl / Alt | `grab_left` / `grab_right` |
| Grapple left / right (both: reel in) | Left / right mouse | `grapple_left` / `grapple_right` |
| Rocket boost (hold) | Middle mouse | `rocket_boost` |
| Pause | Esc | `pause` |
| Dev: spectator camera | Tab | `toggle_spectator` |
| Dev: test hub (debug builds; every scene, everything unlocked) | F1 | `toggle_test_hub` |

## Paint screen

Opens in the intro (paint yourself, then your board) and from **Esc → Repaint** in any
level (choose Yourself or Your board; the game stays paused and Done brings the pause
menu back). Paint always carries on from your saved look.

| Action | Input |
|---|---|
| Paint / use the tool | Left drag on the model |
| Turn the view | Left drag off the model, or right drag |
| Zoom | Mouse wheel |
| Brush | B |
| Paint bucket (fills the connected area of the colour you click; "Whole part" in the panel fills the whole part) | F |
| Eraser (back to the unpainted look) | E |
| Eyedropper (take a colour off the model) | I, or Alt + click |
| Finish tool (click a finish, then a part, to give it that finish: Original, Matte, Satin, Gloss, Metal, Chrome, Glow; it then goes back to your paint tool so you can paint over it. "Whole body" / "Whole board" gives it to every part) | M |
| Mirror left and right on / off | X |
| Brush size | [ and ] |
| Undo (strokes, fills and finishes) | Ctrl + Z |

Opacity and softness are sliders in the panel's Brush section.

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
