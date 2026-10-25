# p4.12 Halloween, headless: each new rule on its own little stage, then GHOSTFACE bots
# in whole rounds. The black cat (how often it comes, it stays on its floor, petting it
# gives a SHIELD, it runs off), TRICK OR TREAT (the shares of GHOSTFACE, treats and
# tricks; a treat is a real power-up; the PUMPKIN cannot shoot and hops; BACKWARDS swaps
# left and right; the tricks end), PUMPKIN BOMBS (a blast, then 5 seeds that pop; on
# THE HAUNTED HOUSE bombs come as pumpkins), the bats (the sweep drops a flying arrow and
# hides whoever is inside; BAT SWARM knocks away an arrow coming at its fighter) and
# GHOSTFACE (an arrow knocks it down and drops; a second hit at once does nothing; it
# gets up after 2 s; a hit while down ends it; a stomp knocks it down and the next stomp
# ends it; the knife kills in front, not behind; a shield or a dodge is safe; the knife
# waits its cooldown; holding shoot never stops it; the whole fighter reads back the
# same). Exit 1 on a failed check.
#   godot --headless --path bench --script res://tools/halloween_probe.gd -- --rounds=40
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const P = preload("res://sim/proto.gd")
const HAUNTED := 3

var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("🧪 [HalloweenProbe] FAIL: " + what)

func _say(s: String) -> void:
	print("🧪 [HalloweenProbe] " + s)

# A stage: arena n, these seats (people unless bots), the round started and running,
# everyone landed.
func _stage(n: int, seats: int, seed: int, powerups := false, bots := false):
	var s = SimScript.new(0, 24, seed)
	s.respawn = false
	s.powerups = powerups
	s.set_arena(n)
	var list := []
	for i in seats:
		list.append({"id": i, "bot": bots})
	s.start_round(list)
	s.frozen = false
	for k in 40:
		s.step()
	s.take_events()
	return s

# A floor with open room: the feet's spot (x the middle, y the floor's top) with need
# cells of floor and three empty rows above on each side.
func _floor(s, need: int) -> Vector2:
	for cy in range(3, 36):
		for cx in range(need + 1, 63 - need):
			var ok := true
			for k in range(-need, need + 1):
				if s.level.cell(cx + k, cy) != 1 or s.level.cell(cx + k, cy - 1) != 0 or s.level.cell(cx + k, cy - 2) != 0 \
						or s.level.cell(cx + k, cy - 3) != 0:
					ok = false
					break
			if ok:
				return Vector2(cx * 30 + 15, cy * 30)
	push_error("no floor with %d cells of room" % need)
	return Vector2(-1, -1)

func _stand(f, at: Vector2, dx: int) -> void:
	f.x = int(at.x) - 18 + dx
	f.y = int(at.y) - 63
	f.vx = 0.0
	f.vy = 0.0

func _count(evs: Array, kind: int, b := -1) -> int:
	var n := 0
	for e in evs:
		if e[0] == kind and (b < 0 or e[4] == b):
			n += 1
	return n

func _arrow(s, x: float, y: float, vx: float, owner: int):
	var a := SimScript.Arrow.new()
	a.id = 9000 + s.arrows.size()
	a.x = x
	a.y = y
	a.vx = vx
	a.owner = owner
	a.t = 20
	a.state = P.S_FLY
	s.arrows.append(a)
	return a

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var t0 := Time.get_ticks_msec()
	_cat()
	_tricks()
	_pumpkins()
	_bats()
	_ghostface()
	_candies()
	_ghostface_bots(int(args.get("rounds", "40")))
	_say("%s (%d fail) in %d ms" % ["PASS" if fails == 0 else "FAIL", fails, Time.get_ticks_msec() - t0])
	quit(0 if fails == 0 else 1)

func _cat() -> void:
	for n in [1, HAUNTED]:
		var s = _stage(n, 2, 21 + n, true)
		var got := 0
		for i in 2000:
			s._reset_powers_round()
			if s.pet_at >= 0:
				got += 1
		var want: float = SimScript.PET_CHANCE_HW if n == HAUNTED else SimScript.PET_CHANCE
		_say("the black cat comes in %.0f%% of rounds on %s" % [got / 20.0, s.level.name])
		_check(absf(got / 2000.0 - want) < 0.04, "the black cat comes in %.0f%% of rounds, not %.0f%%" % [got / 20.0, want * 100.0])
	var sp = _stage(HAUNTED, 2, 22, true)
	sp.pu_wait = 99999          # no lightning orbs here (a strike could end the round, and the cat with it)
	sp.candy_t = 99999
	sp.pet_at = sp.play_t
	sp.step()
	_check(not sp.pet.is_empty() and _count(sp.take_events(), P.E_CAT_COME) == 1, "the black cat shows up")
	if sp.pet.is_empty():
		return
	var off := 0
	var moved := 0.0
	var x0: float = sp.pet["x"]
	for k in 150:
		sp.step()
		moved = maxf(moved, absf(SimScript.wrap_d(x0, sp.pet["x"], 1920)))
		if sp.level.cell_at(sp.pet["x"], sp.pet["y"] + 2.0) == 0:
			off += 1
	_check(off == 0 and moved > 20.0, "the cat walks its floor (%.0f px) and never steps off it (%d ticks off)" % [moved, off])
	var f = sp.fighters[0]
	f.shield = 0
	_stand(f, Vector2(sp.pet["x"], sp.pet["y"]), 0)
	sp.take_events()
	sp.step()
	var evs: Array = sp.take_events()
	_check(f.shield == 1 and _count(evs, P.E_PET) == 1, "petting the cat gives a SHIELD")
	_check(sp.pet.get("gone", 0) > 0, "then it runs off")
	for k in 60:
		sp.step()
	_check(sp.pet.is_empty(), "and it is gone")

func _tricks() -> void:
	var st = _stage(1, 2, 23)
	var n_mask := 0
	var n_treat := 0
	var n_trick := [0, 0, 0, 0]
	var real := 0
	var f = st.fighters[0]
	for i in 3000:
		f.mask = false
		f.trick = 0
		f.trick_t = 0
		st.take_events()
		st._trick_or_treat(f)
		var evs: Array = st.take_events()
		for e in evs:
			if e[0] == P.E_TRICK:
				if e[4] == 4:
					n_mask += 1
				elif e[4] == 0:
					n_treat += 1
				else:
					n_trick[e[4]] += 1
			elif e[0] == P.E_PU_GET and e[4] != P.PU_TRICK and e[4] != P.PU_MASK:
				real += 1
	var tricks: int = n_trick[1] + n_trick[2] + n_trick[3]
	_say("TRICK OR TREAT x3000: GHOSTFACE %d, treats %d, tricks %d (pumpkin %d, backwards %d, tiny %d)" % [n_mask, n_treat, tricks, n_trick[1], n_trick[2], n_trick[3]])
	var m := SimScript.MASK_CHANCE
	_check(absf(n_mask / 3000.0 - m) < 0.03, "GHOSTFACE share %.2f" % (n_mask / 3000.0))
	_check(absf(n_treat / 3000.0 - SimScript.TREAT * (1.0 - m)) < 0.03, "treat share %.2f" % (n_treat / 3000.0))
	_check(real == n_treat, "every treat is a real power-up (%d of %d)" % [real, n_treat])
	_check(n_trick[1] > 0 and n_trick[2] > 0 and n_trick[3] > 0, "all three tricks happen")
	# the PUMPKIN: no shots, it hops by itself, it ends
	var s5 = _stage(1, 2, 24)
	var pk = s5.fighters[0]
	var at := _floor(s5, 3)
	_stand(pk, at, 0)
	pk.arrows = 3
	pk.trick = 1
	pk.trick_t = SimScript.TRICK_TICKS[1]
	var hops := 0
	var n0: int = s5.arrows.size()
	for k in SimScript.TRICK_TICKS[1] + 5:
		s5.apply_input(pk, P.B_SHOOT if k % 20 < 10 else 0, 0)
		s5.step()
		hops += _count(s5.take_events().filter(func(e): return e[3] == pk.id), P.E_JUMP)
	_check(s5.arrows.size() == n0, "a PUMPKIN cannot shoot")
	_check(hops >= 4, "a PUMPKIN hops by itself (%d hops in 3 s)" % hops)
	_check(pk.trick == 0, "the PUMPKIN trick ends after 3 s")
	# BACKWARDS: right walks left
	var s6 = _stage(1, 2, 25)
	var bw = s6.fighters[0]
	_stand(bw, _floor(s6, 3), 0)
	bw.trick = 2
	bw.trick_t = SimScript.TRICK_TICKS[2]
	var bx: int = bw.x
	for k in 12:
		s6.apply_input(bw, P.B_RIGHT, 0)
		s6.step()
	_check(bw.x < bx, "BACKWARDS: holding right walks left (%d px)" % (bw.x - bx))

func _pumpkins() -> void:
	var sh = _stage(HAUNTED, 2, 26)
	var bombs := 0
	var pumpkins := 0
	for i in 3000:
		var k: int = sh._pick_regular()
		if k == P.PU_BOMB:
			bombs += 1
		elif k == P.PU_PUMPKIN:
			pumpkins += 1
	_check(bombs == 0 and pumpkins > 0, "on THE HAUNTED HOUSE the bombs come as PUMPKIN BOMBS (%d bombs, %d pumpkins in 3000)" % [bombs, pumpkins])
	var s = _stage(1, 2, 27)
	var o = s.fighters[0]
	_stand(o, _floor(s, 4), 0)
	s.fighters[1].x = (o.x + 960) % 1920
	s._give(o, P.PU_PUMPKIN)
	_check(o.pw_kind == P.A_PUMPKIN and int(s.keep.get(o.id, 0)) == P.A_PUMPKIN, "PUMPKIN BOMBS: every arrow is a pumpkin, all match")
	o.arrows = 3
	s.take_events()
	s._fire(o, 0.0)
	_check(s.arrows.size() > 0 and s.arrows[-1].kind == P.A_PUMPKIN, "the shot is a pumpkin")
	var big := 0
	var seeds := 0
	var most_seeds := 0
	for k in 300:
		s.step()
		var n := 0
		for a in s.arrows:
			if not a.dead and a.kind == P.A_SEED:
				n += 1
		most_seeds = maxi(most_seeds, n)
		for e in s.take_events():
			if e[0] == P.E_EXPLODE:
				if (e[4] & 2) != 0:
					big += 1
				elif (e[4] & 4) != 0:
					seeds += 1
	_say("a pumpkin: %d blast, %d seeds out, %d seed pops" % [big, most_seeds, seeds])
	_check(big == 1 and most_seeds == SimScript.SEEDS and seeds == SimScript.SEEDS, "a pumpkin bursts, then its %d seeds pop" % SimScript.SEEDS)

func _bats() -> void:
	var s = _stage(HAUNTED, 2, 28)
	_check(s.bats_at == SimScript.BATS_FIRST, "on THE HAUNTED HOUSE the first swarm comes %d s after FIGHT" % (SimScript.BATS_FIRST / 60))
	s.bats_at = s.play_t
	s.step()
	_check(_count(s.take_events(), P.E_BATS) == 1 and not s.bats.is_empty(), "the swarm screeches first")
	for k in SimScript.BATS_WARN + 1:
		s.step()
	_check(int(s.bats.get("phase", -1)) == 1, "then it sweeps in")
	for k in 200:   # well inside the screen (the band is not drawn past an edge)
		if s.bats["x"] > 400.0 and s.bats["x"] < 1520.0:
			break
		s.step()
	# an arrow just ahead of it, and a fighter inside it
	var dir: float = s.bats["dir"]
	var lead: float = s.bats["x"] + dir * SimScript.BATS_W * 0.5
	var ar = _arrow(s, lead + dir * 14.0, s.bats["y"], dir * 2.0, 1)
	var f = s.fighters[0]
	f.x = int(s.bats["x"]) - 18
	f.y = int(s.bats["y"]) - 31
	s.step()
	s.step()
	_check(ar.state != P.S_FLY, "an arrow flying into the swarm drops")
	_check(f.batted > 0 and SimScript.hidden(f), "whoever is inside is hidden")
	var gone := false
	for k in 400:
		s.step()
		if s.bats.is_empty():
			gone = true
			break
	_check(gone and s.bats_at > s.play_t + SimScript.BATS_EVERY[0] - 5, "it leaves, and the next one comes 20 to 30 s later")
	# BAT SWARM: an arrow coming at its fighter is knocked away
	var sw = _stage(1, 2, 29)
	var o = sw.fighters[0]
	var at := _floor(sw, 6)
	_stand(o, at, 0)
	sw._give(o, P.PU_BATS)
	_check(o.bats_t == SimScript.BAT_SWARM_TICKS, "BAT SWARM: 8 s of bats")
	var a2 = _arrow(sw, at.x - 160.0, at.y - 35.0, 12.0, 1)
	for k in 30:
		sw.step()
	_check(o.state != P.F_DEAD and a2.state != P.S_FLY, "BAT SWARM's bats knock away an arrow coming at it")

func _ghostface() -> void:
	# an arrow knocks it down (it lives, the arrow drops); another hit at once does
	# nothing; it gets up after MASK_DOWN; down again, a hit after the grace ends it
	var s = _stage(1, 3, 30)
	var g = s.fighters[0]
	_stand(g, _floor(s, 4), 0)
	g.mask = true
	for k in 3:
		s.step()
	var a1 = _arrow(s, g.x + 18.0, g.y + 20.0, 4.0, 1)
	s._arrow_hit_fighters(a1)
	var evs: Array = s.take_events()
	_check(g.state == P.F_HURT and g.down_t == SimScript.MASK_DOWN and _count(evs, P.E_MASK_DOWN) == 1, "an arrow knocks GHOSTFACE down, it lives")
	_check(a1.state == P.S_FALL, "the arrow drops off it")
	var a2 = _arrow(s, g.x + 18.0, g.y + 20.0, 4.0, 1)
	s._arrow_hit_fighters(a2)
	_check(g.state != P.F_DEAD, "a second hit at once does nothing (the grace)")
	var up := 0
	for k in SimScript.MASK_DOWN + 2:
		s.step()
		up += _count(s.take_events(), P.E_MASK_UP)
	_check(up == 1 and g.state == P.F_NORMAL and g.down_t == 0, "it gets up after %d s" % (SimScript.MASK_DOWN / 60))
	var a3 = _arrow(s, g.x + 18.0, g.y + 20.0, 4.0, 1)
	s._arrow_hit_fighters(a3)
	for k in SimScript.MASK_GRACE + 2:
		s.step()
	_check(g.state == P.F_HURT and g.down_t > 0, "down again")
	var a4 = _arrow(s, g.x + 18.0, g.y + 20.0, 4.0, 1)
	s._arrow_hit_fighters(a4)
	evs = s.take_events()
	_check(g.state == P.F_DEAD and _count(evs, P.E_DEATH, 1) == 1, "an arrow while it is down ends it")
	# a stomp knocks it down, the next stomp ends it
	var s2 = _stage(1, 2, 31)
	var g2 = s2.fighters[0]
	var top = s2.fighters[1]
	var at := _floor(s2, 3)
	_stand(g2, at, 0)
	g2.mask = true
	top.x = g2.x
	top.y = g2.y - 80
	top.vy = 6.0
	var downs := 0
	var stomp_deaths := 0
	for k in 150:
		s2.step()
		var e2: Array = s2.take_events()
		downs += _count(e2, P.E_MASK_DOWN)
		stomp_deaths += _count(e2, P.E_DEATH, 3)
		if g2.state == P.F_DEAD:
			break
	_check(downs == 1 and stomp_deaths == 1 and g2.state == P.F_DEAD, "a stomp knocks it down, the next stomp ends it (%d down, %d stomp deaths)" % [downs, stomp_deaths])
	# the closing walls end it standing
	var s3 = _stage(1, 2, 32)
	s3.fighters[0].mask = true
	s3._kill(s3.fighters[0], 255, 6)
	_check(s3.fighters[0].state == P.F_DEAD, "the closing walls end it standing")
	# the knife: in front, not behind; a shield and a dodge are safe; the cooldown
	var s4 = _stage(1, 5, 33)
	var at4 := _floor(s4, 4)
	var k0 = s4.fighters[0]
	var front = s4.fighters[1]
	var back = s4.fighters[2]
	_stand(k0, at4, 0)
	_stand(front, at4, 52)
	_stand(back, at4, -52)
	s4.fighters[3].x = (k0.x + 700) % 1920
	s4.fighters[4].x = (k0.x + 1200) % 1920
	k0.mask = true
	k0.facing = 1
	s4.apply_input(k0, P.B_SHOOT, 0)
	s4.step()
	_check(not k0.aiming, "holding shoot never stops GHOSTFACE to aim")
	s4.apply_input(k0, 0, 0)
	var evs4 := []
	for k in SimScript.KNIFE_HIT_AT + 3:
		s4.step()
		s4.apply_input(k0, 0, 0)
		evs4.append_array(s4.take_events())
	_check(_count(evs4, P.E_KNIFE) == 1, "letting go of shoot swings the knife")
	_check(front.state == P.F_DEAD and _count(evs4, P.E_DEATH, 11) == 1, "the knife ends whoever is in front")
	_check(back.state != P.F_DEAD, "and not whoever is behind")
	s4.apply_input(k0, P.B_SHOOT, 0)
	s4.step()
	s4.apply_input(k0, 0, 0)
	s4.step()
	_check(_count(s4.take_events(), P.E_KNIFE) == 0 and k0.knife_cd > 0, "the knife waits its cooldown")
	var s5 = _stage(1, 4, 34)
	var at5 := _floor(s5, 4)
	var k5 = s5.fighters[0]
	var sh = s5.fighters[1]
	_stand(k5, at5, 0)
	_stand(sh, at5, 52)
	s5.fighters[2].x = (k5.x + 700) % 1920
	s5.fighters[3].x = (k5.x + 1200) % 1920
	k5.mask = true
	k5.facing = 1
	sh.shield = 1
	s5.apply_input(k5, P.B_SHOOT, 0)
	s5.step()
	s5.apply_input(k5, 0, 0)
	for k in SimScript.KNIFE_HIT_AT + 3:
		s5.step()
		s5.apply_input(k5, 0, 0)
	_check(sh.state != P.F_DEAD and sh.shield == 0, "a SHIELD takes the knife")
	var s6 = _stage(1, 4, 35)
	var at6 := _floor(s6, 4)
	var k6 = s6.fighters[0]
	var dg = s6.fighters[1]
	_stand(k6, at6, 0)
	_stand(dg, at6, 52)
	s6.fighters[2].x = (k6.x + 700) % 1920
	s6.fighters[3].x = (k6.x + 1200) % 1920
	k6.mask = true
	k6.facing = 1
	s6.apply_input(k6, P.B_SHOOT, 0)
	s6.step()
	s6._start_dodge(dg, Vector2(0, -1))
	s6.apply_input(k6, 0, 0)
	for k in SimScript.KNIFE_HIT_AT + 3:
		s6.step()
		s6.apply_input(k6, 0, 0)
	_check(dg.state != P.F_DEAD, "a dodge is safe from the knife")
	# GHOSTFACE runs while shoot is held (no stop to aim)
	var s7 = _stage(1, 2, 36)
	var k7 = s7.fighters[0]
	_stand(k7, _floor(s7, 4), 0)
	k7.mask = true
	var x7: int = k7.x
	for k in 15:
		s7.apply_input(k7, P.B_SHOOT | P.B_RIGHT, 0)
		s7.step()
	_check(k7.x > x7 + 20, "GHOSTFACE runs with shoot held (%d px)" % (k7.x - x7))
	# the whole fighter reads back the same, mid-swing and down
	for want_down in [false, true]:
		var s8 = _stage(1, 2, 37)
		var k8 = s8.fighters[0]
		k8.mask = true
		if want_down:
			s8._collapse(k8)
		else:
			k8.knife_t = 9
			k8.knife_cd = 20
		var buf := StreamPeerBuffer.new()
		s8.write_fighter_state(buf, k8)
		buf.seek(0)
		var r := SimScript.Fighter.new()
		s8.read_fighter_state(buf, r)
		for key in ["mask", "down_t", "knife_t", "knife_cd", "knife_hit", "trick", "trick_t", "state", "dodge_t"]:
			_check(r.get(key) == k8.get(key), "the whole fighter's %s read back %s, not %s" % [key, r.get(key), k8.get(key)])

# p4.13 candies: no orb is a candy; a body drops one; it lands and rests on a floor; a
# touch opens it (TRICK OR TREAT); left alone it goes after CANDY_LIFE; one falls from
# the sky; never more than CANDY_MAX at once.
func _candies() -> void:
	var s0 = _stage(1, 2, 50, true)
	var tricks := 0
	for i in 3000:
		if s0._pick_regular() == P.PU_TRICK:
			tricks += 1
	_check(tricks == 0, "no orb is a TRICK OR TREAT any more (%d of 3000)" % tricks)
	var s = _stage(1, 3, 51, true)
	s.pu_wait = 99999          # no orb drops (no lightning) in this stage
	s.candy_t = 99999
	s.candy_drop = 1.0
	var at := _floor(s, 4)
	var v = s.fighters[1]
	_stand(v, at, 0)
	var o = s.fighters[0]
	o.x = (int(at.x) + 700) % 1920
	s.take_events()
	s._kill(v, 0, 1)
	_check(s.candies.size() == 1 and _count(s.take_events(), P.E_CANDY_DROP, 0) == 1, "a body drops a candy")
	var rested := -1
	for k in 150:
		s.step()
		if s.candies.size() == 1 and s.candies[0]["rest"]:
			rested = k
			break
	_check(rested > 0, "the candy falls and rests (after %d ticks)" % rested)
	if rested > 0:
		var c: Dictionary = s.candies[0]
		_check(s.level.cell_at(c["x"], c["y"] + 9.0) != 0, "it rests on a floor (x %d, y %d)" % [c["x"], c["y"]])
		var w = s.fighters[2]
		w.x = int(c["x"]) - 18
		w.y = int(c["y"]) - 40
		w.vx = 0.0
		w.vy = 0.0
		s.take_events()
		s.step()
		var evs: Array = s.take_events()
		_check(s.candies.is_empty() and _count(evs, P.E_CANDY_GET) == 1 and _count(evs, P.E_TRICK) == 1,
			"touching it opens it: TRICK OR TREAT (candy %d, trick %d)" % [_count(evs, P.E_CANDY_GET), _count(evs, P.E_TRICK)])
	var s2 = _stage(1, 2, 52, true)
	s2.pu_wait = 99999
	s2.candy_t = 99999
	s2.candies.clear()
	s2._spawn_candy(300.0, 60.0, 0.0, 0.0, false)
	s2.candies[0]["t"] = SimScript.CANDY_LIFE - 3
	for f in s2.fighters:
		f.x = 1500
	for k in 5:
		s2.step()
	_check(s2.candies.is_empty(), "a candy nobody takes goes after %d s" % (SimScript.CANDY_LIFE / 60))
	s2.candy_t = 1
	s2.take_events()
	s2.step()
	s2.step()
	_check(s2.candies.size() == 1 and s2.candies[0]["sky"] and _count(s2.take_events(), P.E_CANDY_DROP, 1) == 1, "one falls from the sky")
	var s3 = _stage(1, 8, 53, true)
	s3.pu_wait = 99999
	s3.candy_t = 99999
	s3.candy_drop = 1.0
	for f in s3.fighters:
		f.x = 900
	for i in range(1, 8):
		s3._kill(s3.fighters[i], 0, 1)
	_check(s3.candies.size() == SimScript.CANDY_MAX, "never more than %d candies at once (%d)" % [SimScript.CANDY_MAX, s3.candies.size()])

func _ghostface_bots(rounds: int) -> void:
	var s = SimScript.new(0, 24, 41)
	s.respawn = false
	s.powerups = false
	s.set_arena(1)
	var swings := 0
	var knife_kills := 0
	var downs := 0
	var wins := 0
	var deaths := {}
	var inside := 0
	for r in rounds:
		var list := []
		for i in 8:
			list.append({"id": i, "bot": true})
		s.start_round(list)
		s.frozen = false
		s.fighters[0].mask = true
		var t := 0
		while s.alive_count() > 1 and t < 3600:
			t += 1
			s.step()
			for f in s.fighters:
				if f.state != P.F_DEAD and s.box_hits_solid(f.x, f.y, SimScript.BODY_W, SimScript.BODY_H):
					inside += 1
			var last_cause := {}
			for e in s.take_events():
				if e[0] == P.E_KNIFE and e[3] == 0:
					swings += 1
				elif e[0] == P.E_MASK_DOWN and e[3] == 0:
					downs += 1
				elif e[0] == P.E_DEATH:
					last_cause[e[3]] = e[4]
					if e[3] == 0:
						deaths[e[4]] = deaths.get(e[4], 0) + 1
				elif e[0] == P.E_KILL and e[3] == 0 and int(last_cause.get(e[4], 0)) == 11:
					knife_kills += 1
		var last = s.last_alive()
		if last != null and s.alive_count() == 1 and last.id == 0:
			wins += 1
	var dl := []
	for k in deaths:
		dl.append("%s %d" % [P.CAUSES.get(k, str(k)), deaths[k]])
	_say("a GHOSTFACE bot in %d rounds of 8 bots: %d swings, %d knife knockouts, knocked down %d times, won %d (%.0f%%, 1 in 8 is %.0f%%); its ends: %s" % [
		rounds, swings, knife_kills, downs, wins, 100.0 * wins / maxi(1, rounds), 100.0 / 8.0, ", ".join(dl)])
	_check(knife_kills >= 3, "GHOSTFACE bots get knife knockouts (%d)" % knife_kills)
	_check(inside == 0, "no living body is ever inside a block (%d ticks)" % inside)
