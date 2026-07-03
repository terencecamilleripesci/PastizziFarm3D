extends Node3D
# ===== Pastizzi Farm 3D — v2.8 GRID ENGINE (the FarmVille 2 way) =====
# The farm is a tile grid. You PLACE soil patches anywhere, plant one crop
# per patch, trees live on their own tiles and regrow forever.
# Tools: Plot / Seeds / Water / Shovel. Everything saves on-device.

const TILE := 2.2
const CROPS := [
	{ "id": "tadam",  "name": "Tadam",  "e": "🍅", "mins": 2.0,  "seed": 10, "pay": 25,  "model": "res://assets/tomato.glb",     "h": 1.5, "lvl": 1 },
	{ "id": "frawli", "name": "Frawli", "e": "🍓", "mins": 5.0,  "seed": 20, "pay": 55,  "model": "res://assets/strawberry.glb", "h": 1.3, "lvl": 2 },
	{ "id": "laring", "name": "Larinġ", "e": "🍊", "mins": 8.0,  "seed": 35, "pay": 95,  "model": "res://assets/orange.glb",     "h": 2.5, "tree": true, "lvl": 4 },
	{ "id": "qargha", "name": "Qargħa", "e": "🎃", "mins": 12.0, "seed": 50, "pay": 150, "model": "res://assets/pumpkin.glb",    "h": 1.7, "lvl": 6 },
	{ "id": "gheneb", "name": "Għeneb", "e": "🍇", "mins": 20.0, "seed": 80, "pay": 260, "model": "res://assets/vine.glb",       "h": 2.3, "tree": true, "lvl": 8 },
]
const PATCH_COST := 25
const SAVE_PATH := "user://farm2.json"
const DAY_SECONDS := 180.0
const HOUSE_COSTS := [0, 400, 900]

var coins := 120
var grid := {}                        # Vector2i -> {k:"patch"/"tree", c, t, rg, node, soil, mark}
var tool := "plot"                    # plot | seed | water | shovel
var sel_crop := 0
var house_lvl := 1
var zone2 := false

var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var coins_label: Label
var hint_label: Label
var up_btn: Button
var seed_bar: HBoxContainer
var tool_btns: Array = []
var seed_btns: Array = []
var grid_overlay: MeshInstance3D
var zone2_node: Node3D
var gate_node: Node3D
var cam_max_x := 20.0
var day_t := 0.0
var touches := {}
var pinch_dist := 0.0
var drag_last := Vector2.ZERO
var dragging := false
var chicken: Node3D
var chick_target := Vector3.ZERO
var egg_timer := 0.0
var eggs: Array = []
var goat: Node3D
var goat_target := Vector3.ZERO
var milk_timer := 0.0
var milks: Array = []
var donkey: Node3D
var donkey_target := Vector3.ZERO
var dog: Node3D
var luzzu: Node3D
var clouds: Array = []
var butterflies: Array = []
var farmer: Node3D
var farmer_ap: AnimationPlayer            # walk
var farmer_idle_ap: AnimationPlayer
var farmer_harv_ap: AnimationPlayer
var farmer_walk_n: Node3D
var farmer_idle_n: Node3D
var farmer_harv_n: Node3D
var chr := ""                             # "m" | "f" — chosen at join
var chr_panel: PanelContainer
var other: Node3D                          # the character you didn't pick wanders
var other_t := Vector3.ZERO
var kid_b: Node3D
var kid_b_t := Vector3.ZERO
var kid_g: Node3D
var kid_g_t := Vector3.ZERO
var farmer_dest := Vector3.ZERO
var farmer_act := {}                  # {type, tile} — runs when nannu arrives
var farmer_busy := false
var xp := 0
var lvl := 1
var xp_bar: ProgressBar
var lvl_label: Label

func _ready() -> void:
	_build_world()
	_build_zone2()
	_build_camera_and_light()
	_build_ui()
	_build_animals()
	_build_kids()
	_load()

# ================= helpers =================
func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m

func _tmat(path: String, tile: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.uv1_scale = Vector3(tile, tile, tile)
	m.roughness = 1.0
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

func _anim_setup(n: Node3D, autoplay: bool) -> AnimationPlayer:
	if not n:
		return null
	var aps := n.find_children("*", "AnimationPlayer", true)
	if aps.is_empty():
		return null
	var ap: AnimationPlayer = aps[0]
	for an in ap.get_animation_list():
		ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	if autoplay and ap.get_animation_list().size() > 0:
		ap.play(ap.get_animation_list()[0])
	return ap

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

# ================= world =================
func _build_world() -> void:
	var ground := _box(Vector3(26, 0.5, 26), Vector3(0, -0.25, 0), Color(1, 1, 1))
	ground.material_override = _tmat("res://assets/tex_grass.png", 9.0)
	_box(Vector3(60, 0.2, 18), Vector3(0, -0.4, -26), Color(0.16, 0.45, 0.68))
	var stone := Color(0.85, 0.74, 0.55)
	var wall_mat := _tmat("res://assets/tex_stone.png", 4.0)
	for wall in [_box(Vector3(26, 1.0, 0.7), Vector3(0, 0.5, -13), stone), _box(Vector3(26, 1.0, 0.7), Vector3(0, 0.5, 13), stone), _box(Vector3(0.7, 1.0, 26), Vector3(-13, 0.5, 0), stone), _box(Vector3(0.7, 1.0, 26), Vector3(13, 0.5, 0), stone)]:
		wall.material_override = wall_mat
	var house := _model("res://assets/house.glb", 3.4)
	if house:
		add_child(house)
		house.position += Vector3(-9.3, 0, -9.3)
		house.rotation_degrees.y = 35
	var well := _model("res://assets/well.glb", 2.2)
	if well:
		add_child(well)
		well.position += Vector3(9.5, 0, -9.5)
	for p in [Vector3(-10, 0, 8.5), Vector3(10.5, 0, 8.5), Vector3(-10.5, 0, 0)]:
		var ol := _model("res://assets/olive.glb", 3.1)
		if ol:
			add_child(ol)
			ol.position += p
			ol.rotation_degrees.y = randf_range(0, 360)
	for i in range(3):
		var pp := _model("res://assets/prickly.glb", 1.3)
		if pp:
			add_child(pp)
			pp.position += Vector3(5.0 + i * 2.4, 0, -11.6)
			pp.rotation_degrees.y = randf_range(0, 360)
	luzzu = _model("res://assets/luzzu.glb", 2.4)
	if luzzu:
		add_child(luzzu)
		luzzu.position += Vector3(-4, -0.25, -19)
	for i in range(14):
		var fx := randf_range(-12, 12)
		var fz := (-12.2 if randf() < 0.5 else 12.2) + randf_range(-0.5, 0.5)
		if randf() < 0.4:
			var t2 := fx
			fx = (-12.2 if randf() < 0.5 else 12.2)
			fz = t2
		_cyl(0.02, 0.03, 0.4, Vector3(fx, 0.2, fz), Color(0.3, 0.52, 0.22))
		_sphere(0.12, Vector3(fx, 0.45, fz), [Color(0.95, 0.45, 0.6), Color(0.98, 0.85, 0.3), Color(0.9, 0.9, 0.95), Color(0.85, 0.4, 0.9)][randi() % 4])
	for i in range(6):
		var r := _sphere(randf_range(0.25, 0.5), Vector3(randf_range(-11, 11), 0.1, randf_range(9.5, 11.5)), Color(0.62, 0.58, 0.52))
		r.scale.y = 0.55
	for i in range(3):
		var cl := Node3D.new()
		add_child(cl)
		_sphere(1.4, Vector3(0, 0, 0), Color(1, 1, 1), cl).scale = Vector3(1.6, 0.55, 1)
		_sphere(1.0, Vector3(1.4, 0.15, 0.2), Color(1, 1, 1), cl).scale = Vector3(1.3, 0.5, 1)
		cl.position = Vector3(randf_range(-16, 16), 9.0 + i * 1.2, -6 - i * 4)
		clouds.append(cl)
	for i in range(3):
		var b := Node3D.new()
		add_child(b)
		var col: Color = [Color(1, 1, 1), Color(0.98, 0.85, 0.3), Color(0.9, 0.6, 0.8)][i]
		_box(Vector3(0.22, 0.02, 0.16), Vector3(-0.1, 0, 0), col, b)
		_box(Vector3(0.22, 0.02, 0.16), Vector3(0.1, 0, 0), col, b)
		b.set_meta("bseed", randf() * 100.0)
		butterflies.append(b)
	grid_overlay = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24.2, 24.2)
	grid_overlay.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/tex_grid.png")
	gm.uv1_scale = Vector3(11, 11, 1)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_overlay.material_override = gm
	grid_overlay.position = Vector3(0, 0.03, 0)
	add_child(grid_overlay)

func _house_extras() -> void:
	var stone := Color(0.85, 0.74, 0.55)
	if house_lvl >= 2 and not has_node("hx2"):
		var n := Node3D.new()
		n.name = "hx2"
		add_child(n)
		_box(Vector3(1.8, 1.2, 1.8), Vector3(-7.2, 0.6, -9.8), stone, n)
		_sphere(0.55, Vector3(-7.9, 1.5, -8.9), Color(0.85, 0.3, 0.5), n)
		_sphere(0.4, Vector3(-7.4, 1.3, -8.7), Color(0.9, 0.4, 0.6), n)
	if house_lvl >= 3 and not has_node("hx3"):
		var n := Node3D.new()
		n.name = "hx3"
		add_child(n)
		_cyl(0.5, 0.6, 1.6, Vector3(-11.2, 0.8, -8.2), stone, n)
		_sphere(0.55, Vector3(-11.2, 1.85, -8.2), Color(0.95, 0.8, 0.4), n)
		_box(Vector3(0.06, 0.7, 0.06), Vector3(-11.2, 2.6, -8.2), Color(0.5, 0.35, 0.2), n)
		_box(Vector3(0.5, 0.3, 0.04), Vector3(-10.95, 2.75, -8.2), Color(0.85, 0.2, 0.2), n)

func _build_zone2() -> void:
	zone2_node = Node3D.new()
	add_child(zone2_node)
	var g2 := _box(Vector3(12, 0.5, 26), Vector3(20, -0.25, 0), Color(1, 1, 1), zone2_node)
	g2.material_override = _tmat("res://assets/tex_grass.png", 7.0)
	var stone := Color(0.85, 0.74, 0.55)
	var wm2 := _tmat("res://assets/tex_stone.png", 4.0)
	for w2 in [_box(Vector3(12, 1.0, 0.7), Vector3(20, 0.5, -13), stone, zone2_node), _box(Vector3(12, 1.0, 0.7), Vector3(20, 0.5, 13), stone, zone2_node), _box(Vector3(0.7, 1.0, 26), Vector3(26, 0.5, 0), stone, zone2_node)]:
		w2.material_override = wm2
	var wm := _model("res://assets/windmill.glb", 5.0)
	if wm:
		zone2_node.add_child(wm)
		wm.position += Vector3(24, 0, -9)
		wm.rotation_degrees.y = -110
	zone2_node.visible = false
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
	sun.light_color = Color(1, 0.98, 0.93)
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.96, 0.96, 0.94)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)

# ================= production HUD =================
func _btn_style(b: Button, sel: bool) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 0.84, 0.35) if sel else Color(0.99, 0.95, 0.85)
		if st == "pressed":
			sb.bg_color = sb.bg_color.darkened(0.12)
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.55, 0.38, 0.18)
		sb.set_content_margin_all(6)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(0.32, 0.19, 0.08))
	b.add_theme_color_override("font_pressed_color", Color(0.32, 0.19, 0.08))
	b.add_theme_color_override("font_hover_color", Color(0.32, 0.19, 0.08))

func _panel_style(p: PanelContainer, dark: bool = true) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.07, 0.04, 0.82) if dark else Color(0.99, 0.95, 0.85, 0.95)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.91, 0.71, 0.29)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var chip := PanelContainer.new()
	_panel_style(chip)
	chip.position = Vector2(14, 14)
	ui.add_child(chip)
	coins_label = Label.new()
	coins_label.add_theme_font_size_override("font_size", 24)
	chip.add_child(coins_label)
	var xchip := PanelContainer.new()
	_panel_style(xchip)
	xchip.position = Vector2(14, 74)
	ui.add_child(xchip)
	var xrow := HBoxContainer.new()
	xrow.add_theme_constant_override("separation", 8)
	xchip.add_child(xrow)
	lvl_label = Label.new()
	lvl_label.add_theme_font_size_override("font_size", 16)
	xrow.add_child(lvl_label)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(110, 14)
	xp_bar.show_percentage = false
	var xbg := StyleBoxFlat.new()
	xbg.bg_color = Color(0.25, 0.15, 0.08)
	xbg.set_corner_radius_all(7)
	var xfg := StyleBoxFlat.new()
	xfg.bg_color = Color(0.95, 0.75, 0.25)
	xfg.set_corner_radius_all(7)
	xp_bar.add_theme_stylebox_override("background", xbg)
	xp_bar.add_theme_stylebox_override("fill", xfg)
	xrow.add_child(xp_bar)
	_refresh_xp()
	var title := Label.new()
	title.text = "🥟 Pastizzi Farm  v2.8"
	title.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	title.offset_left = -240
	title.offset_top = 70
	title.add_theme_font_size_override("font_size", 15)
	title.modulate = Color(1, 1, 1, 0.75)
	ui.add_child(title)
	up_btn = Button.new()
	up_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	up_btn.offset_left = -235
	up_btn.offset_right = -14
	up_btn.offset_top = 14
	up_btn.offset_bottom = 58
	up_btn.add_theme_font_size_override("font_size", 14)
	up_btn.pressed.connect(_upgrade_house)
	_btn_style(up_btn, false)
	ui.add_child(up_btn)
	_refresh_up_btn()
	var hp := PanelContainer.new()
	_panel_style(hp)
	hp.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hp.offset_top = -208
	hp.offset_bottom = -160
	hp.offset_left = 12
	hp.offset_right = -12
	ui.add_child(hp)
	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hp.add_child(hint_label)
	var tbar := HBoxContainer.new()
	tbar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tbar.offset_top = -152
	tbar.offset_bottom = -104
	tbar.offset_left = 12
	tbar.offset_right = -12
	tbar.add_theme_constant_override("separation", 8)
	ui.add_child(tbar)
	for t in [["plot", "⛏️ Hoe 🪙25"], ["seed", "🌱 Seeds"], ["water", "🚿 Water 🪙5"], ["shovel", "🧹 Shovel"]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_font_size_override("font_size", 14)
		tb.pressed.connect(_pick_tool.bind(t[0]))
		tbar.add_child(tb)
		tool_btns.append([t[0], tb])
	seed_bar = HBoxContainer.new()
	seed_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	seed_bar.offset_top = -96
	seed_bar.offset_bottom = -14
	seed_bar.offset_left = 12
	seed_bar.offset_right = -12
	seed_bar.add_theme_constant_override("separation", 8)
	ui.add_child(seed_bar)
	for i in range(CROPS.size()):
		var c: Dictionary = CROPS[i]
		var b := Button.new()
		var tree_tag := " 🌳" if c.get("tree", false) else ""
		b.text = "%s %s\n🪙%d · %sm%s" % [c.e, c.name, c.seed, str(c.mins), tree_tag]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_pick_seed.bind(i))
		seed_bar.add_child(b)
		seed_btns.append(b)
	_pick_seed(0)
	_pick_tool("plot")
	_refresh_seed_buttons()
	_update_coins()
	# character select (shown at join until chosen)
	chr_panel = PanelContainer.new()
	_panel_style(chr_panel)
	chr_panel.set_anchors_preset(Control.PRESET_CENTER)
	chr_panel.offset_left = -150
	chr_panel.offset_right = 150
	chr_panel.offset_top = -120
	chr_panel.offset_bottom = 120
	ui.add_child(chr_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	chr_panel.add_child(vb)
	var ct := Label.new()
	ct.text = "🥟 Choose your farmer!"
	ct.add_theme_font_size_override("font_size", 20)
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ct)
	var bb := Button.new()
	bb.text = "👨‍🌾  BOY"
	bb.add_theme_font_size_override("font_size", 22)
	bb.custom_minimum_size = Vector2(0, 56)
	bb.pressed.connect(_choose_chr.bind("m"))
	_btn_style(bb, false)
	vb.add_child(bb)
	var gb2 := Button.new()
	gb2.text = "👩‍🌾  GIRL"
	gb2.add_theme_font_size_override("font_size", 22)
	gb2.custom_minimum_size = Vector2(0, 56)
	gb2.pressed.connect(_choose_chr.bind("f"))
	_btn_style(gb2, false)
	vb.add_child(gb2)
	chr_panel.visible = true

func _choose_chr(c: String) -> void:
	chr = c
	chr_panel.visible = false
	_build_farmer()
	hint_label.text = "🎉 Welcome to your għalqa! Grab the ⛏️ Hoe and till your first patch."
	_save()

func _pick_tool(t: String) -> void:
	tool = t
	for pb in tool_btns:
		_btn_style(pb[1], pb[0] == t)
	seed_bar.visible = (t == "seed")
	grid_overlay.visible = (t == "plot")
	hint_label.text = {
		"plot": "⛏️ HOE: tap any grass tile to till it into soil (🪙%d) — one tile at a time, anywhere you like" % PATCH_COST,
		"seed": "🌱 Pick a seed, tap tilled soil (🌳 trees plant on empty grass)",
		"water": "🚿 Tap a growing crop — 🪙5 cuts 25% of the wait",
		"shovel": "🧹 Tap to dig out a crop or an empty patch",
	}[t]

func _pick_seed(i: int) -> void:
	sel_crop = i
	for j in range(seed_btns.size()):
		_btn_style(seed_btns[j], j == i)

func _update_coins() -> void:
	coins_label.text = "🪙 %d" % coins

func _refresh_up_btn() -> void:
	if house_lvl >= 3:
		up_btn.text = "🏠 Razzett Lv3 MAX (+20%)"
		up_btn.disabled = true
	else:
		up_btn.text = "🏠 Upgrade → 🪙%d (+10%%)" % HOUSE_COSTS[house_lvl]

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
	hint_label.text = "🏠 The razzett grows — all prices +10%!"
	_save()

func _xp_need() -> int:
	return 30 * lvl

func _gain_xp(n: int) -> void:
	xp += n
	while xp >= _xp_need():
		xp -= _xp_need()
		lvl += 1
		confetti_lvl()
	_refresh_xp()
	_refresh_seed_buttons()

func confetti_lvl() -> void:
	_burst(farmer.position if farmer else Vector3.ZERO, Color(1, 0.85, 0.3), 12)
	_float_text(farmer.position if farmer else Vector3.ZERO, "LEVEL %d!" % lvl, Color(1, 0.9, 0.4))
	hint_label.text = "🎉 LEVEL %d! New things unlock as you grow." % lvl

func _refresh_xp() -> void:
	if xp_bar:
		xp_bar.max_value = _xp_need()
		xp_bar.value = xp
	if lvl_label:
		lvl_label.text = "Lv %d" % lvl

func _refresh_seed_buttons() -> void:
	for i in range(seed_btns.size()):
		var c: Dictionary = CROPS[i]
		var need: int = c.get("lvl", 1)
		var tree_tag := " 🌳" if c.get("tree", false) else ""
		if lvl < need:
			seed_btns[i].text = "🔒 Lv%d\n%s %s" % [need, c.e, c.name]
			seed_btns[i].disabled = true
		else:
			seed_btns[i].text = "%s %s\n🪙%d · %sm%s" % [c.e, c.name, c.seed, str(c.mins), tree_tag]
			seed_btns[i].disabled = false

func _mult() -> float:
	return 1.0 + 0.1 * float(house_lvl - 1)

# ================= the grid =================
func _tile_at(world: Vector3) -> Vector2i:
	return Vector2i(int(round(world.x / TILE)), int(round(world.z / TILE)))

func _tile_pos(t: Vector2i) -> Vector3:
	return Vector3(t.x * TILE, 0, t.y * TILE)

func _tile_in_land(t: Vector2i) -> bool:
	if abs(t.y) > 5:
		return false
	if t.x >= -5 and t.x <= 5:
		return true
	if zone2 and t.x >= 7 and t.x <= 11:
		return true
	return false

func _k_of(cidx: int, t: float, rg: bool) -> float:
	var mins: float = CROPS[cidx].mins
	if rg:
		mins = mins * 0.6
	var k: float = clamp((Time.get_unix_time_from_system() - t) / (mins * 60.0), 0.0, 1.0)
	if rg:
		k = max(k, 0.82)
	return k

func _place_patch(tile: Vector2i, pay: bool = true) -> void:
	if pay:
		coins -= PATCH_COST
		_update_coins()
	var soil := _box(Vector3(TILE * 0.94, 0.12, TILE * 0.94), _tile_pos(tile) + Vector3(0, 0.06, 0), Color(1, 1, 1))
	soil.material_override = _tmat("res://assets/tex_soil.png", 1.0)
	grid[tile] = { "k": "patch", "c": -1, "t": 0.0, "rg": false, "node": null, "soil": soil, "mark": null }
	if pay:   # tilling feel: the soil flips up out of the grass + clods fly
		soil.scale = Vector3(0.2, 0.05, 0.2)
		var tw := create_tween()
		tw.tween_property(soil, "scale", Vector3(1.06, 1.3, 1.06), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(soil, "scale", Vector3(1, 1, 1), 0.12)
		for i in range(4):
			var clod := _box(Vector3(0.16, 0.12, 0.16), _tile_pos(tile) + Vector3(0, 0.25, 0), Color(0.45, 0.3, 0.17))
			clod.rotation_degrees = Vector3(randf_range(0, 90), randf_range(0, 90), 0)
			var tw2 := create_tween()
			tw2.set_parallel(true)
			tw2.tween_property(clod, "position", clod.position + Vector3(randf_range(-1.0, 1.0), randf_range(0.7, 1.3), randf_range(-1.0, 1.0)), 0.4)
			tw2.tween_property(clod, "scale", Vector3.ZERO, 0.45)
			tw2.chain().tween_callback(clod.queue_free)

func _plant_at(tile: Vector2i, cidx: int, t: float, rg: bool = false) -> void:
	var crop: Dictionary = CROPS[cidx]
	var e: Dictionary = grid.get(tile, {})
	var holder := Node3D.new()
	holder.position = _tile_pos(tile) + Vector3(0, 0.13, 0)
	add_child(holder)
	var mh: float = crop.h * (1.0 if crop.get("tree", false) else 0.8)
	var m := _model(crop.model, mh)
	if m:
		m.rotation_degrees.y = randf_range(0, 360)
		holder.add_child(m)
	holder.scale = Vector3(0.1, 0.1, 0.1)
	if crop.get("tree", false) and e.is_empty():
		grid[tile] = { "k": "tree", "c": cidx, "t": t, "rg": rg, "node": holder, "soil": null, "mark": null }
	else:
		e.c = cidx
		e.t = t
		e.rg = rg
		e.node = holder
		grid[tile] = e

func _clear_tile(tile: Vector2i, remove_patch: bool) -> void:
	var e: Dictionary = grid.get(tile, {})
	if e.is_empty():
		return
	if e.node and is_instance_valid(e.node):
		e.node.queue_free()
	if e.mark and is_instance_valid(e.mark):
		e.mark.queue_free()
	if e.k == "tree" or (remove_patch and e.soil):
		if e.soil and is_instance_valid(e.soil):
			e.soil.queue_free()
		grid.erase(tile)
	else:
		e.node = null
		e.c = -1
		e.t = 0.0
		e.rg = false
		e.mark = null
		grid[tile] = e

# ================= input =================
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
	if not hit.is_empty():
		if hit.collider.has_meta("gate"):
			if coins < 800:
				hint_label.text = "The orchard costs 🪙800 — keep farming!"
				return
			coins -= 800
			_update_coins()
			_open_zone2()
			_burst(Vector3(13, 1, 0), Color(1, 0.85, 0.3), 12)
			hint_label.text = "🌳 THE ORCHARD IS YOURS — more land to the east!"
			_save()
			return
		if hit.collider.has_meta("egg"):
			coins += 8
			_update_coins()
			_burst(hit.collider.position, Color(0.98, 0.95, 0.85), 5)
			_float_text(hit.collider.position, "+8 🪙", Color(1, 0.9, 0.35))
			eggs.erase(hit.collider)
			hit.collider.queue_free()
			_save()
			return
		if hit.collider.has_meta("milk"):
			coins += 15
			_update_coins()
			_burst(hit.collider.position, Color(0.92, 0.94, 0.97), 5)
			_float_text(hit.collider.position, "+15 🪙", Color(0.9, 0.95, 1))
			milks.erase(hit.collider)
			hit.collider.queue_free()
			_save()
			return
	if abs(dir.y) < 0.001:
		return
	var pt: float = (0.1 - from.y) / dir.y
	if pt <= 0:
		return
	var world := from + dir * pt
	var tile := _tile_at(world)
	if not _tile_in_land(tile):
		return
	var e: Dictionary = grid.get(tile, {})
	# in-Nannu walks to the tile, then does the work
	if not e.is_empty() and e.c >= 0 and _k_of(e.c, e.t, e.rg) >= 1.0:
		_send_farmer(tile, "harvest")
		return
	match tool:
		"plot":
			if not e.is_empty():
				hint_label.text = "That tile is taken — pick an empty one."
				return
			_send_farmer(tile, "plot")
		"seed":
			_send_farmer(tile, "seed_%d" % sel_crop)
		"water":
			_send_farmer(tile, "water")
		"shovel":
			if e.is_empty():
				return
			_send_farmer(tile, "shovel")
	return

func _send_farmer(tile: Vector2i, act: String) -> void:
	if not farmer:
		hint_label.text = "Pick your farmer first! 👨‍🌾👩‍🌾"
		return
	farmer_dest = _tile_pos(tile) + Vector3(1.4, 0, 1.4)
	farmer_act = { "a": act, "tile": tile }
	farmer_busy = true
	hint_label.text = "🚶 On the way…"

func _farmer_arrived() -> void:
	var act: String = farmer_act.get("a", "")
	var tile: Vector2i = farmer_act.get("tile", Vector2i.ZERO)
	farmer_act = {}
	farmer_busy = false
	_do_action(tile, act)

func _do_action(tile: Vector2i, act: String) -> void:
	var e: Dictionary = grid.get(tile, {})
	if act == "harvest":
		if e.is_empty() or e.c < 0 or _k_of(e.c, e.t, e.rg) < 1.0:
			return
		var crop: Dictionary = CROPS[e.c]
		var pay := int(round(crop.pay * _mult()))
		coins += pay
		_update_coins()
		_burst(_tile_pos(tile), Color(1, 0.85, 0.3), 7)
		_float_text(_tile_pos(tile), "+%d 🪙" % pay, Color(1, 0.9, 0.35))
		if e.mark and is_instance_valid(e.mark):
			e.mark.queue_free()
		e.mark = null
		if e.k == "tree":
			e.t = Time.get_unix_time_from_system()
			e.rg = true
			grid[tile] = e
			hint_label.text = "Harvested %s +%d 🪙 — the tree regrows! 🌳" % [crop.name, pay]
		else:
			if e.node and is_instance_valid(e.node):
				e.node.queue_free()
			e.node = null
			e.c = -1
			e.t = 0.0
			grid[tile] = e
			hint_label.text = "Harvested %s — +%d coins!" % [crop.name, pay]
		_gain_xp(4 if e.k == "tree" else 3)
		_save()
		return
	var act_tool := act
	if act.begins_with("seed_"):
		sel_crop = int(act.substr(5))
		act_tool = "seed"
	match act_tool:
		"plot":
			if not e.is_empty():
				hint_label.text = "That tile is taken — pick an empty one."
				return
			if coins < PATCH_COST:
				hint_label.text = "Tilling costs 🪙%d!" % PATCH_COST
				return
			_place_patch(tile)
			_burst(_tile_pos(tile), Color(0.5, 0.35, 0.2), 5)
			hint_label.text = "⛏️ Tilled! Switch to 🌱 Seeds to plant it."
			_gain_xp(2)
			_save()
		"seed":
			var crop: Dictionary = CROPS[sel_crop]
			if lvl < crop.get("lvl", 1):
				hint_label.text = "🔒 %s unlocks at level %d — keep farming!" % [crop.name, crop.get("lvl", 1)]
				return
			if crop.get("tree", false):
				if not e.is_empty():
					hint_label.text = "🌳 Trees need an empty GRASS tile (no patch)."
					return
				if coins < crop.seed:
					hint_label.text = "Not enough coins (🪙%d)!" % crop.seed
					return
				coins -= crop.seed
				_update_coins()
				_plant_at(tile, sel_crop, Time.get_unix_time_from_system())
				_burst(_tile_pos(tile), Color(0.5, 0.35, 0.2), 5)
				hint_label.text = "%s tree planted — it will produce forever! 🌳" % crop.name
				_gain_xp(2)
				_save()
			else:
				if e.is_empty() or e.get("k") != "patch":
					hint_label.text = "Field crops need tilled soil — use the ⛏️ Hoe first!"
					return
				if e.c >= 0:
					hint_label.text = "This patch is busy — it's growing."
					return
				if coins < crop.seed:
					hint_label.text = "Not enough coins (🪙%d)!" % crop.seed
					return
				coins -= crop.seed
				_update_coins()
				_plant_at(tile, sel_crop, Time.get_unix_time_from_system())
				_burst(_tile_pos(tile), Color(0.5, 0.35, 0.2), 3)
				hint_label.text = "%s %s planted — %s min" % [crop.e, crop.name, str(crop.mins)]
				_gain_xp(1)
				_save()
		"water":
			if e.is_empty() or e.c < 0 or _k_of(e.c, e.t, e.rg) >= 1.0:
				hint_label.text = "Nothing growing there to water."
				return
			if coins < 5:
				hint_label.text = "Watering costs 🪙5"
				return
			coins -= 5
			_update_coins()
			var mins: float = CROPS[e.c].mins * (0.6 if e.rg else 1.0)
			var left: float = mins * 60.0 - (Time.get_unix_time_from_system() - e.t)
			e.t -= left * 0.25
			grid[tile] = e
			_burst(_tile_pos(tile), Color(0.4, 0.7, 1.0), 6)
			_float_text(_tile_pos(tile), "🚿 -25%", Color(0.55, 0.8, 1))
			hint_label.text = "Watered — 25% faster!"
			_gain_xp(1)
			_save()
		"shovel":
			if e.is_empty():
				return
			_clear_tile(tile, e.c < 0)
			_burst(_tile_pos(tile), Color(0.5, 0.35, 0.2), 5)
			hint_label.text = "Cleared."
			_save()

# ================= animals =================
func _build_animals() -> void:
	chicken = Node3D.new()
	add_child(chicken)
	var mc := _model("res://assets/chicken.glb", 1.15)
	if mc:
		chicken.add_child(mc)
	chicken.position = Vector3(7, 0, 7)
	chick_target = chicken.position
	goat = Node3D.new()
	add_child(goat)
	var mg := _model("res://assets/goat.glb", 1.5)
	if mg:
		goat.add_child(mg)
	goat.position = Vector3(-7, 0, 5)
	goat_target = goat.position
	donkey = Node3D.new()
	add_child(donkey)
	var md := _model("res://assets/donkey.glb", 1.8)
	if md:
		donkey.add_child(md)
	donkey.position = Vector3(9, 0, -3)
	donkey_target = donkey.position
	dog = Node3D.new()
	add_child(dog)
	var mdg := _model("res://assets/dog.glb", 1.4)
	if mdg:
		dog.add_child(mdg)
	dog.position = Vector3(-9, 0, 9)

func _build_farmer() -> void:
	if chr == "":
		return
	if farmer:
		farmer.queue_free()
	if other:
		other.queue_free()
	farmer = Node3D.new()
	add_child(farmer)
	var base := "man" if chr == "m" else "woman"
	farmer_walk_n = _model("res://assets/%s_walk.glb" % base, 1.9)
	if farmer_walk_n:
		farmer.add_child(farmer_walk_n)
		farmer_ap = _anim_setup(farmer_walk_n, false)
		farmer_walk_n.visible = false
	farmer_idle_n = _model("res://assets/%s_idle.glb" % base, 1.9)
	if farmer_idle_n:
		farmer.add_child(farmer_idle_n)
		farmer_idle_ap = _anim_setup(farmer_idle_n, true)
	farmer_harv_n = _model("res://assets/%s_harvest.glb" % base, 1.9)
	if farmer_harv_n:
		farmer.add_child(farmer_harv_n)
		farmer_harv_ap = _anim_setup(farmer_harv_n, false)
		farmer_harv_n.visible = false
	farmer.position = Vector3(-7.5, 0, -7.5)
	farmer_dest = farmer.position
	# the other one strolls the farm
	other = Node3D.new()
	add_child(other)
	var ob := "woman" if chr == "m" else "man"
	var om := _model("res://assets/%s_walk.glb" % ob, 1.9)
	if om:
		other.add_child(om)
		_anim_setup(om, true)
	other.position = Vector3(6, 0, 9)
	other_t = other.position

func _worker_mode(mode: String) -> void:
	if farmer_walk_n:
		farmer_walk_n.visible = mode == "walk"
	if farmer_idle_n:
		farmer_idle_n.visible = mode == "idle"
	if farmer_harv_n:
		farmer_harv_n.visible = mode == "harv"
	if mode == "walk" and farmer_ap and not farmer_ap.is_playing():
		farmer_ap.play(farmer_ap.get_animation_list()[0])
	if mode == "idle" and farmer_idle_ap and not farmer_idle_ap.is_playing():
		farmer_idle_ap.play(farmer_idle_ap.get_animation_list()[0])
	if mode == "harv" and farmer_harv_ap:
		farmer_harv_ap.play(farmer_harv_ap.get_animation_list()[0])

func _build_kids() -> void:
	kid_b = Node3D.new()
	add_child(kid_b)
	var mb := _model("res://assets/boy.glb", 1.55)
	if mb:
		kid_b.add_child(mb)
		_anim_setup(mb, true)
	kid_b.position = Vector3(4, 0, 10)
	kid_b_t = kid_b.position
	kid_g = Node3D.new()
	add_child(kid_g)
	var mg2 := _model("res://assets/girl.glb", 1.55)
	if mg2:
		kid_g.add_child(mg2)
		_anim_setup(mg2, true)
	kid_g.position = Vector3(-4, 0, 10)
	kid_g_t = kid_g.position

func _kid_walk(n: Node3D, target: Vector3, speed: float, delta: float) -> Vector3:
	if n.position.distance_to(target) < 0.4:
		return _roam_spot()
	var dir := (target - n.position).normalized()
	n.position += dir * delta * speed
	n.look_at(n.position + dir)
	n.rotate_y(PI)
	return target

func _roam_spot() -> Vector3:
	for i in range(12):
		var v := Vector3(randf_range(-11.5, 11.5), 0, randf_range(-11.5, 11.5))
		if abs(v.x) > 7.2 or v.z < -7.2 or v.z > 10.0:
			return v
	return Vector3(9, 0, 9)

func _walk(n: Node3D, target: Vector3, speed: float, bob_ms: float, delta: float) -> Vector3:
	if n.position.distance_to(target) < 0.3:
		return _roam_spot()
	var dir := (target - n.position).normalized()
	n.position += dir * delta * speed
	n.position.y = abs(sin(Time.get_ticks_msec() / bob_ms)) * 0.08
	n.look_at(n.position + dir)
	n.rotate_y(PI)
	return target

# ================= live loop =================
func _process(delta: float) -> void:
	for tile in grid:
		var e: Dictionary = grid[tile]
		if e.c >= 0 and e.node and is_instance_valid(e.node):
			var k: float = _k_of(e.c, e.t, e.rg)
			var ms: float = 0.12 + 0.88 * k
			if k >= 1.0:
				ms = 1.0 + sin(Time.get_ticks_msec() / 200.0) * 0.07
				if not e.mark:
					var l := Label3D.new()
					l.text = "!"
					l.font_size = 110
					l.modulate = Color(1, 0.85, 0.25)
					l.outline_size = 20
					l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					l.position = _tile_pos(tile) + Vector3(0, 2.4, 0)
					add_child(l)
					e.mark = l
					grid[tile] = e
				elif is_instance_valid(e.mark):
					e.mark.position.y = 2.4 + sin(Time.get_ticks_msec() / 250.0) * 0.15
			elif k > 0.25:
				e.node.rotation.z = sin(Time.get_ticks_msec() / 420.0 + float(tile.x) * 1.7 + float(tile.y)) * 0.05
			e.node.scale = Vector3(ms, ms, ms)
	if farmer and farmer_busy:
		var fd := farmer_dest - farmer.position
		fd.y = 0
		if fd.length() < 0.4:
			farmer.position.y = 0
			if farmer_act.get("a", "") == "harvest" and farmer_harv_ap:
				_worker_mode("harv")
				var held: Dictionary = farmer_act
				farmer_act = {}
				farmer_busy = false
				var tw := create_tween()
				tw.tween_interval(0.9)
				tw.tween_callback(func():
					_do_action(held.tile, "harvest")
					_worker_mode("idle"))
			else:
				_worker_mode("idle")
				_farmer_arrived()
		else:
			_worker_mode("walk")
			var fdir := fd.normalized()
			farmer.position += fdir * delta * 3.2
			farmer.look_at(farmer.position + fdir)
			farmer.rotate_y(PI)
	if other:
		other_t = _kid_walk(other, other_t, 0.9, delta)
	kid_b_t = _kid_walk(kid_b, kid_b_t, 1.15, delta)
	kid_g_t = _kid_walk(kid_g, kid_g_t, 1.05, delta)
	chick_target = _walk(chicken, chick_target, 1.1, 90.0, delta)
	goat_target = _walk(goat, goat_target, 0.8, 130.0, delta)
	donkey_target = _walk(donkey, donkey_target, 0.55, 170.0, delta)
	var to_chick := chicken.position - dog.position
	if to_chick.length() > 2.2:
		var ddir := to_chick.normalized()
		dog.position += ddir * delta * 1.0
		dog.position.y = abs(sin(Time.get_ticks_msec() / 80.0)) * 0.12
		dog.look_at(dog.position + ddir)
		dog.rotate_y(PI)
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
	for cl in clouds:
		cl.position.x += delta * 0.45
		if cl.position.x > 22:
			cl.position.x = -22
	if luzzu:
		luzzu.position.x += delta * 0.25
		if luzzu.position.x > 16:
			luzzu.position.x = -16
		luzzu.rotation.z = sin(Time.get_ticks_msec() / 700.0) * 0.05
	for b in butterflies:
		var sd: float = b.get_meta("bseed")
		var tt := Time.get_ticks_msec() / 1000.0 + sd
		b.position = Vector3(sin(tt * 0.5) * 9.0 + sin(tt * 1.7), 1.2 + sin(tt * 2.2) * 0.35, cos(tt * 0.37) * 9.0)
		b.rotation.y = tt
		var flap := absf(sin(tt * 14.0))
		var wi := 0
		for w in b.get_children():
			w.rotation.z = (0.9 - flap) * (1.0 if wi == 0 else -1.0)
			wi += 1
	day_t += delta
	var a := day_t * TAU / DAY_SECONDS
	var daylight := 0.55 + 0.45 * sin(a)
	sun.rotation_degrees = Vector3(-30.0 - 35.0 * daylight, -30.0 + 15.0 * sin(a * 0.5), 0)
	sun.light_energy = clamp(0.35 + 0.65 * daylight, 0.35, 1.0)
	env.background_color = Color(0.10, 0.14, 0.30).lerp(Color(0.53, 0.75, 0.92), clamp(daylight, 0.0, 1.0))
	env.ambient_light_energy = 0.32 + 0.3 * daylight

# ================= save / load =================
func _save() -> void:
	var tiles := {}
	for tile in grid:
		var e: Dictionary = grid[tile]
		tiles["%d,%d" % [tile.x, tile.y]] = { "k": e.k, "c": e.c, "t": e.t, "rg": e.rg }
	var d := { "v": 2, "coins": coins, "hl": house_lvl, "z2": zone2, "xp": xp, "lvl": lvl, "chr": chr, "tiles": tiles }
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
	coins = int(d.get("coins", 120))
	chr = str(d.get("chr", ""))
	if chr != "":
		chr_panel.visible = false
		_build_farmer()
	xp = int(d.get("xp", 0))
	lvl = int(d.get("lvl", 1))
	_refresh_xp()
	_refresh_seed_buttons()
	house_lvl = int(d.get("hl", 1))
	_house_extras()
	_refresh_up_btn()
	if d.get("z2", false):
		_open_zone2()
	var tiles: Dictionary = d.get("tiles", {})
	for key in tiles:
		var parts: PackedStringArray = key.split(",")
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var e: Dictionary = tiles[key]
		var ci := int(e.get("c", -1))
		if e.get("k") == "tree" and ci >= 0 and ci < CROPS.size():
			_plant_at(tile, ci, float(e.get("t", 0)), bool(e.get("rg", false)))
		else:
			_place_patch(tile, false)
			if ci >= 0 and ci < CROPS.size():
				_plant_at(tile, ci, float(e.get("t", 0)), bool(e.get("rg", false)))
	_update_coins()
