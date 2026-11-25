# The sounds (tools/make_sfx.py writes this; do not edit)

Mono, 16 bit, 32000 Hz. peak: the biggest sample (0 dB is the most a file holds; none may pass -6). rms: the average level. loud: K weighted with no bass under 150 Hz, the loudest 0.2 s (what the ear hears from a small speaker; the target is beside it). DC: the wave's average (0 is right). first/last: the first and last sample of 32767 (0 = no click).

| sound | for | s | peak dB | rms dB | loud | target | DC | clipped | first/last | bytes |
|---|---|---|---|---|---|---|---|---|---|---|
| shoot | a bow let go (a twang) | 0.30 | -6.6 | -23.3 | -22.0 | -22 | -0.0000 | 0 | 0/0 | 19244 |
| thunk | an arrow hits a wall | 0.20 | -6.7 | -21.0 | -22.0 | -22 | 0.0004 | 0 | 0/0 | 12844 |
| ko | a knockout (a bonk and a squeak) | 0.23 | -6.8 | -18.7 | -18.0 | -18 | 0.0004 | 0 | 0/0 | 14634 |
| stomp | a stomp (a boing) | 0.42 | -6.4 | -21.6 | -19.0 | -19 | -0.0005 | 0 | 0/0 | 26924 |
| dodge | a dodge (a whoosh) | 0.24 | -12.0 | -26.9 | -24.0 | -24 | 0.0000 | 0 | 0/0 | 15404 |
| catch | an arrow caught (a snap) | 0.10 | -6.6 | -18.8 | -20.0 | -20 | 0.0001 | 0 | 0/0 | 6666 |
| grab | your own arrow picked up from the floor | 0.07 | -11.7 | -22.4 | -27.0 | -27 | -0.0000 | 0 | 0/0 | 4524 |
| dry | let go with an empty quiver | 0.09 | -10.0 | -21.6 | -26.0 | -26 | -0.0000 | 0 | 0/0 | 5804 |
| tink | two arrows meet in the air | 0.13 | -14.1 | -28.3 | -27.0 | -27 | -0.0000 | 0 | 0/0 | 8364 |
| powerup | a power-up taken (a sparkle) | 0.51 | -10.7 | -24.5 | -20.0 | -20 | -0.0000 | 0 | 0/0 | 32952 |
| shield_pop | a shield breaks (a pop) | 0.20 | -6.7 | -18.7 | -19.0 | -19 | 0.0002 | 0 | 0/0 | 12662 |
| pop | a small pop (popcorn, a seed, a ghost) | 0.07 | -6.5 | -17.8 | -23.0 | -23 | -0.0002 | 0 | 0/0 | 4524 |
| boom | a blast (a cartoon boom) | 0.70 | -7.4 | -22.3 | -17.0 | -17 | -0.0000 | 0 | 0/0 | 44844 |
| zap | lightning strikes | 0.45 | -8.9 | -25.4 | -20.0 | -20 | 0.0000 | 0 | 0/0 | 28844 |
| poof | a puff of smoke or poison | 0.26 | -9.7 | -26.2 | -25.0 | -25 | -0.0000 | 0 | 0/0 | 16684 |
| freeze | FREEZE | 0.45 | -13.3 | -26.5 | -21.0 | -21 | 0.0000 | 0 | 0/0 | 28914 |
| count | the countdown's 3, 2, 1 | 0.17 | -8.5 | -18.8 | -20.0 | -20 | 0.0000 | 0 | 0/0 | 10924 |
| fight | FIGHT | 0.45 | -11.6 | -20.6 | -19.0 | -19 | -0.0000 | 0 | 0/0 | 28794 |
| round_win | a round is won (a short sting) | 0.67 | -11.5 | -21.4 | -19.0 | -19 | 0.0000 | 0 | 0/0 | 42822 |
| draw | a draw (the sad trombone) | 1.76 | -12.9 | -20.8 | -20.0 | -20 | 0.0000 | 0 | 0/0 | 112684 |
| fanfare | the match winner (a silly fanfare) | 2.88 | -10.1 | -24.1 | -19.0 | -19 | 0.0000 | 0 | 0/0 | 184364 |
| phew | PHEW (a slide whistle up) | 0.60 | -16.6 | -20.1 | -18.0 | -18 | -0.0000 | 0 | 0/0 | 38444 |
| taunt | a player's taunt (8 pitches) | 0.35 | -9.9 | -21.5 | -20.0 | -20 | -0.0000 | 0 | 0/0 | 22412 |
| gobble | the turkey comes | 0.76 | -8.6 | -22.6 | -20.0 | -20 | 0.0000 | 0 | 0/0 | 48874 |
| gobble_startled | the turkey is caught, THE BIG TURKEY is knocked down | 0.46 | -9.2 | -21.6 | -19.0 | -19 | -0.0000 | 0 | 0/0 | 29256 |
| splat | a pie lands | 0.33 | -6.6 | -22.4 | -19.0 | -19 | 0.0002 | 0 | 0/0 | 21478 |
| wahwah | covered in cream, a dish's trick | 0.80 | -12.6 | -22.0 | -20.0 | -20 | -0.0000 | 0 | 0/0 | 51244 |
| lid | a dish's lid (a clang and a ta-da) | 0.76 | -8.6 | -24.0 | -20.0 | -20 | 0.0000 | 0 | 0/0 | 48560 |
| crows | CROWS | 0.71 | -9.0 | -22.4 | -20.0 | -20 | 0.0000 | 0 | 0/0 | 45484 |
| gust | the gust of leaves | 0.98 | -12.1 | -27.9 | -22.0 | -22 | -0.0000 | 0 | 0/0 | 62968 |
| peck | THE BIG TURKEY pecks | 0.09 | -6.7 | -19.2 | -22.0 | -22 | 0.0004 | 0 | 0/0 | 5804 |
| meow | the black cat | 0.50 | -14.2 | -23.2 | -21.0 | -21 | -0.0000 | 0 | 0/0 | 32044 |
| bats | bats | 0.60 | -11.7 | -26.7 | -22.0 | -22 | -0.0000 | 0 | 0/0 | 38444 |
| furnace | a furnace blasts | 0.79 | -7.2 | -21.0 | -19.0 | -19 | 0.0000 | 0 | 0/0 | 50922 |
| steam | a pipe vents steam | 0.60 | -13.0 | -30.3 | -23.0 | -23 | 0.0000 | 0 | 0/0 | 38444 |
| click | a lobby button (a soft click) | 0.04 | -7.5 | -21.4 | -28.0 | -28 | -0.0000 | 0 | 0/0 | 2924 |
| join | a player joins (a blip) | 0.22 | -13.8 | -23.3 | -23.0 | -23 | 0.0000 | 0 | 0/0 | 14124 |

37 sounds, 19.0 s and 1214846 bytes in all (1.16 MB as .wav files; the game's pack holds them smaller, see the patch page).

Problems: none
