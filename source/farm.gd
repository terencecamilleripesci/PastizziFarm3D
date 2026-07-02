extends Node3D
# ===== Pastizzi Farm 3D — v0.2 =====
# Real farm loop: crops grow in REAL minutes (keep growing while you're away),
# progress saves on-device, pinch/wheel zoom, drag pan, day/night cycle.

const CROPS := [
	{ "id": "tadam",  "name": "Tadam",  "e": "🍅", "color": Color(0.86, 0.22, 0.16), "mins": 2.0,  "seed": 10, "pay": 25 },
	{ "id": "frawli", "name": "Frawli", "e": "🍓", "color": Color(0.93, 0.30, 0.44), "mins": 5.0,  "seed": 20, "pay": 55 },
	{ "id": "laring", "name": "Larinġ", "e": "🍊", "color": Color(0.98, 0.60, 0.12), "mins": 8.0,  "seed": 35, "pay": 95 },
	{ "id": "qargha", "name": "Qargħa", "e": "🎃", "color": Color(0.90, 0.48, 0.10), "mins": 12.0, "seed": 50, "pay": 150 },
	{ "id": "gheneb", "name": "Għeneb", "e": "🍇", "color": Color(0.48, 0.24, 0.60), "mins": 20.0, "seed": 80, "pay": 260 },
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
var ext := 0                          # extra land bought (0..3)
var clouds: Array = []
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
	_build_camera_and_light()
	_build_ui()
	_load()

# ---------- helpers ----------
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

# ---------- world ----------
func _build_world() -> void:
	_box(Vector3(26, 0.5, 26), Vector3(0, -0.25, 0), Color(0.45, 0.62, 0.28))       # field
	_box(Vector3(60, 0.2, 18), Vector3(0, -0.4, -26), Color(0.16, 0.45, 0.68))      # the sea beyond
	var stone := Color(0.85, 0.74, 0.55)
	_box(Vector3(26, 1.0, 0.7), Vector3(0, 0.5, -13), stone)
	_box(Vector3(26, 1.0, 0.7), Vector3(0, 0.5, 13), stone)
	_box(Vector3(0.7, 1.0, 26), Vector3(-13, 0.5, 0), stone)
	_box(Vector3(0.7, 1.0, 26), Vector3(13, 0.5, 0), stone)
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
	# stone well
	_cyl(1.0, 1.0, 0.9, Vector3(9.5, 0.45, -9.5), Color(0.78, 0.68, 0.5))
	_cyl(0.0, 1.2, 0.8, Vector3(9.5, 1.9, -9.5), Color(0.6, 0.34, 0.2))
	# olive trees
	for p in [Vector3(-10, 0, 8.5), Vector3(10.5, 0, 8.5), Vector3(-10.5, 0, 0)]:
		_cyl(0.22, 0.3, 1.6, p + Vector3(0, 0.8, 0), Color(0.45, 0.32, 0.2))
		_sphere(1.15, p + Vector3(0, 2.1, 0), Color(0.38, 0.5, 0.28))
		_sphere(0.8, p + Vector3(0.7, 1.7, 0.3), Color(0.42, 0.56, 0.3))
	# prickly pears
	for i in range(3):
		_box(Vector3(0.8, 1.1, 0.4), Vector3(5.0 + i * 2.2, 0.55, -11.8), Color(0.35, 0.55, 0.25))
	# drifting clouds
	for i in range(3):
		var cl := Node3D.new()
		add_child(cl)
		_sphere(1.4, Vector3(0, 0, 0), Color(1, 1, 1, 1), cl).scale = Vector3(1.6, 0.55, 1)
		_sphere(1.0, Vector3(1.4, 0.15, 0.2), Color(1, 1, 1, 1), cl).scale = Vector3(1.3, 0.5, 1)
		cl.position = Vector3(randf_range(-16, 16), 9.0 + i * 1.2, -6 - i * 4)
		clouds.append(cl)

const EXT_COSTS := [150, 300, 600]
func _build_plots() -> void:
	for r in range(4):                                             # row 4 = buyable land
		for c in range(3):
			var pos := Vector3((c - 1) * 4.2, 0.05, (r - 1) * 4.2)
			var locked := r == 3
			var soil := _box(Vector3(3.4, 0.3, 3.4), pos, Color(0.55, 0.5, 0.42) if locked else Color(0.42, 0.28, 0.16))
			if not locked:
				for k in range(3):                                 # tilled ridges
					_box(Vector3(3.0, 0.1, 0.35), pos + Vector3(0, 0.2, (k - 1) * 1.0), Color(0.36, 0.23, 0.12))
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(3.4, 1.6, 3.4)
			shape.shape = bs
			body.add_child(shape)
			body.position = pos
			add_child(body)
			body.set_meta("plot", plots.size())
			plots.append({ "body": body, "soil": soil, "locked": locked, "crop": -1, "node": null, "stem": null, "fruits": [], "planted": 0.0 })

func _unlock_plot(i: int) -> void:
	var p: Dictionary = plots[i]
	p.locked = false
	p.soil.material_override = _mat(Color(0.42, 0.28, 0.16))
	for k in range(3):
		_box(Vector3(3.0, 0.1, 0.35), p.body.position + Vector3(0, 0.2, (k - 1) * 1.0), Color(0.36, 0.23, 0.12))

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
	title.text = "🥟 Pastizzi Farm 3D"
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
	var bar := HBoxContainer.new()
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
	_pick_seed(0)
	_build_chicken()
	_build_goat()
	_update_coins()

func _pick_seed(i: int) -> void:
	sel_crop = i
	for j in range(seed_btns.size()):
		seed_btns[j].modulate = Color(1, 0.85, 0.4) if j == i else Color(1, 1, 1)

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
	var d := { "coins": coins, "ext": ext, "plots": [] }
	for p in plots:
		d.plots.append({ "crop": p.crop, "planted": p.planted })
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
	ext = int(d.get("ext", 0))
	for e in range(ext):
		_unlock_plot(9 + e)
	var saved: Array = d.get("plots", [])
	for i in range(min(saved.size(), plots.size())):
		var s: Dictionary = saved[i]
		var ci := int(s.get("crop", -1))
		if ci >= 0 and ci < CROPS.size():
			_spawn_crop(i, ci, float(s.planted))
	_update_coins()

# ---------- crops ----------
func _spawn_crop(i: int, crop_idx: int, planted: float) -> void:
	var p: Dictionary = plots[i]
	var crop: Dictionary = CROPS[crop_idx]
	var holder := Node3D.new()
	holder.position = p.body.position
	add_child(holder)
	var stem := _cyl(0.09, 0.13, 1.0, Vector3(0, 0.5, 0), Color(0.3, 0.5, 0.2), holder)
	var fruits: Array = []
	for off in [Vector3(0.35, 0.95, 0.1), Vector3(-0.3, 0.8, 0.2), Vector3(0.05, 1.1, -0.3)]:
		var fr := _sphere(0.28, off, crop.color, holder)
		fr.scale = Vector3.ZERO
		fruits.append(fr)
	p.crop = crop_idx
	p.node = holder
	p.stem = stem
	p.fruits = fruits
	p.planted = planted

func _plant(i: int) -> void:
	var crop: Dictionary = CROPS[sel_crop]
	if coins < crop.seed:
		hint_label.text = "Not enough coins for %s seeds (🪙%d) — harvest something first!" % [crop.name, crop.seed]
		return
	coins -= crop.seed
	_update_coins()
	_burst(plots[i].body.position, Color(0.5, 0.35, 0.2), 5)
	_float_text(plots[i].body.position, "-%d" % crop.seed, Color(1, 0.85, 0.4))
	_spawn_crop(i, sel_crop, Time.get_unix_time_from_system())
	hint_label.text = "%s planted — ready in %s min!" % [crop.name, str(crop.mins)]
	_save()

func _harvest(i: int) -> void:
	var p: Dictionary = plots[i]
	var crop: Dictionary = CROPS[p.crop]
	coins += crop.pay
	_update_coins()
	_burst(p.body.position, crop.color, 8)
	_float_text(p.body.position, "+%d 🪙" % crop.pay, Color(1, 0.9, 0.35))
	if p.get("mark") and is_instance_valid(p.mark):
		p.mark.queue_free()
	p.mark = null
	hint_label.text = "Harvested %s — +%d coins!" % [crop.name, crop.pay]
	p.node.queue_free()
	p.node = null
	p.stem = null
	p.fruits = []
	p.crop = -1
	p.planted = 0.0
	_save()

func _growth(p: Dictionary) -> float:
	if p.crop < 0:
		return 0.0
	var elapsed: float = Time.get_unix_time_from_system() - p.planted
	return clamp(elapsed / (CROPS[p.crop].mins * 60.0), 0.0, 1.0)

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
		cam.position.x = clamp(cam.position.x, 4, 20)
		cam.position.z = clamp(cam.position.z, 4, 20)
		drag_last = pos

func _tap(screen_pos: Vector2) -> void:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
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
	if p.locked:
		if i - 9 != ext:
			hint_label.text = "Buy the land plots in order — next one costs 🪙%d" % EXT_COSTS[ext]
			return
		var cost: int = EXT_COSTS[ext]
		if coins < cost:
			hint_label.text = "That land costs 🪙%d — keep farming!" % cost
			return
		coins -= cost
		ext += 1
		_unlock_plot(i)
		_update_coins()
		hint_label.text = "🌾 New land! The għalqa grows."
		_save()
		return
	if p.crop < 0:
		_plant(i)
	elif _growth(p) >= 1.0:
		_harvest(i)
	else:
		var left: float = CROPS[p.crop].mins * 60.0 - (Time.get_unix_time_from_system() - p.planted)
		hint_label.text = "%s still growing — %d s left" % [CROPS[p.crop].name, int(max(0, left))]

# ---------- it-tiġieġa: wandering chicken that lays eggs ----------
func _build_chicken() -> void:
	chicken = Node3D.new()
	add_child(chicken)
	_box(Vector3(0.55, 0.45, 0.75), Vector3(0, 0.42, 0), Color(0.95, 0.93, 0.88), chicken)
	_box(Vector3(0.3, 0.3, 0.3), Vector3(0, 0.75, 0.42), Color(0.95, 0.93, 0.88), chicken)
	_box(Vector3(0.1, 0.14, 0.18), Vector3(0, 0.88, 0.42), Color(0.85, 0.2, 0.15), chicken)
	_box(Vector3(0.08, 0.08, 0.16), Vector3(0, 0.72, 0.6), Color(0.95, 0.65, 0.2), chicken)
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
	_box(Vector3(0.7, 0.6, 1.1), Vector3(0, 0.65, 0), Color(0.82, 0.8, 0.75), goat)
	_box(Vector3(0.4, 0.4, 0.45), Vector3(0, 1.05, 0.6), Color(0.82, 0.8, 0.75), goat)
	_box(Vector3(0.08, 0.25, 0.08), Vector3(-0.14, 1.35, 0.55), Color(0.4, 0.35, 0.3), goat)
	_box(Vector3(0.08, 0.25, 0.08), Vector3(0.14, 1.35, 0.55), Color(0.4, 0.35, 0.3), goat)
	for lx in [-0.22, 0.22]:
		for lz in [-0.4, 0.4]:
			_box(Vector3(0.12, 0.5, 0.12), Vector3(lx, 0.25, lz), Color(0.7, 0.68, 0.62), goat)
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

# ---------- live growth + day/night ----------
func _process(delta: float) -> void:
	for p in plots:
		if p.crop >= 0 and p.node:
			var k := _growth(p)
			p.stem.scale = Vector3(1, 0.15 + 0.85 * k, 1)
			p.stem.position.y = 0.5 * p.stem.scale.y
			var fk: float = clamp((k - 0.7) / 0.3, 0.0, 1.0)
			for fr in p.fruits:
				fr.scale = Vector3(fk, fk, fk)
			if k >= 1.0:
				var bob := 1.0 + sin(Time.get_ticks_msec() / 200.0) * 0.08
				for fr in p.fruits:
					fr.scale = Vector3(bob, bob, bob)
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
	_chicken_process(delta)
	_goat_process(delta)
	for cl in clouds:
		cl.position.x += delta * 0.45
		if cl.position.x > 22:
			cl.position.x = -22
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
