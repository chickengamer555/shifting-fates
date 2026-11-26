# Third-party material

Material in this repository that was not made by the Shifting Fates author. Each item keeps
its own license.

## Bundled in this repository

| File | Source | License |
|---|---|---|
| `Assets/shaders/sky.gdshader` | "Starry sky" by breadpack, godotshaders.com: https://godotshaders.com/shader/starry-sky/ | MIT (per godotshaders.com: "The shader code and all code snippets in this post are under MIT license"). Copyright (c) breadpack. |
| `third_party/fonts/fontawesome/fa-solid-900.ttf` | Font Awesome Free 5.15.4, https://fontawesome.com | Font: SIL OFL 1.1 (see `LICENSE.txt` beside it) |
| `third_party/fonts/inter/Inter-Variable.ttf` | Inter by The Inter Project Authors (https://github.com/rsms/inter), via Google Fonts (the player's lines and HUD numbers) | SIL OFL 1.1 (see `LICENSE.txt` beside it) |
| `third_party/fonts/cinzel/Cinzel-Variable.ttf` | Cinzel by The Cinzel Project Authors, via Google Fonts (the gods' dialogue font) | SIL OFL 1.1 (see `LICENSE.txt` beside it) |
| `third_party/audio/kenney_impact_sounds/` (ollie pop, landing) | "Impact Sounds" by Kenney, https://kenney.nl/assets/impact-sounds | CC0 1.0 (see `License.txt` beside them) |
| `third_party/audio/kenney_scifi_sounds/` (dash, rocket loop, combo sub-bass) | "Sci-Fi Sounds" by Kenney, https://kenney.nl/assets/sci-fi-sounds (via https://opengameart.org/content/sci-fi-sounds) | CC0 1.0 (see `License.txt` beside them) |
| `third_party/audio/oga_coin_get/` (combo-gain hit) | Coin01 from "Level up, power up, Coin get (13 Sounds)" by wobbleboxx, https://opengameart.org/content/level-up-power-up-coin-get-13-sounds | CC0 1.0 (see `License.txt` beside it) |
| `third_party/audio/oga_scrapes/` (grind loop) | "Scrapes" by AntumDeluge, https://opengameart.org/content/scrapes | CC0 1.0 (see `LICENSE.txt` beside it) |
| `third_party/audio/skate_surfaces/` (rolling loop and landing per surface: concrete, wood, metal, grass, water) | BigSoundBank by Joseph Sardin, https://bigsoundbank.com: #1287 "Trash can rolling on a road", #1316 "Devil handling", #1513 "Rowing Quickly", #1841 "Jumping on wooden pontoon", #1839 "Jumping on Grass", #1771 "Falling sheet steel bar", #1529 "Splash, Small"; plus "Bowling Ball Rolling" by qubodup (https://opengameart.org/content/bowling-ball-rolling) and water_flowing from "30 CC0 SFX loops" by rubberduck (https://opengameart.org/content/30-cc0-sfx-loops) | CC0 1.0 (see `LICENSE.txt` beside them for the file-by-file list) |
| `third_party/audio/grapple/` (hook fire, attach, reel loop, release) | BigSoundBank, https://bigsoundbank.com: #1239 and #1238 "Climbing carabiner", #2961 "Complete whip", #1435 "Fishing reel, fast", #1818 "Sliding rope"; plus clink1 from "Metal Impact Sounds" by BMacZero (https://opengameart.org/content/metal-impact-sounds) | CC0 1.0 (see `LICENSE.txt` beside them) |
| `third_party/audio/holy_ui/` (menu hover, click, back) | BigSoundBank, https://bigsoundbank.com: #2080 Chimes "dream", #1689 "Triangle", #2554 "Tibetan bowl struck" | CC0 1.0 (see `LICENSE.txt` beside them) |
| `third_party/audio/hospital_conversation/` (the muffled conversation in the opening: doctor voice intro, loop, outro) | BigSoundBank, https://bigsoundbank.com: #0681 "Evening with Friends: Sofia Coppola" mixed with #0874 "Motherhood: Corridor" | CC0 1.0 (see `LICENSE.txt` beside them) |
| `third_party/audio/oga_storm_arwen/` (low and mid wind layers) | "Storm Arwen 2022" by Tsorthan Grove, https://opengameart.org/content/storm-arwen-2022 | CC0 1.0 (see `LICENSE.txt` beside them) |
| `third_party/audio/oga_wind_whoosh_loop/` (high wind layer) | "wind whoosh loop" by SketchMan3, https://opengameart.org/content/wind-whoosh-loop | CC0 1.0 (see `LICENSE.txt` beside it) |
| `third_party/audio/oga_swishes/` (trick whoosh) | "Swishes Sound Pack" by artisticdude, https://opengameart.org/content/swishes-sound-pack | CC0 1.0 (see `LICENSE.txt` beside it) |
| `third_party/audio/oga_ghostly_humming/` (God's voice intro, loop, outro) | "Ghostly Humming" by Nocturnal_Vanguard (AuraVoice), https://opengameart.org/content/ghostly-humming | CC0 1.0 (see `LICENSE.txt` beside them) |
| `third_party/models/quaternius_ual/source/UAL1_Standard.glb` | "Universal Animation Library [Standard]" by Quaternius (mannequin + clips), https://quaternius.com/packs/universalanimationlibrary.html | CC0 1.0 (see `LICENSE.txt` beside it) |
| `third_party/models/kenney_mini_skate/source/skateboard.glb` | "Mini Skate" 2.0 by Kenney (www.kenney.nl), via https://opengameart.org/content/mini-skate | CC0 1.0 (see `LICENSE.txt` beside it) |
| `third_party/models/baked/*` | The two models above, split into paintable parts with fresh UVs, plus selected animation clips, by `scripts/dev/skater_model_baker.gd` | CC0 1.0 (derived from the CC0 sources above) |
| Godot Engine | https://godotengine.org | MIT (engine; not bundled) |

All audio above was trimmed, converted to mono Ogg Vorbis and level-normalised for this game
(the God voice is also layered with chorus and echo; the rolling loops were made seamless, the
metal loop is the concrete recording through short metallic echoes, and the hospital
conversation is heavily low-passed so it sounds muffled through a wall). `scenes/audio/heart_monitor_loop.ogg`
is a generated 1 kHz sine beep made for this game, so it falls under `ASSETS_LICENSE.md`.

### Level meshes

- Terrains and primitive shapes generated by the author's own Chickbry 3D tool are the
  author's work and fall under `ASSETS_LICENSE.md`.
- **Some levels also use models and textures from Bryce 3D's built-in object library**
  (for example 3D critter faces, Acuris "WALLEYE", "wart_hog", "oldtree" and the
  `Bark.TIF` texture). These are **not** the author's work and their redistribution terms
  are unconfirmed. **Do not publish them in this repository until their license is
  confirmed** or they are replaced with original models.

## Used locally, NOT in this repository

The design calls for these fonts. Their licenses do not allow them to be redistributed, so
they live in the git-ignored `local_fonts/` folder on the author's machine. The game uses
them when present and falls back to the bundled fonts in a fresh clone.

| Font | Author | License summary |
|---|---|---|
| The Jacatra (combo score) | Ryal Docallisme HAS | Donationware, free for personal use. Commercial use: contact the author. |
| KR Lynda's Christian Dings (gods' flashing text) | KAT (katsfunfonts.com) | **Personal use only**, no commercial use. |
| Laus Sus Cris | (fontspace.com) | Personal use only; commercial use needs a paid registration. Not downloaded. |

**Before selling or publicly releasing a build:** exported builds include `local_fonts/`.
Get permission or a license from each author first, or remove the folder before exporting.
