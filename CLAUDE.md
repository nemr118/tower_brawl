# Tower Brawl - Claude Code Developer Rules

## Architecture Orientation
- **Engine**: Godot 4 (Exported for Web / HTML5)
- **Networking**: Custom WebSocket implementation (`WebSocketPeer` in Godot, `websocket-server` in Python). We do **NOT** use `ENetMultiplayerPeer` or Godot's High-Level Multiplayer API.
- **Server**: `serve_game.py` is the authoritative python backend tracking lobby state, active players, and match logic.
- **Client Root**: `scripts/global.gd` handles all network packet parsing and delegates state to the UI.

## Critical Rules for Claude
1. **DO NOT EDIT `.tscn` OR BINARY FILES.** You are operating in a text-based environment. Editing Godot scene files via CLI will corrupt them. Only edit `.gd` (GDScript) or `.py` files.
2. **THE BROWSER CACHING BUG.** Godot's web exports aggressively cache `.pck` files in IndexedDB. If you modify GDScript, you MUST export the web build, and then manually rename `index.pck` to `index_v9.pck` (incrementing the version) and update the `mainPack` string in `index.html`. If you don't do this, the user's browser will load the old code and your fixes will seem broken!
3. **DO NOT RELY ON `_process` FOR NETWORK STATE.** The UI is entirely event-driven using signals from `global.gd`. Do not add polling loops to UI scripts.
4. **SPECTATOR VS PLAYER.** The network heavily relies on the `Global.is_spectator` boolean. A client connects as a spectator and is only given a slot ID if they explicitly send a `request_join` packet and the server replies with `assign_id`.
