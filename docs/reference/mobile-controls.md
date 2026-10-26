---
tags: [reference, research, controls]
status: research 2026-10-26 (two helpers' web research, and our own code)
---
# Phone controls: what other games do, and what to change (research 2026-10-26)

Why: the second gathering night (2026-10-25). The user: "With the wall climbs, ledge grabs, dashes, and movement on a virtual joystick, it was hard to get the character to do exactly what you wanted." [[v0.2.0-p4.15 - Climb Out]] fixed the wall rules. Then: "Anything else we can do to make mobile controls as crisp as possible? Maybe benchmark brawlhalla and other platforms games. Its a pretty tactical platforms, controls make a huge difference."

Sources are numbered at the end. "(Our guess)" marks reasoning with no source.

## Our controls in numbers (p4.15)
On a phone about 65 mm tall in landscape (an iPhone 13 or 14, a Pixel 7). Everything is sized as a share of the screen's height (`touch_sticks.gd`, 240 design px = the stick's reach).

| Action | What the thumb does | How far |
|---|---|---|
| Run | the left thumb moves sideways (within 68° of level) | 1.2 mm |
| Jump | the left thumb moves up, 45° or steeper | 1.2 mm |
| Jump again (p4.15) | pump: down 3.2 mm, up 2.2 mm; or swing over the top | |
| Dodge, the stick's way | push past the stick's rim | 16 mm from where the thumb landed |
| Dodge, the button | the right thumb goes to the DODGE circle | 11 mm across, about 24 mm from where the aim ring rests |
| Drop through a ledge | down to the rim | 16 mm |
| Shoot | the right thumb down, pull 6.6 mm, let go | the fighter stands still while the thumb is down |

The path from the glass to the screen is short. A touch changes the stick at once. The next 60 Hz tick moves your fighter on the phone itself (prediction, no network wait), and the same frame draws it. The phone's own touch and display delay comes on top: about 40 to 90 ms in all, from the published numbers (our guess for this game) [T1][T2].

## What other games do
| Game | Jump | Dodge or dash | Aim and attack | The stick | Settings |
|---|---|---|---|---|---|
| Brawlhalla Mobile | not documented for touch (the PC's keyboard: up = jump) [G6] | a DODGE button; the direction comes from the stick; no direction = dodge in place [G3] | buttons; the direction from the stick [G3] | a D-pad, or a stick [G4] | move and resize every control [G4][G5] |
| Brawl Stars | none | none | a tap = a quick shot at the nearest enemy; a drag aims with a line; letting go fires [G9][G15] | anywhere on the left; can be locked [G9] | size, position, swap sides (2020) [G9][G13] |
| Roblox (the default) | a JUMP button, bottom right, 70 points on phones [G18] | none | per game | appears where the thumb lands; full speed after 20 points of push [G17][G18] | the player picks the stick type [G17] |
| Stumble Guys | a button on the right [G16] | a dive | none | a stick | |
| Dead Cells | a button [G20] | a button; swipe-to-dodge became optional [G19][G20] | buttons; "Auto-Hit" swings by itself [G19][G21] | floating or fixed [G20] | move and resize everything [G19] |
| Terraria | a button; jumping with the stick is a choice: double-tap up (default), swipe up ("Legacy"), off [G23] | a dash button (2026) [G23] | a second stick, auto-target [G22] | a stick | "Simplified" (for younger players) and "Advanced" schemes, a layout editor [G23] |
| Smash Legends | a button [G25] | none (jump is the escape) | buttons [G25] | floating [G25] | |
| Super Mario Run | a tap; next to a wall, a tap = a wall jump [G26] | | | none | |

What players said and what changed:
- **Brawlhalla:** reviewers report missed presses and a "horrendously positioned" default layout. Moving the buttons or a controller fixed it [G1][G2].
- **Dead Cells:** testers did not agree on swipe-to-dodge, so it became optional. "Jump and dodge were the hardest buttons to place" [G19]. A reviewer found swipe-dodge "too unreliable" [G20].
- **Terraria:** "any upward movement = jump" became a "Legacy" choice; double-tap up is the default and it can be turned off [G23].
- **Fighting games:** most Smash players turn "tap jump" (up on the stick = jump) off, because it jumps by accident [G27]; some top players keep it [G28]. Brawlhalla forum posters call turning it off "the consensus" [G7].
- **Children:** in a study of 7 to 10 year olds on touch screens, children missed small targets far more than adults, and a gap between a button and the screen's edge nearly doubled misses. The authors advise bigger touch areas than the drawing, running to the edge [G33].

## The browser side
- Godot's web build reads touch events. A press and a lift reach the game at once; moves wait for the next frame [T3][T4].
- Safari draws at 60 Hz even on 120 Hz iPhones (a default players will not change). Low Power Mode drops a page to 30 fps [T5][T6]. Android Chrome: probably the screen's rate; measure it [T7].
- Godot's "agile event flushing" is for Android apps, not the web [T8].
- iPhones have no vibration in Safari. The `<input switch>` trick needed a real tap and was blocked in iOS 26.5 [T9][T10]. Android Chrome can vibrate (`Input.vibrate_handheld`), after a first tap [T11].
- Godot's DPI reading on the web is not real (devicePixelRatio × 96), so it cannot size controls in millimetres [T12]. Browser CSS pixels are close to the same size on every phone and tablet (our guess: about 0.16 mm).
- Things we already do right: `touch-action: none` on the page, each touch kept by the control it started on, no smoothing delay on your own fighter [T13].

## What to change, ranked
**1. Measure first (small).**
- Pull the ROG's logs: each phone's frame rate in matches (a phone at 40 fps feels mushy whatever the controls), which devices played (any tablets?), and shots let go inside the ring (resting or tapping right thumbs).
- Add touch numbers to the phone report: jumps that went off within 0.1 s of the thumb landing with under 2 mm of movement (likely by accident); the thumb's speed when it crossed the stick's rim (a fast flick was meant, a slow push was not); right-thumb touches that never reached the ring, and how long they held the fighter still; how far the aim moved in the last 50 ms before a let-go; frames that ran 0 or 2 ticks.
- If the user likes: film a DODGE tap with an iPhone's 240 fps slow motion (about 4 ms a video frame): the delay from finger to screen.

**2. Small fixes (no trade-off).**
- The DODGE button can lose a quick tap: a press and a lift between two ticks (in a slow frame) never send a dodge. Hold it for 2 ticks, like the stick's jump and rim dodge already do [T3].
- Let-go wobble: as a thumb lifts, the touch point can slide, and the shot takes the last point. Use the aim from about 50 ms before the lift, unless the thumb was moving fast (a meant flick) [T14].
- The page: add `-webkit-touch-callout: none` (the long-press popup), `-webkit-tap-highlight-color: transparent` and `overscroll-behavior: none` [T15].
- A dodge pressed up to 0.1 s early (during the cooldown or a ledge hang) still goes when it can (our guess; TowerFall has no dodge buffer, Celeste buffers its dash [T16]).
- The jump buffer 5 ticks to 6 (TowerFall's) [T17].

**3. A resting right thumb should not freeze you (the user's call).**
- Today any touch on the right half raises the bow, and a raised bow keeps you still on the ground (TowerFall's rule). A thumb resting on the glass, or a tap, stops your run.
- Change: the bow comes up only once the thumb starts to pull (about 2 mm). After that, TowerFall's rule as now.

**4. A JUMP button and a DODGE button beside it (the big one; the user's call).**
- Every phone game here that jumps uses a jump button, and kids know Roblox's: the stick on the left, JUMP bottom right [G16][G17][G20][G23][G25].
- For us: JUMP in the bottom-right corner (hold = a higher jump; next to a wall = a wall jump, as p4.15 made it; with the stick down = drop through a ledge). DODGE just above or beside it, the way the stick points (Brawlhalla's way) [G3]. The rest of the right half stays pull-to-shoot. The stick only runs (down = fall faster), and its middle follows the thumb past the rim, so turning round is always a short move [G32].
- The cost: one right thumb cannot jump while it draws the bow. You jump, then pull in the air (the air never roots you).
- Keep today's stick as CLASSIC (the stick jumps, the rim dodges). Each player picks BUTTONS or CLASSIC in the lobby, like Terraria's Simplified and Advanced [G23]. Try both on a night.
- Sizes: JUMP and DODGE 12 to 15 mm across (Apple's least is 44 pt, about 7 mm; Roblox's JUMP 70 pt, about 12 mm), touch areas bigger than drawn and running to the screen's edge [G29][G18][G33].

**5. Sizes in millimetres, not a share of the screen (small to medium).** On a tablet today's stick would be about three times a thumb. Size controls in browser CSS pixels instead.

**6. Feedback (small).** A flash on the stick's ring at a jump, a wall jump and a dodge; the dodge's cooldown shown on its button [G29]. Android: a 12 to 15 ms buzz on a dodge and about 30 ms when hit, with an off switch [T11][T18]. iPhones: the flash, and sound later (G9).

**7. Later.**
- A small layout editor: size, move JUMP and DODGE, swap sides for left-handed players (Brawlhalla, Brawl Stars, Dead Cells and Terraria all have one) [G4][G9][G19][G23].
- A tap = a quick shot at the best enemy the arrow can reach (Brawl Stars) [G9]. The server would pick the aim with the bots' aiming code: medium work.
- A practice room: wall jumps, ledge grabs and catches, with prompts.
- Help for a jump that clips a block's corner (Celeste nudges 4 px [T16]; TowerFall only for dodges).
- Tip for the night: an iPhone in Low Power Mode runs the game at 30 fps [T6].

## Measure on a real phone (before changing the feel)
The frame rate in Safari, the Home Screen app and Low Power Mode; how often a frame runs 0 or 2 ticks; finger-to-screen delay (240 fps video); lost taps (touches against presses the game used); two thumbs at once; long-press, double-tap and edge swipes during play; the aim in the last 50 ms before a let-go; whether an Android phone's buzz feels crisp or buzzy [T18].

## Sources
Games:
[G1] https://ee.pocketgamer.com/articles/084083/brawlhalla-review-a-mobile-port-done-right/ ·
[G2] https://www.taptap.io/es/post/1763892 ·
[G3] https://gamingonphone.com/guides/brawlhalla-beginners-guide-tips-and-tricks/ ·
[G4] https://androidayuda.com/juegos/recomendados/brawhalla/ ·
[G5] https://news.ubisoft.com/en-us/article/1kyM6xMlvLXtYa0un5XpKN/brawlhalla-now-available-on-mobile ·
[G6] https://brawlhalla.wiki.gg/wiki/Controls ·
[G7] https://steamcommunity.com/app/291550/discussions/0/1738882740680316650 ·
[G9] https://game8.co/games/Brawl-Stars/archives/316910 ·
[G13] https://androidphoria.com/juegos/brawl-stars-nuevos-controles-personalizables ·
[G15] https://www.pocketgamer.com/brawl-stars/brawl-stars-tips-and-tricks-a-guide-for-the-beginner-brawler/ ·
[G16] https://www.giga.de/tipp/stumble-guys-mit-controller-spielen/ ·
[G17] https://create.roblox.com/docs/en-us/reference/engine/enums/DevTouchMovementMode.md ·
[G18] https://github.com/MaximumADHD/Roblox-Client-Tracker/tree/roblox/scripts/PlayerScripts/StarterPlayerScripts/PlayerModule.module (Roblox's player scripts) ·
[G19] https://www.computerbase.de/2019-05/dead-cells-android-ios/ ·
[G20] https://multiplayer.it/recensioni/dead-cells-la-recensione-su-ios.html ·
[G21] https://www.pocketgamer.com/articles/083177/dead-cells-the-acclaimed-metroidvania-roguelike-is-available-now-for-android/ ·
[G22] https://terraria.wiki.gg/wiki/Game_controls ·
[G23] https://terraria.wiki.gg/wiki/Mobile_version_history ·
[G25] https://www.gamezebo.com/walkthroughs/smash-legends-beginners-guide-hint-tips-and-tricks/ ·
[G26] https://www.mariowiki.com/Super_Mario_Run ·
[G27] https://www.ssbwiki.com/Tap_jump ·
[G28] https://www.eventhubs.com/news/2014/dec/02/zero-and-d1-explain-why-you-should-leave-tap-jump-super-smash-bros-wii-u-ultrachentvs-first-attack-s3-ep-13 ·
[G29] https://developer.apple.com/design/human-interface-guidelines/game-controls ·
[G32] https://patents.google.com/patent/US9937416B2/en (a stick whose middle follows the thumb) ·
[G33] https://lisa-anthony.com/wp-content/uploads/2013/04/anthony-et-al-jpuc2013.pdf (children and touch targets)

The browser:
[T1] https://android.googlesource.com/platform/external/walt/+/refs/heads/android14-dev/docs/DragLatency.md ·
[T2] https://www.inkandswitch.com/slow-software ·
[T3] https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/js/libs/library_godot_input.js ·
[T4] https://developer.chrome.com/blog/aligning-input-events ·
[T5] https://bugs.webkit.org/show_bug.cgi?id=290671 ·
[T6] https://bugs.webkit.org/show_bug.cgi?id=215745 ·
[T7] https://developer.mozilla.org/en-US/docs/Web/API/Window/requestAnimationFrame ·
[T8] https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-input-devices-buffering-agile-event-flushing ·
[T9] https://github.com/tijnjh/ios-haptics/issues/2 ·
[T10] https://github.com/tijnjh/ios-haptics/issues/8 ·
[T11] https://developer.mozilla.org/en-US/docs/Web/API/Navigator/vibrate ·
[T12] https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/js/libs/library_godot_display.js ·
[T13] https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html ·
[T14] our guess from the research; measure it first ·
[T15] https://developer.mozilla.org/en-US/docs/Web/CSS/touch-action and https://bugs.webkit.org/show_bug.cgi?id=296492 ·
[T16] https://github.com/NoelFB/Celeste/blob/master/Source/Player/Player.cs ·
[T17] https://towerfall.wiki.gg/wiki/Advanced_techniques ·
[T18] https://developer.android.com/develop/ui/views/haptics/haptics-principles

## What the night's logs said (2026-10-25, pulled 2026-10-26)
The ROG's `v2_server.jsonl` and journal (`playtest_logs/2026-10-26_rog/`), read with `tools/v2_night_report.py` and a few one-off counts.
- **The frame rate is the biggest controls problem on iPhones.** In matches, a median of: Player 1's iPhone 16 fps on HIGH (picked by hand, so AUTO never stepped down) but 60 fps on LOW; Brooks's iPhone 15 fps; the 2532 x 1170 iPhones 22 and 30 fps even on LOW; Mhamm's iPad 16 fps on NORMAL; one iPhone 60 fps on LOW. The Androids: 36 fps (the user's, HIGH) and 43 fps (Andrew's, HIGH). At 15 to 20 fps a touch takes two or three times as long to show, and a fast move jumps 25 to 100 px between frames.
- **Sessions got slower as they went on:** the user's Android 50 fps in its first third, 33 in its last; Mhamm's iPad 25 to 14 fps in 20 minutes. That fits the leaks p4.15 fixed; the phone report now carries memory (`mem_mb`, `tex_mb`) to confirm it.
- **The warping:** every phone had snapshot gaps over 133 ms in 0.5% to 5% of its 5-second windows (the worst 165 to 734 ms), about one visible warp a minute with p4.14's drawing. p4.16's glide and ease hide those. The ROG's own Wi-Fi power save was already off (NetworkManager `wifi.powersave = 2`); the pings were a median 47 ms, 90% under 73 ms (7 to 17 ms at home): the gathering's Wi-Fi ("Starlink"), two hops.
- **Kids let go inside the ring a lot:** 20% to 37% of their right-thumb touches ended with no arrow (Andrew 25 of 124, Player 4 20 of 61, Player 5 11 of 30, Player 1 16 of 70); the user 4% (9 of 233).
- **The night:** 31 matches, 257 rounds (THE HAUNTED HOUSE 129, THE BOILER ROOM 102, THE KEEP 13, THE BRIDGES 13); the server's worst tick 10.6 ms; 0.45% of the inputs late. 56 candies opened: GHOSTFACE 18, PUMPKIN HEAD 8, TINY 7, BACKWARDS 2.
- **Page errors:** "Invalid polygon data, triangulation failed" (an iPhone, 4 times: a drawn shape that crosses itself), "Could not create render target" (an Android), "Too many packets in queue" (an iPhone whose page sat in the background), "Script error." (an iPhone).
- **What this changes in the ranking above:** performance first (a slow phone makes every control feel mushy), then the small fixes and the bow only on a pull; the BUTTONS layout is worth judging again once the phones run near 60 fps.
