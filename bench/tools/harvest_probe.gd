# p4.18 the Harvest season, headless: each new rule on its own little stage. The seasons
# (the dates, the names, MIX's list), the turkey (how often it comes and when; it walks
# its floor; it runs from a fighter; chased over a whole arena it is never inside a block
# and never stands on air; touching it gives a power-up and it flies off), PIE (the arrow
# kind is kept; the splat creams who is near and kills who is in the blast; the cream
# hides the others and ends; PIE drops only in the Harvest season; bombs come as popcorn
# on the season's arenas), the catch-up SHIELD (2 points behind, people only, said once)
# and the costume's lunge. Exit 1 on a failed check.
#   godot --headless --path bench --script res://tools/harvest_probe.gd
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const P = preload("res://sim/proto.gd")
const KEEP := 1

var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("🧪 [HarvestProbe] FAIL: " + what)

func _say(s: String) -> void:
	print("🧪 [HarvestProbe] " + s)

# A stage: arena n in a season, these seats (people unless bots), the round running, everyone landed.
func _stage(n: int, seats: int, seed: int, season := "harvest", bots := false):
	var s = SimScript.new(0, 24, seed)
	s.respawn = false
	s.powerups = true
	s.season = season
	s.set_arena(n)
	var list := []
	for i in seats:
		list.append({"id": i, "bot": bots})
	s.start_round(list)
	s.frozen = false
	s.pu_wait = 999999        # no lightning orbs on these stages
	s.candy_t = 999999
	s.candy_drop = 0.0
	for k in 40:
		s.step()
	s.take_events()
	return s

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

# A floor with open room (halloween_probe's): the feet's spot with need cells of floor
# and three empty rows above on each side.
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

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_seasons()
	_turkey()
	_pie()
	_catch_up()
	_lunge()
	_say("%s (%d fail) in %d ms" % ["PASS" if fails == 0 else "FAIL", fails, Time.get_ticks_msec() - t0])
	quit(0 if fails == 0 else 1)

func _seasons() -> void:
	_check(P.season_for(10, 1) == "halloween" and P.season_for(11, 2) == "halloween", "Halloween runs 1 October to 2 November")
	_check(P.season_for(11, 3) == "harvest" and P.season_for(11, 30) == "harvest", "the Harvest runs 3 to 30 November")
	_check(P.season_for(12, 1) == "" and P.season_for(9, 30) == "" and P.season_for(7, 4) == "", "no season the rest of the year")
	_check(P.pu_name(P.PU_PUMPKIN, "harvest") == "POPCORN ARROWS" and P.pu_name(P.PU_PUMPKIN, "") == "PUMPKIN BOMBS", "PUMPKIN BOMBS are POPCORN ARROWS in the Harvest")
	_check(P.pu_name(P.PU_MASK, "harvest") == "THE BIG TURKEY" and P.pu_name(P.PU_MASK, "halloween") == "GHOSTFACE", "the costume's name follows the season")
	_check(P.pu_name(P.PU_FIRE, "harvest") == "FIRE ARROWS" and P.pu_short(P.PU_PIE, "harvest") == "PIE", "the other names stay")
	for n in 5:
		_check(P.trick_name(n, "") != "" and P.trick_name(n, "harvest") != "", "a candy's result %d has a name in each season" % n)
	_check(P.trick_name(4, "") == "GHOSTFACE" and P.trick_name(1, "harvest") == "TURKEY TIME", "the tricks' names follow the season")
	var hv: Array = LevelScript.mix_for("harvest")
	var other: Array = LevelScript.mix_for("")
	var bad := 0
	for n in hv:
		var th := str(LevelScript.LAYOUTS[n].get("theme", ""))
		if th == "halloween" or th == "nightmare":
			bad += 1
	for n in other:
		var th := str(LevelScript.LAYOUTS[n].get("theme", ""))
		if th == "barn" or th == "table":
			bad += 1
	_check(bad == 0 and hv.size() >= 2 and other.size() >= 2, "MIX: the Harvest leaves the spooky arenas out (%s), the rest of the year leaves the Harvest's out (%s)" % [str(hv), str(other)])
	_say("MIX in the Harvest: %s; the rest of the year: %s" % [str(hv), str(other)])

func _barn() -> int:
	for n in LevelScript.count():
		if str(LevelScript.LAYOUTS[n].get("theme", "")) == "barn":
			return n
	return -1

func _turkey() -> void:
	# how often, and when
	var arenas := [KEEP]
	if _barn() >= 0:
		arenas.append(_barn())
	for n in arenas:
		var s = _stage(n, 2, 31 + n)
		var got := 0
		var early := 0
		for i in 2000:
			s._reset_powers_round()
			if s.pet_at >= 0:
				got += 1
				if s.pet_at >= SimScript.TURKEY_AT[0] and s.pet_at <= SimScript.TURKEY_AT[1]:
					early += 1
		var want: float = SimScript.TURKEY_CHANCE_BARN if s.level.theme == "barn" else SimScript.TURKEY_CHANCE
		_say("the turkey comes in %.0f%% of rounds on %s, 2 to 4 s in" % [got / 20.0, s.level.name])
		_check(absf(got / 2000.0 - want) < 0.04 and early == got, "the turkey comes in %.0f%% of rounds (want %.0f%%), %d of %d times 2 to 4 s in" % [got / 20.0, want * 100.0, early, got])
	# out of the season the cat comes, 2 to 5 s in
	var sc = _stage(KEEP, 2, 5, "")
	var late := 0
	for i in 500:
		sc._reset_powers_round()
		if sc.pet_at > 300 or (sc.pet_at >= 0 and sc.pet_at < 120):
			late += 1
	_check(late == 0, "out of the season the cat comes 2 to 5 s in (%d times outside that)" % late)
	# it shows up as the turkey and walks its floor while nobody is near
	var s2 = _stage(KEEP, 2, 41)
	for f in s2.fighters:
		f.state = P.F_DEAD      # nobody to run from
	var alive = s2.fighters[0]
	s2.pet_at = s2.play_t
	s2._update_pet()
	_check(not s2.pet.is_empty() and int(s2.pet.get("kind", 0)) == 1 and _count(s2.take_events(), P.E_CAT_COME, -1) == 1, "the turkey shows up in the Harvest season")
	if s2.pet.is_empty():
		return
	var y0: float = s2.pet["y"]
	var off := 0
	var moved := 0.0
	var x0: float = s2.pet["x"]
	for k in 200:
		s2._update_pet()
		moved = maxf(moved, absf(SimScript.wrap_d(x0, s2.pet["x"], 1920)))
		if s2.pet["y"] != y0 or s2.level.cell_at(s2.pet["x"], s2.pet["y"] + 2.0) == 0:
			off += 1
	_check(off == 0 and moved > 20.0, "with nobody near, the turkey walks its floor (%.0f px) and stays on it (%d ticks off)" % [moved, off])
	# it runs from a fighter
	alive.state = P.F_NORMAL
	_stand(alive, Vector2(s2.pet["x"], s2.pet["y"]), -150)
	var px: float = s2.pet["x"]
	s2._update_pet()
	s2._update_pet()
	var step: float = SimScript.wrap_d(px, s2.pet["x"], 1920)
	_check(step > 6.0, "a fighter 150 px to its left: the turkey runs right (%.1f px in 2 ticks)" % step)
	# a touch: a power-up, and it flies off
	alive.pw_kind = 0
	alive.shield = 0
	_stand(alive, Vector2(s2.pet["x"], s2.pet["y"]), 0)
	s2.take_events()
	s2._update_pet()
	var evs: Array = s2.take_events()
	_check(_count(evs, P.E_PET, 1) == 1 and _count(evs, P.E_PU_GET) == 1 and int(s2.pet["gone"]) > 0, "touching the turkey: one catch, one power-up, and it leaves")
	for k in 45:
		s2._update_pet()
	_check(s2.pet.is_empty(), "the caught turkey is gone within 45 ticks")
	# chased over whole arenas: never inside a block, never standing on air
	var inside := 0
	var on_air := 0
	var caught := 0
	var runs := 0
	var fell := 0
	for n in LevelScript.PLAY:
		for seed in 6:
			var s3 = _stage(n, 3, 700 + n * 10 + seed)
			if s3.hazards != null:
				s3.hazards = null       # THE BOILER ROOM's fire would end the chasers
			s3.walls_start = 0
			s3.pet_at = s3.play_t
			s3._update_pet()
			if s3.pet.is_empty():
				continue
			runs += 1
			var was_air := false
			for k in 850:
				if s3.pet.is_empty():
					break
				for f in s3.fighters:      # every fighter runs at the turkey
					var d: float = SimScript.wrap_d(f.x + 18, s3.pet["x"], 1920)
					s3.apply_input(f, P.B_RIGHT if d > 0.0 else P.B_LEFT, 0)
				s3.step()
				if s3.pet.is_empty():
					break
				if int(s3.pet["gone"]) > 0:
					caught += 1
					break
				if s3.level.cell_at(s3.pet["x"], s3.pet["y"] - 1.0) == 1:
					inside += 1
				if not s3.pet["air"] and s3.level.cell_at(s3.pet["x"], s3.pet["y"] + 2.0) == 0:
					on_air += 1
				if was_air and not s3.pet["air"]:
					fell += 1          # it landed on a floor
				was_air = s3.pet["air"]
	_say("the chase on %d arenas: %d runs, the turkey caught in %d, it hopped or fell and landed %d times" % [LevelScript.PLAY.size(), runs, caught, fell])
	_check(runs >= 12 and inside == 0 and on_air == 0, "chased by 3 fighters for 14 s on every arena: never inside a block (%d ticks), never standing on air (%d ticks)" % [inside, on_air])
	_check(fell > 0, "a chased turkey leaves its floor and lands again (%d times)" % fell)

func _pie() -> void:
	var s = _stage(KEEP, 3, 51)
	var a0 = s.fighters[0]
	var b0 = s.fighters[1]
	var c0 = s.fighters[2]
	s._give(a0, P.PU_PIE)
	_check(a0.pw_kind == P.A_PIE and int(s.keep.get(a0.id, -1)) == P.A_PIE, "PIE is an arrow kind, kept for the match")
	var at := _floor(s, 9)
	_stand(a0, at, -240)
	_stand(b0, at, 150)         # near the splat, outside the blast
	_stand(c0, at, 0)
	c0.x = posmod(c0.x + 900, 1920)    # far away
	c0.y = 100
	s.take_events()
	var pie := SimScript.Arrow.new()
	pie.id = 9100
	pie.kind = P.A_PIE
	pie.owner = a0.id
	pie.x = at.x
	pie.y = at.y - 30.0
	s._pie(pie)
	var evs: Array = s.take_events()
	var blast_r: float = SimScript.EXPLODE_R * SimScript.PIE_FX
	_check(_count(evs, P.E_PIE) == 1 and b0.pied_t == SimScript.PIED_TICKS and b0.state != P.F_DEAD, "a pie 150 px away (the blast is %.0f px): cream, not the end" % blast_r)
	_check(c0.pied_t == 0, "a fighter far away gets no cream")
	s.step()
	_check(b0.in_smoke and not c0.in_smoke, "the creamed fighter sees nobody (the smoke rule)")
	for k in SimScript.PIED_TICKS + 2:
		s.step()
	_check(b0.pied_t == 0 and not b0.in_smoke, "the cream is gone after %d ticks" % SimScript.PIED_TICKS)
	# in the blast: the end
	var s2 = _stage(KEEP, 2, 52)
	var at2 := _floor(s2, 9)
	_stand(s2.fighters[1], at2, 30)
	var pie2 := SimScript.Arrow.new()
	pie2.kind = P.A_PIE
	pie2.owner = 0
	pie2.x = at2.x
	pie2.y = at2.y - 30.0
	s2._pie(pie2)
	_check(s2.fighters[1].state == P.F_DEAD, "a fighter in the pie's blast is out")
	# a pie arrow that flies into a wall splats at once
	var s3 = _stage(KEEP, 2, 53)
	var f3 = s3.fighters[0]
	s3._give(f3, P.PU_PIE)
	var at3 := _floor(s3, 9)
	_stand(f3, at3, 0)
	_stand(s3.fighters[1], at3, 0)
	s3.fighters[1].x = posmod(s3.fighters[1].x + 900, 1920)
	s3.take_events()
	s3._shoot(f3, 0.0, f3.pw_kind)
	var splats := 0
	for k in 240:
		s3.step()
		splats += _count(s3.take_events(), P.E_PIE)
	_check(splats == 1, "a pie that is shot splats once (%d)" % splats)
	# it drops only in the Harvest season; bombs are popcorn on the season's arenas
	var pies := 0
	var s4 = _stage(KEEP, 2, 54)
	for i in 3000:
		if s4._pick_regular() == P.PU_PIE:
			pies += 1
	var s5 = _stage(KEEP, 2, 55, "")
	var pies_off := 0
	for i in 3000:
		if s5._pick_regular() == P.PU_PIE:
			pies_off += 1
	_say("PIE is %.1f%% of the regular drops in the Harvest season" % (pies / 30.0))
	_check(pies > 200 and pies < 520 and pies_off == 0, "PIE drops in the Harvest season (%d of 3000), never outside it (%d)" % [pies, pies_off])
	s4.level.theme = "barn"
	var bombs := 0
	var corn := 0
	for i in 3000:
		var k: int = s4._pick_regular()
		bombs += 1 if k == P.PU_BOMB else 0
		corn += 1 if k == P.PU_PUMPKIN else 0
	_check(bombs == 0 and corn > 200, "on the Harvest's own arenas the bombs come as popcorn (%d popcorn, %d bombs)" % [corn, bombs])
	s5.level.theme = "barn"
	corn = 0
	for i in 3000:
		corn += 1 if s5._pick_regular() == P.PU_PUMPKIN else 0
	_check(corn == 0, "out of the season a Harvest arena has plain bombs (%d popcorn)" % corn)

func _catch_up() -> void:
	var s = SimScript.new(0, 24, 61)
	s.respawn = false
	s.powerups = true
	s.season = "harvest"
	s.set_arena(KEEP)
	s.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}, {"id": 2, "bot": false}, {"id": 3, "bot": true}])
	var pts := [3, 1, 2, 0]
	for i in 4:
		s.fighters[i].points = pts[i]
	s.catch_up()
	_check(s.fighters[1].shield == 1 and s.fighters[0].shield == 0 and s.fighters[2].shield == 0, "2 points behind the leader: a SHIELD; 1 behind or the leader: none")
	_check(s.fighters[3].shield == 0, "a bot 3 points behind gets no SHIELD")
	s.frozen = false
	s.pu_wait = 999999
	var said := 0
	for k in 30:
		s.step()
		said += _count(s.take_events(), P.E_CATCH_UP)
	_check(said == 1, "the catch-up SHIELD is said once, at FIGHT (%d)" % said)
	# a new round with level points: nobody
	s.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}])
	s.fighters[0].points = 2
	s.fighters[1].points = 1
	s.catch_up()
	_check(s.fighters[0].shield == 0 and s.fighters[1].shield == 0, "1 point apart: no SHIELD")

func _lunge() -> void:
	var s = _stage(KEEP, 3, 71)
	var k0 = s.fighters[0]
	var near = s.fighters[1]
	var far = s.fighters[2]
	var at := _floor(s, 9)
	_stand(k0, at, -120)
	_stand(near, at, -120 + 112)       # past the old reach (66 + 18 px), inside the lunge
	_stand(far, at, -120 + 230)
	k0.mask = true
	k0.facing = 1
	for k in 4:
		s.step()
	s.take_events()
	s._knife(k0, 0.0, true)
	_check(absf(k0.vx - SimScript.KNIFE_LUNGE) < 0.01, "the swing starts with a lunge (%.1f px a tick)" % k0.vx)
	for k in SimScript.KNIFE_TICKS + 2:
		s.step()
	_check(near.state == P.F_DEAD and far.state != P.F_DEAD, "the lunge reaches a fighter 112 px in front, not one 230 px away")
