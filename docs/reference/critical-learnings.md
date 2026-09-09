---
tags: [reference]
---
# Critical learnings and old bug fixes

The early lessons that shaped the rules in `CLAUDE.md`. Read this page when a symptom looks like one of these three. Commands: [[Commands]].

## The "Ghost Player" ID collision bug
**The bug:** the Godot client caches the player's ID in `localStorage` so it can rejoin after a browser crash. If the server restarted, it could assign that slot (say Player 1) to a bot. When the user refreshed, the client saw `localStorage == 1`, saw Player 1 in the lobby, and falsely assumed *it* was Player 1, hiding the "Join Match" button for good.
**The fix:** a strict `Global.is_spectator` boolean. The client ignores its `localStorage` ID and acts as a spectator until the server answers a `request_join` packet with `assign_id` (rule 4 in `CLAUDE.md`). Today a client token gates the slot reclaim on the server side as well.

## The scene transition void
**The bug:** bots forced the match to start on the server, but the server never told the spectator clients. The bots fought in the void while the user was stuck on the character select screen.
**The fix:** the server broadcasts an explicit `{"type": "scene_transition"}` packet the moment the lobby locks in. The client forces a hard transition to `res://scenes/arena.tscn`, pulling players and spectators alike out of the lobby.

## The GDScript silent fail
**The pitfall:** a syntax error in a GDScript file does not stop `godot --headless --export-release`; it ships the broken script.
**The trap:** `godot --headless --check-only scripts/x.gd` does NOT work here. Without `--script` it launches the whole game (a stale process was found hung for over an hour). With `--script` it runs before autoloads are registered, so every script that mentions `Global` fails with `Identifier not found: Global` even when it is correct.
**The fix:** `bump_build.sh` runs `tools/check_scripts.gd`, a SceneTree script that loads every `.gd` file after autoloads exist and exits non-zero on any parse or compile error. Run it alone with:
```bash
godot --headless --path . --script tools/check_scripts.gd -- --no-net
```

## Mobile caching
Mobile browsers (iOS Safari most of all) cache hard. If a phone does not see an update, the `.pck` version must change (`index_v<version>.pck`); `bump_build.sh` does that on every bump (rule 2 in `CLAUDE.md`). Phones need `https://192.168.4.21:8443` (a secure context for `SharedArrayBuffer`); `http://192.168.4.21:8000` is PC only.

## A collision shape change costs one floor frame (v0.1.4)
**The bug:** the v0.1.3 duck swapped the fighter's `CollisionShape2D` shape while `is_on_floor()` and down were held. At exact rest on a floor, the frame a shape changes `move_and_slide()` reports no floor, whatever the change (a new resource, the same one resized, a polygon with the same origin, with or without `apply_floor_snap()`). So the duck went off the next frame, on the one after, for ever; the look-down timer never reached 1.5 s.
**The fix:** `DUCK_GRACE_S` 0.1 in `player.gd`: a ducked fighter keeps the duck that long without a floor. Any state tied to `is_on_floor()` across a shape change needs the same grace. `tools/duck_probe.gd` shows it in 10 s.

Related: [[handoff_to_claude]] and [[anti_gravity_session_log]] in `archive/passdown/` (the original write-ups).
