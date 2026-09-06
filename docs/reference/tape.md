---
tags: [reference]
---
# The tape: history ring and kill stamps

Built in v0.0.25 (Phase 3c). Read this page when working on `scripts/history_ring.gd`, the `history_status` card or the `tape` scenario. Playback: [[replay]]. Commands: [[Commands]].

Every screen keeps a tape of the last six seconds of the fight, as that screen drew it (`scripts/history_ring.gd`, driven by `arena.gd`). One frame per physics tick (60 a second), 360 slots made once and reused: 5 s before a kill (`BEFORE_S`) plus a 1 s tail after it (`TAIL_S`). `arena.gd` records in `_physics_process` at `process_physics_priority = 10` (after the fighters moved; sim recording, not network polling).

**A frame:** `seq, msec, round, rot, flips, present, fighters {pid: [x, y, aim_x, aim_y, flags]}, n_proj + projectiles [[weapon_id, x, y, rot, stuck, shooter]], powerup [x, y, present]`; flags = the `sync_pos` bits plus `FLAG_BUBBLE` 64 and `FLAG_DEAD` 128 (tape only).

**Stamps and the freeze.** The server's `player_died` carries `weapon`; `net_player_died(killer, victim, stock, weapon)` → `_on_net_player_died` stamps the newest frame (`tape.stamp`: `{seq, round, killer, victim, weapon, closing, fighters}`). On `round_end` (`_on_round_end_sync` → `tape.close_round()`) the newest stamp becomes the closing kill, the tape records 60 more frames and freezes; `_start_round` calls `tape.clear(round)`. Ring API: `next_frame` / `projectile_slot` / `commit` to record, `stamp`, `close_round`, `clear`, `status_card`, `status_line`.

**How to see it:**
```bash
grep "📼 \[Tape\]" .harness_logs/godot1.log | tail -3     # one line per stamp and per freeze on a headless client
#   📼 [Tape] round=1 frozen=1 closing=1 killer=3 victim=4 weapon=Firebolt seq=695 before=300 after=60 span_ms=5989 fps=59.9 stamps=9 frames=360
grep "\[TAPE\]" server.log | tail                          # [TAPE] P3's screen froze the round 1 tape: P3 killed P4 with 'Firebolt', 300 frames before, 60 after
python3 -c "import json; [print(s['id'], s['tape']) for s in json.load(open('status.json'))['seats']]"   # the history_status card per seat
./venv/bin/python tools/chaos_bots.py --scenario tape      # the Phase 3c scenario (about 24 s)
```
The browser console prints the same `📼 [Tape]` line. The card (`history_status`, client to server, never relayed, kept as `seats[].tape` in `status.json` by `player_tapes`): `frames, span_ms, fps, recording, frozen, round, stamps, closing_seq, last {seq, round, killer, victim, weapon, closing, before, after, fighters}, replay`. On the deck: the `Tape` column in SEATS, the inspect line of a round-end column, and the `[TAPE]` events on key `0` ([[deck]]).

**Good numbers:** `before=300 after=60 fps=59.9`. The harness fails a tape under 280 frames before the closing kill, under 30 after, or outside 50 to 70 fps (`tape` scenario: two standing Godot clients, two bots with `shoot = False`, scripted deaths, a known Firebolt closing kill, checks `tape.missing / wrong-kill / short / no-tail / fps / stamp-count / no-card`; `tape_gate` on `fleet` and `lag`; `GodotClient.tapes()` / `.slot()`).

Related: [[replay]], [[deck]], [[v0.0.25 - History Ring and Kill Stamps]].
