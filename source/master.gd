extends Node3D
# ============================================================
#  PASTIZZI MASTER 3D — M1 "The Loop"  (v3.0)
#  Slot (50-spin meter, 5/hr regen, bet x1-x10) -> coins ->
#  buy building stars (5 buildings x 5 stars, 3D upgrades) ->
#  village complete -> sail to next village.
# ============================================================

const SAVE := "user://master1.json"
const SPIN_CAP := 50
const REGEN_SECS := 720.0          # 5 spins/hour = 1 per 720s
const VILLAGES := ["Birgu", "Marsaxlokk", "L-Imdina", "Valletta", "Għawdex"]
const V_TINT := [Color(0.62,0.6,0.78), Color(0.55,0.68,0.82), Color(0.72,0.62,0.7), Color(0.66,0.6,0.62), Color(0.55,0.72,0.62)]
const B_NAMES := ["Il-Forn", "Il-Knisja", "It-Torri", "Il-Luzzu", "Il-Monti"]
const B_ICONS := ["🥟", "⛪", "🗼", "🛶", "🏪"]

# ---------- state ----------
var coins := 3000
var spins := 25
var last_ts := 0
var village := 0
var stars := [0, 0, 0, 0, 0]
var bet := 1
var slot_spinning := false
var slot_prize := {}
var slot_elapsed := 0.0
var reel_stop := [0.9, 1.5, 2.1]
var reel_done := [false, false, false]
var reel_stopping := [false, false, false]
var rp := [0.0, 0.0, 0.0]           # reel scroll position, in cells
const SYMS_ORDER := ["sack", "big", "attack", "raid", "energy", "small"]
const CELL := 80.0
var sailing := false
var sail_t := 0.0

# ---------- nodes ----------
var cam: Camera3D
var env: Environment
var luzzu: Node3D
var b_roots: Array = [null, null, null, null, null]
var wander_a: Node3D
var wander_b: Node3D
var wt_a := Vector3.ZERO
var wt_b := Vector3.ZERO
var t := 0.0

# ---------- ui ----------
var ui: CanvasLayer
var lbl_coins: Label
var lbl_spins: Label
var lbl_regen: Label
var lbl_village: Label
var lbl_hint: Label
var slot_panel: PanelContainer
var reels: Array = []
var lbl_slotmsg: Label
var btn_spin: Button
var bet_btns: Array = []
var build_panel: PanelContainer
var build_rows: Array = []

func _ready() -> void:
	randomize()
	_load()
	_build_world()
	_build_ui()
	_refresh_all()

# ============ WORLD ============
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

func _prism(size: Vector3, pos: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
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

func _anim_setup(n: Node3D) -> void:
	if not n:
		return
	var aps := n.find_children("*", "AnimationPlayer", true)
	if aps.is_empty():
		return
	var ap: AnimationPlayer = aps[0]
	for an in ap.get_animation_list():
		ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	if ap.get_animation_list().size() > 0:
		ap.play(ap.get_animation_list()[0])

func _build_world() -> void:
	# island
	var side := _box(Vector3(16, 3.4, 16), Vector3(0, -1.7, 0), Color(1, 1, 1))
	side.material_override = _tmat("res://assets/tex_stone.png", 5.0)
	var top := _box(Vector3(15.6, 0.5, 15.6), Vector3(0, 0.2, 0), Color(1, 1, 1))
	top.material_override = _tmat("res://assets/tex_grass.png", 6.0)
	var plaza := _box(Vector3(9, 0.14, 9), Vector3(0.5, 0.5, 0.5), Color(0.88, 0.78, 0.6))
	plaza.material_override = _tmat("res://assets/tex_stone.png", 7.0)
	var tier := _box(Vector3(9, 1.2, 6), Vector3(1, 0.9, -4.5), Color(1, 1, 1))
	tier.material_override = _tmat("res://assets/tex_stone.png", 4.0)
	for i in range(3):
		_box(Vector3(3, 0.28, 0.7), Vector3(0, 0.55 + i * 0.28, -1.2 - i * 0.62), Color(0.86, 0.76, 0.58))
	# sea + dock
	_box(Vector3(60, 0.3, 60), Vector3(0, -3.6, 0), Color(0.24, 0.62, 0.78))
	_box(Vector3(3.4, 0.35, 2.2), Vector3(-8.2, -2.4, 5.6), Color(0.52, 0.36, 0.2))
	for px in [-9.4, -7.0]:
		for pz in [4.7, 6.5]:
			_cyl(0.12, 0.12, 1.4, Vector3(px, -3.0, pz), Color(0.42, 0.28, 0.15))
	# greenery
	var ol := _model("res://assets/olive.glb", 2.6)
	if ol:
		add_child(ol)
		ol.position += Vector3(-6.2, 0.45, -4.6)
	var ol2 := _model("res://assets/olive.glb", 2.2)
	if ol2:
		add_child(ol2)
		ol2.position += Vector3(6.4, 0.45, 4.6)
		ol2.rotation_degrees.y = 160
	var pr := _model("res://assets/prickly.glb", 1.0)
	if pr:
		add_child(pr)
		pr.position += Vector3(-6.6, 0.45, 4.4)
	# lamps
	for lp in [Vector3(-2.6, 0.55, 3.4), Vector3(3.6, 0.55, 3.2)]:
		_cyl(0.06, 0.09, 1.7, lp + Vector3(0, 0.85, 0), Color(0.16, 0.24, 0.45))
		_sphere(0.17, lp + Vector3(0, 1.85, 0), Color(1, 0.9, 0.55))
	# wandering characters for life
	wander_a = Node3D.new()
	add_child(wander_a)
	var ma := _model("res://assets/man_walk.glb", 1.7)
	if ma:
		wander_a.add_child(ma)
		_anim_setup(ma)
	wander_a.position = Vector3(3, 0.55, 2)
	wt_a = wander_a.position
	wander_b = Node3D.new()
	add_child(wander_b)
	var mb := _model("res://assets/woman_walk.glb", 1.65)
	if mb:
		wander_b.add_child(mb)
		_anim_setup(mb)
	wander_b.position = Vector3(-2, 0.55, 1)
	wt_b = wander_b.position
	# buildings at current star levels
	for b in range(5):
		_rebuild_building(b)
	# camera / light / sky
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.5
	cam.position = Vector3(13, 12.5, 13)
	add_child(cam)
	cam.look_at(Vector3(0, -0.6, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.05
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = V_TINT[village % V_TINT.size()]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.93, 1.0)
	env.ambient_light_energy = 0.65
	we.environment = env
	add_child(we)

const B_POS := [Vector3(-4.6, 0.45, 0.6), Vector3(1.0, 1.55, -4.5), Vector3(5.4, 0.45, -1.2), Vector3(-5.6, -3.3, 7.6), Vector3(2.6, 0.55, 4.6)]

func _rebuild_building(b: int) -> void:
	if b_roots[b]:
		b_roots[b].queue_free()
	var root := Node3D.new()
	add_child(root)
	root.position = B_POS[b]
	b_roots[b] = root
	var lvl: int = stars[b]
	if lvl == 0:
		# empty plot: dirt + sign
		var d := _box(Vector3(2.4, 0.1, 2.4), Vector3(0, 0.05, 0), Color(0.62, 0.48, 0.3), root)
		d.material_override = _tmat("res://assets/tex_soil.png", 1.0)
		_cyl(0.05, 0.05, 0.9, Vector3(0.8, 0.45, 0.8), Color(0.45, 0.3, 0.16), root)
		_box(Vector3(0.7, 0.4, 0.06), Vector3(0.8, 0.95, 0.8), Color(0.85, 0.72, 0.45), root)
		if b == 3:
			root.position = Vector3(-5.6, -3.2, 7.6)
		return
	var s := 0.55 + 0.1125 * lvl        # scale grows with stars: 0.66 -> 1.11
	match b:
		0:  # bakery
			var m := _model("res://assets/house.glb", 3.2 * s)
			if m:
				root.add_child(m)
				m.rotation_degrees.y = 32
		1:  # church (primitives until Meshy model approved)
			_box(Vector3(2.6 * s, 1.8 * s, 3.4 * s), Vector3(0, 0.9 * s, 0), Color(0.9, 0.82, 0.66), root)
			_prism(Vector3(2.8 * s, 1.0 * s, 3.6 * s), Vector3(0, 2.3 * s, 0), Color(0.72, 0.3, 0.24), root)
			_box(Vector3(0.8 * s, 1.4 * s, 0.8 * s), Vector3(-0.8 * s, 3.2 * s, -1.0 * s), Color(0.9, 0.82, 0.66), root)
			_prism(Vector3(0.9 * s, 0.6 * s, 0.9 * s), Vector3(-0.8 * s, 4.2 * s, -1.0 * s), Color(0.85, 0.7, 0.4), root)
			if lvl >= 3:
				_cyl(0.04, 0.04, 0.8, Vector3(0.9 * s, 3.2 * s, 0), Color(0.5, 0.35, 0.2), root)
				_box(Vector3(0.5, 0.3, 0.02), Vector3(1.15 * s, 3.45 * s, 0), Color(0.9, 0.15, 0.2), root)
		2:  # tower
			var m := _model("res://assets/windmill.glb", 5.2 * s)
			if m:
				root.add_child(m)
				m.rotation_degrees.y = -105
		3:  # luzzu + dock upgrades
			var m := _model("res://assets/luzzu.glb", 1.9 * (0.8 + 0.08 * lvl))
			if m:
				root.add_child(m)
				m.rotation_degrees.y = 25
			luzzu = root
		4:  # market stall
			_box(Vector3(2.2 * s, 0.8 * s, 1.0 * s), Vector3(0, 0.4 * s, 0), Color(0.62, 0.44, 0.26), root)
			for i in range(6):
				_box(Vector3(0.36 * s, 0.06, 1.5 * s), Vector3((-0.9 + i * 0.36) * s, 1.35 * s, 0), (Color(0.2, 0.4, 0.75) if i % 2 == 0 else Color(0.97, 0.96, 0.92)), root)
			for cx in [-1.0, 1.0]:
				_cyl(0.05, 0.05, 1.3 * s, Vector3(cx * s, 0.75 * s, 0.6 * s), Color(0.45, 0.3, 0.16), root)
	# star decorations
	if lvl >= 2 and b != 3:
		_sphere(0.14, Vector3(1.1, 0.35, 1.1), Color(0.92, 0.4, 0.5), root)
		_sphere(0.14, Vector3(-1.1, 0.35, 1.1), Color(0.95, 0.7, 0.3), root)
	if lvl >= 4 and b != 3:
		_cyl(0.04, 0.04, 2.2, Vector3(1.4, 1.1, -0.8), Color(0.5, 0.35, 0.2), root)
		_box(Vector3(0.6, 0.4, 0.02), Vector3(1.7, 1.9, -0.8), Color(0.95, 0.95, 0.95), root)
		_box(Vector3(0.3, 0.4, 0.021), Vector3(1.85, 1.9, -0.8), Color(0.8, 0.15, 0.18), root)
	if lvl >= 5:
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.85, 0.4)
		glow.light_energy = 1.6
		glow.omni_range = 4.0
		glow.position = Vector3(0, 2.2, 0)
		root.add_child(glow)

# ============ ECONOMY ============
func _star_cost(b: int, s: int) -> int:
	return int(500.0 * (1.0 + 0.3 * b) * (1.0 + 0.75 * s) * pow(1.7, village))

func _total_stars() -> int:
	var n := 0
	for v in stars:
		n += int(v)
	return n

# ============ UI ============
func _style(p: PanelContainer, bg: Color = Color(0.09, 0.05, 0.04, 0.94)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.border_color = Color(0.91, 0.71, 0.29)
	sb.set_border_width_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)

func _bstyle(b: Button, gold: bool = false) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.91, 0.71, 0.29) if gold else Color(0.55, 0.16, 0.14)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color(0.2, 0.1, 0.02) if gold else Color(1, 0.95, 0.9))

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	# top bar
	var top := PanelContainer.new()
	_style(top)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 8
	ui.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	top.add_child(hb)
	lbl_coins = Label.new()
	lbl_coins.add_theme_font_size_override("font_size", 19)
	hb.add_child(lbl_coins)
	lbl_spins = Label.new()
	lbl_spins.add_theme_font_size_override("font_size", 19)
	hb.add_child(lbl_spins)
	lbl_regen = Label.new()
	lbl_regen.add_theme_font_size_override("font_size", 13)
	lbl_regen.modulate = Color(1, 1, 1, 0.75)
	hb.add_child(lbl_regen)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	lbl_village = Label.new()
	lbl_village.add_theme_font_size_override("font_size", 17)
	hb.add_child(lbl_village)
	# hint
	lbl_hint = Label.new()
	lbl_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_hint.offset_top = 64
	lbl_hint.offset_left = 14
	lbl_hint.offset_right = -14
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.add_theme_font_size_override("font_size", 15)
	lbl_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	lbl_hint.add_theme_constant_override("shadow_offset_y", 2)
	lbl_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	ui.add_child(lbl_hint)
	# bottom bar
	var bot := HBoxContainer.new()
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_bottom = -14
	bot.offset_top = -74
	bot.offset_left = 14
	bot.offset_right = -14
	bot.add_theme_constant_override("separation", 12)
	ui.add_child(bot)
	var bslot := Button.new()
	bslot.text = "🎰 SLOT"
	bslot.add_theme_font_size_override("font_size", 22)
	bslot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bslot.custom_minimum_size = Vector2(0, 58)
	_bstyle(bslot, true)
	bslot.pressed.connect(func(): _toggle(slot_panel))
	bot.add_child(bslot)
	var bbuild := Button.new()
	bbuild.text = "🏗️ BUILD"
	bbuild.add_theme_font_size_override("font_size", 22)
	bbuild.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bbuild.custom_minimum_size = Vector2(0, 58)
	_bstyle(bbuild)
	bbuild.pressed.connect(func(): _toggle(build_panel); _refresh_build())
	bot.add_child(bbuild)
	# ----- slot panel -----
	slot_panel = PanelContainer.new()
	_style(slot_panel, Color(0.32, 0.09, 0.08, 0.97))
	slot_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	slot_panel.offset_left = -168
	slot_panel.offset_right = 168
	slot_panel.offset_top = -382
	slot_panel.offset_bottom = -86
	slot_panel.visible = false
	ui.add_child(slot_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	slot_panel.add_child(sv)
	var st := Label.new()
	st.text = "🎰 VIVA IL-FESTA!"
	st.add_theme_font_size_override("font_size", 22)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_color_override("font_color", Color(1, 0.87, 0.5))
	sv.add_child(st)
	var rh := HBoxContainer.new()
	rh.alignment = BoxContainer.ALIGNMENT_CENTER
	rh.add_theme_constant_override("separation", 10)
	sv.add_child(rh)
	reels.clear()
	for i in range(3):
		var win := Panel.new()
		var wsb := StyleBoxFlat.new()
		wsb.bg_color = Color(0.97, 0.93, 0.82, 1)
		wsb.corner_radius_top_left = 12
		wsb.corner_radius_top_right = 12
		wsb.corner_radius_bottom_left = 12
		wsb.corner_radius_bottom_right = 12
		wsb.border_color = Color(0.62, 0.44, 0.1)
		wsb.set_border_width_all(2)
		win.add_theme_stylebox_override("panel", wsb)
		win.custom_minimum_size = Vector2(84, 88)
		win.clip_contents = true
		var strip := Control.new()
		win.add_child(strip)
		for j in range(18):
			var c := Label.new()
			c.text = SYM[SYMS_ORDER[j % 6]]
			c.add_theme_font_size_override("font_size", 40)
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			c.position = Vector2(0, j * CELL)
			c.size = Vector2(84, CELL)
			strip.add_child(c)
		rh.add_child(win)
		reels.append(strip)
		rp[i] = float(i * 2)
		_update_reel(i)
	lbl_slotmsg = Label.new()
	lbl_slotmsg.text = "Match 3 to win!"
	lbl_slotmsg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_slotmsg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_slotmsg.custom_minimum_size = Vector2(0, 44)
	lbl_slotmsg.add_theme_font_size_override("font_size", 14)
	sv.add_child(lbl_slotmsg)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 8)
	sv.add_child(bh)
	var bl := Label.new()
	bl.text = "Bet:"
	bh.add_child(bl)
	bet_btns.clear()
	for m in [1, 2, 5, 10]:
		var bb := Button.new()
		bb.text = "x%d" % m
		bb.custom_minimum_size = Vector2(52, 40)
		_bstyle(bb)
		bb.pressed.connect(_set_bet.bind(m))
		bh.add_child(bb)
		bet_btns.append(bb)
	btn_spin = Button.new()
	btn_spin.text = "SPIN!"
	btn_spin.add_theme_font_size_override("font_size", 24)
	btn_spin.custom_minimum_size = Vector2(0, 56)
	_bstyle(btn_spin, true)
	btn_spin.pressed.connect(_spin)
	sv.add_child(btn_spin)
	# ----- build panel -----
	build_panel = PanelContainer.new()
	_style(build_panel)
	build_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_panel.offset_left = -180
	build_panel.offset_right = 180
	build_panel.offset_top = -418
	build_panel.offset_bottom = -86
	build_panel.visible = false
	ui.add_child(build_panel)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	build_panel.add_child(bv)
	var bt := Label.new()
	bt.text = "🏗️ Build your village"
	bt.add_theme_font_size_override("font_size", 20)
	bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bt.add_theme_color_override("font_color", Color(1, 0.87, 0.5))
	bv.add_child(bt)
	build_rows.clear()
	for b in range(5):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		bv.add_child(row)
		var nm := Label.new()
		nm.add_theme_font_size_override("font_size", 15)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var stl := Label.new()
		stl.add_theme_font_size_override("font_size", 15)
		stl.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
		row.add_child(stl)
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(118, 42)
		_bstyle(buy, true)
		buy.pressed.connect(_buy_star.bind(b))
		row.add_child(buy)
		build_rows.append({ "nm": nm, "st": stl, "buy": buy })

func _update_reel(i: int) -> void:
	var strip: Control = reels[i]
	strip.position = Vector2(0, 4.0 - (fposmod(rp[i], 6.0) + 6.0) * CELL)

func _toggle(p: PanelContainer) -> void:
	var was: bool = p.visible
	slot_panel.visible = false
	build_panel.visible = false
	p.visible = not was

# ============ SLOT ============
const PRIZES := [
	{ "k": "sack",   "w": 34, "txt": "Coins!" },
	{ "k": "big",    "w": 12, "txt": "BIG coins!" },
	{ "k": "attack", "w": 12, "txt": "ATTACK bounty! (full attacks in next update)" },
	{ "k": "raid",   "w": 7,  "txt": "RAID bounty! (full raids in next update)" },
	{ "k": "energy", "w": 12, "txt": "Free spins!" },
	{ "k": "small",  "w": 23, "txt": "A few coins" },
]
const SYM := { "sack": "💰", "big": "👑", "attack": "🔨", "raid": "🦊", "energy": "⚡", "small": "🥟" }

func _set_bet(m: int) -> void:
	bet = m
	_refresh_all()

func _spin() -> void:
	if slot_spinning or sailing:
		return
	if spins < bet:
		lbl_slotmsg.text = "Not enough spins — regen is 5/hour, or lower the bet!"
		return
	spins -= bet
	slot_spinning = true
	slot_elapsed = 0.0
	reel_done = [false, false, false]
	reel_stopping = [false, false, false]
	# pick prize by weight
	var tw := 0
	for p in PRIZES:
		tw += int(p.w)
	var r := randi() % tw
	for p in PRIZES:
		r -= int(p.w)
		if r < 0:
			slot_prize = p
			break
	lbl_slotmsg.text = "..."
	_refresh_all()
	_save()

func _slot_payout() -> void:
	var k: String = slot_prize.k
	var msg: String = slot_prize.txt
	if k == "sack":
		var n := (300 + randi() % 400) * bet
		coins += n
		msg = "💰 +%d coins!" % n
	elif k == "big":
		var n := (1200 + randi() % 1300) * bet
		coins += n
		msg = "👑 JACKPOT +%d coins!" % n
	elif k == "attack":
		var n := (800 + randi() % 800) * bet
		coins += n
		msg = "🔨 Attack bounty +%d! (real attacks: next update)" % n
	elif k == "raid":
		var n := (1500 + randi() % 1500) * bet
		coins += n
		msg = "🦊 Raid bounty +%d! (real raids: next update)" % n
	elif k == "energy":
		var n := (2 + randi() % 3) * bet
		spins += n
		msg = "⚡ +%d free spins!" % n
	else:
		var n := (80 + randi() % 170) * bet
		coins += n
		msg = "🥟 +%d coins" % n
	lbl_slotmsg.text = msg
	lbl_hint.text = msg
	_refresh_all()
	_save()

# ============ BUILD ============
func _buy_star(b: int) -> void:
	if stars[b] >= 5:
		return
	var cost := _star_cost(b, stars[b])
	if coins < cost:
		lbl_hint.text = "Need 🪙%d — spin the slot!" % cost
		return
	coins -= cost
	stars[b] += 1
	_rebuild_building(b)
	_refresh_all()
	_refresh_build()
	lbl_hint.text = "⭐ %s is now %d-star!" % [B_NAMES[b], stars[b]]
	_save()
	if _total_stars() >= 25:
		_village_complete()

func _village_complete() -> void:
	sailing = true
	sail_t = 0.0
	spins += 15
	coins += 2000 * (village + 1)
	lbl_hint.text = "🎉 %s COMPLETE! +15 spins! Sailing on…" % VILLAGES[village % VILLAGES.size()]
	slot_panel.visible = false
	build_panel.visible = false
	_save()

func _arrive_next() -> void:
	village += 1
	stars = [0, 0, 0, 0, 0]
	for b in range(5):
		_rebuild_building(b)
	env.background_color = V_TINT[village % V_TINT.size()]
	sailing = false
	lbl_hint.text = "⛵ Welcome to %s! Build it to 25 stars." % VILLAGES[village % VILLAGES.size()]
	_refresh_all()
	_save()

# ============ HUD ============
func _refresh_all() -> void:
	lbl_coins.text = "🪙 %d" % coins
	lbl_spins.text = "🎰 %d/%d" % [spins, SPIN_CAP]
	lbl_village.text = "%s ⭐%d/25" % [VILLAGES[village % VILLAGES.size()], _total_stars()]
	for i in range(bet_btns.size()):
		var m: int = [1, 2, 5, 10][i]
		bet_btns[i].modulate = Color(1, 1, 1, 1.0 if m == bet else 0.55)
	btn_spin.text = "SPIN!  (x%d = %d 🎰)" % [bet, bet]
	btn_spin.disabled = slot_spinning or spins < bet

func _refresh_build() -> void:
	for b in range(5):
		var r: Dictionary = build_rows[b]
		r.nm.text = "%s %s" % [B_ICONS[b], B_NAMES[b]]
		var s := ""
		for i in range(5):
			s += "★" if i < stars[b] else "☆"
		r.st.text = s
		if stars[b] >= 5:
			r.buy.text = "MAX ✓"
			r.buy.disabled = true
		else:
			var c := _star_cost(b, stars[b])
			r.buy.text = "🪙 %d" % c
			r.buy.disabled = coins < c

# ============ SAVE ============
func _save() -> void:
	var d := { "c": coins, "s": spins, "ts": int(Time.get_unix_time_from_system()), "v": village, "st": stars, "b": bet }
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func _load() -> void:
	last_ts = int(Time.get_unix_time_from_system())
	if not FileAccess.file_exists(SAVE):
		return
	var f := FileAccess.open(SAVE, FileAccess.READ)
	if not f:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	coins = int(d.get("c", 3000))
	spins = int(d.get("s", 25))
	village = int(d.get("v", 0))
	bet = int(d.get("b", 1))
	var st = d.get("st", [0, 0, 0, 0, 0])
	for i in range(5):
		stars[i] = int(st[i])
	# offline spin regen
	var then := int(d.get("ts", last_ts))
	var gained := int(float(last_ts - then) / REGEN_SECS)
	if gained > 0 and spins < SPIN_CAP:
		spins = min(SPIN_CAP, spins + gained)

# ============ LOOP ============
var regen_accum := 0.0

func _process(delta: float) -> void:
	t += delta
	# camera: gentle sway orbit (slow)
	var a := t * 0.06
	if sailing:
		sail_t += delta
		# luzzu sails away, camera follows a bit, then arrive
		if luzzu:
			luzzu.position += Vector3(-delta * 3.0, 0, delta * 1.6)
		if sail_t > 3.2:
			_arrive_next()
	cam.position = Vector3(cos(a) * 18.4, 12.5, sin(a) * 18.4)
	cam.look_at(Vector3(0, -0.6, 0))
	# spin regen (live)
	if spins < SPIN_CAP:
		regen_accum += delta
		if regen_accum >= REGEN_SECS:
			regen_accum = 0.0
			spins += 1
			_refresh_all()
			_save()
		lbl_regen.text = "+1 in %dm" % int(ceil((REGEN_SECS - regen_accum) / 60.0))
	else:
		lbl_regen.text = "FULL"
	# slot reels: fast roll -> staggered overshoot-settle stops
	if slot_spinning:
		slot_elapsed += delta
		for i in range(3):
			if reel_done[i] or reel_stopping[i]:
				continue
			if slot_elapsed >= reel_stop[i]:
				reel_stopping[i] = true
				var prize_idx := SYMS_ORDER.find(slot_prize.k)
				var target := ceili(rp[i]) + 4
				while target % 6 != prize_idx:
					target += 1
				var tw := create_tween()
				tw.tween_method(_settle_reel.bind(i), rp[i], float(target), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.finished.connect(_reel_finished.bind(i))
			else:
				rp[i] += delta * (14.0 + i * 2.0)
				_update_reel(i)
	# wanderers
	wt_a = _wander(wander_a, wt_a, 1.0, delta)
	wt_b = _wander(wander_b, wt_b, 0.9, delta)
	# luzzu bob (when not sailing)
	if luzzu and not sailing:
		luzzu.rotation.z = sin(t * 1.4) * 0.05

func _settle_reel(v: float, i: int) -> void:
	rp[i] = v
	_update_reel(i)

func _reel_finished(i: int) -> void:
	reel_done[i] = true
	if reel_done[0] and reel_done[1] and reel_done[2]:
		slot_spinning = false
		_slot_payout()

func _wander(n: Node3D, target: Vector3, speed: float, delta: float) -> Vector3:
	if not n:
		return target
	if n.position.distance_to(target) < 0.4:
		return Vector3(randf_range(-3.0, 4.0), 0.55, randf_range(-2.0, 4.0))
	var dir := (target - n.position).normalized()
	n.position += dir * delta * speed
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.01:
		n.look_at(n.position + flat)
		n.rotate_y(PI)
	return target
