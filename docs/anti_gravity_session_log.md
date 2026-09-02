# Anti-Gravity Debugging Session Log

## The Initial Problem
The user was stuck on the character select screen. The "Join Match" button was missing, and the lobby falsely showed them as "Player 1 (You) Choosing...". Because they couldn't click Join, they were trapped as a spectator, and the server ignored their lock-in requests.

## The Investigation & Fixes
1. **The ID Collision Bug:** We discovered the client was reading `localStorage` (e.g., `my_player_id = 1`) and assuming it was already in the game if Player 1 was active on the server. We patched `global.gd` to introduce a strict `Global.is_spectator = true` flag. The client now ignores `localStorage` for lobby presence until the server explicitly responds with an `assign_id` packet.
2. **The Godot Caching Nightmare:** After patching the GDScript, the user's browser fiercely cached the old `.pck` via IndexedDB. We learned that to successfully push a code update to the browser, we MUST rename `index.pck` (e.g., to `index_v8.pck`) and update `mainPack` in `index.html`.
3. **The Silent Compiler Failure:** During the caching battle, Anti-Gravity accidentally introduced a syntax error (`var Global.locked_opponents = {}`) in `character_select.gd`. Godot 4's headless exporter failed silently, sweeping the error under the rug and bundling the old, broken `.gdc` bytecode into the new `.pck`. We learned to ALWAYS run `godot --headless --check-only` before exporting.
4. **The Scene Transition Void:** We spawned headless Python "Chaos Bots" (`/tmp/chaos_bots.py`) to stress test the server. The bots locked in and forced the match to start. The server transitioned to `PLAYING`, but failed to broadcast this state change to the lobby. The bots fought in the void while the user was stuck in the lobby. We patched `serve_game.py` to broadcast `{"type": "scene_transition"}`, and patched `global.gd` to instantly transition to `arena.tscn` when receiving it.

## Conclusion
The project was left in a highly stable state. The network logic correctly distinguishes between active players and spectators, cache-busting workflows have been established, and the chaos bots are currently running in the background to continuously test server stability.
