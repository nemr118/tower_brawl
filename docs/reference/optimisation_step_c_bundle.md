---
tags: [reference, optimisation, netcode]
---
# Optimisation Step C, build 3 — the `sync_bundle` (v0.0.36)

The design behind [[v0.0.36 - Relay Packet Coalescing]]: how the relay turns 40 movement packets a second into 20, what the bytes look like, and what the harness checks. The measured numbers live on the patch page. Profile 3 of [[optimisation_step_b_profiles]] is the reason: the packet count cost more than the bytes.

## The problem in one line
Each of 3 puppets sent 12 to 13 `sync_pos` a second and the relay forwarded every one on its own, so every client took about 40 small packets a second, each wrapped in 40 to 50 B of WebSocket and TCP/IP headers around 11 B of payload.

## The packet
Server to client only. Type byte `3`, then the entry count `n`, then `n` entries of 10 B. An entry is a `sync_pos` from byte 1 on:

```
sync_bundle (2 + 10 n B)
[0] 3   [1] n   then for each entry:
[0] sender u8  [1..2] tick u16  [3..4] x*10 s16  [5..6] y*10 s16  [7..8] aim 0.1° u16  [9] flags u8
```

`n` is 1 to 25 (`BIN_BUNDLE_MAX`), so a frame is at most 252 B. Client to server is unchanged: type 1, 11 B, from `player.gd` at 20 Hz with idle suppression. `spawn_projectile` (type 2) is still relayed the moment it arrives; it is under 1 packet a second and an arrow should not wait. A client that sends a type 3 frame is dropped like any other unknown binary type (the `fuzz` scenario proves it).

## The relay (`serve_game.py`)
- `RELAY_BUNDLE_MS = 50`. The reader threads no longer call `broadcast` for a type 1 packet; they stamp the sender byte and hand `payload[1:]` to one `MovementBatcher` (thread name `batcher`).
- The batcher keeps a list of `(sender, entry)` in arrival order. Nothing is dropped and nothing is replaced by a newer sample: with jitter two ticks of one sender can land in one window, and a receiver reads a missing tick as "stood still for that long".
- Every 50 ms on the server's monotonic clock (aligned to the window boundaries, so it does not drift) it flushes: one frame per kind of recipient. A player in slot `k` gets the entries whose sender is not `k`, and no socket ever gets an entry it sent itself, the same as the old `exclude=sock`; spectators get all of the others'. The second rule matters for a fighter that presses leave: it is a spectator by the time of the flush, but the sample it sent as a fighter is still not for it (the first v0.0.36 suite run failed `simultaneous_leave` on exactly this, finding `oracle.bundle-own-echo`). Frames are built once per distinct set of left-out entries, at most 5 per flush. A list of 25 pending entries flushes early.
- The frames go through the same `ClientConn.enqueue(frame, movement=True)` as before, so backpressure still drops movement first and the `slow_reader` gate still holds.
- Why 50 ms: three unsynchronised 20 Hz senders put about one sample each into every 50 ms window, so the count falls to about 20 bundles a second. A 25 ms window would still be non-empty most of the time (about 35 a second) for little gain.
- `RELAY_BUNDLE_MS = 0` turns it off: every `sync_pos` is relayed at once as type 1, as before, and the client needs no rebuild because it decodes both.
- The `[STATS 10s]` line ends with `bundles=20.0/s x2.9`: bundles a second and mean entries per bundle.

## The client (`scripts/global.gd`)
`_handle_net_binary` checks `size == 2 + 10 n` and loops over the entries. The dictionary build moved into `_emit_sync_entry(pkt, base)` with `base = 1` for a plain `sync_pos` and `base = 2 + 10 i` for entry `i`. Own entries are skipped by sender (the server leaves them out anyway). `player.gd` did not change: the `net_player_state_received` signal fires once per entry, per sender in ascending tick, and all entries of one bundle share one `at_msec`. NetStats counts the frame under `sync_bundle` (2 B) and every entry under `sync_pos` (10 B), so the `in:` list still shows the puppet sample rate and the byte totals still add up.

## What it costs
Up to 50 ms of extra delay per sample, 25 ms on average, or a fixed 35 ms when the senders' 50 ms ticks lock phase with the server's windows (the `bundle` scenario sees 35 to 38 ms on loopback). Puppets render 2 ticks (100 ms) behind the newest sample, so the interpolation absorbs it. The fleet's jitter gate is the measurement; section 5 of [[Playtest — Master Validation Suite]] is the human check on a phone over Wi-Fi.

## The harness (`tools/chaos_bots.py`)
- `decode_bundle` flattens a frame into `sync_pos` dicts; `_on_packet` feeds each one through the same schema, duplicate, oracle and reaction path as before, so `count("sync_pos")`, `wait_for`, `max_sync_gap`, `_reload_in_gap_spread` and the tick-order oracle work unchanged.
- New oracle findings: `oracle.bundle-size` (a frame that is not `2 + 10 n` bytes, or `n` outside 1..25) and `oracle.bundle-own-echo` (a fighter finds its own slot in a bundle).
- `fuzz`: a joined client sends a type 3 frame; the server must stay up, keep relaying, and the other players must not see its entry.
- `bundle`, the 24th scenario: 3 bots move at 20 Hz for 10 s while a fourth socket only watches. Per client: 16 to 22 bundles a second, at least 1.8 entries per fighter bundle (2.8 for the watcher), no `sync_pos` outside a bundle, relay delay p95 under 70 ms (each bot records when a tick left, the receiver looks it up).
- `fleet` notes now print `in N pkt/s (B sync_bundle, S sync_pos)` per client; the puppet gate (jitter, snaps, dips) is unchanged.
- The METRICS line counts a bundle as one inbound packet, not its entries.
