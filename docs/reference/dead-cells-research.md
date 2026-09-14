---
tags: [reference, design, research, art]
status: research 2026-09-10 (the art direction)
---
# Dead Cells: how its art works (research for the new look)

On 2026-09-10 the user chose Dead Cells-style art for Tower Brawl, with fighters about 90 px tall: "still pixelly, but not quite as much as TowerFall". This page is how Dead Cells gets its look and feel, and what that means for us. The gameplay stays TowerFall's ([[towerfall-research]]). The plan: [[v0.2-transformation-plan]].

Public articles only (Dead Cells is not installed on this PC). No Dead Cells art or code comes into this repo: we copy the method, not the pictures.

## 1. The characters: 3D models turned into pixel art
Motion Twin's artist Thomas Vasseur made all the graphics alone in the first year, so he needed a fast way to make a lot of animation. His pipeline:
1. **A simple 2D pixel model sheet first**, as the design.
2. **A very low-detail 3D model in 3ds Max** with a basic skeleton. Low detail is fine: a Dead Cells character is only about **50 px tall** in the game.
3. **Animation pose to pose, like 2D.** Key poses first, with the fewest frames that read and time well. Only then add frames, and only just before or after a key, "never in-between". Impact comes from effects, not smooth motion. Animations run at 30 frames a second.
4. **A homebrew renderer** draws each frame at the final small size with **no anti-aliasing**, so the edges come out as hard pixels.
5. **Every frame is saved as a PNG plus a normal map.** In the game a simple **toon shader** lights the sprite through its normal map, so torches and spells light the fighter live.
6. **Parts are reused.** Armour or a weapon is attached to the skeleton, with no new animation; old parts become new monsters. In his words the most useful trick of the whole workflow, saving hundreds of hours.
7. **Retakes take minutes.** Slowing an attack for balance means moving keyframes, not redrawing.

**The costs they accepted:** some pixels flicker from frame to frame (never solved: cleaning by hand would kill the speed), and less fine detail than hand-drawn pixel art. They chose animation over detail.

## 2. Colour and the world
- **Saturated colour** everywhere: "saturated backgrounds and characters really shine when it comes to keeping the player awake and alert".
- **Inside places use opposite colours** (complementary) and feel closed in; **outside places use neighbouring colours** (analogous) and feel deep.
- **Backgrounds are painted in grey, then coloured with a gradient map.** Turning a level from orange to blue is one gradient change, no repainting.
- **The world's normal maps are drawn by hand**, for control over how the lights hit them.
- **Readability in three levels:**
  1. what you stand on and bump into: the strongest contrast against the background;
  2. things you can use (platforms, ladders): medium contrast;
  3. **threats: the most saturated and brightest** things on screen.
- The background melts together without hard breaks; enemies and projectiles stand out.
- Depth: parallax layers, particles that suggest air, clouds in front, light that suggests the time of day.

## 3. The feel
- Dead Cells' lead designer Sébastien Bénard (GDC 2019, "Dead Cells: What the F*n!?") says the game "cheats" for the player in 30 to 40 small ways, so a hard game feels fair. Named examples: a jump pressed just after running off a ledge still works, and the game helps you up a ledge you almost reached. TowerFall does the same (coyote time, a jump buffer, ledge grab, aim help: [[towerfall-research]]).
- His "game feel" demo switches the small extras off and on: without them the same game feels dead.

## 4. What this means for Tower Brawl
**Our fighters are 90 px, nearly twice Dead Cells' 50.** More detail can show. But the 3D prototype's lesson holds: at 90 px **the outline and the colour blocks are what you see**, not the triangle count or the texture (`~/Work/tower_brawl_3d_proto/KICKOFF.md`, `renders/shrink.py`).

**We already have most of the Dead Cells pipeline** in `~/Work/tower_brawl_3d_proto`:

| Dead Cells | Our prototype today |
|---|---|
| low-detail 3D model | low poly (`--tris 1500`), the class recipe |
| a skeleton, parts attached | the shared rig; the approved v5 "parts" plan (body, one mirrored arm, weapon, clothes shell) |
| pose-to-pose clips | Mixamo clips trimmed by `retarget_mixamo.py` (`PICK` table) |
| toon shader, lit from normals | `toon.gdshader`, `hero.gdshader` (banded light, two rim lights) |
| hard edges | `outline.gdshader`; the 90 px inset (key G) |
| rendered to small PNGs + normal maps | **missing: a bake step** |

**Two ways to put the fighters in the game** (D14 in [[Design Decisions v0.2]]):
- **Bake them, like Dead Cells.** The prototype gets a `--bake` mode: every frame of every clip drawn 90 px tall with no anti-aliasing, saved as a colour sheet, a normal-map sheet and a team-colour mask, plus a frame table. The game draws sprites lit by Godot's 2D lights through the normal maps. For 360° aim the body is baked without its arms, and the arms and weapon (the `aim` bone) are baked as a second layer at 24 angles (15° apart); the arrow still flies at the exact angle. *Good:* the cheapest thing a phone can draw (8 fighters = 16 sprites), the same on every device, and the replay is just sprites. *Bad:* a bake after every change; the aim picture moves in 15° steps; some pixel flicker (Dead Cells has it too).
- **Draw the 3D models live** at 90 px (the prototype's plan at the end of its session 4). *Good:* exact aim, no bake. *Bad:* 8 skinned models with outlines and lighting in WebGL 2 on phones is unmeasured; the arena's 2D lights and the fighters' 3D lights are two systems to keep in step; a model moving by less than a pixel shimmers.
- **Recommended: bake**, with the prototype as our "homebrew renderer", unless the render spike (plan phase G0b) shows live 3D holding 60 fps with 8 fighters on the weakest phone.

**Godot notes for the look** (web builds use the Compatibility renderer, WebGL 2):
- A sprite gets a normal map through a `CanvasTexture`. With normal maps on, lights look weaker: raise the light's `height` and `energy`.
- Godot 4 draws all 2D lights in one pass, but a bigger light costs more (it touches more pixels). Soft shadow filtering (PCF13) is expensive: few lights only.
- Glows that don't need real light (arrow trails, sparks) are cheaper as additive sprites; they ignore normal maps.
- Pixel art scaled by a non-whole number shimmers. The spike checks a 1920 x 1080 canvas on a 1440 px tall screen.

**Rules for our art bible** (plan track A0):
1. Silhouette and three colour blocks per class, judged at 90 px, never bigger.
2. Every fighter has a rim light and a dark outline, so it reads on any background.
3. Arrows and other threats are the brightest, most saturated things on screen; ledges are the highest-contrast shapes; the background is soft.
4. One arena theme = grey background layers + one gradient map; a second theme is a new gradient, not new paintings.
5. Pose-to-pose clips with few frames; impact from effects (a flash, a short hit stop, particles), not from more frames.
6. The player colour lives in a mask, so any class can wear any of 8 player colours.

## Sources
- [Art Design Deep Dive: Using a 3D pipeline for 2D animation in Dead Cells](https://www.gamedeveloper.com/production/art-design-deep-dive-using-a-3d-pipeline-for-2d-animation-in-i-dead-cells-i-) (Thomas Vasseur, Game Developer); [Game Anim summary](https://www.gameanim.com/2018/01/31/dead-cells-3d-pipeline-2d-animation/)
- [Art Design Deep Dive: Giving back colors to cryptic worlds in Dead Cells](https://www.gamedeveloper.com/production/art-design-deep-dive-giving-back-colors-to-cryptic-worlds-in-i-dead-cells-i-) (Game Developer)
- [Dead Cells: Using 3D Pipeline for 2D Animation](https://sudonull.com/post/14066-Dead-Cells-Using-3D-Pipeline-for-2D-Animation) (the ~50 px figure)
- [GDC Vault: "Dead Cells: What the F*n!?"](https://www.gdcvault.com/play/1025788/-Dead-Cells-What-the); [80.lv: hidden tricks that make the game feel fair](https://80.lv/articles/dead-cells-hidden-tricks-that-make-the-game-feel-fair)
- [Deepnight: game feel demo](https://deepnight.net/games/game-feel/)
- Godot: [2D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html), [CanvasTexture](https://docs.godotengine.org/en/stable/classes/class_canvastexture.html), [Godot 4 2D improvements](https://godotengine.org/article/godots-2d-engine-gets-several-improvements-upcoming-40/)
