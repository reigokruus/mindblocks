extends Node3D
## The room the notes float in: a cozy home office, built from plain boxes,
## cylinders and spheres so it matches the chunky blocks. Muted, warm colors
## keep the pastel blocks standing out. The furniture is laid out in "room
## units" of about 10 cm and then shown SCALE times bigger around the user,
## so a block (2 world units) is a sugar cube (about 4 cm), the laptop is
## about 15 blocks wide, and flying around feels like being a fly or a fairy.
## The start view hovers just above the desk, by the laptop and the lamp.
## The front wall has a window opening; the starry sky (the environment's
## background) shows through it. Nothing here is pickable: picking only
## looks at notes.

## World size and place of the room: world = OFFSET + room units * SCALE.
## OFFSET puts the desk top a little below the starting view, its front edge
## just in front of it.
const SCALE := 5.0
const OFFSET := Vector3(0.0, 28.5, 107.5)
const HALF_X := 36.0  # walls at x = ±HALF_X
const HALF_Z := 32.0  # walls at z = ±HALF_Z (the window wall is at -HALF_Z)
const FLOOR := -16.0
const CEILING := 12.0
const WALL := 1.0  # wall thickness
## Window opening in the front wall.
const WIN_X := 10.0  # half width
const WIN_LOW := -4.0
const WIN_HIGH := 8.0
const DESK_Y := FLOOR + 7.5  # desk top surface (75 cm)
const DESK_Z := -HALF_Z + 7.5

const WOOD := Color("9b7653")
const WOOD_DARK := Color("6f533a")
const WALL_COLOR := Color("e8dfd0")
const ACCENT_WALL := Color("a9b8a0")
const TRIM := Color("f7f4ee")

var _materials := {}
var _model: Node3D  # the furniture, built in room units and scaled up


## Flat tops something can rest on, in room units: [x0, x1, z0, z1, top y].
## Drop lines and rings under notes land on the highest one below them.
const SURFACES := [
	[-15.0, 15.0, DESK_Z - 6.0, DESK_Z + 6.0, DESK_Y],  # desk
	[HALF_X - 18.5, HALF_X - 1.5, HALF_Z - 25.5, HALF_Z - 0.5, FLOOR + 5.75],  # bed
	[-HALF_X + 0.2, -HALF_X + 4.2, -11.0, 3.0, FLOOR + 21.7],  # bookshelf
]


func _ready() -> void:
	_model = Node3D.new()
	_model.position = OFFSET
	_model.scale = Vector3.ONE * SCALE
	add_child(_model)
	_build_shell()
	_build_window()
	_build_desk()
	_build_chair()
	_build_bookshelf()
	_build_bed()
	_build_plant(Vector3(-HALF_X + 5.0, FLOOR, -HALF_Z + 5.0), 1.0)
	_build_decor()
	_merge_meshes()
	_build_lights()
	_build_dust()


## Solid parts of the furniture, as boxes in room units: [min corner, max corner].
## Notes and the camera are pushed out of these (and kept inside the walls),
## so nothing passes through the furniture. Rough shapes are fine: they only
## need to match what you'd bump into.
const SOLIDS := [
	[Vector3(-15, DESK_Y - 1.0, DESK_Z - 6), Vector3(15, DESK_Y, DESK_Z + 6)],  # desk top
	[Vector3(-14, FLOOR, DESK_Z - 5.3), Vector3(-13, DESK_Y - 1.0, DESK_Z - 4.3)],  # desk legs
	[Vector3(13, FLOOR, DESK_Z - 5.3), Vector3(14, DESK_Y - 1.0, DESK_Z - 4.3)],
	[Vector3(-14, FLOOR, DESK_Z + 4.3), Vector3(-13, DESK_Y - 1.0, DESK_Z + 5.3)],
	[Vector3(13, FLOOR, DESK_Z + 4.3), Vector3(14, DESK_Y - 1.0, DESK_Z + 5.3)],
	[Vector3(-7.2, DESK_Y, DESK_Z - 1.7), Vector3(-0.8, DESK_Y + 0.45, DESK_Z + 2.7)],  # laptop base
	[Vector3(-7.2, DESK_Y, DESK_Z - 2.9), Vector3(-0.8, DESK_Y + 4.4, DESK_Z - 1.4)],  # laptop lid
	[Vector3(7.5, DESK_Y, DESK_Z - 3.0), Vector3(10.5, DESK_Y + 0.5, DESK_Z)],  # lamp base
	[Vector3(8.7, DESK_Y, DESK_Z - 1.8), Vector3(9.3, DESK_Y + 6.8, DESK_Z - 1.2)],  # lamp pole
	[Vector3(6.4, DESK_Y + 5.4, DESK_Z - 2.9), Vector3(10.6, DESK_Y + 8.4, DESK_Z + 1.1)],  # lamp shade
	[Vector3(2.8, DESK_Y, DESK_Z + 2.3), Vector3(4.6, DESK_Y + 1.3, DESK_Z + 3.7)],  # mug
	[Vector3(-12.5, DESK_Y, DESK_Z - 2.5), Vector3(-9.5, DESK_Y + 3.3, DESK_Z + 0.5)],  # desk plant
	[Vector3(-16.5, FLOOR, DESK_Z + 6.5), Vector3(-7.5, FLOOR + 13.0, DESK_Z + 15.5)],  # chair
	[Vector3(-HALF_X, FLOOR, -11.0), Vector3(-HALF_X + 4.2, FLOOR + 22.0, 3.0)],  # bookshelf
	[Vector3(-35.0, FLOOR + 22.0, -1.0), Vector3(-32.6, FLOOR + 26.0, 1.0)],  # plant on the shelf
	[Vector3(HALF_X - 18.5, FLOOR, HALF_Z - 25.7), Vector3(HALF_X - 1.5, FLOOR + 5.75, HALF_Z - 0.5)],  # bed
	[Vector3(HALF_X - 18.5, FLOOR, HALF_Z - 1.1), Vector3(HALF_X - 1.5, FLOOR + 9.0, HALF_Z)],  # headboard
	[Vector3(HALF_X - 17.0, FLOOR + 5.0, HALF_Z - 5.4), Vector3(HALF_X - 3.0, FLOOR + 7.0, HALF_Z - 1.6)],  # pillows
	[Vector3(-HALF_X, FLOOR, -HALF_Z), Vector3(-HALF_X + 8.5, FLOOR + 10.2, -HALF_Z + 8.5)],  # big plant
	[Vector3(-11.5, WIN_LOW - 0.85, -HALF_Z), Vector3(11.5, WIN_LOW - 0.35, -HALF_Z + 2.1)],  # window sill
	[Vector3(HALF_X - 0.75, 3.4, -14.6), Vector3(HALF_X, 8.6, -9.4)],  # wall clock
]

static var _world_solids: Array[AABB] = []


## SOLIDS in world space (worked out once).
static func world_solids() -> Array[AABB]:
	if _world_solids.is_empty():
		for b in SOLIDS:
			var lo := to_world(b[0])
			_world_solids.append(AABB(lo, to_world(b[1]) - lo))
	return _world_solids


## Pushes a sphere of `radius` at `p` out of the furniture and back inside the
## walls, floor and ceiling, each time the shortest way out (so something
## moving along a surface slides along it). Returns {pos, normal (of the
## deepest push, or zero), depth (how far it was pushed at most)}.
static func push_out(p: Vector3, radius: float) -> Dictionary:
	var normal := Vector3.ZERO
	var depth := 0.0
	for pass_i in 2:  # a second pass settles pushes between neighbouring pieces
		for box in world_solids():
			var e := box.grow(radius)
			if not e.has_point(p):
				continue
			var best := INF
			var push := Vector3.ZERO
			for axis in 3:
				var to_low := p[axis] - e.position[axis]
				var to_high := e.end[axis] - p[axis]
				if to_low < best:
					best = to_low
					push = Vector3.ZERO
					push[axis] = -to_low
				if to_high < best:
					best = to_high
					push = Vector3.ZERO
					push[axis] = to_high
			p += push
			if best > depth:
				depth = best
				normal = push.normalized()
	var inside := p.clamp(world_min() + Vector3.ONE * radius, world_max() - Vector3.ONE * radius)
	var wall := inside - p
	if wall.length() > depth:
		depth = wall.length()
		normal = wall.normalized()
	return {"pos": inside, "normal": normal, "depth": depth}


## A point in room units, in world space.
static func to_world(p: Vector3) -> Vector3:
	return OFFSET + p * SCALE


## The room's inside, in world space: its lowest and highest corners.
static func world_min() -> Vector3:
	return to_world(Vector3(-HALF_X, FLOOR, -HALF_Z))


static func world_max() -> Vector3:
	return to_world(Vector3(HALF_X, CEILING, HALF_Z))


## Inside the room by at least `margin` (world units): the nearest such point to `p`.
static func clamp_inside(p: Vector3, margin: float) -> Vector3:
	var lo := world_min() + Vector3.ONE * margin
	var hi := world_max() - Vector3.ONE * margin
	return p.clamp(lo, hi)


## World height of the surface right below `p`: the desk, the bed, the top
## of the bookshelf, or else the floor.
static func surface_below(p: Vector3) -> float:
	var r := (p - OFFSET) / SCALE
	var best := FLOOR
	for s in SURFACES:
		if r.x >= s[0] and r.x <= s[1] and r.z >= s[2] and r.z <= s[3] and s[4] <= r.y and s[4] > best:
			best = s[4]
	return OFFSET.y + best * SCALE


func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), emission]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		# Lit per corner instead of per pixel: the room fills the whole screen,
		# and on flat, plainly colored shapes it looks the same for far less GPU work.
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		if emission > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = emission
		_materials[key] = m
	return _materials[key]


func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D = null, emission: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color, emission)
	mi.position = pos
	(parent if parent else _model).add_child(mi)
	return mi


func _cylinder(top: float, bottom: float, height: float, pos: Vector3, color: Color,
		parent: Node3D = null, emission: float = 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color, emission)
	mi.position = pos
	(parent if parent else _model).add_child(mi)
	return mi


func _sphere(radius: float, pos: Vector3, color: Color, parent: Node3D = null, emission: float = 0.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color, emission)
	mi.position = pos
	(parent if parent else _model).add_child(mi)
	return mi


## Floor with plank stripes and a rug, ceiling, three plain walls, the front
## (accent) wall around the window opening, and skirting boards.
func _build_shell() -> void:
	var w := HALF_X * 2.0
	var d := HALF_Z * 2.0
	var h := CEILING - FLOOR
	var mid_y := (FLOOR + CEILING) * 0.5
	_box(Vector3(w, 0.6, d), Vector3(0, FLOOR - 0.3, 0), WOOD)
	var x := -HALF_X + 4.0
	while x < HALF_X:
		_box(Vector3(0.12, 0.04, d), Vector3(x, FLOOR + 0.02, 0), WOOD_DARK)
		x += 4.0
	_box(Vector3(34, 0.15, 24), Vector3(0, FLOOR + 0.08, 4), Color("a8604a"))
	_box(Vector3(30, 0.25, 20), Vector3(0, FLOOR + 0.125, 4), Color("c48a68"))
	_box(Vector3(w, 0.6, d), Vector3(0, CEILING + 0.3, 0), Color("f3efe8"))
	# Back and side walls
	_box(Vector3(w, h, WALL), Vector3(0, mid_y, HALF_Z + WALL * 0.5), WALL_COLOR)
	_box(Vector3(WALL, h, d), Vector3(-HALF_X - WALL * 0.5, mid_y, 0), WALL_COLOR)
	_box(Vector3(WALL, h, d), Vector3(HALF_X + WALL * 0.5, mid_y, 0), WALL_COLOR)
	# Front wall: four pieces around the window opening
	var fz := -HALF_Z - WALL * 0.5
	var side := HALF_X - WIN_X
	_box(Vector3(side, h, WALL), Vector3(-(WIN_X + side * 0.5), mid_y, fz), ACCENT_WALL)
	_box(Vector3(side, h, WALL), Vector3(WIN_X + side * 0.5, mid_y, fz), ACCENT_WALL)
	_box(Vector3(WIN_X * 2.0, WIN_LOW - FLOOR, WALL), Vector3(0, (FLOOR + WIN_LOW) * 0.5, fz), ACCENT_WALL)
	_box(Vector3(WIN_X * 2.0, CEILING - WIN_HIGH, WALL), Vector3(0, (WIN_HIGH + CEILING) * 0.5, fz), ACCENT_WALL)
	# Skirting boards
	_box(Vector3(w, 1.0, 0.4), Vector3(0, FLOOR + 0.5, HALF_Z - 0.2), TRIM)
	_box(Vector3(w, 1.0, 0.4), Vector3(0, FLOOR + 0.5, -HALF_Z + 0.2), TRIM)
	_box(Vector3(0.4, 1.0, d), Vector3(-HALF_X + 0.2, FLOOR + 0.5, 0), TRIM)
	_box(Vector3(0.4, 1.0, d), Vector3(HALF_X - 0.2, FLOOR + 0.5, 0), TRIM)


## A white frame and cross bars in the opening, and a sill. No glass: the
## night sky behind it is the scene's background.
func _build_window() -> void:
	var z := -HALF_Z - 0.2
	var cy := (WIN_LOW + WIN_HIGH) * 0.5
	var hh := WIN_HIGH - WIN_LOW
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.8, hh + 0.8, 1.4), Vector3(sx * WIN_X, cy, z), TRIM)
	for y: float in [WIN_LOW, WIN_HIGH]:
		_box(Vector3(WIN_X * 2.0 + 0.8, 0.8, 1.4), Vector3(0, y, z), TRIM)
	_box(Vector3(0.4, hh, 0.6), Vector3(0, cy, z), TRIM)
	_box(Vector3(WIN_X * 2.0, 0.4, 0.6), Vector3(0, cy, z), TRIM)
	_box(Vector3(WIN_X * 2.0 + 3.0, 0.5, 2.6), Vector3(0, WIN_LOW - 0.6, -HALF_Z + 0.8), TRIM)


## Desk under the window, with an open laptop (glowing screen), a desk lamp,
## a mug and a small plant.
func _build_desk() -> void:
	var top := DESK_Y
	_box(Vector3(30, 1.0, 12), Vector3(0, top - 0.5, DESK_Z), WOOD)
	for sx: float in [-13.5, 13.5]:
		for sz: float in [-4.8, 4.8]:
			_box(Vector3(1.0, top - 1.0 - FLOOR, 1.0), Vector3(sx, (top - 1.0 + FLOOR) * 0.5, DESK_Z + sz), WOOD_DARK)
	# Laptop: base with a keyboard, and the lid tilted back on its hinge
	var lx := -4.0
	_box(Vector3(6.4, 0.3, 4.4), Vector3(lx, top + 0.15, DESK_Z + 0.5), Color("5a5f68"))
	_box(Vector3(5.6, 0.04, 2.6), Vector3(lx, top + 0.31, DESK_Z + 0.2), Color("2f333a"))
	for row in 4:
		for col in 12:
			_box(Vector3(0.36, 0.08, 0.5), Vector3(lx - 2.5 + col * 0.455, top + 0.36, DESK_Z - 0.85 + row * 0.62),
				Color("454a53"))
	_box(Vector3(1.8, 0.04, 1.0), Vector3(lx, top + 0.32, DESK_Z + 2.0), Color("454a53"))  # touchpad
	var hinge := Node3D.new()
	hinge.position = Vector3(lx, top + 0.3, DESK_Z - 1.7)
	hinge.rotation_degrees.x = -15.0  # lid leans back, away from the viewer
	_model.add_child(hinge)
	_box(Vector3(6.4, 4.2, 0.25), Vector3(0, 2.1, 0), Color("5a5f68"), hinge)
	_box(Vector3(5.8, 3.6, 0.05), Vector3(0, 2.15, 0.15), Color("6fa8dc"), hinge, 0.5)
	# Desk lamp: base, pole, tilted shade, glowing bulb (its light is in _build_lights)
	var lamp := Vector3(9.0, top, DESK_Z - 1.5)
	_cylinder(1.3, 1.5, 0.5, lamp + Vector3(0, 0.25, 0), Color("2f333a"))
	_cylinder(0.22, 0.22, 6.5, lamp + Vector3(0, 3.5, 0), Color("2f333a"))
	var head := Node3D.new()
	head.position = lamp + Vector3(-0.6, 6.8, 0.6)
	head.rotation_degrees = Vector3(20, 0, 20)  # pointing down at the desk, toward the laptop
	_model.add_child(head)
	_cylinder(0.7, 2.0, 2.2, Vector3.ZERO, Color("d9a441"), head)
	_sphere(0.6, Vector3(0, -0.9, 0), Color("fff1c9"), head, 3.0)
	# Mug and a little plant
	_cylinder(0.65, 0.6, 1.3, Vector3(3.5, top + 0.65, DESK_Z + 3.0), Color("d65f5f"))
	_box(Vector3(0.18, 0.8, 0.18), Vector3(4.45, top + 0.7, DESK_Z + 3.0), Color("d65f5f"))  # handle
	_box(Vector3(0.4, 0.16, 0.18), Vector3(4.3, top + 1.05, DESK_Z + 3.0), Color("d65f5f"))
	_box(Vector3(0.4, 0.16, 0.18), Vector3(4.3, top + 0.35, DESK_Z + 3.0), Color("d65f5f"))
	_cylinder(1.0, 0.8, 1.6, Vector3(-11.0, top + 0.8, DESK_Z - 1.0), Color("c7a27c"))
	for leaf: Vector3 in [Vector3(0, 2.4, 0), Vector3(0.7, 2.0, 0.3), Vector3(-0.6, 2.1, -0.3)]:
		_sphere(0.9, Vector3(-11.0, top, DESK_Z - 1.0) + leaf, Color("6f9e5c"))


## Office chair pulled out from the desk and turned aside, so it doesn't hide the laptop.
func _build_chair() -> void:
	var chair := Node3D.new()
	chair.position = Vector3(-12.0, FLOOR, DESK_Z + 11.0)
	chair.rotation_degrees.y = 35.0
	_model.add_child(chair)
	var dark := Color("3d4a5c")
	_box(Vector3(8.0, 0.5, 1.0), Vector3(0, 0.6, 0), Color("2f333a"), chair)
	_box(Vector3(1.0, 0.5, 8.0), Vector3(0, 0.6, 0), Color("2f333a"), chair)
	_cylinder(0.4, 0.4, 4.4, Vector3(0, 3.0, 0), Color("8a8f98"), chair)
	_box(Vector3(6.5, 1.0, 6.0), Vector3(0, 5.5, 0), dark, chair)
	_box(Vector3(6.5, 7.0, 0.9), Vector3(0, 9.5, 3.0), dark, chair)


## Bookshelf against the left wall, with rows of colored books.
func _build_bookshelf() -> void:
	var x := -HALF_X + 2.2
	var z := -4.0
	var height := 22.0
	var width := 14.0
	var depth := 4.0
	var shelf := Node3D.new()
	shelf.position = Vector3(x, FLOOR, z)
	_model.add_child(shelf)
	_box(Vector3(depth, height, 0.6), Vector3(0, height * 0.5, -width * 0.5), WOOD, shelf)
	_box(Vector3(depth, height, 0.6), Vector3(0, height * 0.5, width * 0.5), WOOD, shelf)
	_box(Vector3(0.4, height, width), Vector3(-depth * 0.5, height * 0.5, 0), WOOD_DARK, shelf)
	var colors: Array[Color] = [Color("c0504d"), Color("4f81bd"), Color("9bbb59"), Color("f2c14e"),
		Color("8064a2"), Color("4bacc6"), Color("e98f58"), Color("e8e3d9")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # the same books every time
	for level in 5:
		var y := 0.6 + level * 5.2
		_box(Vector3(depth, 0.6, width), Vector3(0, y, 0), WOOD, shelf)
		if level == 4:
			break
		var bz := -width * 0.5 + 0.8
		while bz < width * 0.5 - 2.0:
			var thick := rng.randf_range(0.6, 1.1)
			var tall := rng.randf_range(2.8, 4.2)
			_box(Vector3(depth - 1.0, tall, thick), Vector3(0.2, y + 0.3 + tall * 0.5, bz + thick * 0.5),
				colors[rng.randi() % colors.size()], shelf)
			bz += thick + 0.08
	_build_plant(Vector3(x, FLOOR + height + 0.3, z + 4.0), 0.45)


## Bed in the back right corner, head against the back wall.
func _build_bed() -> void:
	var c := Vector3(HALF_X - 10.0, FLOOR, HALF_Z - 13.0)
	_box(Vector3(17, 3.0, 25), c + Vector3(0, 1.5, 0), WOOD)
	_box(Vector3(16, 2.5, 24), c + Vector3(0, 4.25, 0), Color("f1ece4"))
	# The blanket hangs a little past the mattress at the foot end: if their faces
	# lined up exactly they'd flicker against each other (z-fighting).
	_box(Vector3(16.4, 2.7, 15.4), c + Vector3(0, 4.4, -4.7), Color("7d93b8"))
	for px: float in [-4.0, 4.0]:
		_box(Vector3(6.0, 1.6, 3.6), c + Vector3(px, 6.2, 9.5), Color("faf7f2"))
	_box(Vector3(17, 9.0, 1.0), c + Vector3(0, 4.5, 12.4), WOOD_DARK)


## A potted plant: a pot and a few round leaf clumps. `s` scales it.
func _build_plant(base: Vector3, s: float) -> void:
	_cylinder(2.4 * s, 1.8 * s, 4.0 * s, base + Vector3(0, 2.0 * s, 0), Color("c7a27c"))
	for leaf: Vector3 in [Vector3(0, 6.5, 0), Vector3(1.8, 5.2, 0.6), Vector3(-1.6, 5.4, -0.8),
			Vector3(0.4, 5.0, 1.8), Vector3(-0.5, 8.0, 0.3)]:
		_sphere(2.2 * s, base + leaf * s, Color("5f8f4e"))


## Door, pictures and a wall clock.
func _build_decor() -> void:
	# Door on the back wall
	var door := Vector3(-18.0, FLOOR + 10.5, HALF_Z - 0.25)
	_box(Vector3(10, 21, 0.5), door, Color("8a6243"))
	_box(Vector3(11, 22, 0.3), door + Vector3(0, 0.5, 0.15), TRIM)
	_sphere(0.5, door + Vector3(3.8, -0.5, -0.5), Color("d9c27a"))
	# A poster of blocks on the back wall, above the bed's foot
	var poster := Vector3(8.0, 2.0, HALF_Z - 0.2)
	_box(Vector3(12, 9, 0.3), poster, Color("2f333a"))
	_box(Vector3(11, 8, 0.32), poster + Vector3(0, 0, -0.05), Color("f3efe8"))
	for b: Array in [[Vector3(-2.5, 1.2, 0), Color("ffe680")], [Vector3(0, -1.0, 0), Color("a8d8ff")],
			[Vector3(2.6, 1.0, 0), Color("ffb3c7")]]:
		_box(Vector3(2.2, 2.2, 0.36), poster + b[0] + Vector3(0, 0, -0.08), b[1])
	# Framed picture on the left wall
	var pic := Vector3(-HALF_X + 0.2, 3.0, 14.0)
	_box(Vector3(0.3, 8, 11), pic, Color("6f533a"))
	_box(Vector3(0.32, 6.6, 9.6), pic + Vector3(0.05, 0, 0), Color("b8d4c8"))
	_box(Vector3(0.34, 2.4, 9.6), pic + Vector3(0.08, -2.1, 0), Color("7fa37a"))
	# Wall clock on the right wall
	var clock := Node3D.new()
	clock.position = Vector3(HALF_X - 0.3, 6.0, -12.0)
	clock.rotation_degrees.z = 90.0  # face points into the room
	_model.add_child(clock)
	_cylinder(2.6, 2.6, 0.4, Vector3.ZERO, Color("2f333a"), clock)
	_cylinder(2.3, 2.3, 0.45, Vector3.ZERO, Color("faf7f2"), clock)
	_box(Vector3(0.2, 0.5, 1.6), Vector3(0, 0.3, 0.6), Color("2f333a"), clock)
	_box(Vector3(1.4, 0.5, 0.2), Vector3(-0.5, 0.3, 0), Color("2f333a"), clock)


## Combines the hundreds of little parts into one mesh per material, so the
## room is drawn in a couple of dozen draw calls instead of hundreds.
func _merge_meshes() -> void:
	var to_model := _model.global_transform.affine_inverse()
	var tools := {}  # material -> SurfaceTool
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat := mi.material_override
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(mi.mesh, 0, to_model * mi.global_transform)
	for child in _model.get_children():
		_model.remove_child(child)
		child.queue_free()
	for mat in tools:
		var merged := MeshInstance3D.new()
		merged.mesh = (tools[mat] as SurfaceTool).commit()
		merged.material_override = mat
		_model.add_child(merged)


## Two lights in all, with main's sun: just the desk lamp, warm, with no
## shadows so note text stays clear. (In the Compatibility renderer every
## extra light draws everything it reaches again, so a room-wide ceiling
## light would double the cost of drawing the room; the glowing ceiling
## disc stays, and a little more ambient light stands in for it.)
func _build_lights() -> void:
	# Lights live outside the scaled model, so their ranges are in world units.
	var lamp := OmniLight3D.new()
	lamp.position = to_world(Vector3(8.0, DESK_Y + 5.0, DESK_Z - 0.4))
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.8
	lamp.omni_range = 12.0 * SCALE  # the desk area, not the whole room
	add_child(lamp)
	var disc := _cylinder(3.2, 3.2, 0.6, to_world(Vector3(0, CEILING - 0.3, 0)), Color("fff6e0"), self, 1.2)
	disc.scale = Vector3.ONE * SCALE


## A few glowing dust motes drifting slowly in the lamp's light (world space).
func _build_dust() -> void:
	var dust := CPUParticles3D.new()
	dust.position = to_world(Vector3(4.0, DESK_Y + 4.0, DESK_Z))
	dust.amount = 30
	dust.lifetime = 12.0
	dust.preprocess = 12.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(14, 5, 8) * SCALE
	dust.direction = Vector3.UP
	dust.spread = 180.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.3
	dust.initial_velocity_max = 1.2
	var mote := SphereMesh.new()
	mote.radius = 0.12
	mote.height = 0.24
	mote.radial_segments = 6
	mote.rings = 3
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.9, 0.65, 0.7)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.material = glow
	dust.mesh = mote
	add_child(dust)
