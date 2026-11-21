extends Node2D

const Fighter = preload("res://fighter.gd")
const Combat = preload("res://combat.gd")
const ImpactAudio = preload("res://impact_audio.gd")
const COOL := Color("#9ce6df")
const WARM := Color("#efad83")
const PAPER := Color("#e7f1ec")
const MUTED := Color("#94aab1")
const POSTURE := Color("#ffd084")
const MESSAGES := ["受击", "格挡", "精准弹反", "架势崩溃"]
const HITSTOP := [0.035, 0.050, 0.083, 0.100]
const SHAKE := [3.0, 2.2, 4.0, 5.0]
const ENEMY_HITS_TO_GUARD := 2
const ENEMY_CHAIN_WINDOW := 1.4
const ENEMY_GUARD_DURATION := 0.85
const ENEMY_GUARD_RANGE := 155.0
const ENEMY_COUNTER_RANGE := 143.0
const ENEMY_COUNTER_WINDUP := 0.30
const PLAYER_WINDUP := 0.19
const GUARD_BUFFER := 0.10
const ENEMY_WINDUP := 0.165
const ENEMY_ATTACK_RANGE := 127.0
const ENEMY_CHASE_SPEED := 260.0
const ENEMY_WINDUP_SPEED := 160.0

var player: Fighter
var rival: Fighter
var audio: ImpactAudio
var ui_font := SystemFont.new()
var enemy_chain_hits := 0
var enemy_chain_left := 0.0
var enemy_counter_pending := false
var attack_buffer := 0.0
var guard_buffer := 0.0
var freeze := 0.0
var impact_time := 0.0
var impact_at := Vector2.ZERO
var impact_kind := Combat.Kind.HIT
var started := false
var debug := false
var player_trail: Array[Vector2] = []
var rival_trail: Array[Vector2] = []
var stage := Node2D.new()


func _ready() -> void:
	ui_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC",
		"PingFang SC", "SimHei"])
	add_child(stage)
	stage.draw.connect(draw_stage)
	audio = ImpactAudio.new()
	audio.volume_db = -7.0
	add_child(audio)
	reset_duel()


func reset_duel() -> void:
	player = Fighter.new(365.0, 1.0, COOL)
	rival = Fighter.new(635.0, -1.0, WARM)
	rival.move_speed = ENEMY_CHASE_SPEED
	enemy_chain_hits = 0
	enemy_chain_left = 0.0
	enemy_counter_pending = false
	attack_buffer = 0.0
	guard_buffer = 0.0
	freeze = 0.0
	impact_time = 0.0
	started = false
	player_trail.clear()
	rival_trail.clear()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				reset_duel()
			KEY_F1:
				debug = not debug
			KEY_J:
				attack_buffer = 0.14
				guard_buffer = 0.0
				started = true
			KEY_K:
				guard_buffer = GUARD_BUFFER
				attack_buffer = 0.0
				started = true


func _physics_process(dt: float) -> void:
	impact_time = maxf(impact_time - dt, 0.0)
	if freeze > 0.0:
		freeze -= dt
		return
	if player.health <= 0.0 or rival.health <= 0.0:
		player.tick(dt, 0.0)
		rival.tick(dt, 0.0)
		return
	var direction := float(Input.is_physical_key_pressed(KEY_D)
		or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A)
		or Input.is_physical_key_pressed(KEY_LEFT))
	if direction != 0.0:
		started = true
	if not started:
		return

	face_opponent(player, rival)
	face_opponent(rival, player)
	player.guard_held = Input.is_physical_key_pressed(KEY_K)
	if player.state in [Fighter.State.READY, Fighter.State.GUARD]:
		if guard_buffer > 0.0:
			player.defend()
			guard_buffer = 0.0
		elif attack_buffer > 0.0:
			player.attack(PLAYER_WINDUP)
			attack_buffer = 0.0
	guard_buffer = maxf(guard_buffer - dt, 0.0)
	attack_buffer = maxf(attack_buffer - dt, 0.0)
	var rival_direction := enemy_intent(dt)
	var player_edge := player.blade()
	var rival_edge := rival.blade()
	var player_body := player.body()
	var rival_body := rival.body()
	player.tick(dt, direction)
	rival.tick(dt, rival_direction)
	separate_fighters()
	update_trail(player, player_trail)
	update_trail(rival, rival_trail)

	var player_hit := Combat.contact(player, rival, player_edge, rival_edge, rival_body)
	var rival_hit := Combat.contact(rival, player, rival_edge, player_edge, player_body)
	if not player_hit.is_empty() and (rival_hit.is_empty() or player_hit.t <= rival_hit.t):
		impact(player, rival, player_hit)
	elif not rival_hit.is_empty():
		impact(rival, player, rival_hit)


func face_opponent(actor: Fighter, opponent: Fighter) -> void:
	if actor.state in [Fighter.State.READY, Fighter.State.GUARD]:
		actor.facing = signf(opponent.x - actor.x)


func enemy_intent(dt: float) -> float:
	enemy_chain_left = maxf(enemy_chain_left - dt, 0.0)
	if enemy_chain_left <= 0.0:
		enemy_chain_hits = 0
	var distance := absf(player.x - rival.x)
	if rival.state == Fighter.State.GUARD:
		if rival.age >= ENEMY_GUARD_DURATION or distance > ENEMY_GUARD_RANGE:
			rival.guard_held = false
			rival.enter(Fighter.State.READY)
		return 0.0
	if rival.state != Fighter.State.READY:
		return 0.0
	if enemy_counter_pending:
		enemy_counter_pending = false
		if distance <= ENEMY_COUNTER_RANGE:
			rival.attack(ENEMY_COUNTER_WINDUP, true)
			return 0.0
	if enemy_chain_hits >= ENEMY_HITS_TO_GUARD:
		enemy_chain_hits = 0
		if distance <= ENEMY_GUARD_RANGE:
			rival.guard_held = true
			rival.enter(Fighter.State.GUARD)
			return 0.0
	if distance > ENEMY_ATTACK_RANGE:
		return rival.facing
	rival.attack(ENEMY_WINDUP, false, ENEMY_WINDUP_SPEED)
	return 0.0


func separate_fighters() -> void:
	var gap := rival.x - player.x
	if gap >= 43.0:
		return
	var middle := clampf((player.x + rival.x) * 0.5, 77.5, 922.5)
	player.x = middle - 21.5
	rival.x = middle + 21.5


func update_trail(actor: Fighter, trail: Array[Vector2]) -> void:
	if actor.active():
		trail.push_back(actor.blade()[1])
		if trail.size() > 10:
			trail.pop_front()
	elif not trail.is_empty():
		trail.pop_front()


func impact(attacker: Fighter, defender: Fighter, result: Dictionary) -> void:
	var exposed := defender.state == Fighter.State.STAGGER
	impact_kind = Combat.resolve(attacker, defender, result.kind)
	if defender == rival:
		rival.guard_held = false
		enemy_counter_pending = impact_kind == Combat.Kind.BLOCK
	if defender == rival and impact_kind == Combat.Kind.HIT and not exposed:
		enemy_chain_hits += 1
		enemy_chain_left = ENEMY_CHAIN_WINDOW
	else:
		enemy_chain_hits = 0
	impact_at = result.at
	impact_time = 0.59
	freeze = HITSTOP[impact_kind]
	audio.strike(impact_kind)


func _process(_dt: float) -> void:
	queue_redraw()
	stage.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1000, 560), Color("#111b26"))
	draw_circle(Vector2(740, 203), 77, Color("#1c3039"), true, -1, true)
	draw_circle(Vector2(740, 203), 64, Color("#acc4be"), true, -1, true)
	draw_circle(Vector2(722, 188), 61, Color("#111b26"), true, -1, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 365), Vector2(160, 239),
		Vector2(269, 326), Vector2(382, 267), Vector2(540, 345), Vector2(755, 276),
		Vector2(1000, 344), Vector2(1000, 417), Vector2(0, 417)]), Color("#192c37"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 346), Vector2(171, 318),
		Vector2(310, 387), Vector2(592, 367), Vector2(818, 326), Vector2(1000, 374),
		Vector2(1000, 417), Vector2(0, 417)]), Color("#1e3440"))
	draw_rect(Rect2(0, 417, 1000, 143), Color("#101820"))
	draw_line(Vector2(0, 417), Vector2(1000, 417), Color("#496069"), 2)
	for i in range(20):
		var x := float(i * 52)
		draw_line(Vector2(x, 423), Vector2(x + 30, 423), Color("#23353f"))


func draw_stage() -> void:
	var elapsed := 0.59 - impact_time
	var shake := Vector2(sin(elapsed * 180.0), cos(elapsed * 141.0))
	shake *= float(SHAKE[impact_kind]) * maxf(1.0 - elapsed / 0.15, 0.0)
	stage.draw_set_transform(shake)
	draw_trail(player_trail, COOL)
	draw_trail(rival_trail, WARM)
	draw_fighter(player)
	draw_fighter(rival)
	if impact_time > 0.0:
		draw_impact(elapsed)
	stage.draw_set_transform(Vector2.ZERO)
	draw_hud()


func draw_trail(trail: Array[Vector2], tint: Color) -> void:
	for i in range(1, trail.size()):
		var strength := float(i) / trail.size()
		stage.draw_line(trail[i - 1], trail[i], Color(tint, strength * 0.45),
			strength * 6.0, true)


func draw_fighter(actor: Fighter) -> void:
	var fall := actor.fall()
	var hip := actor.hip()
	var shoulder := actor.shoulder()
	var head := actor.head()
	var hand := actor.world(actor.hand())
	if actor.state == Fighter.State.DOWN:
		hand = actor.world(actor.hand() + Vector2(actor.lean() * 0.48, fall * 0.55))
	var step := sin(actor.stride) * 25.0 * actor.step_weight
	var front := actor.world(Vector2(22 + step, -maxf(step * 0.35, 0.0)))
	var back := actor.world(Vector2(-23 - step, minf(step * 0.35, 0.0)))
	stage.draw_line(actor.world(Vector2(-34, 3)), actor.world(Vector2(34, 3)),
		Color("#0b121a"), 9.0, true)
	limb(hip, actor.world(Vector2(-17 - step * 0.5, -29 + fall * 0.25)), back,
		actor.ink.darkened(0.37), 6.0)
	limb(hip, actor.world(Vector2(14 + step * 0.5, -27 + fall * 0.28)), front, actor.ink, 6.0)
	stage.draw_line(hip, shoulder, actor.ink, 8.0, true)
	stage.draw_line(shoulder, head + Vector2(0, 11), actor.ink, 5.0, true)
	stage.draw_circle(head, 13.0, actor.ink, false, 4.0, true)
	var elbow := shoulder.lerp(hand, 0.52) + Vector2(-actor.facing * 11, 13)
	limb(shoulder, elbow, hand, actor.ink, 5.0)
	var edge := actor.blade()
	var blade_direction := (edge[1] - edge[0]).normalized()
	var normal := blade_direction.orthogonal()
	stage.draw_line(hand - blade_direction * 10, hand + blade_direction * 9,
		Color("#718189"), 6.0, true)
	stage.draw_line(hand + blade_direction * 9 - normal * 8,
		hand + blade_direction * 9 + normal * 8, POSTURE, 3.0, true)
	var blade_base := hand + blade_direction * 9
	var tip := hand + blade_direction * Fighter.BLADE_LENGTH
	stage.draw_colored_polygon(PackedVector2Array([blade_base - normal * 2,
		blade_base + normal * 3, tip - blade_direction * 10 + normal * 1.5, tip]),
		PAPER if actor.parry_left <= 0.0 else POSTURE)
	stage.draw_circle(hand, 4.5, actor.ink, true, -1, true)
	if debug:
		var body := actor.body()
		stage.draw_line(body[0], body[1], Color(0.9, 0.3, 0.3, 0.26),
			Combat.BODY_RADIUS * 2.0, true)
		stage.draw_circle(body[0], Combat.BODY_RADIUS, Color("#f08383"), false, 1.0, true)
		stage.draw_circle(body[1], Combat.BODY_RADIUS, Color("#f08383"), false, 1.0, true)
		stage.draw_line(edge[0], edge[1], Color("#7cfa77") if actor.active()
			or actor.state == Fighter.State.GUARD else MUTED, 2.0, true)


func limb(a: Vector2, b: Vector2, c: Vector2, tint: Color, width: float) -> void:
	stage.draw_polyline(PackedVector2Array([a, b, c]), tint, width, true)
	stage.draw_circle(b, width * 0.5, tint, true, -1, true)


func draw_impact(elapsed: float) -> void:
	var tint := POSTURE if impact_kind >= Combat.Kind.PARRY else PAPER
	if impact_kind == Combat.Kind.HIT:
		tint = Color("#fa8f80")
	var fade := maxf(1.0 - elapsed / 0.32, 0.0)
	var count := 14 if impact_kind >= Combat.Kind.PARRY else 7
	for i in range(count):
		var ray := Vector2.from_angle(i * TAU / count + 0.19)
		var travel := (73.0 + (i % 4) * 34.0) * elapsed
		stage.draw_line(impact_at + ray * travel,
			impact_at + ray * (travel + (9.0 + (i % 3) * 7.0) * fade),
			Color(tint, fade), 1.0 + fade, true)
	if impact_kind >= Combat.Kind.PARRY and elapsed < 0.23:
		stage.draw_arc(impact_at, 8.0 + elapsed * 165.0, 0, TAU, 36,
			Color(tint, fade * 0.55), 1.5, true)
	if elapsed < 0.13:
		stage.draw_circle(impact_at, 4.5, Color(tint, fade), true, -1, true)
	caption(MESSAGES[impact_kind], Vector2(impact_at.x - 78, impact_at.y - 25 - elapsed * 24),
		18, Color(tint, minf(impact_time * 4, 1.0)), 156)


func caption(value: String, at: Vector2, size: int, color: Color, centered := -1) -> void:
	var alignment := HORIZONTAL_ALIGNMENT_CENTER if centered > 0 else HORIZONTAL_ALIGNMENT_LEFT
	stage.draw_string(ui_font, at, value, alignment, centered, size, color)


func draw_hud() -> void:
	caption("BLADE ECHO  /  对练场", Vector2(360, 55), 13, MUTED, 280)
	draw_bars(player, 49, "你")
	draw_bars(rival, 711, "对手")
	var prompt := "看对手举刀，等刀落下时按 K"
	if not started:
		prompt = "按移动、攻击或防御键开始"
	elif rival.health <= 0.0:
		prompt = "对练胜利   /   按 R 再战"
	elif player.health <= 0.0:
		prompt = "对练结束   /   按 R 再战"
	elif rival.state == Fighter.State.GUARD:
		prompt = "对手架刀了 · 留意还击"
	elif rival.state == Fighter.State.SWING and rival.short_cut:
		prompt = "对手短斩 · 看准时机按 K"
	caption(prompt, Vector2(130, 468), 21, PAPER, 740)
	caption("A / D  移动     J  挥刀     K  按住格挡 · 临撞按下弹反     R  重置     F1  调试",
		Vector2(40, 512), 16, MUTED, 920)
	if debug:
		var states := ["待机", "防御", "挥刀", "回弹", "硬直", "倒地"]
		caption("%s  |  弹反 %d ms  |  对手 %s" % [states[player.state],
			roundi(player.parry_left * 1000), states[rival.state]],
			Vector2(100, 543), 13, POSTURE, 800)


func draw_bars(actor: Fighter, x: float, label: String) -> void:
	caption(label, Vector2(x, 45), 17, actor.ink)
	caption("%03d" % roundi(actor.health), Vector2(x + 195, 45), 14, PAPER, 45)
	stage.draw_rect(Rect2(x, 57, 240, 7), Color("#2c3d48"))
	stage.draw_rect(Rect2(x, 57, 240 * actor.health / 100.0, 7), actor.ink)
	stage.draw_rect(Rect2(x, 71, 240, 4), Color("#2c3d48"))
	stage.draw_rect(Rect2(x, 71, 240 * actor.posture / 100.0, 4), POSTURE)
