extends Node3D
## 小森便利店：網格擺貨架的療癒小 Demo
## 左鍵擺放 / R 旋轉 / 右鍵取消或收起 / 點擊家具搬動 / 滾輪縮放

const Art = preload("res://art.gd")
const CustomerScript = preload("res://customer.gd")

const W := 10
const D := 8

var store_d := D
var defs := {
	"snack":    {"name": "零食架",   "size": Vector2i(2, 1), "price": 80,  "income": 18, "item": "餅乾",   "color": Color("#f7b9c4")},
	"drink":    {"name": "飲料冰箱", "size": Vector2i(1, 1), "price": 100, "income": 15, "item": "果汁",   "color": Color("#8fd3c7")},
	"fruit":    {"name": "水果攤",   "size": Vector2i(2, 1), "price": 60,  "income": 12, "item": "蘋果",   "color": Color("#ff9aa2")},
	"bread":    {"name": "麵包架",   "size": Vector2i(1, 1), "price": 50,  "income": 10, "item": "甜甜圈", "color": Color("#e8b86d")},
	"icecream": {"name": "冰淇淋櫃", "size": Vector2i(2, 1), "price": 90,  "income": 20, "item": "冰淇淋", "color": Color("#c7ceea")},
	"plant":    {"name": "盆栽",     "size": Vector2i(1, 1), "price": 20,  "income": 0,  "item": "",       "color": Color("#7ccf8a")},
	"counter":  {"name": "收銀台",   "size": Vector2i(2, 1), "price": 0,   "income": 0,  "item": "",       "color": Color("#ffd6a5"), "fixed": true},
}
var hotbar := ["snack", "drink", "fruit", "bread", "icecream", "plant"]
var entrance := [Vector2i(4, 7), Vector2i(5, 7)]
var counter_spots := [Vector2i(7, 2), Vector2i(7, 3)]
var clerk_cells := [Vector2i(9, 2), Vector2i(9, 3)]
var no_build := {}

var coins := 0
var served := 0
var furniture := {}      # id -> {id, type, anchor, rot, node, cells}
var occ := {}            # Vector2i -> id
var next_id := 1
var astar: AStarGrid2D
var customers: Array = []

var cam: Camera3D
var furn_root: Node3D
var clerk: Node3D
var font: FontFile

var held_type := ""
var held_rot := 0
var held_anchor := Vector2i.ZERO
var held_move := {}
var held_ok := false
var ghost: Node3D
var ghost_tint := -1
var check_key := ""
var hover_cell := Vector2i(-99, -99)
var hover_pad: MeshInstance3D
var pad_mats := {}
var ghost_mats := []
var time := 0.0
var spawn_timer := 1.5

var ui_coins: Label
var ui_served: Label
var ui_cute: Label
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var buttons := {}
var btn_group := ButtonGroup.new()

var shot_path := ""
var shot_stage := 0


func _ready() -> void:
	randomize()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
	# 內附 Noto Sans TC 子集字型（網頁版沒有系統字型可用）
	# 新增中文文字後請重新產生字型子集
	font = load("res://fonts/NotoSansTC-Bold.woff2")
	font.allow_system_fallback = false
	for c in entrance + counter_spots + clerk_cells:
		no_build[c] = true

	_build_env()
	_build_store()
	furn_root = Node3D.new()
	add_child(furn_root)
	_build_pads()
	_build_ui()

	# 起始店面
	add_furniture("counter", Vector2i(8, 2), 3, false)
	add_furniture("snack", Vector2i(1, 1), 0, false)
	add_furniture("bread", Vector2i(4, 1), 0, false)
	add_furniture("drink", Vector2i(0, 3), 1, false)
	add_furniture("drink", Vector2i(0, 4), 1, false)
	add_furniture("fruit", Vector2i(3, 4), 0, false)
	add_furniture("plant", Vector2i(0, 7), 0, false)
	add_furniture("plant", Vector2i(9, 7), 0, false)
	add_furniture("plant", Vector2i(9, 0), 0, false)
	_build_clerk()
	coins = 300
	_refresh_ui()
	if shot_path != "":
		spawn_timer = 0.2


# ================================================================ 座標工具

func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x - W / 2.0 + 0.5, 0.0, c.y - D / 2.0 + 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x + W / 2.0), floori(p.z + D / 2.0))


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < D


func clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, W - 1), clampi(c.y, 0, D - 1))


func fsize(type: String, rot: int) -> Vector2i:
	var s: Vector2i = defs[type]["size"]
	return s if rot % 2 == 0 else Vector2i(s.y, s.x)


func footprint(anchor: Vector2i, fs: Vector2i) -> Array:
	var res := []
	for x in fs.x:
		for y in fs.y:
			res.append(anchor + Vector2i(x, y))
	return res


func footprint_center(anchor: Vector2i, fs: Vector2i) -> Vector3:
	return cell_to_world(anchor) + Vector3((fs.x - 1) * 0.5, 0.0, (fs.y - 1) * 0.5)


func mouse_cell(mp: Vector2) -> Vector2i:
	var o := cam.project_ray_origin(mp)
	var n := cam.project_ray_normal(mp)
	if absf(n.y) < 0.0001:
		return Vector2i(-99, -99)
	var hit := o + n * (-o.y / n.y)
	return world_to_cell(hit)


# ================================================================ 尋路

func build_astar(extra: Array = []) -> AStarGrid2D:
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, W, D)
	a.cell_size = Vector2(1, 1)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	a.update()
	for c in occ.keys():
		a.set_point_solid(c, true)
	for c in clerk_cells + extra:
		a.set_point_solid(c, true)
	return a


func path_world(from: Vector2i, to: Vector2i) -> Array:
	from = clamp_cell(from)
	if not in_bounds(to) or astar.is_point_solid(to) or astar.is_point_solid(from):
		return []
	var out := []
	for c in astar.get_id_path(from, to):
		out.append(cell_to_world(c))
	return out


func product_ids() -> Array:
	var res := []
	for id in furniture:
		if defs[furniture[id]["type"]]["income"] > 0:
			res.append(id)
	return res


func access_cells(id: int) -> Array:
	var res := []
	if not furniture.has(id):
		return res
	for c in furniture[id]["cells"]:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if in_bounds(n) and not occ.has(n) and not clerk_cells.has(n) and not res.has(n):
				res.append(n)
	return res


# ================================================================ 擺放

func can_place(type: String, anchor: Vector2i, rot: int) -> bool:
	var cells := footprint(anchor, fsize(type, rot))
	for c in cells:
		if not in_bounds(c) or occ.has(c) or no_build.has(c):
			return false
	for cu in customers:
		if cu.blocks_any(cells):
			return false
	# 保證從門口一定走得到收銀台
	var a := build_astar(cells)
	for s in counter_spots:
		if a.get_id_path(entrance[0], s).size() > 0:
			return true
	return false


func add_furniture(type: String, anchor: Vector2i, rot: int, pop: bool) -> int:
	var fs := fsize(type, rot)
	var node := Art.build_furniture(type)
	node.position = footprint_center(anchor, fs)
	node.rotation.y = rot * PI / 2.0
	furn_root.add_child(node)
	var id := next_id
	next_id += 1
	var cells := footprint(anchor, fs)
	furniture[id] = {"id": id, "type": type, "anchor": anchor, "rot": rot, "node": node, "cells": cells}
	for c in cells:
		occ[c] = id
	if pop:
		node.scale = Vector3(1.3, 0.5, 1.3)
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_sparkle(node.position + Vector3(0, 0.5, 0))
	_layout_changed()
	return id


func remove_furniture(id: int, anim: bool) -> void:
	var f: Dictionary = furniture[id]
	for c in f["cells"]:
		occ.erase(c)
	furniture.erase(id)
	var node: Node3D = f["node"]
	if anim:
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector3(0.01, 0.01, 0.01), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(node.queue_free)
	else:
		node.queue_free()
	_layout_changed()


func _layout_changed() -> void:
	astar = build_astar()
	check_key = ""
	for c in customers:
		c.on_layout_changed()
	_refresh_ui()


func _hold(type: String, rot: int) -> void:
	_free_ghost()
	held_type = type
	held_rot = rot
	ghost = Art.build_furniture(type)
	add_child(ghost)
	ghost.rotation.y = rot * PI / 2.0
	var fs := fsize(type, rot)
	ghost.position = footprint_center(hover_cell - Vector2i((fs.x - 1) / 2, (fs.y - 1) / 2), fs) + Vector3(0, 0.15, 0)
	ghost_tint = -1
	check_key = ""


func _free_ghost() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null


func _clear_held() -> void:
	_free_ghost()
	held_type = ""
	held_move = {}
	for t in buttons:
		buttons[t].set_pressed_no_signal(false)


func _cancel_held() -> void:
	if not held_move.is_empty():
		add_furniture(held_move["type"], held_move["anchor"], held_move["rot"], true)
	_clear_held()


func _tint_ghost(node: Node, m: Material) -> void:
	for ch in node.get_children():
		if ch is MeshInstance3D:
			ch.material_override = m
		_tint_ghost(ch, m)


func _on_left() -> void:
	if held_type != "":
		if not held_ok:
			toast("這裡放不下喔～")
			return
		if held_move.is_empty():
			var price: int = defs[held_type]["price"]
			if coins < price:
				toast("金幣不夠了… 等顧客來買東西吧！")
				return
			coins -= price
			add_furniture(held_type, held_anchor, held_rot, true)
			popup_text("-%d" % price, footprint_center(held_anchor, fsize(held_type, held_rot)) + Vector3(0, 1.6, 0), Color("#e07a8f"))
		else:
			add_furniture(held_type, held_anchor, held_rot, true)
			_clear_held()
		_refresh_ui()
	elif occ.has(hover_cell):
		var f: Dictionary = furniture[occ[hover_cell]]
		if defs[f["type"]].has("fixed"):
			toast("收銀台要留給店長喔！")
			return
		held_move = {"type": f["type"], "anchor": f["anchor"], "rot": f["rot"]}
		var t: String = f["type"]
		var r: int = f["rot"]
		remove_furniture(f["id"], false)
		for b in buttons:
			buttons[b].set_pressed_no_signal(false)
		_hold(t, r)


func _on_right() -> void:
	if held_type != "":
		_cancel_held()
	elif occ.has(hover_cell):
		var f: Dictionary = furniture[occ[hover_cell]]
		if defs[f["type"]].has("fixed"):
			return
		var price: int = defs[f["type"]]["price"]
		coins += price
		toast("收起了%s，退回 %d 金幣" % [defs[f["type"]]["name"], price])
		remove_furniture(f["id"], true)
		_refresh_ui()


func _on_hotbar(on: bool, type: String) -> void:
	if on:
		if not held_move.is_empty():
			add_furniture(held_move["type"], held_move["anchor"], held_move["rot"], false)
			held_move = {}
		_hold(type, 0)
	elif held_type == type and held_move.is_empty():
		_clear_held()


func _unhandled_input(e: InputEvent) -> void:
	if shot_path != "":
		return
	var mb := e as InputEventMouseButton
	if mb and mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_LEFT: _on_left()
			MOUSE_BUTTON_RIGHT: _on_right()
			MOUSE_BUTTON_WHEEL_UP: cam.fov = clampf(cam.fov - 2.0, 22.0, 50.0)
			MOUSE_BUTTON_WHEEL_DOWN: cam.fov = clampf(cam.fov + 2.0, 22.0, 50.0)
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_R and held_type != "":
			held_rot = (held_rot + 1) % 4
			check_key = ""
		elif k.keycode == KEY_ESCAPE:
			_cancel_held()
		elif k.keycode >= KEY_1 and k.keycode < KEY_1 + hotbar.size():
			var b: Button = buttons[hotbar[k.keycode - KEY_1]]
			b.button_pressed = not b.button_pressed


# ================================================================ 每幀

func _process(dt: float) -> void:
	time += dt
	if shot_path == "":
		hover_cell = mouse_cell(get_viewport().get_mouse_position())
	_update_ghost(dt)

	# 店長待機呼吸
	if clerk:
		var br := sin(time * 3.0) * 0.03
		clerk.get_node("Model/Pivot").scale = Vector3(1.0 - br * 0.5, 1.0 + br, 1.0 - br * 0.5)

	spawn_timer -= dt
	if spawn_timer <= 0.0:
		spawn_timer = randf_range(2.0, 3.0) if shot_path != "" else randf_range(3.5, 6.5)
		if customers.size() < 5 and product_ids().size() > 0:
			spawn_customer()

	if shot_path != "":
		_shot_logic()


func _update_ghost(dt: float) -> void:
	if held_type == "":
		if in_bounds(hover_cell):
			hover_pad.visible = true
			if occ.has(hover_cell):
				var f: Dictionary = furniture[occ[hover_cell]]
				_set_pad(f["anchor"], fsize(f["type"], f["rot"]), "pick")
			else:
				_set_pad(hover_cell, Vector2i.ONE, "hover")
		else:
			hover_pad.visible = false
		return
	var fs := fsize(held_type, held_rot)
	held_anchor = hover_cell - Vector2i((fs.x - 1) / 2, (fs.y - 1) / 2)
	var key := "%s|%s|%d" % [held_type, held_anchor, held_rot]
	if key != check_key:
		check_key = key
		held_ok = can_place(held_type, held_anchor, held_rot)
	ghost.visible = in_bounds(hover_cell)
	hover_pad.visible = ghost.visible
	var target := footprint_center(held_anchor, fs) + Vector3(0, 0.18 + sin(time * 4.0) * 0.05, 0)
	ghost.position = ghost.position.lerp(target, minf(1.0, dt * 18.0))
	ghost.rotation.y = lerp_angle(ghost.rotation.y, held_rot * PI / 2.0, minf(1.0, dt * 14.0))
	var tint := 1 if held_ok else 0
	if tint != ghost_tint:
		ghost_tint = tint
		_tint_ghost(ghost, ghost_mats[tint])
	_set_pad(held_anchor, fs, "ok" if held_ok else "bad")


func _set_pad(anchor: Vector2i, fs: Vector2i, kind: String) -> void:
	hover_pad.position = footprint_center(anchor, fs) + Vector3(0, 0.02, 0)
	hover_pad.scale = Vector3(fs.x - 0.06, 1.0, fs.y - 0.06)
	hover_pad.material_override = pad_mats[kind]


# ================================================================ 顧客

func spawn_customer() -> void:
	var c = CustomerScript.new()
	add_child(c)
	c.setup(self, Art.SPECIES.pick_random(), Vector3(randf_range(-0.5, 0.5), 0, D / 2.0 + 5.0))
	customers.append(c)


func customer_left(c) -> void:
	customers.erase(c)
	c.queue_free()


func pay(c, type: String) -> void:
	var plants := 0
	for id in furniture:
		if furniture[id]["type"] == "plant":
			plants += 1
	var income: int = defs[type]["income"] + plants * 2
	coins += income
	served += 1
	popup_text("+%d 金幣" % income, c.position + Vector3(0, 1.5, 0), Color("#e8a317"))
	var tw := create_tween()
	tw.tween_property(clerk, "position:y", 0.25, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(clerk, "position:y", 0.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	_refresh_ui()


# ================================================================ 特效

func popup_text(text: String, pos: Vector3, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 60
	l.pixel_size = 0.005
	l.outline_size = 16
	l.modulate = color
	l.outline_modulate = Color.WHITE
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 12
	l.outline_render_priority = 11
	l.position = pos
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", pos.y + 0.9, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.6)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)


func _sparkle(pos: Vector3) -> void:
	for i in 10:
		var s := Node3D.new()
		add_child(s)
		s.position = pos
		Art.sphere(s, 0.06, Art.pastel(), Vector3.ZERO, 0.0)
		var ang := TAU * i / 10.0
		var to := pos + Vector3(cos(ang) * 0.9, randf_range(0.3, 1.0), sin(ang) * 0.9)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(s, "position", to, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(s, "scale", Vector3(0.01, 0.01, 0.01), 0.6).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(s.queue_free)


# ================================================================ 場景

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#ffe9d9")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff0e6")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = true
	env.ssao_intensity = 1.2
	env.ssao_radius = 0.6
	# 相容渲染器（網頁版）打光明顯偏亮，降低光量並關閉霧，讓兩邊看起來一致
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var light_scale := 0.55 if compat else 1.0
	env.ambient_light_energy *= light_scale
	env.fog_enabled = not compat
	env.fog_light_color = Color("#ffe9d9")
	env.fog_density = 0.008
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_color = Color("#fff4e2")
	sun.light_energy = 0.75 * light_scale
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.position = Vector3(0, 11.0, 12.0)
	cam.look_at(Vector3(0, 0.3, 0.2))


func _build_store() -> void:
	var env := Node3D.new()
	add_child(env)
	var hd := D / 2.0
	var hw := W / 2.0

	# 草地與石板路
	Art.box(env, Vector3(70, 0.2, 70), Color("#b8e0a0"), Vector3(0, -0.2, 0), 0.0)
	for i in 7:
		Art.cyl(env, 0.36, 0.36, 0.05, Color("#f6ead8"), Vector3(randf_range(-0.12, 0.12), -0.08, hd + 1.0 + i * 0.85), 0.015)
	Art.box(env, Vector3(1.8, 0.03, 0.7), Color("#ffb3c1"), Vector3(0, -0.08, hd + 0.45), 0.015)

	# 地板（格子）
	Art.box(env, Vector3(W + 0.4, 0.12, D + 0.4), Color("#d8b48c"), Vector3(0, -0.07, 0), 0.0)
	var tile_a := Color("#fff4e0")
	var tile_b := Color("#f8e3c8")
	for x in W:
		for z in D:
			var c := cell_to_world(Vector2i(x, z))
			Art.box(env, Vector3(0.96, 0.06, 0.96), tile_a if (x + z) % 2 == 0 else tile_b, c + Vector3(0, -0.03, 0), 0.0)

	# 牆壁
	var wall := Color("#fde6bb")
	var mint := Color("#b8e0d2")
	Art.box(env, Vector3(W + 0.4, 2.6, 0.2), wall, Vector3(0, 1.3, -hd - 0.1))
	Art.box(env, Vector3(W + 0.4, 0.9, 0.24), mint, Vector3(0, 0.45, -hd - 0.1), 0.02)
	for sx in [-1.0, 1.0]:
		Art.box(env, Vector3(0.2, 2.6, D + 0.4), wall, Vector3(sx * (hw + 0.1), 1.3, 0))
		Art.box(env, Vector3(0.24, 0.9, D + 0.4), mint, Vector3(sx * (hw + 0.1), 0.45, 0), 0.02)
		Art.box(env, Vector3(hw - 1.0 + 0.2, 0.5, 0.2), wall, Vector3(sx * (1.0 + (hw - 1.0 + 0.2) / 2.0), 0.25, hd + 0.1))

	# 窗戶與窗簾
	for wx in [-2.6]:
		Art.box(env, Vector3(2.1, 1.2, 0.06), Color.WHITE, Vector3(wx, 1.65, -hd + 0.01), 0.02)
		Art.box(env, Vector3(1.9, 1.0, 0.07), Color("#cdeefd"), Vector3(wx, 1.65, -hd + 0.02), 0.0)
		Art.box(env, Vector3(0.06, 1.0, 0.09), Color.WHITE, Vector3(wx, 1.65, -hd + 0.03), 0.0)
		Art.box(env, Vector3(1.9, 0.06, 0.09), Color.WHITE, Vector3(wx, 1.65, -hd + 0.03), 0.0)
		for cx in [-1.05, 1.05]:
			Art.box(env, Vector3(0.35, 1.3, 0.08), Color("#ffb3c1"), Vector3(wx + cx, 1.62, -hd + 0.06), 0.02)
	# 時鐘
	var clock := Art.cyl(env, 0.32, 0.32, 0.06, Color("#fffaf0"), Vector3(1.6, 1.85, -hd + 0.04), 0.025)
	clock.rotation.x = PI / 2
	Art.box(env, Vector3(0.04, 0.2, 0.02), Color("#6b4a3a"), Vector3(1.6, 1.93, -hd + 0.08), 0.0)
	var hand := Art.box(env, Vector3(0.04, 0.15, 0.02), Color("#6b4a3a"), Vector3(1.65, 1.82, -hd + 0.08), 0.0)
	hand.rotation.z = 2.2
	# 招牌
	Art.box(env, Vector3(4.4, 0.85, 0.16), Color("#ff9fb4"), Vector3(0, 3.0, -hd - 0.1))
	var sign_label := Label3D.new()
	sign_label.text = "小森便利店"
	sign_label.font = font
	sign_label.font_size = 120
	sign_label.pixel_size = 0.0055
	sign_label.outline_size = 24
	sign_label.modulate = Color.WHITE
	sign_label.outline_modulate = Color("#c96a80")
	sign_label.position = Vector3(0, 3.0, -hd + 0.0)
	env.add_child(sign_label)
	for sx in [-1.0, 1.0]:
		Art.sphere(env, 0.13, Color("#fff1a8"), Vector3(sx * 1.9, 3.0, -hd + 0.0), 0.02)

	# 戶外樹木與小花
	for tp in [Vector3(-8, 0, -2.5), Vector3(8.5, 0, 0.5), Vector3(-7.5, 0, 4.5), Vector3(7.2, 0, -4.8),
			Vector3(-9.5, 0, -7), Vector3(9.5, 0, 5.5), Vector3(-4, 0, -7.5), Vector3(4.5, 0, -7.8)]:
		_tree(env, tp)
	for i in 60:
		var p := Vector3(randf_range(-12, 12), -0.05, randf_range(-9, 10))
		if absf(p.x) < hw + 0.8 and p.z < hd + 0.8:
			continue
		if absf(p.x) < 1.0 and p.z > hd:
			continue
		Art.sphere(env, 0.07, Art.pastel(), p, 0.012)
		Art.sphere(env, 0.03, Color("#fff8d0"), p + Vector3(0, 0.05, 0), 0.0)


func _tree(parent: Node3D, p: Vector3) -> void:
	Art.cyl(parent, 0.12, 0.17, 1.1, Color("#b07b55"), p + Vector3(0, 0.45, 0), 0.025)
	Art.sphere(parent, 0.85, Color("#8fd18a"), p + Vector3(0, 1.55, 0), 0.03)
	Art.sphere(parent, 0.6, Color("#7cc47a"), p + Vector3(-0.5, 1.25, 0.25), 0.03)
	Art.sphere(parent, 0.55, Color("#a3dc95"), p + Vector3(0.45, 1.35, 0.2), 0.03)
	if randf() < 0.6:
		for k in 3:
			Art.sphere(parent, 0.08, Color("#ff8a8a"), p + Vector3(randf_range(-0.5, 0.5), randf_range(1.3, 1.9), 0.75), 0.012)


func _build_clerk() -> void:
	clerk = Node3D.new()
	add_child(clerk)
	clerk.position = Vector3(cell_to_world(Vector2i(9, 2)).x, 0, (cell_to_world(Vector2i(9, 2)).z + cell_to_world(Vector2i(9, 3)).z) / 2.0)
	var model := Art.build_animal("panda", Color("#8fd3c7"))
	model.name = "Model"
	clerk.add_child(model)
	clerk.rotation.y = -PI / 2.0
	var piv: Node3D = model.get_node("Pivot")
	Art.box(piv, Vector3(0.3, 0.26, 0.05), Color("#8fd3c7"), Vector3(0, 0.24, 0.2), 0.012)
	var head: Node3D = model.get_node("Pivot/Head")
	Art.cyl(head, 0.2, 0.22, 0.08, Color("#8fd3c7"), Vector3(0, 0.2, 0), 0.015)
	Art.box(head, Vector3(0.36, 0.03, 0.18), Color("#8fd3c7"), Vector3(0, 0.17, 0.18), 0.012)
	var tag := Label3D.new()
	tag.text = "店長"
	tag.font = font
	tag.font_size = 44
	tag.pixel_size = 0.005
	tag.outline_size = 12
	tag.modulate = Color("#6b4a3a")
	tag.outline_modulate = Color.WHITE
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 1.25, 0)
	clerk.add_child(tag)


func _build_pads() -> void:
	var m := BoxMesh.new()
	m.size = Vector3(1, 0.02, 1)
	hover_pad = MeshInstance3D.new()
	hover_pad.mesh = m
	hover_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hover_pad)
	for k in [["hover", Color(1, 1, 1, 0.55)], ["pick", Color(1, 0.85, 0.4, 0.6)],
			["ok", Color(0.55, 0.95, 0.6, 0.6)], ["bad", Color(1, 0.5, 0.5, 0.6)]]:
		pad_mats[k[0]] = _flat_mat(k[1])
	ghost_mats = [_flat_mat(Color(1, 0.55, 0.55, 0.55)), _flat_mat(Color(0.6, 1, 0.7, 0.55))]


func _flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# ================================================================ UI

func _sbox(bg: Color, border: Color, radius: int = 18, bw: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0.45, 0.28, 0.2, 0.18)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


func _icon(c: Color) -> ImageTexture:
	var sz := 36
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(sz / 2.0, sz / 2.0)
	for x in sz:
		for y in sz:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(ctr)
			if d < 15.5:
				var col := c
				if d > 13.0:
					col = c.darkened(0.3)
				elif Vector2(x, y).distance_to(ctr - Vector2(5, 5)) < 4.0:
					col = c.lightened(0.6)
				img.set_pixel(x, y, col)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", Color("#6b4a3a"))
	root.theme = theme
	layer.add_child(root)

	var brown := Color("#d9a982")
	var cream := Color("#fff8ec")

	# 左上：店鋪資訊
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _sbox(cream, brown))
	info.position = Vector2(16, 16)
	root.add_child(info)
	var v := VBoxContainer.new()
	info.add_child(v)
	var title := Label.new()
	title.text = "小森便利店"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#e07a8f"))
	v.add_child(title)
	ui_coins = Label.new()
	v.add_child(ui_coins)
	ui_served = Label.new()
	v.add_child(ui_served)
	ui_cute = Label.new()
	ui_cute.add_theme_font_size_override("font_size", 15)
	v.add_child(ui_cute)

	# 右上：操作說明
	var help := PanelContainer.new()
	help.add_theme_stylebox_override("panel", _sbox(cream, brown))
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.offset_left = -16
	help.offset_right = -16
	help.offset_top = 16
	root.add_child(help)
	var hl := Label.new()
	hl.text = "點下方貨架 → 左鍵擺放\nR 旋轉　右鍵 取消／收起\n點已擺的家具可以搬動\n滾輪 縮放鏡頭"
	hl.add_theme_font_size_override("font_size", 15)
	help.add_child(hl)

	# 下方：家具快捷列
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _sbox(Color("#fff3df"), brown, 24, 4))
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = -16
	bar.offset_bottom = -16
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	bar.add_child(hb)
	btn_group.allow_unpress = true
	var normal := _sbox(cream, Color("#e8c7a8"), 16, 3)
	var hover := _sbox(Color("#fff0f3"), Color("#f2a7b8"), 16, 3)
	var pressed := _sbox(Color("#ffd3de"), Color("#e07a8f"), 16, 4)
	for i in hotbar.size():
		var t: String = hotbar[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = btn_group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(104, 96)
		b.text = "%s\n%d 金幣" % [defs[t]["name"], defs[t]["price"]]
		b.icon = _icon(defs[t]["color"])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("hover_pressed", pressed)
		for cn in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(cn, Color("#6b4a3a"))
		b.toggled.connect(_on_hotbar.bind(t))
		b.tooltip_text = "快捷鍵 %d" % (i + 1)
		hb.add_child(b)
		buttons[t] = b

	# 上方中央：提示訊息
	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", _sbox(Color("#fff0f3"), Color("#f2a7b8"), 20, 3))
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.offset_top = 18
	toast_panel.offset_bottom = 18
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.modulate.a = 0.0
	root.add_child(toast_panel)
	toast_label = Label.new()
	toast_panel.add_child(toast_label)


func toast(msg: String) -> void:
	toast_label.text = msg
	if toast_tween:
		toast_tween.kill()
	toast_panel.modulate.a = 1.0
	toast_tween = create_tween()
	toast_tween.tween_interval(1.6)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.5)


func _refresh_ui() -> void:
	if ui_coins == null:
		return
	var plants := 0
	for id in furniture:
		if furniture[id]["type"] == "plant":
			plants += 1
	ui_coins.text = "金幣　%d" % coins
	ui_served.text = "來客　%d 位" % served
	ui_cute.text = "盆栽 %d 盆 → 每位顧客多給 %d 金幣" % [plants, plants * 2]


# ================================================================ 截圖模式（--shot=路徑）

func _shot_logic() -> void:
	if shot_stage == 0 and time > 0.5:
		shot_stage = 1
		buttons["icecream"].button_pressed = true
		hover_cell = Vector2i(6, 5)
	elif shot_stage == 1 and time > 6.0:
		shot_stage = 2
		get_viewport().get_texture().get_image().save_png(shot_path.replace(".png", "_1.png"))
	elif shot_stage == 2 and time > 6.3:
		shot_stage = 3
		_on_left()
		buttons["icecream"].button_pressed = false
		hover_cell = Vector2i(-99, -99)
	elif shot_stage == 3 and time > 15.0:
		shot_stage = 4
		get_viewport().get_texture().get_image().save_png(shot_path.replace(".png", "_2.png"))
		get_tree().quit()
