extends Node3D
## 可愛動物顧客：進店 → 逛貨架 → 結帳 → 開心離開

const Art = preload("res://art.gd")

var main
var model: Node3D
var pivot: Node3D
var bubble: Label3D
var waypoints: Array = []
var tail: Array = []          # 網格路徑之後接著走的額外點（例如門外）
var state := "enter"
var phase := 0
var timer := 0.0
var speed := 1.5
var walk_t := 0.0
var target_id := -1
var goal_cell := Vector2i(-1, -1)
var bought := ""
var look_pos := Vector3.ZERO
var has_look := false


func setup(m, species: String, start: Vector3) -> void:
	main = m
	position = start
	model = Art.build_animal(species, Art.pastel())
	model.scale = Vector3.ONE * 1.25
	add_child(model)
	pivot = model.get_node("Pivot")
	bubble = Label3D.new()
	bubble.font = main.font
	bubble.font_size = 72
	bubble.pixel_size = 0.005
	bubble.outline_size = 20
	bubble.modulate = Color("#6b4a3a")
	bubble.outline_modulate = Color.WHITE
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.render_priority = 10
	bubble.outline_render_priority = 9
	bubble.position = Vector3(0, 1.45, 0)
	bubble.visible = false
	add_child(bubble)
	speed = randf_range(1.3, 1.8)
	walk_t = randf() * 10.0
	goal_cell = main.entrance.pick_random()
	waypoints = [main.cell_to_world(goal_cell)]
	state = "enter"


func _process(dt: float) -> void:
	if waypoints.size() > 0:
		var tgt: Vector3 = waypoints[0]
		var d := tgt - position
		d.y = 0.0
		var step := speed * dt
		if d.length() <= step:
			position = Vector3(tgt.x, 0.0, tgt.z)
			waypoints.pop_front()
			if waypoints.is_empty():
				_arrive()
		else:
			position += d.normalized() * step
			_turn_to(d, dt)
		walk_t += dt
		pivot.position.y = absf(sin(walk_t * 10.0)) * 0.08
		pivot.rotation.z = sin(walk_t * 10.0) * 0.1
		pivot.scale = Vector3.ONE
	else:
		pivot.position.y = lerpf(pivot.position.y, 0.0, minf(1.0, dt * 10.0))
		pivot.rotation.z = lerpf(pivot.rotation.z, 0.0, minf(1.0, dt * 10.0))
		var br := sin(walk_t * 4.0) * 0.03
		walk_t += dt
		pivot.scale = Vector3(1.0 - br * 0.5, 1.0 + br, 1.0 - br * 0.5)
		if has_look:
			_turn_to(look_pos - position, dt)
	if timer > 0.0:
		timer -= dt
		if timer <= 0.0:
			_next_phase()


func _turn_to(d: Vector3, dt: float) -> void:
	d.y = 0.0
	if d.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), minf(1.0, dt * 10.0))


func _arrive() -> void:
	match state:
		"enter":
			_go_shelf()
		"to_shelf":
			state = "browse"
			phase = 0
			timer = 1.3
			_say("?")
			if main.furniture.has(target_id):
				look_pos = main.furniture[target_id]["node"].position
				has_look = true
		"to_counter":
			state = "pay"
			timer = 1.0
			look_pos = main.clerk.global_position
			has_look = true
			_say("結帳～")
		"leave":
			main.customer_left(self)


func _next_phase() -> void:
	match state:
		"browse":
			if phase == 0:
				phase = 1
				timer = 1.2
				if main.furniture.has(target_id):
					var t: String = main.furniture[target_id]["type"]
					bought = t
					_say("♥ " + main.defs[t]["item"])
					_hop()
				else:
					_say("咦？")
			else:
				_hide_bubble()
				if bought != "":
					_go_counter()
				else:
					_go_leave()
		"pay":
			main.pay(self, bought)
			_say("謝謝♪")
			_hop()
			state = "paid"
			timer = 0.9
		"paid", "sad":
			_hide_bubble()
			_go_leave()


func _set_path(p: Array) -> void:
	waypoints = p + tail
	if waypoints.size() > 0:
		var first: Vector3 = waypoints[0]
		if Vector2(first.x - position.x, first.z - position.z).length() < 0.05:
			waypoints.pop_front()
	if waypoints.is_empty():
		_arrive.call_deferred()


func _cur_cell() -> Vector2i:
	return main.clamp_cell(main.world_to_cell(position))


func _go_shelf() -> void:
	var ids: Array = main.product_ids()
	ids.shuffle()
	var cur := _cur_cell()
	for id in ids:
		var cells: Array = main.access_cells(id)
		cells.shuffle()
		for c in cells:
			var p: Array = main.path_world(cur, c)
			if p.size() > 0:
				target_id = id
				goal_cell = c
				tail = []
				has_look = false
				state = "to_shelf"
				_set_path(p)
				return
	_say("…")
	state = "sad"
	timer = 1.2


func _go_counter() -> void:
	var spots: Array = main.counter_spots.duplicate()
	spots.shuffle()
	var cur := _cur_cell()
	for s in spots:
		var p: Array = main.path_world(cur, s)
		if p.size() > 0:
			goal_cell = s
			tail = []
			has_look = false
			state = "to_counter"
			_set_path(p)
			return
	_go_leave()


func _go_leave() -> void:
	has_look = false
	state = "leave"
	goal_cell = main.entrance.pick_random()
	var door: Vector3 = main.cell_to_world(goal_cell)
	tail = [door + Vector3(0, 0, 1.2), Vector3(randf_range(-0.6, 0.6), 0, main.store_d / 2.0 + 5.0)]
	var p: Array = main.path_world(_cur_cell(), goal_cell)
	if p.is_empty():
		p = [door]
	_set_path(p)


## 版面改變（擺放/收起家具）時重新規劃路線
func on_layout_changed() -> void:
	match state:
		"to_shelf":
			if not main.furniture.has(target_id) or not main.access_cells(target_id).has(goal_cell):
				_go_shelf()
				return
			_repath()
		"to_counter":
			_repath()
		"leave":
			if position.z < main.store_d / 2.0:
				_repath()


func _repath() -> void:
	var p: Array = main.path_world(_cur_cell(), goal_cell)
	if p.size() > 0:
		_set_path(p)


## 擺放時不能壓到顧客站的格子
func blocks_any(cells: Array) -> bool:
	var mine := [main.world_to_cell(position)]
	if waypoints.size() > 0:
		mine.append(main.world_to_cell(waypoints[0]))
	for c in mine:
		if cells.has(c):
			return true
	return false


func _say(text: String) -> void:
	bubble.text = text
	bubble.visible = true
	bubble.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(bubble, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_bubble() -> void:
	bubble.visible = false


func _hop() -> void:
	var tw := create_tween()
	tw.tween_property(model, "position:y", 0.25, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(model, "position:y", 0.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
