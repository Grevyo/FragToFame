# Credits and third-party assets

Frag to Fame's code, maps, UI, Magnet artwork and balance data are original to the project.
The weapon and knife models below are third-party work used under their licences. Creative Commons
Attribution (CC BY 4.0) allows commercial use provided the author is credited, which this file
and the in-game credits (to be added before release) do.

## Weapon models

| Weapon (in game) | Model title | Author | Licence | Source |
|---|---|---|---|---|
| Desert Eagle | Low-Poly Desert Eagle | TastyTony | CC BY 4.0 | https://sketchfab.com/3d-models/low-poly-desert-eagle-b81da261345f4462b2c4412352162287 |
| G17 | Low-Poly G17 | TastyTony | CC BY 4.0 | https://sketchfab.com/3d-models/low-poly-g17-60efc54ac59e47d18bdff94b2f5144ff |
| M1911 | Low-Poly M1911 | TastyTony | CC BY 4.0 | https://sketchfab.com/3d-models/low-poly-m1911-117f542d21954ae0a59afaedadcff338 |
| L118A1 | Low-Poly L118A1 | TastyTony | CC BY 4.0 | https://sketchfab.com/3d-models/low-poly-l118a1-5e2f001d6e6245bcacf2b1e2de8892f4 |
| Mk23 SOCOM | Low-Poly Mk23 Mod0 | notcplkerry | CC BY 4.0 | https://sketchfab.com/3d-models/low-poly-mk23-mod0-9698a59bea1d4504a8ca6f8c79455671 |
| M24 | M24 Low-Poly | GoldbergR | CC BY 4.0 | https://sketchfab.com/3d-models/m24-low-poly-1244656c19994cbe9126f2e0bb8dfbbe |
| SKS | Russian SKS | raveenpath45 | CC BY 4.0 | https://sketchfab.com/3d-models/russian-sks-2f44bffbd75a4b359fe1d2538b5d6d10 |
| M14 EBR | M14 Ebr | 3dartist63 | CC BY 4.0 | https://sketchfab.com/3d-models/m14-ebr-4d3b43b49c69441881cc565fb341bcb1 |
| AK-47 | (not recorded in the file) | unknown | **unknown** | — |
| M4A1 | (not recorded in the file) | unknown | **unknown** | — |

## Knife models

All seven knife looks come from one pack: **Low Poly Knife Collection** by **BUttERflY_Bee**
(https://sketchfab.com/BUttERflY_Bee), CC BY 4.0,
https://sketchfab.com/3d-models/low-poly-knife-collection-000c0c7c9ee740a28469e3c393ae133d

| Knife (in game) | Mesh in the pack |
|---|---|
| Combat Knife | Combat_knife |
| Bayonet | Bayonet_knife |
| Butterfly Knife | Butterfly_knife |
| Karambit | Krambit_knife |
| Nomad Knife | Nomad_knife |
| Skeleton Knife | Skeleton_knife |
| T-Handle Dagger | T-handle_dagger |

Changes made: each knife is saved as its own model with its original textures; the butterfly
knife's handles are separated into their own parts, placed on their pivot pins, so they can
swing. Paint-zone masks and Coat kit guides were generated from the pack's UV layouts. The
meshes and textures are otherwise unchanged.

Licence text: https://creativecommons.org/licenses/by/4.0/

Changes made to the CC BY models: UV layouts were re-made for the Desert Eagle, G17, M1911,
L118A1, Mk23, M24 and M14 EBR so each has one paintable texture ("Coat layout"); their original
material colours were baked into that texture. The Mk23's suppressor is moved onto the barrel
and its spare parts are hidden. Models are turned and scaled to a common orientation at load.

## Character models

| Pack | Author | Licence | In the repository | Source |
|---|---|---|---|---|
| Ultimate Modular Males | Quaternius | CC0 1.0 | yes (`assets/characters/quaternius_modular_males`) | https://quaternius.com |
| Universal Base Characters [Standard] | Quaternius | CC0 1.0 | yes (`assets/characters/quaternius_universal_base`) | https://quaternius.com |
| Creative Characters FREE | ithappy | Royalty-free use; no redistribution grant | **no**: git-ignored, local imports only | https://www.cgtrader.com/free-3d-models/character/anatomy/creative-characters-free |

CC0 needs no credit; Quaternius is credited anyway. Changes made: every pack is split into one
model per item, textures are stored next to the models, bones are renamed to the humanoid
profile at import, and two Universal texture names are corrected (`*_png.png`). The meshes,
textures and animations are otherwise unchanged. Before a commercial release that includes the
ithappy items, confirm the pack's licence covers shipping its models inside the game.

## Open items before a commercial release

- **AK-47 and M4A1 models:** the files carry no author or licence information. Their origin
  and licence must be confirmed (or the models replaced) before the game is sold.
- **Weapon names:** the weapons use real-world designations. Some ("Desert Eagle", "G17") are
  trademarks of their manufacturers. Decide whether to keep them or use original names, as the
  rest of the game does.

## Libraries

- godot-sqlite (MIT) — see `addons/godot-sqlite`.
