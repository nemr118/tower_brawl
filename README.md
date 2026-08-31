# 🏰 TowerBrawl: Arena of Champions 🏰

A fast-paced local multiplayer 2D arena brawler built in **Godot 4.7**, fusing the tight platforming and projectile mechanics of **TowerFall Ascension** with the distinct hero archetypes and signature abilities of **Brawlhalla**.

---

## ✨ Core Gameplay Features

* **4 Distinct Champion Classes:**
  * 🏹 **Ranger (Kira):** Precision bow shots (3 arrows max). Pluck spent arrows out of walls to reload! Catch incoming arrows mid-air by dashing. Special: *Backflip Retreat Shot*.
  * ⚔️ **Knight (Valen):** Devastating broadsword slashes and lunging momentum. Special: *Shield Guard & Parry* (deflects incoming arrows and firebolts back at the shooter!).
  * 🔮 **Mage (Ignis):** Explosive pyromantic Firebolts (3 recharge charges). Special: *Arcane Void Blink* (teleports 90px in direction).
  * 🗡️ **Rogue (Nyx):** Rapid throwing Kunai blades (4 charges). Special: *Shadow Dash Ambush* (instant hyper-dash that slashes through foes).
* **TowerFall-Style Screen Wrap:** Walk off the left edge to wrap to the right; drop through the bottom pit to fall from the ceiling.
* **Mario-Style Head Stomp:** Land directly on an opponent's head to score a bounce knockout!
* **Arrow Catching & Pickups:** Spent arrows stick into walls and platforms, becoming physical pickups. Dashing directly into an in-flight projectile catches it out of the air.
* **3-Stock Elimination Rounds:** Fast 30–60 second rounds with instant respawns and spawn-invulnerability auras. First player to 5 match crowns wins!

---

## 🎮 Controls

### ⌨️ Keyboard
* **Player 1:**
  * **Move:** `W` `A` `S` `D`
  * **Jump:** `Space` or `W`
  * **Attack:** `J` (Shoot Arrow / Sword Slash / Firebolt / Kunai)
  * **Special:** `K` (Backflip / Shield Parry / Blink / Shadow Slash)
  * **Dash / Catch:** `L` or `Shift`
* **Player 2:**
  * **Move:** `Arrow Keys`
  * **Jump:** `Up Arrow` or `Numpad 0`
  * **Attack:** `/` (Slash) or `Numpad 1`
  * **Special:** `.` (Period) or `Numpad 2`
  * **Dash / Catch:** `,` (Comma) or `Numpad 3`

### 🎮 Gamepads (Xbox / PlayStation / Switch Pro)
* **P1, P2, P3, P4:**
  * **Move:** Left Analog Stick or D-Pad
  * **Jump:** `A` / `Cross`
  * **Attack:** `X` / `Square`
  * **Special:** `Y` / `Triangle`
  * **Dash:** `B` / `Circle` or Triggers (`LT` / `RT`)

### ⚡ Shortcuts
* `[F1]` Cycle Player 1 Class (Ranger ➔ Knight ➔ Mage ➔ Rogue)
* `[F2]` Cycle Player 2 Class
* `[R]` Reset Match & Scores

---

## 🚀 How to Play

Open a terminal and run:

```bash
godot /home/nemr/Work/tower_brawl/project.godot
```
Or open the Godot 4 Editor and import `/home/nemr/Work/tower_brawl/project.godot`.
