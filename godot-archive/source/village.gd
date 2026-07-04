extends Node3D
# ===== Pastizzi Village 3D — diorama look-test =====
# Goal: match the isometric village art (floating limestone island,
# plaza, buildings, dock with luzzu) using assets we already own.

var cam: Camera3D
var luzzu: Node3D
var t := 0.0

func _ready() -> void:
	_build()

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

func _place(path: String, h: float, pos: Vector3, rot_y: float = 0.0) -> Node3D:
	var m := _model(path, h)
	if m:
		add_child(m)
		m.position += pos
		m.rotation_degrees.y = rot_y
	return m

func _build() -> void:
	# --- floating island: stone-block sides, grass top (like the art) ---
	var side := _box(Vector3(16, 3.4, 16), Vector3(0, -1.7, 0), Color(1, 1, 1))
	side.material_override = _tmat("res://assets/tex_stone.png", 5.0)
	var top := _box(Vector3(15.6, 0.5, 15.6), Vector3(0, 0.2, 0), Color(1, 1, 1))
	top.material_override = _tmat("res://assets/tex_grass.png", 6.0)
	# plaza (sandy flagstones)
	var plaza := _box(Vector3(9, 0.14, 9), Vector3(0.5, 0.5, 0.5), Color(0.88, 0.78, 0.6))
	plaza.material_override = _tmat("res://assets/tex_stone.png", 7.0)
	# second tier at the back (church platform, like the art)
	var tier := _box(Vector3(9, 1.2, 6), Vector3(1, 0.9, -4.5), Color(1, 1, 1))
	tier.material_override = _tmat("res://assets/tex_stone.png", 4.0)
	# steps
	for i in range(3):
		_box(Vector3(3, 0.28, 0.7), Vector3(0, 0.55 + i * 0.28, -1.2 - i * 0.62), Color(0.86, 0.76, 0.58))
	# --- buildings from our own library ---
	_place("res://assets/house.glb", 3.2, Vector3(-4.6, 0.45, 0.6), 32)          # bakery (red-roof farmhouse)
	_place("res://assets/windmill.glb", 5.2, Vector3(5.4, 0.45, -1.2), -105)     # tower stand-in
	_place("res://assets/well.glb", 1.9, Vector3(0.6, 0.62, 0.8), 0)             # fountain stand-in (plaza centre)
	# olive trees + prickly pears
	_place("res://assets/olive.glb", 2.6, Vector3(-6.2, 0.45, -4.6), 40)
	_place("res://assets/olive.glb", 2.2, Vector3(6.4, 0.45, 4.6), 160)
	_place("res://assets/prickly.glb", 1.0, Vector3(-6.6, 0.45, 4.4), 80)
	_place("res://assets/prickly.glb", 0.9, Vector3(6.8, 0.45, 1.8), 210)
	# --- dock + sea + luzzu (front-left, like the art) ---
	_box(Vector3(60, 0.3, 60), Vector3(0, -3.6, 0), Color(0.24, 0.62, 0.78))     # sea
	var dock := _box(Vector3(3.4, 0.35, 2.2), Vector3(-8.2, -2.4, 5.6), Color(0.52, 0.36, 0.2))
	for px in [-9.4, -7.0]:
		for pz in [4.7, 6.5]:
			_cyl(0.12, 0.12, 1.4, Vector3(px, -3.0, pz), Color(0.42, 0.28, 0.15))
	luzzu = _place("res://assets/luzzu.glb", 1.9, Vector3(-5.6, -3.3, 7.6), 25)
	# --- plaza dressing: lamp posts, benches, flower pots, bunting poles ---
	for lp in [Vector3(-2.6, 0.55, 3.4), Vector3(3.6, 0.55, 3.2), Vector3(-2.8, 0.55, -2.2)]:
		_cyl(0.06, 0.09, 1.7, lp + Vector3(0, 0.85, 0), Color(0.16, 0.24, 0.45))
		_sphere(0.17, lp + Vector3(0, 1.85, 0), Color(1, 0.9, 0.55))
	for bp in [Vector3(1.8, 0.62, 3.9), Vector3(-1.2, 0.62, -3.0)]:
		_box(Vector3(1.5, 0.12, 0.5), bp, Color(0.6, 0.42, 0.24))
		_box(Vector3(1.5, 0.1, 0.14), bp + Vector3(0, 0.3, -0.18), Color(0.6, 0.42, 0.24))
	for fp in [Vector3(-4.0, 0.6, 3.4), Vector3(4.4, 0.6, -3.4), Vector3(2.4, 1.55, -4.2), Vector3(-3.4, 1.55, -5.8)]:
		_cyl(0.28, 0.2, 0.4, fp, Color(0.75, 0.42, 0.25))
		_sphere(0.3, fp + Vector3(0, 0.35, 0), [Color(0.92, 0.36, 0.5), Color(0.95, 0.7, 0.3), Color(0.85, 0.35, 0.75)][randi() % 3])
	# market stall (striped awning, like the art)
	var stall := Node3D.new()
	add_child(stall)
	stall.position = Vector3(2.6, 0.55, 4.6)
	stall.rotation_degrees.y = -12
	_box(Vector3(2.2, 0.8, 1.0), Vector3(0, 0.4, 0), Color(0.62, 0.44, 0.26), stall)
	for i in range(6):
		_box(Vector3(0.36, 0.06, 1.5), Vector3(-0.9 + i * 0.36, 1.35 - (i % 2) * 0.001, 0), (Color(0.2, 0.4, 0.75) if i % 2 == 0 else Color(0.97, 0.96, 0.92)), stall)
	for cx in [-1.0, 1.0]:
		_cyl(0.05, 0.05, 1.3, Vector3(cx, 0.75, 0.6), Color(0.45, 0.3, 0.16), stall)
	_sphere(0.22, Vector3(-0.4, 0.95, 0.1), Color(0.9, 0.55, 0.2), stall)
	_sphere(0.2, Vector3(0.3, 0.95, -0.1), Color(0.85, 0.3, 0.25), stall)
	# Maltese flag on the tower side
	_cyl(0.05, 0.05, 2.6, Vector3(5.4, 5.6, -1.2), Color(0.5, 0.35, 0.2))
	_box(Vector3(1.0, 0.62, 0.03), Vector3(5.95, 6.6, -1.2), Color(0.95, 0.95, 0.95))
	_box(Vector3(0.5, 0.62, 0.031), Vector3(6.2, 6.6, -1.2), Color(0.8, 0.15, 0.18))
	# --- camera & light: match the photo's angle + lavender sky ---
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 15.5
	cam.position = Vector3(13, 12.5, 13)
	add_child(cam)
	cam.look_at(Vector3(0, -0.6, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	sun.light_color = Color(1, 0.97, 0.9)
	sun.light_energy = 1.05
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.6, 0.78)   # the art's lavender
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.93, 1.0)
	env.ambient_light_energy = 0.65
	we.environment = env
	add_child(we)

func _process(delta: float) -> void:
	t += delta
	# slow cinematic orbit so you can judge it from all sides
	var a := t * 0.15
	cam.position = Vector3(cos(a) * 18.4, 12.5, sin(a) * 18.4)
	cam.look_at(Vector3(0, -0.6, 0))
	if luzzu:
		luzzu.rotation.z = sin(t * 1.4) * 0.05
		luzzu.position.y = -3.3 + sin(t * 1.1) * 0.06
