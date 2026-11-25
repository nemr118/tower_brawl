# p4.22 the Christmas season, headless: each new rule on its own little stage. The season
# (the dates, the names, MIX's list), SNOWBALLS (the arrow kind is kept; the burst packs
# who is near into a snowman and knocks nobody out; a dodge, the shooter and a teammate are
# safe; a frozen fighter cannot move and can still be hit; a direct hit knocks out; it
# drops only in the Christmas season; bombs come as ornaments on the season's arenas), the
# reindeer (how often it comes and when; it trots its floor and is never inside a block or
# over air; touching it is a ride: flying for RIDE_TICKS, then a fall; a knockout ends the
# ride), the silly rounds (the five old ones under their Christmas names, SECRET SANTA and
# SLIP AND SLIDE), what SNOWBALLS are worth to their holder, and whole rounds of 8 bots in
# the season on each of MIX's arenas (nobody ends inside a block, every round ends, what
# happened). Exit 1 on a failed check.
#   godot --headless --path bench --script res://tools/christmas_probe.gd [-- --rounds=40 --worth=300]
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const P = preload("res://sim/proto.gd")
const KEEP := 1

var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("🧪 [ChristmasProbe] FAIL: " + what)

func _say(s: String) -> void:
	print("🧪 [ChristmasProbe] " + s)

# A stage: arena n in a season, these seats (people unless bots), the round running, everyone landed.
func _stage(n: int, seats: int, seed: int, season := "christmas", bots := false):
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
	s.pu_wait = 999999        # no orbs on these stages
	s.candy_t = 999999
	s.candy_drop = 0.0
	s.pet_at = -1
	for k in 40:
		s.step()
	s.take_events()
	return s

func _stand(f, at: Vector2, dx: int) -> void:
	f.x = posmod(int(at.x) - 18 + dx, 1920)
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

func _arg(name: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return int(a.get_slice("=", 1))
	return fallback

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_season()
	_snowballs()
	_deer()
	_silly()
	_state_bytes()
	_worth(_arg("worth", 300))
	_rounds(_arg("rounds", 40))
	_say("%s (%d fail) in %d ms" % ["PASS" if fails == 0 else "FAIL", fails, Time.get_ticks_msec() - t0])
	quit(0 if fails == 0 else 1)

func _season() -> void:
	_check(P.season_for(12, 1) == "christmas" and P.season_for(12, 25) == "christmas" and P.season_for(12, 31) == "christmas", "Christmas runs all of December")
	_check(P.season_for(11, 30) == "harvest" and P.season_for(1, 1) == "", "the Harvest before it, no season after it")
	_check(P.SEASON_PICKS.has("christmas") and P.SEASON_LABEL.get("christmas", "") == "CHRISTMAS", "the SEASON button has CHRISTMAS")
	_check(P.pu_name(P.PU_MASK, "christmas") == "KRAMPUS" and P.pu_name(P.PU_TRICK, "christmas") == "A PRESENT"
		and P.pu_name(P.PU_PUMPKIN, "christmas") == "ORNAMENT BOMBS" and P.pu_name(P.PU_BATS, "christmas") == "SNOW FLURRY"
		and P.pu_name(P.PU_RAIN, "christmas") == "BLIZZARD" and P.pu_name(P.PU_SNOWBALL, "christmas") == "SNOWBALLS",
		"the power-ups' names follow the season")
	_check(P.pu_name(P.PU_MASK, "harvest") == "THE BIG TURKEY" and P.pu_name(P.PU_MASK, "halloween") == "GHOSTFACE" and P.pu_name(P.PU_RAIN, "") == "RAIN",
		"the other seasons' names are as they were")
	for k in [P.PU_RAIN, P.PU_TRICK, P.PU_PUMPKIN, P.PU_BATS, P.PU_MASK, P.PU_SNOWBALL]:
		_check(P.pu_short(k, "christmas") != "" and P.pu_help(k, "christmas") != "", "power-up %d has a short name and a help line in the season" % k)
	_check(P.trick_name(0, "christmas") == "GIFT" and P.trick_name(1, "christmas") == "SNOWMAN" and P.trick_name(2, "christmas") == "BRAIN FREEZE"
		and P.trick_name(3, "christmas") == "ELF-SIZED" and P.trick_name(4, "christmas") == "KRAMPUS", "a present's results have their names")
	_check(P.candy_word("christmas") == "present" and P.candy_word("harvest") == "dish" and P.candy_word("") == "candy", "a candy is a present in the season")
	_check(P.team_names("christmas") == ["TEAM NAUGHTY", "TEAM NICE"], "the teams are NAUGHTY and NICE")
	var names := {}
	for i in 8:
		names[P.bot_name(i, "christmas")] = true
		_check(P.is_bot_name(P.bot_name(i, "christmas")), "a person may not take the bot name %s" % P.bot_name(i, "christmas"))
	_check(names.size() == 8, "eight bots have eight names (%d)" % names.size())
	var mix: Array = LevelScript.mix_for("christmas")
	var themes: Array = []
	for n in mix:
		themes.append(str(LevelScript.LAYOUTS[n].get("theme", "")))
	_check(mix.size() == 4 and themes.has("rooftops") and themes.has("workshop") and not themes.has("halloween") and not themes.has("barn"),
		"MIX in the season is the castle arenas, THE ROOFTOPS and SANTA'S WORKSHOP (%s)" % str(mix))
	for other in ["", "halloween", "harvest"]:
		for n in LevelScript.mix_for(other):
			var th := str(LevelScript.LAYOUTS[n].get("theme", ""))
			_check(th != "rooftops" and th != "workshop", "MIX in season '%s' leaves the Christmas arenas out" % other)
	_check(P.silly_kinds("christmas").size() == 7, "seven silly rounds in the season (%d)" % P.silly_kinds("christmas").size())
	for kind in P.silly_kinds("christmas"):
		_check(P.silly_name(kind, "christmas") != "", "silly round %d has a name" % kind)
	for other in ["", "halloween", "harvest"]:
		_check(not P.silly_kinds(other).has(P.SILLY_SECRET) and not P.silly_kinds(other).has(P.SILLY_ICE), "SECRET SANTA and SLIP AND SLIDE are only played in the Christmas season ('%s')" % other)

func _ball(owner: int, x: float, y: float):
	var a := SimScript.Arrow.new()
	a.kind = P.A_SNOWBALL
	a.owner = owner
	a.x = x
	a.y = y
	return a

func _snowballs() -> void:
	# the arrow kind, kept for the match
	var s = _stage(KEEP, 5, 41)
	var at := _floor(s, 9)
	var me = s.fighters[0]
	s._give(me, P.PU_SNOWBALL)
	_check(me.pw_kind == P.A_SNOWBALL and int(s.keep.get(0, 0)) == P.A_SNOWBALL, "SNOWBALLS: every arrow is a snowball, kept for the match")
	# the burst: near is packed in snow, far is not, the shooter is not, one in a dodge is not; nobody is out
	var near = s.fighters[1]
	var far = s.fighters[2]
	var roll = s.fighters[3]
	var edge = s.fighters[4]
	_stand(me, at, 0)
	_stand(near, at, 60)
	_stand(far, at, 60 + 400)
	_stand(roll, at, -60)
	_stand(edge, at, int(SimScript.SNOW_R) - 12)
	roll.state = P.F_DODGE
	roll.dodge_t = 30
	s.take_events()
	s._snowball(_ball(0, at.x + 20.0, at.y - 31.0))
	var evs: Array = s.take_events()
	_check(near.freeze_t == SimScript.SNOWED_TICKS and edge.freeze_t == SimScript.SNOWED_TICKS, "the burst packs who is within %d px into a snowman for %d ticks" % [int(SimScript.SNOW_R), SimScript.SNOWED_TICKS])
	_check(far.freeze_t == 0, "a fighter 440 px away is not snowed in")
	_check(me.freeze_t == 0, "the shooter is not snowed in by its own snowball")
	_check(roll.freeze_t == 0, "a fighter in a dodge is not snowed in")
	_check(s.alive_count() == 5, "the burst knocks nobody out (%d of 5 alive)" % s.alive_count())
	_check(_count(evs, P.E_SNOW) == 1 and _count(evs, P.E_SNOWED) == 2, "it says one burst and each snowman (%d, %d)" % [_count(evs, P.E_SNOW), _count(evs, P.E_SNOWED)])
	# a snowman cannot move, and thaws
	roll.state = P.F_NORMAL
	var x0: int = near.x
	for k in SimScript.SNOWED_TICKS - 2:
		s.apply_input(near, P.B_RIGHT, 0)
		s.step()
	_check(near.x == x0 and near.freeze_t > 0, "a snowman cannot run (it moved %d px)" % (near.x - x0))
	for k in 30:
		s.apply_input(near, P.B_RIGHT, 0)
		s.step()
	_check(near.freeze_t == 0 and near.x != x0, "it thaws after %d ticks and runs again" % SimScript.SNOWED_TICKS)
	# a snowman can still be hit
	var s2 = _stage(KEEP, 2, 42)
	var at2 := _floor(s2, 9)
	var a0 = s2.fighters[0]
	var b0 = s2.fighters[1]
	_stand(a0, at2, -150)
	_stand(b0, at2, 60)
	s2._give(a0, P.PU_SNOWBALL)
	b0.freeze_t = SimScript.SNOWED_TICKS
	s2.take_events()
	s2._shoot(a0, 0.0, a0.pw_kind)
	var bursts := 0
	for k in 60:
		s2.step()
		bursts += _count(s2.take_events(), P.E_SNOW)
	_check(b0.state == P.F_DEAD, "a direct hit with a snowball knocks out (a snowman too)")
	_check(bursts == 1, "and the snowball bursts on the body, once (%d)" % bursts)
	# a snowball shot into a wall bursts once and is gone (nothing left to pick up)
	var s3 = _stage(KEEP, 2, 43)
	var f3 = s3.fighters[0]
	s3._give(f3, P.PU_SNOWBALL)
	var at3 := _floor(s3, 9)
	_stand(f3, at3, 0)
	_stand(s3.fighters[1], at3, 900)
	s3.take_events()
	s3._shoot(f3, 0.0, f3.pw_kind)
	var b3 := 0
	for k in 240:
		s3.step()
		b3 += _count(s3.take_events(), P.E_SNOW)
	_check(b3 == 1 and s3.arrows.is_empty(), "a snowball that is shot bursts once and leaves no arrow (%d bursts, %d arrows)" % [b3, s3.arrows.size()])
	# TEAMS: a teammate is not snowed in; a foe is
	var s4 = _stage(KEEP, 3, 44)
	var at4 := _floor(s4, 9)
	s4.teams = {0: 0, 1: 0, 2: 1}
	_stand(s4.fighters[0], at4, 0)
	_stand(s4.fighters[1], at4, 50)
	_stand(s4.fighters[2], at4, -50)
	s4._snowball(_ball(0, at4.x, at4.y - 31.0))
	_check(s4.fighters[1].freeze_t == 0 and s4.fighters[2].freeze_t > 0, "TEAMS: a teammate's snowball does not snow you in; a foe's does")
	# the page's own copy says the burst and freezes nobody (the server's word does)
	var s5 = _stage(KEEP, 2, 45)
	var at5 := _floor(s5, 9)
	_stand(s5.fighters[0], at5, 0)
	_stand(s5.fighters[1], at5, 50)
	s5.predicting = true
	s5._snowball(_ball(0, at5.x, at5.y - 31.0))
	_check(s5.fighters[1].freeze_t == 0 and _count(s5.take_events(), P.E_SNOW) == 1, "the page's own copy shows the burst and freezes nobody")
	# the round's winner is not snowed in
	var s6 = _stage(KEEP, 2, 46)
	var at6 := _floor(s6, 9)
	_stand(s6.fighters[0], at6, 0)
	_stand(s6.fighters[1], at6, 50)
	s6.safe = 1
	s6._snowball(_ball(0, at6.x, at6.y - 31.0))
	_check(s6.fighters[1].freeze_t == 0, "the round's winner is not snowed in")
	# it drops only in the Christmas season; bombs are ornaments on the season's arenas
	var balls := 0
	var s7 = _stage(KEEP, 2, 47)
	for i in 3000:
		if s7._pick_regular() == P.PU_SNOWBALL:
			balls += 1
	var balls_off := 0
	for other in ["", "harvest", "halloween"]:
		var s8 = _stage(KEEP, 2, 48, other)
		for i in 1000:
			if s8._pick_regular() == P.PU_SNOWBALL:
				balls_off += 1
	_say("SNOWBALLS are %.1f%% of the regular drops in the Christmas season" % (balls / 30.0))
	_check(balls > 200 and balls < 520 and balls_off == 0, "SNOWBALLS drop in the Christmas season (%d of 3000), never outside it (%d)" % [balls, balls_off])
	var plain := 0
	for i in 2000:
		if s7._pick_regular() == P.PU_PUMPKIN:
			plain += 1
	_check(plain == 0, "on THE KEEP the bombs stay bombs in the season (%d ornaments)" % plain)
	for th in ["rooftops", "workshop"]:
		s7.level.theme = th
		var bombs := 0
		var orns := 0
		for i in 3000:
			var k: int = s7._pick_regular()
			bombs += 1 if k == P.PU_BOMB else 0
			orns += 1 if k == P.PU_PUMPKIN else 0
		_check(bombs == 0 and orns > 150, "on a '%s' arena the bombs are ORNAMENT BOMBS in the season (%d ornaments, %d bombs)" % [th, orns, bombs])
	s7.level.theme = ""

func _deer() -> void:
	# how often, and when
	var came := 0
	var late := 0
	var s = SimScript.new(0, 24, 61)
	s.respawn = false
	s.powerups = true
	s.season = "christmas"
	s.set_arena(KEEP)
	for r in 300:
		s.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}])
		s.frozen = false
		s.pu_wait = 999999
		s.candy_t = 999999
		if s.pet_at >= 0:
			came += 1
			if s.pet_at < SimScript.DEER_AT[0] or s.pet_at > SimScript.DEER_AT[1]:
				late += 1
	_say("the reindeer comes in %d%% of rounds on THE KEEP, 2 to 4 s in" % int(round(came / 3.0)))
	_check(came > 100 and came < 170 and late == 0, "the reindeer comes in about 45%% of rounds (%d of 300), 2 to 4 s in (%d outside that)" % [came, late])
	# it shows up as the reindeer, trots its floor, never inside a block, never over air
	var ticks := 0
	var bad := 0
	var kinds_ok := true
	var said := 0
	for n in LevelScript.mix_for("christmas"):
		for seed in 6:
			var s2 = _stage(n, 2, 600 + n * 10 + seed)
			s2.pet_at = 1
			for k in SimScript.DEER_LIFE + 80:
				s2.step()
				for e in s2.take_events():
					if e[0] == P.E_CAT_COME:
						said += 1
						kinds_ok = kinds_ok and e[3] == 2
				if s2.pet.is_empty():
					continue
				kinds_ok = kinds_ok and int(s2.pet.get("kind", -1)) == 2
				if int(s2.pet["gone"]) > 0:
					continue
				ticks += 1
				if s2.level.cell_at(s2.pet["x"], s2.pet["y"] - 1.0) == 1 or s2.level.cell_at(s2.pet["x"], s2.pet["y"] + 2.0) == 0:
					bad += 1
			_check(s2.pet.is_empty(), "the reindeer leaves by itself after %d ticks (arena %d)" % [SimScript.DEER_LIFE, n])
	_check(said > 0 and kinds_ok, "in the season the pet is the reindeer, and says so (%d came)" % said)
	_check(ticks > 3000 and bad == 0, "trotting on every arena of the season it is never inside a block and never over air (%d ticks, %d bad)" % [ticks, bad])
	# touching it: a ride
	var s3 = _stage(KEEP, 3, 62)
	var at := _floor(s3, 9)
	var me = s3.fighters[0]
	var ice = s3.fighters[1]
	_stand(me, at, -200)
	_stand(ice, at, 40)
	_stand(s3.fighters[2], at, 900)
	ice.freeze_t = 600
	s3.pet = {"x": at.x + 40.0, "y": at.y, "dir": 1, "t": 0, "gone": 0, "kind": 2, "vy": 0.0, "air": false}
	s3.take_events()
	s3.step()
	_check(ice.ride_t == 0 and not s3.pet.is_empty(), "a snowman (frozen) does not get on the reindeer")
	_stand(ice, at, 700)
	s3.pet["x"] = at.x - 200.0
	s3.pet["dir"] = 1
	s3.step()
	var evs: Array = s3.take_events()
	_check(me.ride_t == SimScript.RIDE_TICKS and s3.pet.is_empty() and _count(evs, P.E_PET, 2) == 1, "touching the reindeer is a ride for %d ticks, and says so" % SimScript.RIDE_TICKS)
	_check(SimScript.flying(me) and not me.fly, "a rider flies (FLYING's rule) without having FLYING")
	var y0: int = me.y
	for k in 40:
		s3.apply_input(me, P.B_UP, 0)
		s3.step()
	_check(y0 - me.y > 120, "the stick up lifts a rider (%d px in 40 ticks)" % (y0 - me.y))
	var ended := 0
	for k in SimScript.RIDE_TICKS:
		s3.apply_input(me, 0, 0)
		s3.step()
		ended += _count(s3.take_events(), P.E_RIDE_END)
	_check(me.ride_t == 0 and ended == 1, "the ride is over after %d ticks, said once (%d)" % [SimScript.RIDE_TICKS, ended])
	for k in 240:
		s3.apply_input(me, 0, 0)
		s3.step()
	_check(me.on_ground and me.state != P.F_DEAD, "after the ride it falls and lands")
	# a knockout ends the ride
	var s4 = _stage(KEEP, 2, 63)
	var r4 = s4.fighters[0]
	r4.ride_t = 200
	s4.take_events()
	s4._kill(r4, 1, 1)
	_check(r4.ride_t == 0 and _count(s4.take_events(), P.E_RIDE_END) == 1, "a knockout ends the ride")

# The silly rounds under their Christmas names: every fighter gets the same thing, nothing of
# it is kept for the next round, and 12 whole bot rounds of each kind end.
func _silly() -> void:
	var told: Array = []
	for kind in P.silly_kinds("christmas"):
		var nm := P.silly_name(kind, "christmas")
		var s = SimScript.new(0, 24, 700 + kind)
		s.respawn = false
		s.powerups = true
		s.season = "christmas"
		s.walls_start = 25 * 60
		s.set_arena(KEEP)
		var endless := 0
		var secs: Array = []
		var all_have := true
		var kept := 0
		var opened := 0
		var tricked := 0
		var fighters := 0
		for r in 12:
			var list := []
			for i in 6:
				list.append({"id": i, "bot": true})
			s.reset_powers()
			s.start_round(list)
			s.silly_round(kind)
			kept += s.keep.size()
			var evs: Array = s.take_events()
			opened += _count(evs, P.E_CANDY_GET)
			s.frozen = false
			for f in s.fighters:
				fighters += 1
				tricked += 1 if f.trick != 0 else 0
				var has: bool = [false, f.pw_kind == P.A_SNOWBALL, f.mask, f.trick == 3 and f.trick_t > 3600, f.ride_t > 3600 and not f.fly,
					f.inf and f.big, true, f.icy][kind]
				all_have = all_have and has
			var t := 0
			while s.alive_count() > 1 and t < 3600:
				t += 1
				s.step()
				s.take_events()
			if t >= 3600:
				endless += 1
			secs.append(t / 60.0)
		_check(all_have, "%s: every fighter has it at the start" % nm)
		_check(kept == 0, "%s: nothing of it is kept for the match (%d kept)" % [nm, kept])
		_check(endless == 0, "%s: every round ends within 60 s (%d did not)" % [nm, endless])
		if kind == P.SILLY_SECRET:
			_check(opened == fighters, "SECRET SANTA: everyone opens a present (%d of %d)" % [opened, fighters])
			_check(tricked > fighters / 10 and tricked < fighters / 2, "SECRET SANTA: about a quarter get a trick (%d of %d)" % [tricked, fighters])
		secs.sort()
		told.append("%s a median %.1f s (the longest %.1f)" % [nm, secs[secs.size() / 2], secs[secs.size() - 1]])
		# the round after is plain again
		s.reset_powers()
		s.start_round([{"id": 0, "bot": true}, {"id": 1, "bot": true}])
		s.silly_round(kind)
		s.start_round([{"id": 0, "bot": true}, {"id": 1, "bot": true}])
		var f0 = s.fighters[0]
		_check(f0.pw_kind == 0 and not f0.mask and f0.trick == 0 and not f0.fly and not f0.inf and not f0.big and f0.ride_t == 0 and not f0.icy
			and f0.shield == 0, "%s: the round after is plain" % nm)
	_say("silly rounds, 12 rounds of 6 bots each on THE KEEP: " + "; ".join(told))
	# SECRET SANTA gives back what a fighter kept for the match
	var s2 = _stage(KEEP, 2, 720)
	s2._give(s2.fighters[0], P.PU_FIRE)
	var same := true
	for r in 40:
		s2.start_round([{"id": 0, "bot": true}, {"id": 1, "bot": true}])
		s2.silly_round(P.SILLY_SECRET)
		same = same and int(s2.keep.get(0, 0)) == P.A_FIRE and not s2.keep.has(1)
	_check(same, "SECRET SANTA leaves what a fighter kept for the match as it was")
	# SLIP AND SLIDE: a fighter that lets go of the stick slides much farther on ice
	var slides: Array = []
	for icy in [false, true]:
		var s3 = _stage(KEEP, 1, 730)
		var at := _floor(s3, 9)
		var f = s3.fighters[0]
		_stand(f, at, -240)
		f.icy = icy
		for k in 4:
			s3.step()
		f.vx = SimScript.RUN_MAX
		var x0: int = f.x
		for k in 50:
			s3.apply_input(f, 0, 0)
			s3.step()
		slides.append(f.x - x0)
	_say("letting go at full speed: %d px to a stop on the floor, %d px on ice" % [slides[0], slides[1]])
	_check(slides[1] > slides[0] * 3 and slides[1] < 520, "on ice a fighter slides at least 3 times as far, and stops")

# The whole fighter (what the page's own copy starts from) reads back the same with a ride and the ice.
func _state_bytes() -> void:
	var s = _stage(KEEP, 2, 81)
	var f = s.fighters[0]
	f.ride_t = 123
	f.icy = true
	f.freeze_t = 44
	f.pw_kind = P.A_SNOWBALL
	var buf := StreamPeerBuffer.new()
	s.write_fighter_state(buf, f)
	var g = SimScript.Fighter.new()
	buf.seek(0)
	s.read_fighter_state(buf, g)
	_check(g.ride_t == 123 and g.icy and g.freeze_t == 44 and g.pw_kind == P.A_SNOWBALL and buf.get_position() == buf.get_size(),
		"the whole fighter reads back the same (the ride, the ice, the snow, the arrow kind)")
	var snap := StreamPeerBuffer.new()
	s.pet = {"x": 300.0, "y": 300.0, "dir": 1, "t": 0, "gone": 0, "kind": 2, "vy": 0.0, "air": false}
	s.write_snapshot(snap, [])
	_check(snap.get_size() > 40, "a snapshot with a rider and the reindeer is written (%d bytes)" % snap.get_size())

# What SNOWBALLS are worth: seat 0 holds one arrow kind all match in rounds of 8 bots on THE
# KEEP (no orbs); an even share of wins is 12.5%.
func _worth(n: int) -> void:
	if n <= 0:
		return
	var told: Array = []
	var share := {}
	for kind in [0, P.PU_BOMB, P.PU_PIE, P.PU_SNOWBALL]:
		var s = SimScript.new(0, 24, 900 + kind)
		s.respawn = false
		s.powerups = false
		s.season = "christmas"
		s.walls_start = 25 * 60
		s.set_arena(KEEP)
		var wins := 0
		for r in n:
			var list := []
			for i in 8:
				list.append({"id": i, "bot": true})
			s.start_round(list)
			if kind != 0:
				s.fighters[0].pw_kind = SimScript._arrow_kind_of(kind)
			s.frozen = false
			var t := 0
			while s.alive_count() > 1 and t < 3600:
				t += 1
				s.step()
				s.take_events()
			var last = s.last_alive()
			if last != null and last.id == 0:
				wins += 1
		share[kind] = 100.0 * wins / n
		told.append("%s %.1f%%" % ["plain arrows" if kind == 0 else P.pu_name(kind, "christmas"), share[kind]])
	_say("what an arrow kind is worth (seat 0 holds it, %d rounds of 8 bots, an even share is 12.5%%): %s" % [n, ", ".join(told)])
	_check(share[P.PU_SNOWBALL] < 30.0, "SNOWBALLS do not make their holder win far more than its share (%.1f%%)" % share[P.PU_SNOWBALL])

func _rounds(n: int) -> void:
	for arena in LevelScript.mix_for("christmas"):
		var s = SimScript.new(0, 24, 1000 + arena)
		s.respawn = false
		s.powerups = true
		s.season = "christmas"
		s.walls_start = 25 * 60
		s.set_arena(arena)
		var secs: Array = []
		var inside := 0
		var endless := 0
		var tally := {"came": 0, "rides": 0, "balls": 0, "snowed": 0, "presents": 0, "tricks": 0, "costumes": 0, "swings": 0, "sack": 0, "frozen_ko": 0}
		for r in n:
			var list := []
			for i in 8:
				list.append({"id": i, "bot": true})
			if r % 10 == 0:
				s.reset_powers()
			s.start_round(list)
			s.frozen = false
			var t := 0
			var last_cause := {}
			while s.alive_count() > 1 and t < 3600:
				t += 1
				s.step()
				for f in s.fighters:
					if f.state != P.F_DEAD and s.box_hits_solid(f.x, f.y, SimScript.BODY_W, SimScript.BODY_H):
						inside += 1
				if not s.pet.is_empty() and int(s.pet["gone"]) == 0 and s.level.cell_at(s.pet["x"], s.pet["y"] - 1.0) == 1:
					inside += 1
				for e in s.take_events():
					if e[0] == P.E_PET and e[4] == 2:
						tally["rides"] += 1
					elif e[0] == P.E_CAT_COME and e[3] == 2:
						tally["came"] += 1
					elif e[0] == P.E_SNOW:
						tally["balls"] += 1
					elif e[0] == P.E_SNOWED:
						tally["snowed"] += 1
					elif e[0] == P.E_CANDY_GET:
						tally["presents"] += 1
					elif e[0] == P.E_TRICK and e[4] >= 1 and e[4] <= 3:
						tally["tricks"] += 1
					elif e[0] == P.E_TRICK and e[4] == 4:
						tally["costumes"] += 1
					elif e[0] == P.E_KNIFE:
						tally["swings"] += 1
					elif e[0] == P.E_DEATH:
						last_cause[e[3]] = e[4]
						var df = s.fighter(e[3])
						if df != null and df.freeze_t > 0:
							tally["frozen_ko"] += 1
					elif e[0] == P.E_KILL and int(last_cause.get(e[4], 0)) == 11:
						tally["sack"] += 1
			if t >= 3600:
				endless += 1
			secs.append(t / 60.0)
		secs.sort()
		_say("%d rounds on %s: a median %.1f s; the reindeer came %d times and was ridden %d; %d snowballs burst and packed %d snowmen (%d knocked out while frozen); %d presents (%d tricks, %d costumes); %d swings, %d into the sack" % [
			n, s.level.name, secs[secs.size() / 2], tally["came"], tally["rides"], tally["balls"], tally["snowed"], tally["frozen_ko"], tally["presents"],
			tally["tricks"], tally["costumes"], tally["swings"], tally["sack"]])
		_check(inside == 0, "%s: nobody (and no reindeer) is ever inside a block (%d ticks)" % [s.level.name, inside])
		_check(endless == 0, "%s: every round ends within 60 s (%d did not)" % [s.level.name, endless])
		_check(tally["came"] > 0 and tally["presents"] > 0, "%s: the reindeer comes and presents are opened in %d rounds" % [s.level.name, n])
