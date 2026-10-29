extends RefCounted
## 繪本風程序化模型：家具與動物都由基本形狀組成，再加上暖咖啡色描邊。

const OUTLINE_CODE := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 outline_color : source_color = vec4(0.38, 0.25, 0.21, 1.0);
uniform float width = 0.03;
void vertex() {
	float l = length(VERTEX);
	if (l > 0.0001) {
		VERTEX += VERTEX / l * width;
	}
}
void fragment() {
	ALBEDO = outline_color.rgb;
}
"""

const PASTEL_HEX := ["#ff9aa2", "#ffb7b2", "#ffdac1", "#e2f0cb", "#b5ead7",
	"#c7ceea", "#f6c3e5", "#fff1a8", "#a8d8ff", "#ffc8a2"]
const SPECIES := ["cat", "bear", "rabbit", "frog", "pig", "panda", "fox"]

static var _outline_shader: Shader = null
static var _mats := {}
static var _glass: StandardMaterial3D = null


static func pastel() -> Color:
	return Color(PASTEL_HEX.pick_random())


static func mat(c: Color, ol: float = 0.03) -> Material:
	var key := "%s_%.3f" % [c.to_html(), ol]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if ol > 0.0:
		if _outline_shader == null:
			_outline_shader = Shader.new()
			_outline_shader.code = OUTLINE_CODE
		var o := ShaderMaterial.new()
		o.shader = _outline_shader
		o.set_shader_parameter("width", ol)
		m.next_pass = o
	_mats[key] = m
	return m


static func add(p: Node3D, mesh: PrimitiveMesh, c: Color, pos: Vector3, ol: float) -> MeshInstance3D:
	mesh.material = mat(c, ol)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	p.add_child(mi)
	return mi


static func box(p: Node3D, size: Vector3, c: Color, pos: Vector3, ol: float = 0.03) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add(p, m, c, pos, ol)


static func sphere(p: Node3D, r: float, c: Color, pos: Vector3, ol: float = 0.03, h: float = -1.0) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 if h < 0.0 else h
	m.radial_segments = 24
	m.rings = 12
	return add(p, m, c, pos, ol)


static func cyl(p: Node3D, top: float, bottom: float, h: float, c: Color, pos: Vector3, ol: float = 0.03) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 20
	return add(p, m, c, pos, ol)


static func capsule(p: Node3D, r: float, h: float, c: Color, pos: Vector3, ol: float = 0.03) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return add(p, m, c, pos, ol)


static func torus(p: Node3D, inner: float, outer: float, c: Color, pos: Vector3, ol: float = 0.03) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	return add(p, m, c, pos, ol)


static func glass(p: Node3D, size: Vector3, pos: Vector3) -> MeshInstance3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.8, 0.94, 1.0, 0.28)
		_glass.roughness = 0.15
	var m := BoxMesh.new()
	m.size = size
	m.material = _glass
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return mi


# ---------------------------------------------------------------- 家具
# 每個家具模型以占地中心為原點、正面朝 +Z。

static func build_furniture(type: String) -> Node3D:
	match type:
		"snack": return _snack()
		"drink": return _drink()
		"fruit": return _fruit()
		"bread": return _bread()
		"icecream": return _icecream()
		"plant": return _plant()
		"counter": return _counter()
	return Node3D.new()


static func _snack() -> Node3D:
	var n := Node3D.new()
	var wood := Color("#eac79f")
	var pink := Color("#f7b9c4")
	box(n, Vector3(1.9, 0.14, 0.78), wood.darkened(0.12), Vector3(0, 0.07, 0))
	box(n, Vector3(1.9, 1.5, 0.08), pink, Vector3(0, 0.75, -0.35))
	for sx in [-0.91, 0.91]:
		box(n, Vector3(0.08, 1.5, 0.78), wood, Vector3(sx, 0.75, 0))
	box(n, Vector3(1.98, 0.1, 0.84), pink.darkened(0.1), Vector3(0, 1.53, 0))
	var rows := [0.14, 0.56, 0.98]
	for i in rows.size():
		var y: float = rows[i]
		if i > 0:
			box(n, Vector3(1.74, 0.05, 0.66), wood, Vector3(0, y - 0.025, -0.02), 0.02)
		var x := -0.72
		while x < 0.75:
			var h := randf_range(0.16, 0.3)
			box(n, Vector3(0.17, h, 0.15), pastel(), Vector3(x, y + h * 0.5, 0.1), 0.015)
			x += 0.24
	return n


static func _drink() -> Node3D:
	var n := Node3D.new()
	var body := Color("#d8f1ec")
	var trim := Color("#8fd3c7")
	box(n, Vector3(0.9, 1.8, 0.08), body, Vector3(0, 0.9, -0.36))
	for sx in [-0.41, 0.41]:
		box(n, Vector3(0.08, 1.8, 0.8), body, Vector3(sx, 0.9, 0))
	box(n, Vector3(0.92, 0.12, 0.82), trim, Vector3(0, 0.06, 0))
	box(n, Vector3(0.92, 0.2, 0.82), trim, Vector3(0, 1.85, 0))
	for y in [0.12, 0.58, 1.04]:
		if y > 0.2:
			box(n, Vector3(0.74, 0.03, 0.66), Color.WHITE, Vector3(0, y - 0.015, 0), 0.0)
		for bx in [-0.25, -0.083, 0.083, 0.25]:
			cyl(n, 0.055, 0.06, 0.26, pastel(), Vector3(bx, y + 0.13, 0.05), 0.012)
			cyl(n, 0.03, 0.03, 0.06, Color.WHITE, Vector3(bx, y + 0.29, 0.05), 0.008)
	glass(n, Vector3(0.78, 1.55, 0.03), Vector3(0, 0.9, 0.38))
	box(n, Vector3(0.04, 0.45, 0.05), Color.WHITE, Vector3(0.3, 0.95, 0.42), 0.012)
	return n


static func _fruit() -> Node3D:
	var n := Node3D.new()
	var wood := Color("#d39b6a")
	box(n, Vector3(1.8, 0.5, 0.72), wood, Vector3(0, 0.25, 0))
	box(n, Vector3(1.84, 0.06, 0.76), wood.lightened(0.15), Vector3(0, 0.5, 0))
	var fruits := ["#ff6b6b", "#ffa94d", "#ffe066"]
	for i in 3:
		var crate := Node3D.new()
		crate.position = Vector3(-0.6 + 0.6 * i, 0.6, 0.02)
		crate.rotation.x = 0.28
		n.add_child(crate)
		box(crate, Vector3(0.56, 0.14, 0.64), Color("#f0c995"), Vector3.ZERO, 0.02)
		var fc := Color(fruits[i])
		for fx in 3:
			for fz in 3:
				sphere(crate, 0.075, fc, Vector3(-0.17 + fx * 0.17, 0.12, -0.19 + fz * 0.19), 0.012)
	# 條紋遮陽棚
	for px in [-0.86, 0.86]:
		for pz in [-0.3, 0.3]:
			cyl(n, 0.03, 0.03, 1.2, Color.WHITE, Vector3(px, 1.1, pz), 0.012)
	var canopy := Node3D.new()
	canopy.position = Vector3(0, 1.72, 0.05)
	canopy.rotation.x = 0.18
	n.add_child(canopy)
	for s in 6:
		var col := Color("#ff9aa2") if s % 2 == 0 else Color("#fff8ee")
		box(canopy, Vector3(0.32, 0.06, 0.9), col, Vector3(-0.8 + s * 0.32, 0, 0), 0.015)
		sphere(canopy, 0.08, col, Vector3(-0.8 + s * 0.32, -0.03, 0.45), 0.012)
	return n


static func _bread() -> Node3D:
	var n := Node3D.new()
	var wood := Color("#e0b07c")
	box(n, Vector3(0.86, 1.4, 0.06), wood.darkened(0.08), Vector3(0, 0.7, -0.34))
	for sx in [-0.42, 0.42]:
		box(n, Vector3(0.05, 1.4, 0.7), wood, Vector3(sx, 0.7, 0))
	box(n, Vector3(0.94, 0.08, 0.76), wood.darkened(0.15), Vector3(0, 1.43, 0))
	var tiers := [0.22, 0.62, 1.02]
	for t in tiers.size():
		var tray := Node3D.new()
		tray.position = Vector3(0, tiers[t], 0)
		tray.rotation.x = 0.2
		n.add_child(tray)
		box(tray, Vector3(0.78, 0.05, 0.6), Color("#f6deb8"), Vector3.ZERO, 0.015)
		box(tray, Vector3(0.78, 0.1, 0.03), wood, Vector3(0, 0.04, 0.3), 0.012)
		match t:
			0:  # 圓麵包
				for bx in [-0.22, 0.0, 0.22]:
					sphere(tray, 0.1, Color("#d9924a"), Vector3(bx, 0.08, 0.05), 0.015, 0.13)
			1:  # 長棍
				for bz in [-0.1, 0.12]:
					var loaf := capsule(tray, 0.07, 0.6, Color("#e8a85a"), Vector3(0, 0.09, bz), 0.015)
					loaf.rotation.z = PI / 2
			2:  # 甜甜圈
				for bx in [-0.2, 0.2]:
					torus(tray, 0.035, 0.11, Color("#e8b06a"), Vector3(bx, 0.06, 0.04), 0.012)
					torus(tray, 0.045, 0.1, Color("#ffb3c7"), Vector3(bx, 0.085, 0.04), 0.0)
	return n


static func _icecream() -> Node3D:
	var n := Node3D.new()
	box(n, Vector3(1.8, 0.62, 0.74), Color("#eaf6ff"), Vector3(0, 0.31, 0))
	box(n, Vector3(1.84, 0.1, 0.78), Color("#9ad0ec"), Vector3(0, 0.6, 0))
	box(n, Vector3(1.84, 0.08, 0.78), Color("#9ad0ec"), Vector3(0, 0.04, 0))
	for row in 2:
		for i in 6:
			var p := Vector3(-0.72 + i * 0.29, 0.0, -0.15 + row * 0.3)
			cyl(n, 0.06, 0.008, 0.18, Color("#e9b872"), p + Vector3(0, 0.74, 0), 0.01)
			sphere(n, 0.075, pastel(), p + Vector3(0, 0.86, 0), 0.012)
	glass(n, Vector3(1.76, 0.36, 0.72), Vector3(0, 0.83, 0))
	# 招牌大甜筒
	cyl(n, 0.025, 0.025, 0.6, Color.WHITE, Vector3(0.75, 1.3, -0.3), 0.01)
	cyl(n, 0.16, 0.01, 0.38, Color("#e9b872"), Vector3(0.75, 1.75, -0.3), 0.02)
	sphere(n, 0.19, Color("#ffb3c7"), Vector3(0.75, 2.0, -0.3), 0.025)
	sphere(n, 0.06, Color("#ff5c7a"), Vector3(0.75, 2.22, -0.3), 0.015)
	return n


static func _plant() -> Node3D:
	var n := Node3D.new()
	cyl(n, 0.2, 0.15, 0.32, Color("#ec9a6e"), Vector3(0, 0.16, 0), 0.02)
	cyl(n, 0.23, 0.23, 0.07, Color("#f2b08a"), Vector3(0, 0.33, 0), 0.02)
	sphere(n, 0.22, Color("#7ccf8a"), Vector3(0, 0.6, 0), 0.02)
	sphere(n, 0.17, Color("#5fb874"), Vector3(-0.13, 0.52, 0.06), 0.02)
	sphere(n, 0.16, Color("#8edb98"), Vector3(0.13, 0.55, -0.03), 0.02)
	sphere(n, 0.14, Color("#6cc47c"), Vector3(0.02, 0.82, 0.02), 0.02)
	var fc := pastel()
	for fp in [Vector3(0.1, 0.72, 0.17), Vector3(-0.17, 0.62, 0.14), Vector3(0.05, 0.94, 0.06)]:
		sphere(n, 0.045, fc, fp, 0.01)
	return n


static func _counter() -> Node3D:
	var n := Node3D.new()
	box(n, Vector3(1.8, 0.9, 0.7), Color("#ffd6a5"), Vector3(0, 0.45, 0))
	box(n, Vector3(1.9, 0.08, 0.8), Color("#c98f63"), Vector3(0, 0.94, 0))
	box(n, Vector3(1.8, 0.12, 0.03), Color("#b5ead7"), Vector3(0, 0.72, 0.36), 0.0)
	# 收銀機
	box(n, Vector3(0.42, 0.22, 0.36), Color("#b5ead7"), Vector3(0.4, 1.09, -0.05), 0.02)
	var screen := box(n, Vector3(0.32, 0.2, 0.04), Color("#fff8ee"), Vector3(0.4, 1.3, -0.14), 0.015)
	screen.rotation.x = -0.35
	# 糖果罐與服務鈴
	cyl(n, 0.1, 0.1, 0.2, Color("#ffffff"), Vector3(-0.25, 1.08, 0.08), 0.015)
	for k in 5:
		sphere(n, 0.035, pastel(), Vector3(-0.25 + randf_range(-0.05, 0.05), 1.2, 0.08 + randf_range(-0.05, 0.05)), 0.0)
	sphere(n, 0.07, Color("#ffd166"), Vector3(-0.6, 1.0, 0.12), 0.012, 0.1)
	return n


# ---------------------------------------------------------------- 動物
# 回傳的根節點下有 "Pivot"（走路彈跳用）與 "Pivot/Head"。

static func build_animal(sp: String, scarf: Color) -> Node3D:
	var root := Node3D.new()
	var piv := Node3D.new()
	piv.name = "Pivot"
	root.add_child(piv)
	var fur := Color("#ffb870")
	var belly := Color("#fff3e0")
	match sp:
		"bear":
			fur = Color("#c69468"); belly = Color("#f0d9b5")
		"rabbit":
			fur = Color("#fffaf3"); belly = Color("#ffe4ec")
		"frog":
			fur = Color("#9bdc8a"); belly = Color("#eef8cf")
		"pig":
			fur = Color("#ffc4d0"); belly = Color("#ffe1e8")
		"panda":
			fur = Color("#fdfdfd"); belly = Color("#ffffff")
		"fox":
			fur = Color("#ff9b54"); belly = Color("#fff6ec")
	var black := Color("#3d3438")
	var limb := black if sp == "panda" else fur.darkened(0.08)
	var pink := Color("#ffb3c1")
	var dark := Color("#3a2a2a")
	var ol := 0.018

	for sx in [-0.09, 0.09]:
		sphere(piv, 0.075, limb, Vector3(sx, 0.05, 0.03), ol, 0.1)
	sphere(piv, 0.2, fur, Vector3(0, 0.25, 0), ol, 0.36)
	sphere(piv, 0.13, belly, Vector3(0, 0.23, 0.1), 0.0, 0.24)
	for sx in [-0.19, 0.19]:
		sphere(piv, 0.065, limb, Vector3(sx, 0.27, 0.04), ol)
	torus(piv, 0.09, 0.16, scarf, Vector3(0, 0.42, 0), ol)

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.66, 0)
	piv.add_child(head)
	sphere(head, 0.25, fur, Vector3.ZERO, ol, 0.46)

	if sp != "frog":
		for sx in [-0.09, 0.09]:
			if sp == "panda":
				var patch := sphere(head, 0.065, black, Vector3(sx, 0.01, 0.17), 0.0, 0.1)
				patch.rotation.z = 0.5 if sx > 0 else -0.5
			sphere(head, 0.036, dark, Vector3(sx, 0.02, 0.215), 0.0)
			sphere(head, 0.013, Color.WHITE, Vector3(sx + 0.012, 0.036, 0.245), 0.0)
	for sx in [-0.15, 0.15]:
		var b := sphere(head, 0.045, Color("#ff9fb0"), Vector3(sx, -0.05, 0.195), 0.0, 0.02)
		b.rotation = Vector3(PI / 2, sx * 2.5, 0)
	sphere(head, 0.014, dark, Vector3(0, -0.045, 0.235), 0.0)

	match sp:
		"cat":
			for s in [-1.0, 1.0]:
				var e := cyl(head, 0.0, 0.085, 0.16, fur, Vector3(0.14 * s, 0.2, 0), ol)
				e.rotation.z = -0.4 * s
				var ei := cyl(head, 0.0, 0.05, 0.1, pink, Vector3(0.14 * s, 0.19, 0.035), 0.0)
				ei.rotation.z = -0.4 * s
			sphere(head, 0.022, pink, Vector3(0, -0.015, 0.245), 0.0)
			var tail := capsule(piv, 0.035, 0.34, fur, Vector3(0, 0.3, -0.24), ol)
			tail.rotation.x = -0.6
		"bear":
			for s in [-1.0, 1.0]:
				sphere(head, 0.08, fur, Vector3(0.17 * s, 0.18, 0), ol)
				sphere(head, 0.045, belly, Vector3(0.17 * s, 0.18, 0.045), 0.0)
			sphere(head, 0.1, belly, Vector3(0, -0.07, 0.17), 0.012, 0.08)
			sphere(head, 0.03, dark, Vector3(0, -0.04, 0.25), 0.0)
		"rabbit":
			for s in [-1.0, 1.0]:
				var e := capsule(head, 0.055, 0.34, fur, Vector3(0.08 * s, 0.3, -0.02), ol)
				e.rotation.z = -0.12 * s
				var ei := capsule(head, 0.03, 0.24, pink, Vector3(0.08 * s, 0.3, 0.025), 0.0)
				ei.rotation.z = -0.12 * s
			sphere(head, 0.02, pink, Vector3(0, -0.015, 0.245), 0.0)
			sphere(piv, 0.07, Color.WHITE, Vector3(0, 0.18, -0.2), ol)
		"frog":
			for s in [-1.0, 1.0]:
				sphere(head, 0.085, fur, Vector3(0.11 * s, 0.17, 0.07), ol)
				sphere(head, 0.06, Color.WHITE, Vector3(0.11 * s, 0.18, 0.12), 0.0)
				sphere(head, 0.03, dark, Vector3(0.11 * s, 0.19, 0.175), 0.0)
				sphere(head, 0.01, Color.WHITE, Vector3(0.11 * s + 0.01, 0.2, 0.2), 0.0)
		"pig":
			var snout := cyl(head, 0.075, 0.075, 0.05, Color("#ff9fb6"), Vector3(0, -0.04, 0.235), 0.012)
			snout.rotation.x = PI / 2
			for s in [-1.0, 1.0]:
				sphere(head, 0.015, dark, Vector3(0.025 * s, -0.04, 0.262), 0.0)
				var e := cyl(head, 0.0, 0.07, 0.11, fur, Vector3(0.15 * s, 0.19, 0.03), ol)
				e.rotation = Vector3(0.3, 0, -0.5 * s)
		"panda":
			for s in [-1.0, 1.0]:
				sphere(head, 0.08, black, Vector3(0.17 * s, 0.18, 0), ol)
			sphere(head, 0.025, dark, Vector3(0, -0.02, 0.248), 0.0)
		"fox":
			for s in [-1.0, 1.0]:
				var e := cyl(head, 0.0, 0.09, 0.2, fur, Vector3(0.13 * s, 0.22, 0), ol)
				e.rotation.z = -0.3 * s
				var ei := cyl(head, 0.0, 0.05, 0.12, Color.WHITE, Vector3(0.13 * s, 0.2, 0.04), 0.0)
				ei.rotation.z = -0.3 * s
			sphere(head, 0.11, belly, Vector3(0, -0.07, 0.16), 0.012, 0.09)
			sphere(head, 0.025, dark, Vector3(0, -0.05, 0.255), 0.0)
			var tail := capsule(piv, 0.08, 0.4, fur, Vector3(0, 0.3, -0.27), ol)
			tail.rotation.x = -0.9
			sphere(piv, 0.07, Color.WHITE, Vector3(0, 0.44, -0.42), 0.012)
	return root
