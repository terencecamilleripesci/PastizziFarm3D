extends Node3D
# ===== Pastizzi Farm 3D — prototype =====
# A real 3D Maltese farm: isometric camera, 9 plots, tap to plant,
# crops grow live in 3D, tap to harvest, coins counter.
# Built entirely from primitives — no external assets needed.

const GROW_SECONDS := 12.0          # demo speed — crops grow in 12s
const CROPS := [
	{ "name": "Tadam",  "color": Color(0.86, 0.22, 0.16) },
	{ "name": "Frawli", "color": Color(0.93, 0.30, 0.44) },
	{ "name": "Qargħa", "color": Color(0.95, 0.62, 0.12) },
]

var coins := 0
var plots: Array = []               # { body, soil, crop_mesh, state, t, crop }
var cam: Camera3D
var coins_label: Label
var hint_label: Label
var drag_last := Vector2.ZERO
var dragging := false

func _ready() -> void:
	_build_world()
	_build_plots()
	_build_camera_and_light()
	_build_ui()

# ---------- world ----------
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

func _build_world() -> void:
	# grass field
	_box(Vector3(26, 0.5, 26), Vector3(0, -0.25, 0), Color(0.45, 0.62, 0.28))
	# Maltese limestone rubble walls around the field
	var stone := Color(0.85, 0.74, 0.55)
	_box(Vector3(26, 1.0, 0.7), Vector3(0, 0.5, -13), stone)
	_box(Vector3(26, 1.0, 0.7), Vector3(0, 0.5, 13), stone)
	_box(Vector3(0.7, 1.0, 26), Vector3(-13, 0.5, 0), stone)
	_box(Vector3(0.7, 1.0, 26), Vector3(13, 0.5, 0), stone)
	# a little girna (stone hut) in the corner
	_box(Vector3(2.4, 1.6, 2.4), Vector3(-9.5, 0.8, -9.5), stone)
	var roof := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.9
	cone.height = 1.4
	roof.mesh = cone
	roof.material_override = _mat(Color(0.7, 0.58, 0.4))
	roof.position = Vector3(-9.5, 2.3, -9.5)
	add_child(roof)
	# prickly pears (green blobs) along the far wall
	for i in range(3):
		_box(Vector3(0.8, 1.1, 0.4), Vector3(6.0 + i * 2.2, 0.55, -11.8), Color(0.35, 0.55, 0.25))

func _build_plots() -> void:
	for r in range(3):
		for c in range(3):
			var pos := Vector3((c - 1) * 4.2, 0.05, (r - 1) * 4.2)
			var soil := _box(Vector3(3.4, 0.3, 3.4), pos, Color(0.42, 0.28, 0.16))
			# clickable body
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(3.4, 1.2, 3.4)
			shape.shape = bs
			body.add_child(shape)
			body.position = pos
			add_child(body)
			plots.append({ "body": body, "soil": soil, "crop": null, "crop_mesh": null, "state": "empty", "t": 0.0 })
			body.set_meta("plot", plots.size() - 1)

func _build_camera_and_light() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 17.0
	cam.position = Vector3(12, 14, 12)
	add_child(cam)
	cam.look_at(Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.53, 0.75, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 1.0)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var title := Label.new()
	title.text = "🥟 Pastizzi Farm 3D"
	title.position = Vector2(20, 18)
	title.add_theme_font_size_override("font_size", 30)
	ui.add_child(title)
	coins_label = Label.new()
	coins_label.text = "🪙 0"
	coins_label.position = Vector2(20, 60)
	coins_label.add_theme_font_size_override("font_size", 26)
	ui.add_child(coins_label)
	hint_label = Label.new()
	hint_label.text = "Tap a plot to plant — drag to look around"
	hint_label.position = Vector2(20, 100)
	hint_label.add_theme_font_size_override("font_size", 16)
	ui.add_child(hint_label)

# ---------- input: tap to plant/harvest, drag to pan ----------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		if pressed:
			dragging = false
			drag_last = pos
		else:
			if not dragging:
				_tap(pos)
	elif (event is InputEventScreenDrag) or (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		var delta: Vector2 = event.position - drag_last
		if delta.length() > 6:
			dragging = true
			var right := cam.global_transform.basis.x
			var fwd := -cam.global_transform.basis.z
			fwd.y = 0
			fwd = fwd.normalized()
			cam.position -= right * delta.x * 0.02 + fwd * -delta.y * 0.02
			cam.position.x = clamp(cam.position.x, 4, 20)
			cam.position.z = clamp(cam.position.z, 4, 20)
			drag_last = event.position

func _tap(screen_pos: Vector2) -> void:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit.collider.has_meta("plot"):
		return
	var i: int = hit.collider.get_meta("plot")
	var p: Dictionary = plots[i]
	if p.state == "empty":
		_plant(i)
	elif p.state == "ready":
		_harvest(i)

func _plant(i: int) -> void:
	var p: Dictionary = plots[i]
	var crop: Dictionary = CROPS[randi() % CROPS.size()]
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	mi.mesh = sphere
	mi.material_override = _mat(crop.color)
	mi.position = p.body.position + Vector3(0, 0.7, 0)
	mi.scale = Vector3(0.05, 0.05, 0.05)
	add_child(mi)
	p.crop = crop
	p.crop_mesh = mi
	p.state = "growing"
	p.t = 0.0
	hint_label.text = crop.name + " planted — growing..."

func _harvest(i: int) -> void:
	var p: Dictionary = plots[i]
	var pay := 15 + randi() % 11
	coins += pay
	coins_label.text = "🪙 %d" % coins
	hint_label.text = "Harvested %s — +%d coins!" % [p.crop.name, pay]
	p.crop_mesh.queue_free()
	p.crop_mesh = null
	p.crop = null
	p.state = "empty"

func _process(delta: float) -> void:
	for p in plots:
		if p.state == "growing":
			p.t += delta
			var k: float = clamp(p.t / GROW_SECONDS, 0.0, 1.0)
			var s: float = 0.05 + 0.95 * k
			p.crop_mesh.scale = Vector3(s, s, s)
			if k >= 1.0:
				p.state = "ready"
		elif p.state == "ready":
			p.t += delta
			var bob: float = 1.0 + sin(p.t * 5.0) * 0.08
			p.crop_mesh.scale = Vector3(bob, bob, bob)
