extends RefCounted

enum State { READY, GUARD, SWING, RECOIL, STAGGER, DOWN }

const FLOOR := 417.0
const BLADE_LENGTH := 86.0
const PARRY_WINDOW := 0.12
const PARRY_REARM := 0.30
const ACTIVE := 0.145
const RECOVERY := 0.26

var x: float
var facing: float
var ink: Color
var health := 100.0
var posture := 0.0
var state := State.READY
var age := 0.0
var duration := 0.0
var windup := 0.0
var windup_speed := 0.0
var short_cut := false
var spent := false
var guard_held := false
var parry_left := 0.0
var parry_lock := 0.0
var guard_rebound := 0.0
var posture_delay := 0.0
var velocity := 0.0
var move_speed := 235.0
var stride := 0.0
var step_weight := 0.0
var start_hand := Vector2(28, -83)
var start_angle := -0.58


func _init(at: float, direction: float, color: Color) -> void:
	x = at
	facing = direction
	ink = color


func enter(next: State, seconds := 0.0) -> void:
	start_hand = hand()
	start_angle = blade_angle()
	state = next
	duration = seconds
	age = 0.0
	if next != State.GUARD:
		parry_left = 0.0


func defend() -> void:
	if state != State.READY and state != State.GUARD:
		return
	if state == State.READY:
		enter(State.GUARD)
	if parry_lock <= 0.0:
		parry_left = PARRY_WINDOW
	parry_lock = PARRY_REARM


func attack(preparation: float, is_short_cut := false, approach_speed := 0.0) -> void:
	if state != State.READY and state != State.GUARD:
		return
	enter(State.SWING, preparation + ACTIVE + RECOVERY)
	windup = preparation
	windup_speed = approach_speed
	short_cut = is_short_cut
	spent = false


func active() -> bool:
	return state == State.SWING and not spent and age >= windup and age <= windup + ACTIVE


func tick(dt: float, direction: float) -> void:
	age += dt
	parry_left = maxf(parry_left - dt, 0.0)
	parry_lock = maxf(parry_lock - dt, 0.0)
	guard_rebound = maxf(guard_rebound - dt, 0.0)
	posture_delay = maxf(posture_delay - dt, 0.0)
	if posture_delay <= 0.0:
		posture = maxf(posture - 21.0 * dt, 0.0)
	if duration > 0.0 and age >= duration:
		enter(State.READY)
	if state == State.READY and guard_held:
		enter(State.GUARD)
	elif state == State.GUARD and not guard_held and parry_left <= 0.0 and guard_rebound <= 0.0:
		enter(State.READY)

	var target := 0.0
	if state == State.READY:
		target = direction * move_speed
	elif state == State.GUARD:
		target = direction * 94.0
	elif state == State.SWING:
		if age < windup:
			target = facing * windup_speed
		elif age < windup + 0.075:
			target = facing * 140.0
	velocity = move_toward(velocity, target, 1900.0 * dt)
	x = clampf(x + velocity * dt, 56.0, 944.0)
	stride += absf(velocity) * dt * 0.066
	step_weight = move_toward(step_weight, absf(target) / 235.0, dt * 8.0)


func pressure(amount: float) -> bool:
	posture = minf(posture + amount, 100.0)
	posture_delay = 1.85
	return posture >= 100.0


func break_stance() -> void:
	posture = 0.0
	enter(State.STAGGER, 0.95)
	velocity = -facing * 170.0


func swing_progress() -> float:
	return clampf((age - windup) / ACTIVE, 0.0, 1.0)


func hand() -> Vector2:
	var rest := Vector2(28, -83)
	match state:
		State.GUARD:
			var raised := Vector2(43, -82) + Vector2(-9, -5) * guard_kick()
			if parry_left > 0.0:
				return raised
			return start_hand.lerp(raised, smoothstep(0.0, 0.045, age))
		State.SWING:
			var loaded := Vector2(30, -113) if short_cut else Vector2(8, -128)
			var finish := Vector2(56, -71) if short_cut else Vector2(50, -68)
			if age < windup:
				return start_hand.lerp(loaded, smoothstep(0.0, windup * 0.8, age))
			if age < windup + ACTIVE:
				return loaded.lerp(finish, swing_progress())
			return finish.lerp(rest, smoothstep(windup + ACTIVE, duration, age))
		State.RECOIL:
			return start_hand.lerp(Vector2(15, -96), smoothstep(0.0, 0.11, age))
		State.STAGGER, State.DOWN:
			return start_hand.lerp(Vector2(20, -56), smoothstep(0.0, 0.14, age))
	return start_hand.lerp(rest, smoothstep(0.0, 0.11, age))


func blade_angle() -> float:
	match state:
		State.GUARD:
			if parry_left > 0.0:
				return -1.78
			return lerpf(start_angle, -1.78, smoothstep(0.0, 0.045, age)) - 0.28 * guard_kick()
		State.SWING:
			var loaded := -1.92 if short_cut else -2.23
			var finish := 0.58 if short_cut else 0.90
			if age < windup:
				return lerpf(start_angle, loaded, smoothstep(0.0, windup * 0.8, age))
			if age < windup + ACTIVE:
				var progress := swing_progress()
				return lerpf(loaded, finish, progress * progress * (3.0 - 2.0 * progress))
			return lerpf(finish, -0.58, smoothstep(windup + ACTIVE, duration, age))
		State.RECOIL:
			return lerpf(start_angle, -2.30, smoothstep(0.0, 0.13, age))
		State.STAGGER, State.DOWN:
			return lerpf(start_angle, 1.23, smoothstep(0.0, 0.15, age))
	return lerpf(start_angle, -0.58, smoothstep(0.0, 0.11, age))


func guard_kick() -> float:
	return sin(PI * guard_rebound / 0.14)


func lean() -> float:
	match state:
		State.SWING:
			return lerpf(-9.0, 19.0, swing_progress())
		State.RECOIL, State.STAGGER:
			return -17.0 * smoothstep(0.0, 0.10, age)
		State.DOWN:
			return -72.0 * smoothstep(0.0, 0.22, age)
	return 0.0


func fall() -> float:
	return absf(lean()) * 1.3 if state == State.DOWN else 0.0


func hip() -> Vector2:
	return world(Vector2(-2 + lean() * 0.22, -55 + fall() * 0.39))


func shoulder() -> Vector2:
	return world(Vector2(lean(), -111 + fall()))


func head() -> Vector2:
	return world(Vector2(lean() + 4, -138 + fall() * 1.2))


func world(local: Vector2) -> Vector2:
	return Vector2(x + local.x * facing, FLOOR + local.y)


func blade() -> PackedVector2Array:
	var grip := hand()
	var direction := Vector2.from_angle(blade_angle())
	return PackedVector2Array([world(grip + direction * 9.0), world(grip + direction * BLADE_LENGTH)])


func body() -> PackedVector2Array:
	return PackedVector2Array([head(), hip()])
