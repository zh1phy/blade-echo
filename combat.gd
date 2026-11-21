extends RefCounted

const Fighter = preload("res://fighter.gd")
const BODY_RADIUS := 13.0
const EDGE_RADIUS := 3.8
const SAMPLES := 5
const HIT_ADVANTAGE := 0.08

enum Kind { HIT, BLOCK, PARRY, BREAK }


static func contact(attacker: Fighter, defender: Fighter, old_edge: PackedVector2Array,
		old_guard: PackedVector2Array, old_body: PackedVector2Array) -> Dictionary:
	if not attacker.active() or defender.state == Fighter.State.DOWN:
		return {}
	var edge := attacker.blade()
	var guard := defender.blade()
	var body := defender.body()
	var frontal := (attacker.x - defender.x) * defender.facing > 0.0
	for sample in range(SAMPLES + 1):
		var t := float(sample) / SAMPLES
		var heel := old_edge[0].lerp(edge[0], t)
		var tip := old_edge[1].lerp(edge[1], t)
		if frontal and defender.state == Fighter.State.GUARD:
			var clash := Geometry2D.get_closest_points_between_segments(
				heel, tip, old_guard[0].lerp(guard[0], t), old_guard[1].lerp(guard[1], t))
			if clash[0].distance_squared_to(clash[1]) <= EDGE_RADIUS * EDGE_RADIUS:
				var kind := Kind.PARRY if defender.parry_left > 0.0 else Kind.BLOCK
				return {"kind": kind, "at": clash[0].lerp(clash[1], 0.5), "t": t}
		var flesh := Geometry2D.get_closest_points_between_segments(
			heel, tip, old_body[0].lerp(body[0], t), old_body[1].lerp(body[1], t))
		if flesh[0].distance_squared_to(flesh[1]) <= BODY_RADIUS * BODY_RADIUS:
			return {"kind": Kind.HIT, "at": flesh[0], "t": t}
	return {}


static func resolve(attacker: Fighter, defender: Fighter, kind: Kind) -> Kind:
	attacker.spent = true
	match kind:
		Kind.PARRY:
			defender.enter(Fighter.State.GUARD)
			defender.parry_left = 0.0
			defender.guard_rebound = 0.14
			defender.velocity = -defender.facing * 58.0
			if attacker.pressure(37.0):
				attacker.break_stance()
				return Kind.BREAK
			attacker.enter(Fighter.State.RECOIL, 0.54)
			attacker.velocity = -attacker.facing * 87.0
		Kind.BLOCK:
			attacker.enter(Fighter.State.RECOIL, 0.30)
			attacker.velocity = -attacker.facing * 35.0
			if defender.pressure(26.0):
				defender.break_stance()
				return Kind.BREAK
			defender.enter(Fighter.State.RECOIL, 0.14)
			defender.velocity = -defender.facing * 105.0
		Kind.HIT:
			var exposed := defender.state == Fighter.State.STAGGER
			defender.health = maxf(0.0, defender.health - (34.0 if exposed else 20.0))
			defender.velocity = -defender.facing * 145.0
			if defender.health <= 0.0:
				defender.enter(Fighter.State.DOWN)
			elif defender.pressure(15.0):
				defender.break_stance()
				return Kind.BREAK
			elif exposed:
				var remaining := defender.duration - defender.age
				defender.enter(Fighter.State.STAGGER, maxf(0.27, remaining))
			else:
				var recovery_left := maxf(attacker.duration - attacker.age, 0.0)
				defender.enter(Fighter.State.RECOIL, recovery_left + HIT_ADVANTAGE)
	return kind
