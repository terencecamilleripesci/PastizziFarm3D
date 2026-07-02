extends Node3D
# ===== Pastizzi Farm 3D — v0.2 =====
# Real farm loop: crops grow in REAL minutes (keep growing while you're away),
# progress saves on-device, pinch/wheel zoom, drag pan, day/night cycle.

const CROPS := [
	{ "id": "tadam",  "name": "Tadam",  "color": Color(0.86, 0.22, 0.16), "mins": 2.0,  "pay": 20 },
	{ "id": "frawli", "name": "Frawli", "color": Color(0.93, 0.30, 0.44), "mins": 5.0,  "pay": 45 },
	{ "id": "qargha", "name": "Qargħa", "color": Color(0.95, 0.62, 0.12), "mins": 10.0, "pay": 100 },
]
const SAVE_PATH := "user://farm.json"
const DAY_SECONDS := 180.0            # full day/night loop = 3 minutes

var coins := 0
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
	# girna hut
	_box(Vector3(2.4, 1.6, 2.4), Vector3(-9.5, 0.8, -9.5), stone)
	_cyl(0.0, 1.9, 1.4, Vector3(-9.5, 2.3, -9.5), Color(0.7, 0.58, 0.4))
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

func _build_plots() -> void:
	for r in range(3):
		for c in range(3):
			var pos := Vector3((c - 1) * 4.2, 0.05, (r - 1) * 4.2)
			_box(Vector3(3.4, 0.3, 3.4), pos, Color(0.42, 0.28, 0.16))
			for k in range(3):                                        # tilled ridges
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
			plots.append({ "body": body, "crop": -1, "node": null, "stem": null, "fruits": [], "planted": 0.0 })

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
	hint_label.text = "Tap a plot to plant — crops grow in real time, even while you're away!"
	hint_label.position = Vector2(20, 100)
	hint_label.add_theme_font_size_override("font_size", 15)
	ui.add_child(hint_label)
	_update_coins()

func _update_coins() -> void:
	coins_label.text = "🪙 %d" % coins

# ---------- save / load (survives closing the game) ----------
func _save() -> void:
	var d := { "coins": coins, "plots": [] }
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
	var saved: Array = d.get("plots", [])
	for i in range(min(saved.size(), plots.size())):
		var s: Dictionary = saved[i]
		if int(s.get("crop", -1)) >= 0:
			_spawn_crop(i, int(s.crop), float(s.planted))
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
	var crop_idx := randi() % CROPS.size()
	_spawn_crop(i, crop_idx, Time.get_unix_time_from_system())
	hint_label.text = "%s planted — ready in %s min!" % [CROPS[crop_idx].name, str(CROPS[crop_idx].mins)]
	_save()

func _harvest(i: int) -> void:
	var p: Dictionary = plots[i]
	var crop: Dictionary = CROPS[p.crop]
	coins += crop.pay
	_update_coins()
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
	if hit.is_empty() or not hit.collider.has_meta("plot"):
		return
	var i: int = hit.collider.get_meta("plot")
	var p: Dictionary = plots[i]
	if p.crop < 0:
		_plant(i)
	elif _growth(p) >= 1.0:
		_harvest(i)
	else:
		var left: float = CROPS[p.crop].mins * 60.0 - (Time.get_unix_time_from_system() - p.planted)
		hint_label.text = "%s still growing — %d s left" % [CROPS[p.crop].name, int(max(0, left))]

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
