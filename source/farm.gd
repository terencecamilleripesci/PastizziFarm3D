extends Node3D
# ===== Pastizzi Farm 3D — v0.2 =====
# Real farm loop: crops grow in REAL minutes (keep growing while you're away),
# progress saves on-device, pinch/wheel zoom, drag pan, day/night cycle.

const CROPS := [
	{ "id": "tadam",  "name": "Tadam",  "e": "🍅", "color": Color(0.86, 0.22, 0.16), "mins": 2.0,  "seed": 10, "pay": 25, "model": "res://assets/tomato.glb", "h": 1.7, "per": 9 },
	{ "id": "frawli", "name": "Frawli", "e": "🍓", "color": Color(0.93, 0.30, 0.44), "mins": 5.0,  "seed": 20, "pay": 55, "model": "res://assets/strawberry.glb", "h": 1.4, "per": 9 },
	{ "id": "laring", "name": "Larinġ", "e": "🍊", "color": Color(0.98, 0.60, 0.12), "mins": 8.0,  "seed": 35, "pay": 95, "model": "res://assets/orange.glb", "h": 2.6, "per": 1, "tree": true },
	{ "id": "qargha", "name": "Qargħa", "e": "🎃", "color": Color(0.90, 0.48, 0.10), "mins": 12.0, "seed": 50, "pay": 150, "model": "res://assets/pumpkin.glb", "h": 1.9, "per": 9 },
	{ "id": "gheneb", "name": "Għeneb", "e": "🍇", "color": Color(0.48, 0.24, 0.60), "mins": 20.0, "seed": 80, "pay": 260, "model": "res://assets/vine.glb", "h": 2.5, "per": 1, "tree": true },
]
const SAVE_PATH := "user://farm.json"
const DAY_SECONDS := 180.0            # full day/night loop = 3 minutes

var coins := 50
var sel_crop := 0
var seed_btns: Array = []
var chicken: Node3D
var chick_target := Vector3.ZERO
var egg_timer := 0.0
var eggs: Array = []
var goat: Node3D
var goat_target := Vector3.ZERO
var milk_timer := 0.0
var milks: Array = []
var owned := 1                        # plots owned — start with ONE, buy the rest
var tool := "seed"                    # seed | water | shovel
var tool_btns: Array = []
var seed_bar: HBoxContainer
var house_lvl := 1                    # farmhouse tier (1..3) — boosts sell prices
var zone2 := false                    # the orchard beyond the east wall
var zone2_node: Node3D
var gate_node: Node3D
var up_btn: Button
var cam_max_x := 20.0
var clouds: Array = []
var luzzu: Node3D
var donkey: Node3D
var donkey_target := Vector3.ZERO
var dog: Node3D
var plots: Array = []                 # { body, crop(int idx|-1), node, stem, fruits, planted(unix) }
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var coins_label: Label
var hint_label: Label
var day_t := 0.0
var touches := {}                     # index -> Vector2
var pinch_dist := 0.0
var drag_last := Vector2.ZERO
var dragging := false

func _ready() -> void:
	_build_world()
	_build_plots()
	_build_zone2()
	_build_camera_and_light()
	_build_ui()
	_load()

# ---------- helpers ----------
func _tmat(path: String, tile: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.uv1_scale = Vector3(tile, tile, tile)
	m.roughness = 1.0
	return m

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _cyl(top: float, bottom: float, h: float, pos: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = h
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _sphere(r: float, pos: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi

# ---------- model loader (Meshy GLBs, auto-scaled to a target height) ----------
func _model(path: String, target_h: float) -> Node3D:
	var scene: PackedScene = load(path)
	if not scene:
		return null
	var n: Node3D = scene.instantiate()
	var aabb := AABB()
	var found := false
	for child in n.find_children("*", "MeshInstance3D", true):
		var b: AABB = child.get_aabb()
		if not found:
			aabb = b
			found = true
		else:
			aabb = aabb.merge(b)
	if found and aabb.size.y > 0.01:
		var f := target_h / aabb.size.y
		n.scale = Vector3(f, f, f)
		n.position.y = -aabb.position.y * f
	return n

# ---------- world ----------
func _build_world() -> void:
	var ground := _box(Vector3(26, 0.5, 26), Vector3(0, -0.25, 0), Color(1, 1, 1))   # field
	ground.material_override = _tmat("res://assets/tex_grass.png", 9.0)
	_box(Vector3(60, 0.2, 18), Vector3(0, -0.4, -26), Color(0.16, 0.45, 0.68))      # the sea beyond
	var stone := Color(0.85, 0.74, 0.55)
	var wall_mat := _tmat("res://assets/tex_stone.png", 4.0)
	for wall in [_box(Vector3(26, 1.0, 0.7), Vector3(0, 0.5, -13), stone), _box(Vector3(26, 1.0, 0.7), Vector3(0, 0.5, 13), stone), _box(Vector3(0.7, 1.0, 26), Vector3(-13, 0.5, 0), stone), _box(Vector3(0.7, 1.0, 26), Vector3(13, 0.5, 0), stone)]:
		wall.material_override = wall_mat
	# the farmhouse (real 3D model, generated with Meshy AI)
	var house_scene: PackedScene = load("res://assets/house.glb")
	if house_scene:
		var house := house_scene.instantiate()
		add_child(house)
		house.position = Vector3(-9.3, 0, -9.3)
		house.rotation_degrees.y = 35
		# normalise whatever scale the model shipped with to ~3.4 units tall
		var aabb := AABB()
		var found := false
		for child in house.find_children("*", "MeshInstance3D", true):
			var b: AABB = child.get_aabb()
			if not found:
				aabb = b
				found = true
			else:
				aabb = aabb.merge(b)
		if found and aabb.size.y > 0.01:
			var f := 3.4 / aabb.size.y
			house.scale = Vector3(f, f, f)
			house.position.y = -aabb.position.y * f
	# stone well (real model)
	var well := _model("res://assets/well.glb", 2.2)
	if well:
		add_child(well)
		well.position += Vector3(9.5, 0, -9.5)
	# olive trees (real models)
	for p in [Vector3(-10, 0, 8.5), Vector3(10.5, 0, 8.5), Vector3(-10.5, 0, 0)]:
		var ol := _model("res://assets/olive.glb", 3.1)
		if ol:
			add_child(ol)
			ol.position += p
			ol.rotation_degrees.y = randf_range(0, 360)
	# prickly pears (real models)
	for i in range(3):
		var pp := _model("res://assets/prickly.glb", 1.3)
		if pp:
			add_child(pp)
			pp.position += Vector3(5.0 + i * 2.4, 0, -11.6)
			pp.rotation_degrees.y = randf_range(0, 360)
	# the luzzu bobbing on the sea
	luzzu = _model("res://assets/luzzu.glb", 2.4)
	if luzzu:
		add_child(luzzu)
		luzzu.position += Vector3(-4, -0.25, -19)
	# sandy paths between the plot rows
	for z in [-2.1, 2.1]:
		_box(Vector3(12.6, 0.06, 1.0), Vector3(0, 0.01, z), Color(0.8, 0.7, 0.5))
	for x in [-2.1, 2.1]:
		_box(Vector3(1.0, 0.06, 12.6), Vector3(x, 0.01, 0), Color(0.8, 0.7, 0.5))
	# wildflowers along the walls
	for i in range(14):
		var fx := randf_range(-12, 12)
		var fz := (-12.2 if randf() < 0.5 else 12.2) + randf_range(-0.5, 0.5)
		if randf() < 0.4:
			var t := fx
			fx = (-12.2 if randf() < 0.5 else 12.2)
			fz = t
		_cyl(0.02, 0.03, 0.4, Vector3(fx, 0.2, fz), Color(0.3, 0.52, 0.22))
		_sphere(0.12, Vector3(fx, 0.45, fz), [Color(0.95, 0.45, 0.6), Color(0.98, 0.85, 0.3), Color(0.9, 0.9, 0.95), Color(0.85, 0.4, 0.9)][randi() % 4])
	# scattered rocks
	for i in range(6):
		var r := _sphere(randf_range(0.25, 0.5), Vector3(randf_range(-11, 11), 0.1, randf_range(9.5, 11.5)), Color(0.62, 0.58, 0.52))
		r.scale.y = 0.55
	# drifting clouds
	for i in range(3):
		var cl := Node3D.new()
		add_child(cl)
		_sphere(1.4, Vector3(0, 0, 0), Color(1, 1, 1, 1), cl).scale = Vector3(1.6, 0.55, 1)
		_sphere(1.0, Vector3(1.4, 0.15, 0.2), Color(1, 1, 1, 1), cl).scale = Vector3(1.3, 0.5, 1)
		cl.position = Vector3(randf_range(-16, 16), 9.0 + i * 1.2, -6 - i * 4)
		clouds.append(cl)

const PLOT_COSTS := [0, 25, 50, 90, 140, 200, 280, 380, 500, 650, 800, 1000]
func _build_plots() -> void:
	for r in range(4):
		for c in range(3):
			var pos := Vector3((c - 1) * 4.2, 0.05, (r - 1) * 4.2)
			var wood := Color(0.52, 0.36, 0.2)
			# raised bed: wooden frame, corner posts, domed textured soil
			_box(Vector3(3.9, 0.5, 0.28), pos + Vector3(0, 0.12, -1.84), wood)
			_box(Vector3(3.9, 0.5, 0.28), pos + Vector3(0, 0.12, 1.84), wood)
			_box(Vector3(0.28, 0.5, 3.9), pos + Vector3(-1.84, 0.12, 0), wood)
			_box(Vector3(0.28, 0.5, 3.9), pos + Vector3(1.84, 0.12, 0), wood)
			for cx in [-1.84, 1.84]:
				for cz in [-1.84, 1.84]:
					_cyl(0.16, 0.16, 0.7, pos + Vector3(cx, 0.3, cz), Color(0.45, 0.3, 0.16))
			var soil := _box(Vector3(3.3, 0.42, 3.3), pos + Vector3(0, 0.1, 0), Color(0.6, 0.55, 0.48))
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(3.9, 1.8, 3.9)
			shape.shape = bs
			body.add_child(shape)
			body.position = pos
			add_child(body)
			body.set_meta("plot", plots.size())
			var lbl := Label3D.new()
			lbl.font_size = 52
			lbl.outline_size = 12
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.position = pos + Vector3(0, 1.5, 0)
			add_child(lbl)
			plots.append({ "body": body, "soil": soil, "lbl": lbl, "locked": true, "slots": [null,null,null,null,null,null,null,null,null], "tree": -1, "tnode": null, "tplanted": 0.0, "trg": false })
	_apply_owned()

func _apply_owned() -> void:
	for i in range(min(owned, 12)):
		var p: Dictionary = plots[i]
		if p.locked:
			p.locked = false
			p.soil.material_override = _tmat("res://assets/tex_soil.png", 1.0)
	_refresh_plot_labels()

func _refresh_plot_labels() -> void:
	for i in range(plots.size()):
		var p: Dictionary = plots[i]
		if p.get("zone2"):
			if is_instance_valid(p.get("lbl")) and p.lbl:
				p.lbl.text = ""
			continue
		if not is_instance_valid(p.get("lbl")):
			continue
		if p.locked:
			p.lbl.text = "🪙%d" % PLOT_COSTS[i] if i == owned else "🔒"
			p.lbl.modulate = Color(1, 0.85, 0.35) if i == owned else Color(1, 1, 1, 0.55)
		elif _bed_free_slot(p) >= 0:
			var filled := 0
			for sl in p.slots:
				if sl != null:
					filled += 1
			p.lbl.text = "+" if filled == 0 else "%d/9" % filled
			p.lbl.modulate = Color(0.75, 1, 0.6, 0.9)
		else:
			p.lbl.text = ""

func _build_zone2() -> void:
	zone2_node = Node3D.new()
	add_child(zone2_node)
	var g2 := _box(Vector3(12, 0.5, 26), Vector3(20, -0.25, 0), Color(1, 1, 1), zone2_node)
	g2.material_override = _tmat("res://assets/tex_grass.png", 7.0)
	var stone := Color(0.85, 0.74, 0.55)
	var wm2 := _tmat("res://assets/tex_stone.png", 4.0)
	for w2 in [_box(Vector3(12, 1.0, 0.7), Vector3(20, 0.5, -13), stone, zone2_node), _box(Vector3(12, 1.0, 0.7), Vector3(20, 0.5, 13), stone, zone2_node), _box(Vector3(0.7, 1.0, 26), Vector3(26, 0.5, 0), stone, zone2_node)]:
		w2.material_override = wm2
	for r in range(2):
		for c in range(3):
			var pos := Vector3(17.0 + c * 4.2, 0.05, -4.2 + r * 8.4)
			var soil := _box(Vector3(3.4, 0.3, 3.4), pos, Color(1, 1, 1), zone2_node)
			soil.material_override = _tmat("res://assets/tex_soil.png", 1.0)
			var bc := Color(0.78, 0.68, 0.5)
			_box(Vector3(3.8, 0.22, 0.2), pos + Vector3(0, 0.06, -1.8), bc, zone2_node)
			_box(Vector3(3.8, 0.22, 0.2), pos + Vector3(0, 0.06, 1.8), bc, zone2_node)
			_box(Vector3(0.2, 0.22, 3.8), pos + Vector3(-1.8, 0.06, 0), bc, zone2_node)
			_box(Vector3(0.2, 0.22, 3.8), pos + Vector3(1.8, 0.06, 0), bc, zone2_node)
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(3.4, 1.6, 3.4)
			shape.shape = bs
			body.add_child(shape)
			body.position = pos
			zone2_node.add_child(body)
			body.set_meta("plot", plots.size())
			plots.append({ "body": body, "soil": soil, "lbl": null, "locked": true, "zone2": true, "slots": [null,null,null,null,null,null,null,null,null], "tree": -1, "tnode": null, "tplanted": 0.0, "trg": false })
	var wm := _model("res://assets/windmill.glb", 5.0)
	if wm:
		zone2_node.add_child(wm)
		wm.position += Vector3(24, 0, -9)
		wm.rotation_degrees.y = -110
	zone2_node.visible = false
	# the wooden gate in the east wall (tap to buy the orchard)
	gate_node = Node3D.new()
	add_child(gate_node)
	_box(Vector3(0.5, 1.6, 3.0), Vector3(13, 0.8, 0), Color(0.55, 0.38, 0.2), gate_node)
	var gl := Label3D.new()
	gl.text = "🌳 🪙800"
	gl.font_size = 64
	gl.outline_size = 12
	gl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gl.position = Vector3(12.6, 2.4, 0)
	gate_node.add_child(gl)
	var gb := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var gbs := BoxShape3D.new()
	gbs.size = Vector3(1.2, 2.2, 3.2)
	gs.shape = gbs
	gb.add_child(gs)
	gb.position = Vector3(13, 1.0, 0)
	gate_node.add_child(gb)
	gb.set_meta("gate", true)

func _open_zone2() -> void:
	zone2 = true
	zone2_node.visible = true
	for p in plots:
		if p.get("zone2"):
			p.locked = false
	if is_instance_valid(gate_node):
		gate_node.queue_free()
	cam_max_x = 27.0

func _build_camera_and_light() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 17.0
	cam.position = Vector3(12, 14, 12)
	add_child(cam)
	cam.look_at(Vector3.ZERO)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 1.0)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var title := Label.new()
	title.text = "🥟 Pastizzi Farm 3D  v1.1"
	title.position = Vector2(20, 18)
	title.add_theme_font_size_override("font_size", 30)
	ui.add_child(title)
	coins_label = Label.new()
	coins_label.position = Vector2(20, 60)
	coins_label.add_theme_font_size_override("font_size", 26)
	ui.add_child(coins_label)
	hint_label = Label.new()
	hint_label.text = "Pick a seed below, tap a plot — crops grow in real time, even while you're away!"
	hint_label.position = Vector2(20, 100)
	hint_label.add_theme_font_size_override("font_size", 15)
	ui.add_child(hint_label)
	var tbar := HBoxContainer.new()
	tbar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tbar.offset_top = -152
	tbar.offset_bottom = -104
	tbar.offset_left = 12
	tbar.offset_right = -12
	tbar.add_theme_constant_override("separation", 8)
	ui.add_child(tbar)
	for t in [["seed", "🌱 Seeds"], ["water", "🚿 Water 🪙5"], ["shovel", "🧹 Shovel"]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_font_size_override("font_size", 15)
		tb.pressed.connect(_pick_tool.bind(t[0]))
		tbar.add_child(tb)
		tool_btns.append([t[0], tb])
	var bar := HBoxContainer.new()
	seed_bar = bar
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -92
	bar.offset_bottom = -16
	bar.offset_left = 12
	bar.offset_right = -12
	bar.add_theme_constant_override("separation", 8)
	ui.add_child(bar)
	for i in range(CROPS.size()):
		var b := Button.new()
		var c: Dictionary = CROPS[i]
		b.text = "%s %s\n🪙%d · %sm" % [c.e, c.name, c.seed, str(c.mins)]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_pick_seed.bind(i))
		bar.add_child(b)
		seed_btns.append(b)
	up_btn = Button.new()
	up_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	up_btn.offset_left = -235
	up_btn.offset_right = -14
	up_btn.offset_top = 14
	up_btn.offset_bottom = 58
	up_btn.add_theme_font_size_override("font_size", 15)
	up_btn.pressed.connect(_upgrade_house)
	ui.add_child(up_btn)
	_refresh_up_btn()
	_pick_seed(0)
	_pick_tool("seed")
	_build_chicken()
	_build_goat()
	_build_donkey()
	_build_dog()
	_update_coins()

func _pick_tool(t: String) -> void:
	tool = t
	for pairb in tool_btns:
		pairb[1].modulate = Color(1, 0.85, 0.4) if pairb[0] == t else Color(1, 1, 1)
	if seed_bar:
		seed_bar.visible = (t == "seed")
	hint_label.text = { "seed": "Pick a seed, tap a plot!", "water": "Tap a growing crop — 🪙5 cuts 25%% of the wait", "shovel": "Tap a crop to dig it out" }[t]

func _pick_seed(i: int) -> void:
	sel_crop = i
	for j in range(seed_btns.size()):
		seed_btns[j].modulate = Color(1, 0.85, 0.4) if j == i else Color(1, 1, 1)

func _mult() -> float:
	return 1.0 + 0.1 * float(house_lvl - 1)

func confetti_hint() -> void:
	hint_label.text = "🌳 THE ORCHARD IS YOURS — 6 new plots to the east!"
	_burst(Vector3(13, 1, 0), Color(1, 0.85, 0.3), 12)

func _update_coins() -> void:
	coins_label.text = "🪙 %d" % coins

# ---------- juice: bursts + floating text ----------
func _burst(pos: Vector3, color: Color, n: int = 6) -> void:
	for i in range(n):
		var m := _sphere(0.11, pos + Vector3(0, 0.4, 0), color)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(m, "position", pos + Vector3(randf_range(-1.1, 1.1), randf_range(0.9, 1.8), randf_range(-1.1, 1.1)), 0.55)
		tw.tween_property(m, "scale", Vector3.ZERO, 0.55)
		tw.chain().tween_callback(m.queue_free)

func _float_text(pos: Vector3, txt: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 72
	l.modulate = col
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos + Vector3(0, 1.4, 0)
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", l.position + Vector3(0, 1.3, 0), 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(l.queue_free)

# ---------- save / load (survives closing the game) ----------
func _save() -> void:
	var d := { "coins": coins, "owned": owned, "hl": house_lvl, "z2": zone2, "plots": [] }
	for p in plots:
		var slots_out: Array = []
		for sl in p.slots:
			slots_out.append(null if sl == null else { "c": sl.c, "t": sl.t })
		d.plots.append({ "slots": slots_out, "tree": p.tree, "tt": p.tplanted, "rg": p.trg })
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d == null:
		return
	coins = int(d.get("coins", 0))
	owned = int(d.get("owned", 9 + int(d.get("ext", 0)) if d.has("ext") else 1))
	owned = clamp(owned, 1, 12)
	_apply_owned()
	house_lvl = int(d.get("hl", 1))
	_house_extras()
	_refresh_up_btn()
	if d.get("z2", false):
		_open_zone2()
	var saved: Array = d.get("plots", [])
	for i in range(min(saved.size(), plots.size())):
		var s: Dictionary = saved[i]
		var sl_in: Array = s.get("slots", [])
		for si in range(min(sl_in.size(), 9)):
			if sl_in[si] != null and int(sl_in[si].c) >= 0 and int(sl_in[si].c) < CROPS.size():
				_make_plant(i, si, int(sl_in[si].c), float(sl_in[si].t))
		var tr := int(s.get("tree", -1))
		if tr >= 0 and tr < CROPS.size():
			_make_tree(i, tr, float(s.get("tt", 0)), bool(s.get("rg", false)))
		# legacy save (single crop per bed) → fill the bed
		var ci := int(s.get("crop", -1))
		if ci >= 0 and ci < CROPS.size():
			if CROPS[ci].get("tree", false):
				_make_tree(i, ci, float(s.get("planted", 0)), bool(s.get("rg", false)))
			else:
				for si in range(9):
					_make_plant(i, si, ci, float(s.get("planted", 0)))
	_update_coins()

# ---------- crops ----------
const SLOT_OFFS := [
	Vector3(-1.05, 0, -1.05), Vector3(0, 0, -1.05), Vector3(1.05, 0, -1.05),
	Vector3(-1.05, 0, 0),     Vector3(0, 0, 0),     Vector3(1.05, 0, 0),
	Vector3(-1.05, 0, 1.05),  Vector3(0, 0, 1.05),  Vector3(1.05, 0, 1.05),
]

func _k_of(cidx: int, t: float, rg: bool) -> float:
	var mins: float = CROPS[cidx].mins
	if rg:
		mins = mins * 0.6
	var k: float = clamp((Time.get_unix_time_from_system() - t) / (mins * 60.0), 0.0, 1.0)
	if rg:
		k = max(k, 0.82)
	return k

func _make_plant(i: int, si: int, cidx: int, t: float) -> void:
	var p: Dictionary = plots[i]
	var crop: Dictionary = CROPS[cidx]
	var holder := Node3D.new()
	holder.position = p.body.position + Vector3(0, 0.34, 0) + SLOT_OFFS[si]
	add_child(holder)
	var uh: float = crop.get("h", 1.5) * 0.55
	if crop.has("model"):
		var m := _model(crop.model, uh)
		if m:
			m.rotation_degrees.y = randf_range(0, 360)
			holder.add_child(m)
	else:
		_cyl(0.06, 0.09, uh * 0.6, Vector3(0, uh * 0.3, 0), Color(0.3, 0.5, 0.2), holder)
		_sphere(0.17, Vector3(0, uh * 0.62, 0), crop.color, holder)
	holder.scale = Vector3(0.1, 0.1, 0.1)
	p.slots[si] = { "c": cidx, "t": t, "node": holder }

func _make_tree(i: int, cidx: int, t: float, rg: bool) -> void:
	var p: Dictionary = plots[i]
	var crop: Dictionary = CROPS[cidx]
	var holder := Node3D.new()
	holder.position = p.body.position + Vector3(0, 0.34, 0)
	add_child(holder)
	var m := _model(crop.model, crop.get("h", 2.5))
	if m:
		holder.add_child(m)
	holder.scale = Vector3(0.1, 0.1, 0.1)
	p.tree = cidx
	p.tnode = holder
	p.tplanted = t
	p.trg = rg

func _bed_free_slot(p: Dictionary) -> int:
	if p.tree >= 0:
		return -1
	for si in range(9):
		if p.slots[si] == null:
			return si
	return -1

func _bed_empty(p: Dictionary) -> bool:
	if p.tree >= 0:
		return false
	for si in range(9):
		if p.slots[si] != null:
			return false
	return true

func _plant(i: int) -> void:
	var p: Dictionary = plots[i]
	var crop: Dictionary = CROPS[sel_crop]
	if coins < crop.seed:
		hint_label.text = "Not enough coins for %s seeds (🪙%d)!" % [crop.name, crop.seed]
		return
	if crop.get("tree", false):
		if not _bed_empty(p):
			hint_label.text = "🌳 A tree needs a completely empty bed!"
			return
		coins -= crop.seed
		_update_coins()
		_make_tree(i, sel_crop, Time.get_unix_time_from_system(), false)
		_burst(p.body.position, Color(0.5, 0.35, 0.2), 5)
		hint_label.text = "%s tree planted — first fruit in %s min, then it keeps producing!" % [crop.name, str(crop.mins)]
	else:
		var si := _bed_free_slot(p)
		if si < 0:
			hint_label.text = "This bed is full — harvest or 🧹 clear it!"
			return
		coins -= crop.seed
		_update_coins()
		_make_plant(i, si, sel_crop, Time.get_unix_time_from_system())
		_burst(p.body.position + SLOT_OFFS[si], Color(0.5, 0.35, 0.2), 3)
		var filled := 0
		for s2 in p.slots:
			if s2 != null:
				filled += 1
		hint_label.text = "%s %s planted (%d/9) — ready in %s min" % [crop.e, crop.name, filled, str(crop.mins)]
	_refresh_plot_labels()
	_save()

func _harvest(i: int) -> void:
	var p: Dictionary = plots[i]
	var total := 0
	var n := 0
	for si in range(9):
		var sl = p.slots[si]
		if sl != null and _k_of(sl.c, sl.t, false) >= 1.0:
			total += int(round(CROPS[sl.c].pay * _mult()))
			n += 1
			sl.node.queue_free()
			p.slots[si] = null
	if p.tree >= 0 and _k_of(p.tree, p.tplanted, p.trg) >= 1.0:
		total += int(round(CROPS[p.tree].pay * _mult()))
		n += 1
		p.tplanted = Time.get_unix_time_from_system()
		p.trg = true
	if n == 0:
		return
	coins += total
	_update_coins()
	_burst(p.body.position, Color(1, 0.85, 0.3), 4 + n)
	_float_text(p.body.position, "+%d 🪙" % total, Color(1, 0.9, 0.35))
	if p.get("mark") and is_instance_valid(p.mark):
		p.mark.queue_free()
	p.mark = null
	hint_label.text = "Harvested %d plants — +%d coins!" % [n, total]
	_refresh_plot_labels()
	_save()

func _bed_any_ready(p: Dictionary) -> bool:
	for sl in p.slots:
		if sl != null and _k_of(sl.c, sl.t, false) >= 1.0:
			return true
	if p.tree >= 0 and _k_of(p.tree, p.tplanted, p.trg) >= 1.0:
		return true
	return false

# ---------- input: tap, drag-pan, pinch/wheel zoom ----------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 2:
				var ks := touches.keys()
				pinch_dist = (touches[ks[0]] as Vector2).distance_to(touches[ks[1]])
			dragging = false
			drag_last = event.position
		else:
			touches.erase(event.index)
			if touches.is_empty() and not dragging:
				_tap(event.position)
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() == 2:
			var ks := touches.keys()
			var nd := (touches[ks[0]] as Vector2).distance_to(touches[ks[1]])
			if pinch_dist > 0:
				cam.size = clamp(cam.size * pinch_dist / max(nd, 1.0), 9.0, 26.0)
			pinch_dist = nd
			dragging = true
		else:
			_pan(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.size = clamp(cam.size - 1.2, 9.0, 26.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.size = clamp(cam.size + 1.2, 9.0, 26.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = false
				drag_last = event.position
			elif not dragging:
				_tap(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_pan(event.position)

func _pan(pos: Vector2) -> void:
	var delta := pos - drag_last
	if delta.length() > 6:
		dragging = true
		var right := cam.global_transform.basis.x
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		cam.position -= right * delta.x * 0.02 + fwd * -delta.y * 0.02
		cam.position.x = clamp(cam.position.x, 4, cam_max_x)
		cam.position.z = clamp(cam.position.z, 4, 20)
		drag_last = pos

func _tap(screen_pos: Vector2) -> void:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	if hit.collider.has_meta("gate"):
		if zone2:
			return
		if coins < 800:
			hint_label.text = "The orchard costs 🪙800 — keep farming!"
			return
		coins -= 800
		_update_coins()
		_open_zone2()
		confetti_hint()
		_save()
		return
	if hit.collider.has_meta("milk"):
		coins += 15
		_update_coins()
		_burst(hit.collider.position, Color(0.92, 0.94, 0.97), 5)
		_float_text(hit.collider.position, "+15 🪙", Color(1, 0.9, 0.35))
		milks.erase(hit.collider)
		hit.collider.queue_free()
		hint_label.text = "🥛 +15 coins!"
		_save()
		return
	if hit.collider.has_meta("egg"):
		coins += 8
		_update_coins()
		_burst(hit.collider.position, Color(0.98, 0.95, 0.85), 5)
		_float_text(hit.collider.position, "+8 🪙", Color(1, 0.9, 0.35))
		eggs.erase(hit.collider)
		hit.collider.queue_free()
		hint_label.text = "🥚 +8 coins!"
		_save()
		return
	if not hit.collider.has_meta("plot"):
		return
	var i: int = hit.collider.get_meta("plot")
	var p: Dictionary = plots[i]
	if p.locked and not p.get("zone2"):
		if i != owned:
			hint_label.text = "Buy plots in order — next costs 🪙%d" % PLOT_COSTS[min(owned, 11)]
			return
		var cost: int = PLOT_COSTS[i]
		if coins < cost:
			hint_label.text = "This plot costs 🪙%d — keep farming!" % cost
			return
		coins -= cost
		owned += 1
		_apply_owned()
		_update_coins()
		_burst(p.body.position, Color(0.6, 0.42, 0.24), 7)
		hint_label.text = "🌾 New plot! Your għalqa grows."
		_save()
		return
	if p.locked:
		return
	if _bed_any_ready(p):
		_harvest(i)                                            # ready plants always harvest first
	elif tool == "seed":
		_plant(i)                                              # one seed → one slot
	elif tool == "water":
		var watered := 0
		if coins < 5:
			hint_label.text = "Watering costs 🪙5"
			return
		for sl in p.slots:
			if sl != null and _k_of(sl.c, sl.t, false) < 1.0:
				var left: float = CROPS[sl.c].mins * 60.0 - (Time.get_unix_time_from_system() - sl.t)
				sl.t -= left * 0.25
				watered += 1
		if p.tree >= 0 and _k_of(p.tree, p.tplanted, p.trg) < 1.0:
			var m2: float = CROPS[p.tree].mins * (0.6 if p.trg else 1.0)
			var tleft: float = m2 * 60.0 - (Time.get_unix_time_from_system() - p.tplanted)
			p.tplanted -= tleft * 0.25
			watered += 1
		if watered == 0:
			hint_label.text = "Nothing growing here to water."
			return
		coins -= 5
		_update_coins()
		_burst(p.body.position, Color(0.4, 0.7, 1.0), 6)
		_float_text(p.body.position, "🚿 -25%", Color(0.55, 0.8, 1))
		hint_label.text = "Watered %d plants — they grow 25%% faster!" % watered
		_save()
	elif tool == "shovel":
		var cleared := 0
		for si in range(9):
			if p.slots[si] != null:
				p.slots[si].node.queue_free()
				p.slots[si] = null
				cleared += 1
		if p.tree >= 0:
			p.tnode.queue_free()
			p.tnode = null
			p.tree = -1
			p.trg = false
			cleared += 1
		if p.get("mark") and is_instance_valid(p.mark):
			p.mark.queue_free()
		p.mark = null
		if cleared > 0:
			_burst(p.body.position, Color(0.5, 0.35, 0.2), 5)
			hint_label.text = "Bed cleared (%d plants dug out)." % cleared
		_refresh_plot_labels()
		_save()
	else:
		hint_label.text = "Growing… 🚿 water to speed up, or plant more with 🌱"

# ---------- it-tiġieġa: wandering chicken that lays eggs ----------
const HOUSE_COSTS := [0, 400, 900]
func _refresh_up_btn() -> void:
	if house_lvl >= 3:
		up_btn.text = "🏠 Razzett Lv3 MAX — prices +20%"
		up_btn.disabled = true
	else:
		up_btn.text = "🏠 Upgrade Lv%d → 🪙%d (+10%% prices)" % [house_lvl + 1, HOUSE_COSTS[house_lvl]]
		up_btn.disabled = false

func _upgrade_house() -> void:
	if house_lvl >= 3:
		return
	var cost: int = HOUSE_COSTS[house_lvl]
	if coins < cost:
		hint_label.text = "Upgrade costs 🪙%d — keep farming!" % cost
		return
	coins -= cost
	house_lvl += 1
	_update_coins()
	_house_extras()
	_refresh_up_btn()
	_burst(Vector3(-9.3, 1.5, -9.3), Color(1, 0.85, 0.3), 10)
	_float_text(Vector3(-9.3, 2, -9.3), "Lv%d!" % house_lvl, Color(1, 0.9, 0.4))
	hint_label.text = "🏠 The razzett grows — all sell prices +10%!"
	_save()

func _house_extras() -> void:
	var stone := Color(0.85, 0.74, 0.55)
	if house_lvl >= 2 and not has_node("hx2"):
		var n := Node3D.new()
		n.name = "hx2"
		add_child(n)
		_box(Vector3(1.8, 1.2, 1.8), Vector3(-7.2, 0.6, -9.8), stone, n)          # side annex
		_sphere(0.55, Vector3(-7.9, 1.5, -8.9), Color(0.85, 0.3, 0.5), n)          # bougainvillea
		_sphere(0.4, Vector3(-7.4, 1.3, -8.7), Color(0.9, 0.4, 0.6), n)
	if house_lvl >= 3 and not has_node("hx3"):
		var n := Node3D.new()
		n.name = "hx3"
		add_child(n)
		_cyl(0.5, 0.6, 1.6, Vector3(-11.2, 0.8, -8.2), stone, n)                   # little tower
		_sphere(0.55, Vector3(-11.2, 1.85, -8.2), Color(0.95, 0.8, 0.4), n)        # gold dome
		_box(Vector3(0.06, 0.7, 0.06), Vector3(-11.2, 2.6, -8.2), Color(0.5, 0.35, 0.2), n)
		_box(Vector3(0.5, 0.3, 0.04), Vector3(-10.95, 2.75, -8.2), Color(0.85, 0.2, 0.2), n)  # 🇲🇹 flag

func _build_chicken() -> void:
	chicken = Node3D.new()
	add_child(chicken)
	var m := _model("res://assets/chicken.glb", 1.15)
	if m:
		chicken.add_child(m)
	else:
		_box(Vector3(0.55, 0.45, 0.75), Vector3(0, 0.42, 0), Color(0.95, 0.93, 0.88), chicken)
	chicken.position = Vector3(7, 0, 7)
	chick_target = chicken.position

func _roam_spot() -> Vector3:
	for i in range(12):   # pick spots outside the crop field (|x|>7 or z beyond the plots)
		var v := Vector3(randf_range(-11.5, 11.5), 0, randf_range(-11.5, 11.5))
		if abs(v.x) > 7.2 or v.z < -7.2 or v.z > 10.0:
			return v
	return Vector3(9, 0, 9)

func _chicken_process(delta: float) -> void:
	if chicken.position.distance_to(chick_target) < 0.3:
		chick_target = _roam_spot()
	else:
		var dir := (chick_target - chicken.position).normalized()
		chicken.position += dir * delta * 1.1
		chicken.position.y = abs(sin(Time.get_ticks_msec() / 90.0)) * 0.09
		chicken.look_at(chicken.position + dir)
		chicken.rotate_y(PI)   # model's head is on +Z — face the walk direction
	egg_timer += delta
	if egg_timer >= 45.0 and eggs.size() < 3:
		egg_timer = 0.0
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := SphereShape3D.new()
		bs.radius = 0.6
		shape.shape = bs
		body.add_child(shape)
		body.position = chicken.position + Vector3(0, 0.2, -0.5)
		body.set_meta("egg", true)
		add_child(body)
		_sphere(0.22, Vector3(0, 0, 0), Color(0.98, 0.95, 0.85), body)
		eggs.append(body)
		hint_label.text = "🥚 It-tiġieġa laid an egg — tap it!"

# ---------- il-mogħża: the goat, drops milk ----------
func _build_goat() -> void:
	goat = Node3D.new()
	add_child(goat)
	var m := _model("res://assets/goat.glb", 1.5)
	if m:
		goat.add_child(m)
	else:
		_box(Vector3(0.7, 0.6, 1.1), Vector3(0, 0.65, 0), Color(0.82, 0.8, 0.75), goat)
	goat.position = Vector3(-7, 0, 5)
	goat_target = goat.position

func _goat_process(delta: float) -> void:
	if goat.position.distance_to(goat_target) < 0.3:
		goat_target = _roam_spot()
	else:
		var dir := (goat_target - goat.position).normalized()
		goat.position += dir * delta * 0.8
		goat.position.y = abs(sin(Time.get_ticks_msec() / 130.0)) * 0.06
		goat.look_at(goat.position + dir)
		goat.rotate_y(PI)      # same — walk head-first
	milk_timer += delta
	if milk_timer >= 75.0 and milks.size() < 2:
		milk_timer = 0.0
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := SphereShape3D.new()
		bs.radius = 0.6
		shape.shape = bs
		body.add_child(shape)
		body.position = goat.position + Vector3(0, 0.3, -0.6)
		body.set_meta("milk", true)
		add_child(body)
		_cyl(0.16, 0.2, 0.45, Vector3(0, 0, 0), Color(0.92, 0.94, 0.97), body)
		milks.append(body)
		hint_label.text = "🥛 Il-mogħża left milk — tap it!"

# ---------- il-ħmar & il-kelb tal-fenek ----------
func _build_donkey() -> void:
	donkey = Node3D.new()
	add_child(donkey)
	var m := _model("res://assets/donkey.glb", 1.8)
	if m:
		donkey.add_child(m)
	donkey.position = Vector3(9, 0, -3)
	donkey_target = donkey.position

func _build_dog() -> void:
	dog = Node3D.new()
	add_child(dog)
	var m := _model("res://assets/dog.glb", 1.4)
	if m:
		dog.add_child(m)
	dog.position = Vector3(-9, 0, 9)

func _donkey_process(delta: float) -> void:
	if donkey.position.distance_to(donkey_target) < 0.3:
		donkey_target = _roam_spot()
	else:
		var dir := (donkey_target - donkey.position).normalized()
		donkey.position += dir * delta * 0.55
		donkey.position.y = abs(sin(Time.get_ticks_msec() / 170.0)) * 0.05
		donkey.look_at(donkey.position + dir)
		donkey.rotate_y(PI)

func _dog_process(delta: float) -> void:
	# the kelb tal-fenek playfully chases the chicken (never quite catches her)
	var to_chick := chicken.position - dog.position
	if to_chick.length() > 2.2:
		var dir := to_chick.normalized()
		dog.position += dir * delta * 1.0
		dog.position.y = abs(sin(Time.get_ticks_msec() / 80.0)) * 0.12
		dog.look_at(dog.position + dir)
		dog.rotate_y(PI)

# ---------- live growth + day/night ----------
func _process(delta: float) -> void:
	for p in plots:
		if p.locked:
			continue
		var any_ready := false
		for sl in p.slots:
			if sl != null and is_instance_valid(sl.node):
				var k: float = _k_of(sl.c, sl.t, false)
				var ms: float = 0.12 + 0.88 * k
				if k >= 1.0:
					ms = 1.0 + sin(Time.get_ticks_msec() / 200.0) * 0.08
					any_ready = true
				sl.node.scale = Vector3(ms, ms, ms)
		if p.tree >= 0 and is_instance_valid(p.tnode):
			var tk: float = _k_of(p.tree, p.tplanted, p.trg)
			var tms: float = 0.12 + 0.88 * tk
			if tk >= 1.0:
				tms = 1.0 + sin(Time.get_ticks_msec() / 260.0) * 0.05
				any_ready = true
			p.tnode.scale = Vector3(tms, tms, tms)
		if any_ready:
			if not p.get("mark"):
				var l := Label3D.new()
				l.text = "!"
				l.font_size = 120
				l.modulate = Color(1, 0.85, 0.25)
				l.outline_size = 20
				l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				l.position = p.body.position + Vector3(0, 2.2, 0)
				add_child(l)
				p.mark = l
			elif is_instance_valid(p.mark):
				p.mark.position.y = p.body.position.y + 2.2 + sin(Time.get_ticks_msec() / 250.0) * 0.15
		else:
			if p.get("mark") and is_instance_valid(p.mark):
				p.mark.queue_free()
				p.mark = null
	_chicken_process(delta)
	_goat_process(delta)
	_donkey_process(delta)
	_dog_process(delta)
	for cl in clouds:
		cl.position.x += delta * 0.45
		if cl.position.x > 22:
			cl.position.x = -22
	if luzzu:
		luzzu.position.x += delta * 0.25
		if luzzu.position.x > 16:
			luzzu.position.x = -16
		luzzu.rotation.z = sin(Time.get_ticks_msec() / 700.0) * 0.05
		luzzu.rotation.x = sin(Time.get_ticks_msec() / 900.0) * 0.04
	# gentle day/night cycle
	day_t += delta
	var a := day_t * TAU / DAY_SECONDS
	var daylight := 0.55 + 0.45 * sin(a)          # 0.1 (night) .. 1.0 (noon)
	sun.rotation_degrees = Vector3(-30.0 - 35.0 * daylight, -30.0 + 15.0 * sin(a * 0.5), 0)
	sun.light_energy = clamp(0.25 + 1.05 * daylight, 0.25, 1.3)
	var day_sky := Color(0.53, 0.75, 0.92)
	var night_sky := Color(0.10, 0.14, 0.30)
	env.background_color = night_sky.lerp(day_sky, clamp(daylight, 0.0, 1.0))
	env.ambient_light_energy = 0.25 + 0.45 * daylight
