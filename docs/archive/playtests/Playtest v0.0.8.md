---
tags: [playtest]
build: v0.0.8
---
# Playtest v0.0.8 — browser & mobile (Phase 3a)

**Result: pass.** PC Chromium + Android phone, `https://192.168.4.21:8443/play`.

- Movement stays responsive at 20 Hz; no visible difference from 30 Hz.
- Idle suppression behaves as designed: a standing fighter sends only the 0.5 s keepalive.
- Round lifecycle (deaths, respawns, round end, next round, 5-crown match end) runs cleanly.
- v0.0.6/v0.0.7 fixes hold: touch controls, no joystick-fired arrows, ammo kept across a reload, no forfeit on a reload.

## Open edge case (backlog)
| # | Observation | Cause | Status |
|---|---|---|---|
| 11 | Reloading mid-match as a **Ranger** with an empty quiver: the stuck arrows on the ground are gone on the reloaded client (projectiles are not part of any snapshot), so the player has 0 ammo and nothing to pick up until the next round | Projectile world state is client-local; the combat-state restore correctly keeps the depleted count, but the pickups that would refill it do not survive a reload | Backlog. Options: (a) simple fallback: on a mid-match rejoin restore at least 1 arrow for the Ranger; (b) proper fix with the class-kit revisit: include stuck arrows in the join snapshot (server tracks `spawn_projectile` + stick events) or make arrows regenerate slowly like mage charges |

Related: [[v0.0.8 - Send Queues & 20 Hz Tick]] · [[PASSDOWN]]
