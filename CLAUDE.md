# Tower Brawl - Claude Code Developer Rules

## Architecture Orientation
- **Engine**: Godot 4 (Exported for Web / HTML5)
- **Networking**: Custom WebSocket implementation (`WebSocketPeer` in Godot, `websocket-server` in Python). We do **NOT** use `ENetMultiplayerPeer` or Godot's High-Level Multiplayer API.
- **Server**: `serve_game.py` is the authoritative python backend tracking lobby state, active players, and match logic.
- **Client Root**: `scripts/global.gd` handles all network packet parsing and delegates state to the UI.

## Critical Rules for Claude
1. **DO NOT EDIT `.tscn` OR BINARY FILES.** You are operating in a text-based environment. Editing Godot scene files via CLI will corrupt them. Only edit `.gd` (GDScript) or `.py` files.
2. **THE BROWSER CACHING BUG.** Godot's web exports aggressively cache `.pck` files in IndexedDB keyed by file name. If you modify GDScript, you MUST run `./bump_build.sh`. It compile-checks every script (with autoloads live, because `godot --check-only` cannot see `Global`), bumps `GAME_VERSION` in `scripts/global.gd` (v0.0.x format, single source of truth, mirrored into `serve_game.py`), exports, copies the pck to `index_<version>.pck`, and patches `mainPack` in the HTML. If you skip this, the user's browser will load the old code and your fixes will seem broken! The server rejects joins from a mismatched version, and the client prints a VERSION MISMATCH line to the browser console.
3. **DO NOT RELY ON `_process` FOR NETWORK STATE.** The UI is entirely event-driven using signals from `global.gd`. Do not add polling loops to UI scripts.
4. **SPECTATOR VS PLAYER.** The network heavily relies on the `Global.is_spectator` boolean. A client connects as a spectator and is only given a slot ID if they explicitly send a `request_join` packet and the server replies with `assign_id`.
5. **PATCH NOTES ON EVERY BUMP.** Each version has its own page in `docs/Patch Notes/` (named `vX.Y.Z - Short Title.md`), indexed newest-first in `docs/Changelog.md`. Run `./bump_build.sh --title "Short Title"`: it generates the page from `docs/patch_note_template.md` and inserts the Changelog wikilink; then fill in the page (summary, changes, metrics, harness result). Harness reports per build live in `docs/harness_report_<version>*.json`.
6. **NEW SESSION? READ `docs/PASSDOWN.md` FIRST.** It carries the current status, the open backlog, the next milestone and the roadmap; `docs/Changelog.md` and `docs/Patch Notes/` carry the history.
7. **SPEAK PLAINLY, KEEP THE SPECIFICS.** Explain code, causes, and architecture in direct, simple words—like explaining across a desk. No corporate filler, academic throat-clearing, or conversational padding.
   Crucial: "Plain" never means vague or dumbed down. Always preserve exact identifiers, file paths, function/variable names, packet keys, numbers, and data schemas. State the cause, state the fix, name the file, give the numbers.
8. **WRAP UP AND ASK FOR `/clear` AT EVERY MILESTONE.** Do this when a build is exported, checked, committed and tagged (tree clean), when a roadmap phase or a test milestone ends (for example the step 5 playtest), or when the chat has gone past about 15–20 turns or is full of command-line debugging output. The reply must end with: (a) a check that `docs/PASSDOWN.md` and `docs/Changelog.md` match `git status` and the tag; (b) a short plain-words summary of what was delivered (rule 7); (c) a complete, copy-pasteable Kick-off Prompt for a fresh session right after `/clear`. Then recommend `/clear`.
8b. **MID-TASK? RECOMMEND `/compact`, NOT `/clear`.** Do not let a session go stale from a full context in the middle of a job. If the task is UNFINISHED (the code does not pass the tests yet, or no commit is ready) but the chat has gone past about 20 turns or holds several big command outputs or test dumps: (a) do NOT suggest `/clear` (the tree is dirty or the work is half done); (b) recommend `/compact` to squeeze the old terminal history and keep the focus; (c) first state, in one or two lines, the current guess about the bug and the very next action, so the summary keeps the live thread.

## User Environment & File Paths
- **Screenshots live in `/home/nemr/Pictures`.** When the user mentions a screenshot, look in that folder for the newest image files (`ls -t /home/nemr/Pictures | head`) and open them with the Read tool.
