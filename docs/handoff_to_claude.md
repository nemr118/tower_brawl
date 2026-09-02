# Tower Brawl - Context Baseline for Claude

Hello Claude! This project is being transitioned to you in a **completely stable, working state**. The core networking foundation is complete and the severe desync bugs have been fixed. 

Please read this document carefully to orient yourself with the architecture before making any changes.

## 1. Current Architecture
- **Engine**: Godot 4 (Exported for Web / HTML5). 
- **Networking**: Custom WebSocket implementation (`WebSocketPeer` in Godot, `websockets` in Python). We do **NOT** use `ENetMultiplayerPeer` or Godot's High-Level Multiplayer API.
- **Server**: `serve_game.py` is the authoritative Python backend tracking lobby state, active players, lock-ins, and match logic.
- **Client Root**: `scripts/global.gd` handles all WebSocket packet parsing, input mapping, and delegates state to the UI components.

## 2. The Latest Fixes (What we just accomplished)
- **ID Collision Bug**: Fixed an issue where the client falsely assumed it was in the game based on stale `localStorage` IDs. We introduced a strict `Global.is_spectator` flag that forces the client to remain a spectator until the server explicitly sends an `assign_id` packet.
- **Scene Transition Logic**: The server now explicitly broadcasts `{"type": "scene_transition"}` the moment a match begins. `global.gd` listens for this packet and forces a hard transition to `res://scenes/arena.tscn`, instantly pulling spectators and players out of the lobby and into the game.
- **Chaos Bots**: We wrote a malicious `chaos_bots.py` script that connects headless WebSocket clients to the server to spam random lock-ins, spoof packets, and stress test the server.

## 3. Critical Rules for Claude
1. **DO NOT EDIT `.tscn` OR BINARY FILES.** You are operating in a text-based environment. Editing Godot scene files via CLI will corrupt them. Only edit `.gd` (GDScript) or `.py` files.
2. **THE BROWSER CACHING BUG.** Godot's web exports aggressively cache `.pck` files in IndexedDB. If you modify GDScript, you MUST export the web build, and then manually rename `index.pck` to `index_v9.pck` (incrementing the version) and update the `mainPack` string in `index.html`. If you don't do this, the user's browser will load the old code and your fixes will seem broken!
3. **DO NOT RELY ON `_process` FOR NETWORK STATE.** The UI is entirely event-driven using signals from `global.gd`. Do not add polling loops to UI scripts.

## 4. Next Steps
Please acknowledge that you have read this baseline, and confirm your understanding of the caching bug and the WebSocket architecture. Once you do, ask the user what feature they want to build next!
