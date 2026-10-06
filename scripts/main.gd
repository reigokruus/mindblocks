extends Node3D
## Mindblocks – notes as cubes floating in 3D space.
##
## Everything (environment, camera, UI) is built in code so the scene file
## stays tiny and the whole app can be read top to bottom in this script.

const NoteScript := preload("res://scripts/note.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")

const SAVE_PATH := "user://notes.json"
## The app used to be called Spatial Notes; its save sits in that name's user:// folder.
const OLD_APP_NAME := "Spatial Notes"
const AUTOSAVE_DELAY := 1.0
const BG_COLOR := Color(0.08, 0.09, 0.11)
## Depth guides: a floor grid, with a drop line and a footprint ring under every note.
const FLOOR_Y := -4.0
const GRID_STEP := 4.0
const GRID_HALF := 80.0
const FOOT_RADIUS := 0.35
const FOOT_SEGS := 20
## Links are camera-facing ribbons of this world width (so nearer ones look thicker),
## fading from LINK_NEAR_ALPHA to LINK_FAR_ALPHA over LINK_FADE_DIST.
const LINK_WIDTH := 0.05
const LINK_NEAR_ALPHA := 0.95
const LINK_FAR_ALPHA := 0.2
const LINK_FADE_DIST := 40.0
const LINK_COLOR := Color(0.75, 0.85, 1.0)
## Depth effect: notes more than FOCUS_MARGIN behind the focused note darken
## over DIM_RANGE (up to MAX_DIM).
const FOCUS_MARGIN := 0.75
## The camera is kept at least this far outside every cube.
const CAMERA_RADIUS := 0.4
const DIM_RANGE := 12.0
const MAX_DIM := 0.6
## Cubes never end up closer than SPACING (center to center). A cube that's
## placed too close to others (dropped, created, pasted, copied) floats away
## to the nearest free spot over SETTLE_TIME; the cubes already there stay put.
const SPACING := 2.5
## "+" buttons shown around the selected note: radius, distance of their centers
## from the note's edge, and how far from the note a new note is placed.
const PLUS_RADIUS := 0.28
## Rotating a cube: radians per pixel of mouse movement while R is held,
## and how long an arrow-key quarter turn takes.
const ROTATE_SPEED := 0.01
const TURN_TIME := 0.3
const DOUBLE_TAP_TIME := 0.35  # seconds between two R presses that count as a double-tap
const PLUS_GAP := 0.45
## Move gizmo on the selected cube: one arrow per axis of the cube itself
## (X red, Y green, Z blue, as in the Godot editor's local mode), so the arrows
## run along the cube's sides even when it's turned. Each axis has an arrow on
## both sides of the cube; either one drags along that axis. Arrows start past the + buttons so the two
## don't overlap. Distances are from the cube's center.
const GIZMO_START := 1.8
const GIZMO_SHAFT_END := 2.3
const GIZMO_TIP_END := 2.6
const GIZMO_PICK := 0.2  # how close (world units) the aim ray must pass to grab an arrow
const GIZMO_AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const GIZMO_COLORS: Array[Color] = [Color(0.96, 0.3, 0.35), Color(0.55, 0.85, 0.25), Color(0.3, 0.55, 1.0)]
const PLUS_NEW_OFFSET := 2.5  # center to center: the cube side plus a small gap
## A cube whose center is closer than NEIGHBOR_RANGE counts as sitting against
## one of this cube's faces: that face's + is hidden.
const NEIGHBOR_RANGE := 3.0
## Snapping while moving a cube: if it's within SNAP_DIST of the slot right
## against a face of another cube (PLUS_NEW_OFFSET from its center), a ghost
## shows that slot, and letting go drops the cube there, turned like its
## neighbor. Hold Shift when letting go to place it freely instead.
const SNAP_DIST := 1.5
const SNAP_TIME := 0.2
const PLUS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;

uniform float hover = 0.0;
uniform float radius = 0.28;

varying vec2 local;

void vertex() {
	local = VERTEX.xy;
}

void fragment() {
	float r = length(local) / radius;  // 0 at the center, 1 at the rim
	vec2 a = abs(local) / radius;
	float bar = 0.09;
	float plus = (a.x < bar && a.y < 0.5) || (a.y < bar && a.x < 0.5) ? 1.0 : 0.0;
	float ring = smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float disc = 1.0 - smoothstep(0.96, 1.0, r);
	float fill = mix(0.25, 0.55, hover) * disc;
	ALBEDO = mix(vec3(0.12, 0.13, 0.16), vec3(1.0), max(plus, ring));
	ALPHA = max(max(plus * disc, ring) * mix(0.8, 1.0, hover), fill);
}
"""
const SETTLE_TIME := 0.4
const UNDO_LIMIT := 50
## Undo / redo messages, top right: the newest sits at the bottom of the stack,
## older ones float up and fade; each disappears after TOAST_LIFE seconds.
const TOAST_TOP := 16.0
const TOAST_ROW := 40.0
const TOAST_MAX := 5
const TOAST_LIFE := 2.5
const UNDO_MOVE_TIME := 0.25

const HELP_TEXT := """Mouse — look around · clicks act at the crosshair
Esc — pause and free the cursor · the pause menu has New notespace (start over) and Exit
Double-click empty space — new note · click a cube, then + on a face — new linked cube there
Double-click a note / Enter — edit it
Hold click on a note — carry it (scroll while carrying: nearer / farther)
Drag a colored arrow — move selected cube along that axis
Moving near another cube shows a ghost: let go to snap there (Shift = don't)
R + mouse — rotate selected cube · arrow keys — turn it 90° · R R — straighten it
Shift+click another note — link / unlink with selected
1–7 — recolor selected · F — focus selected · Delete — delete
Alt + drag a cube — drag out a copy · Ctrl+C / Ctrl+X / Ctrl+V — copy / cut / paste where you look
Ctrl+Z — undo (blocks, moves, text edits…) · Ctrl+Y or Ctrl+Shift+Z — redo
Right-drag — orbit · Middle-drag or Shift+right-drag — pan
Scroll — zoom · W A S D / Q E — fly (Shift = faster)
Space — fly up
G — floor guides on / off
H — hide this help · saves automatically"""

var palette: Array[Color] = [
	Color("ffe680"),  # yellow
	Color("ffb3c7"),  # pink
	Color("a8d8ff"),  # blue
	Color("b8f2a6"),  # green
	Color("ffc58a"),  # orange
	Color("d6c2ff"),  # purple
	Color("f2f2f2"),  # white
]

var rig: CameraRigScript
var camera: Camera3D
var notes_root: Node3D
var notes: Dictionary = {}  # id (int) -> note
var links: Array = []  # each entry is [id_a, id_b] with id_a < id_b
var next_id := 1
var last_color: Color
## Undo history, newest last. Each entry is either
## {type: "delete", id, text, color, status, rot, pos, links} or
## {type: "move", id, pos, rot} (where the cube was before it moved / turned) or
## {type: "create", id} (a copied / pasted cube, which undo removes) or
## {type: "group", entries} (several steps undone / redone together) or
## {type: "edit", id, text, color, status} (what a cube said / looked like).
## Every entry also has a "label" (e.g. "block move") for the undo message.
var undo_stack: Array[Dictionary] = []
## Undone steps, newest last, in the same format. Any new action clears it.
var redo_stack: Array[Dictionary] = []
## Cubes currently easing somewhere (undo / redo, snapping, floating free):
## {tween, note, pos, rot}. A quick next undo / redo first jumps them to the end.
var easing: Array[Dictionary] = []
var edit_start: Dictionary = {}  # the cube's text / color / mark when the editor opened
var toast_root: Control
var toasts: Array[Label] = []  # newest last
## Where a cube was when the current carry / arrow drag / R-rotation began.
var move_start: Dictionary = {}

var selected: NoteScript = null
var dragging: NoteScript = null
## The dragged note's offset from the camera, in camera space, so it moves with the view.
var drag_local := Vector3.ZERO
var drag_moved := false
var orbiting := false
var panning := false

## Depth (along the view direction) the eye is focused at; eases toward the aimed note.
var focus_depth := 9.0
var lines_mesh: ImmediateMesh
var lines_mat: StandardMaterial3D
var grid: MeshInstance3D
var guides: MeshInstance3D
var guides_mesh: ImmediateMesh
var plus_buttons: Array[MeshInstance3D] = []
var gizmo: Node3D
var gizmo_mats: Array[StandardMaterial3D] = []
var gizmo_axis := -1  # arrow being dragged, or -1
var snap_ghost: MeshInstance3D
var snap_ghost_mat: StandardMaterial3D
var snap_target: Dictionary = {}  # {pos, rot} while a moving cube is near a free slot
var turn_tween: Tween
var turn_target := Quaternion.IDENTITY
var turn_note: NoteScript = null
var last_r_press := -1.0
## Ctrl+C copies the selected cube here: {text, color, status, rot}.
var clipboard: Dictionary = {}

var dirty := false
var dirty_timer := 0.0

var help_panel: PanelContainer
var editor_panel: PanelContainer
var editor_text: TextEdit
var editing: NoteScript = null
var mark_done_btn: Button
var mark_failed_btn: Button
var pause_panel: Control
var pause_buttons: Control  # Continue / New notespace
var new_confirm: Control  # "Start a new notespace?" with its two buttons
var crosshair: Control
var paused := false


# --- Setup ------------------------------------------------------------------

func _ready() -> void:
	last_color = palette[0]
	_setup_environment()
	rig = CameraRigScript.new()
	rig.process_priority = -1  # fly first, so _process() can then push the camera out of cubes
	add_child(rig)
	camera = rig.camera
	_build_link_lines()
	_build_guides()
	_build_plus_buttons()
	_build_gizmo()
	_build_snap_ghost()
	notes_root = Node3D.new()
	notes_root.name = "Notes"
	add_child(notes_root)
	_build_ui()
	if not _load():
		_create_welcome_notes()
		_save()
	# Start paused: grabbing the mouse before the window has focus silently fails
	# on X11 / XWayland, so the first grab happens when Continue is clicked.
	_set_paused(true)
	# Open big: maximized, but still a normal window (title bar, taskbar).
	# Skipped when the game runs embedded in the editor's Game tab.
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Lights the 3D cards so they show their shape (curl, edges).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 0.85
	add_child(sun)


## Unshaded, transparent, colored per vertex.
func _vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _build_link_lines() -> void:
	lines_mesh = ImmediateMesh.new()
	lines_mat = _vertex_color_material()
	var mi := MeshInstance3D.new()
	mi.mesh = lines_mesh
	add_child(mi)


func _build_plus_buttons() -> void:
	var shader := Shader.new()
	shader.code = PLUS_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * PLUS_RADIUS * 2.0
	for i in NoteScript.FACES.size():
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = 3
		mat.set_shader_parameter("radius", PLUS_RADIUS)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.visible = false
		add_child(mi)
		plus_buttons.append(mi)


func _build_guides() -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.07)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var x := -GRID_HALF
	while x <= GRID_HALF:
		im.surface_add_vertex(Vector3(x, 0, -GRID_HALF))
		im.surface_add_vertex(Vector3(x, 0, GRID_HALF))
		im.surface_add_vertex(Vector3(-GRID_HALF, 0, x))
		im.surface_add_vertex(Vector3(GRID_HALF, 0, x))
		x += GRID_STEP
	im.surface_end()
	grid = MeshInstance3D.new()
	grid.mesh = im
	grid.position.y = FLOOR_Y
	add_child(grid)

	guides_mesh = ImmediateMesh.new()
	guides = MeshInstance3D.new()
	guides.mesh = guides_mesh
	guides.material_override = _vertex_color_material()
	add_child(guides)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Help overlay (top-left)
	help_panel = PanelContainer.new()
	help_panel.position = Vector2(16, 16)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.55), 8))
	var help_label := Label.new()
	help_label.text = HELP_TEXT
	help_label.add_theme_font_size_override("font_size", 14)
	help_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92))
	help_panel.add_child(help_label)
	layer.add_child(help_panel)

	# Note editor (bottom-center)
	editor_panel = PanelContainer.new()
	editor_panel.anchor_left = 0.5
	editor_panel.anchor_right = 0.5
	editor_panel.anchor_top = 1.0
	editor_panel.anchor_bottom = 1.0
	editor_panel.offset_left = -300
	editor_panel.offset_right = 300
	editor_panel.offset_top = -300
	editor_panel.offset_bottom = -20
	# Grow upward if the content needs more room, so the button row stays on screen.
	editor_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	editor_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.13, 0.16, 0.96), 10))
	editor_panel.visible = false
	layer.add_child(editor_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	editor_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Edit note   (Ctrl+Enter or Esc to close)"
	vbox.add_child(title)

	editor_text = TextEdit.new()
	editor_text.custom_minimum_size = Vector2(0, 170)
	editor_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor_text.text_changed.connect(_on_editor_text_changed)
	vbox.add_child(editor_text)

	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 6)
	for c in palette:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(30, 30)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.add_theme_stylebox_override("normal", _panel_style(c, 6))
		swatch.add_theme_stylebox_override("hover", _panel_style(c.lightened(0.2), 6))
		swatch.add_theme_stylebox_override("pressed", _panel_style(c.darkened(0.2), 6))
		swatch.pressed.connect(_on_color_picked.bind(c))
		colors.add_child(swatch)
	vbox.add_child(colors)

	var row := HBoxContainer.new()
	var delete_btn := Button.new()
	delete_btn.text = "Delete note"
	delete_btn.pressed.connect(_on_editor_delete)
	row.add_child(delete_btn)
	mark_done_btn = Button.new()
	mark_done_btn.text = "Mark done"
	mark_done_btn.toggle_mode = true
	mark_done_btn.pressed.connect(_on_status_picked.bind("done"))
	row.add_child(mark_done_btn)
	mark_failed_btn = Button.new()
	mark_failed_btn.text = "Mark failed"
	mark_failed_btn.toggle_mode = true
	mark_failed_btn.pressed.connect(_on_status_picked.bind("failed"))
	row.add_child(mark_failed_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var done_btn := Button.new()
	done_btn.text = "Close"
	done_btn.pressed.connect(_close_editor)
	row.add_child(done_btn)
	vbox.add_child(row)

	# Crosshair (center), shown while the mouse is captured
	crosshair = ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.8)
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -2
	crosshair.offset_right = 2
	crosshair.offset_top = -2
	crosshair.offset_bottom = 2
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(crosshair)

	# Undo / redo messages (top right)
	toast_root = Control.new()
	toast_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toast_root)

	# Pause menu (full screen dim + centered panel)
	pause_panel = ColorRect.new()
	(pause_panel as ColorRect).color = Color(0, 0, 0, 0.5)
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	layer.add_child(pause_panel)
	# Clicking the dimmed area around the menu also continues.
	pause_panel.gui_input.connect(_on_pause_backdrop_input)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(center)
	var menu := PanelContainer.new()
	menu.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.13, 0.16, 0.96), 10))
	center.add_child(menu)
	var menu_box := VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 14)
	menu.add_child(menu_box)
	var paused_label := Label.new()
	paused_label.text = "Paused"
	paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused_label.add_theme_font_size_override("font_size", 28)
	menu_box.add_child(paused_label)
	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(200, 40)
	continue_btn.pressed.connect(_set_paused.bind(false))
	var new_btn := Button.new()
	new_btn.text = "New notespace"
	new_btn.custom_minimum_size = Vector2(200, 40)
	new_btn.pressed.connect(_show_new_confirm.bind(true))
	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.custom_minimum_size = Vector2(200, 40)
	exit_btn.pressed.connect(_exit)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.add_child(continue_btn)
	buttons.add_child(new_btn)
	buttons.add_child(exit_btn)
	pause_buttons = buttons
	menu_box.add_child(buttons)
	# Starting a new notespace asks first, in place of the buttons above.
	var confirm := VBoxContainer.new()
	confirm.add_theme_constant_override("separation", 10)
	confirm.visible = false
	var question := Label.new()
	question.text = "Start a new notespace?\nThis deletes all current blocks."
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm.add_child(question)
	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 10)
	var yes_btn := Button.new()
	yes_btn.text = "Delete and start new"
	yes_btn.custom_minimum_size = Vector2(0, 40)
	yes_btn.pressed.connect(_new_notespace)
	confirm_row.add_child(yes_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(_show_new_confirm.bind(false))
	confirm_row.add_child(cancel_btn)
	confirm.add_child(confirm_row)
	new_confirm = confirm
	menu_box.add_child(confirm)


func _panel_style(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(12)
	return s


# --- Per frame --------------------------------------------------------------

func _process(delta: float) -> void:
	_keep_camera_outside_notes()
	_update_depth_fx(delta)

	if dragging:
		var held := camera.global_position + camera.global_transform.basis * drag_local
		if not held.is_equal_approx(dragging.global_position):
			dragging.global_position = held
			drag_moved = true

	rig.input_blocked = editor_panel.visible or paused
	crosshair.visible = _mouse_captured()
	_redraw_links()
	_update_plus_buttons()
	_update_gizmo()
	_update_snap()
	if guides.visible:
		_redraw_guides()

	if dirty:
		dirty_timer -= delta
		if dirty_timer <= 0.0:
			_save()


## Pushes the camera out of any cube it got into (by flying, zooming, looking
## around, or a cube moving onto it), along the shortest way out, so it slides
## along faces instead of clipping through. The carried cube is skipped.
func _keep_camera_outside_notes() -> void:
	var h := NoteScript.SIZE * 0.5 + CAMERA_RADIUS
	for pass_i in 2:  # a second pass settles pushes between neighbouring cubes
		for v in notes.values():
			var n: NoteScript = v
			if n == dragging:
				continue
			var t := n.global_transform
			var p := t.affine_inverse() * camera.global_position
			if absf(p.x) >= h or absf(p.y) >= h or absf(p.z) >= h:
				continue
			var axis := 0
			for k in [1, 2]:
				if absf(p[k]) > absf(p[axis]):
					axis = k
			var push := Vector3.ZERO
			push[axis] = (h - absf(p[axis])) * (1.0 if p[axis] >= 0.0 else -1.0)
			rig.position += t.basis * push


## Focus on the note being edited, carried or aimed at; darken notes behind it.
func _update_depth_fx(delta: float) -> void:
	var cam_pos := camera.global_position
	var forward := -camera.global_transform.basis.z
	var focus_note: NoteScript = editing if editing else dragging
	if focus_note == null and not paused:
		focus_note = _pick(_aim_pos())
	if focus_note:
		var target := forward.dot(focus_note.global_position - cam_pos)
		focus_depth = lerpf(focus_depth, target, minf(1.0, delta * 8.0))
	for v in notes.values():
		var n: NoteScript = v
		var depth := forward.dot(n.global_position - cam_pos)
		var behind := depth - focus_depth - FOCUS_MARGIN
		n.set_depth_fx(clampf(behind / DIM_RANGE, 0.0, 1.0) * MAX_DIM)


## Each link is a flat ribbon turned toward the camera at both ends, so its
## on-screen width shrinks with distance, and it fades out with distance too.
func _redraw_links() -> void:
	lines_mesh.clear_surfaces()
	var cam_pos := camera.global_position
	var started := false
	for l in links:
		var a: NoteScript = notes.get(l[0])
		var b: NoteScript = notes.get(l[1])
		if not (a and b):
			continue
		if not started:
			lines_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, lines_mat)
			started = true
		var pa := a.global_position
		var pb := b.global_position
		var dir := pb - pa
		var side_a := dir.cross(cam_pos - pa).normalized() * LINK_WIDTH * 0.5
		var side_b := dir.cross(cam_pos - pb).normalized() * LINK_WIDTH * 0.5
		var ca := _link_color(pa.distance_to(cam_pos))
		var cb := _link_color(pb.distance_to(cam_pos))
		for v in [[pa - side_a, ca], [pa + side_a, ca], [pb + side_b, cb],
				[pa - side_a, ca], [pb + side_b, cb], [pb - side_b, cb]]:
			lines_mesh.surface_set_color(v[1])
			lines_mesh.surface_add_vertex(v[0])
	if started:
		lines_mesh.surface_end()


func _link_color(dist: float) -> Color:
	var t := clampf(dist / LINK_FADE_DIST, 0.0, 1.0)
	return Color(LINK_COLOR, lerpf(LINK_NEAR_ALPHA, LINK_FAR_ALPHA, t))


## A drop line from every note to the floor and a ring where it lands, so
## height and position over the floor can be read without moving around.
func _redraw_guides() -> void:
	var cam_pos := camera.global_position
	grid.position.x = snappedf(cam_pos.x, GRID_STEP)
	grid.position.z = snappedf(cam_pos.z, GRID_STEP)
	guides_mesh.clear_surfaces()
	if notes.is_empty():
		return
	guides_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var line_col := Color(1, 1, 1, 0.18)
	for v in notes.values():
		var n: NoteScript = v
		var p := n.global_position
		var foot := Vector3(p.x, FLOOR_Y, p.z)
		var ring_col := Color(n.color, 0.6)
		guides_mesh.surface_set_color(line_col)
		guides_mesh.surface_add_vertex(p)
		guides_mesh.surface_set_color(line_col)
		guides_mesh.surface_add_vertex(foot)
		for i in FOOT_SEGS:
			for k in [i, i + 1]:
				var a: float = TAU * k / FOOT_SEGS
				guides_mesh.surface_set_color(ring_col)
				guides_mesh.surface_add_vertex(foot + Vector3(cos(a), 0, sin(a)) * FOOT_RADIUS)
	guides_mesh.surface_end()


# --- Input ------------------------------------------------------------------

## Runs before the GUI, so it can close the editor on Esc / Ctrl+Enter / outside click,
## and toggle the pause menu on Esc otherwise.
func _input(event: InputEvent) -> void:
	if not editor_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo \
				and (event as InputEventKey).keycode == KEY_ESCAPE:
			_set_paused(not paused)
			get_viewport().set_input_as_handled()
		elif not paused and not _mouse_captured() \
				and event is InputEventMouseButton and event.pressed:
			# The cursor got freed some other way (e.g. by the OS): a click grabs it back.
			_capture_mouse()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		var is_enter := k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER
		if k.keycode == KEY_ESCAPE or (is_enter and k.ctrl_pressed):
			_close_editor()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if not editor_panel.get_global_rect().has_point(mb.position):
			_close_editor()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if editor_panel.visible or paused:
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event as InputEventKey)
	elif event is InputEventKey and not event.pressed and event.keycode == KEY_R:
		_commit_move()  # an R-rotation just ended


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if not e.pressed:
				_end_drag()
				return
			var aim := _aim_pos()
			var axis := _pick_gizmo(aim)
			if axis >= 0:
				if e.alt_pressed:
					_select(_copy_in_place(selected))  # drag out a copy instead
					move_start = {}  # undo removes the copy in one step
				else:
					move_start = _move_record(selected)
				gizmo_axis = axis
				return
			var plus := _pick_plus(aim)
			if plus >= 0:
				_add_note_beside(selected, plus)
				return
			var hit := _pick(aim)
			if e.double_click:
				_end_drag()
				if hit:
					_open_editor(hit)
				else:
					var n := _create_note(_point_in_front(aim), "", last_color)
					_face_camera(n)
					_push_create(n, "new block")
					_open_editor(n)
				return
			if hit and e.shift_pressed and selected and selected != hit:
				_toggle_link(selected, hit)
				return
			if hit and e.alt_pressed:
				hit = _copy_in_place(hit)  # drag out a copy, the original stays
				_select(hit)
				_begin_drag(hit)
				move_start = {}  # undo removes the copy in one step
				return
			_select(hit)
			if hit:
				_begin_drag(hit)
		MOUSE_BUTTON_RIGHT:
			if e.pressed:
				if e.shift_pressed:
					panning = true
				else:
					orbiting = true
			else:
				orbiting = false
				panning = false
		MOUSE_BUTTON_MIDDLE:
			panning = e.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				if dragging:
					_push_drag(-0.6)
				else:
					rig.zoom(0.9)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				if dragging:
					_push_drag(0.6)
				else:
					rig.zoom(1.1)


## A dragged note is carried along by _process(), so it follows any of these.
func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if gizmo_axis >= 0:
		_drag_gizmo(e.relative)
	elif orbiting:
		rig.orbit(e.relative)
	elif panning:
		rig.pan(e.relative)
	elif Input.is_key_pressed(KEY_R) and (dragging or selected):
		_rotate_note(dragging if dragging else selected, e.relative)
	elif _mouse_captured():
		rig.look(e.relative)


## Trackball-style: moving the mouse turns the cube around the camera's up
## and right axes, so it follows the mouse the way it looks on screen.
func _rotate_note(n: NoteScript, relative: Vector2) -> void:
	if move_start.is_empty():
		move_start = _move_record(n)
	var b := camera.global_transform.basis
	var q := Quaternion(b.y, relative.x * ROTATE_SPEED) * Quaternion(b.x, relative.y * ROTATE_SPEED)
	n.quaternion = (q * n.quaternion).normalized()
	_mark_dirty()


## A quarter turn of the selected cube around a camera axis, eased.
func _turn_selected(axis: Vector3, angle: float) -> void:
	if selected == null:
		return
	# Pressed again mid-turn: continue from where the running turn was headed,
	# so quick presses still add up to exact quarter turns.
	var base := selected.quaternion
	if turn_tween and turn_tween.is_running() and turn_note == selected:
		turn_tween.kill()
		base = turn_target
	turn_note = selected
	_push_undo({"type": "move", "id": selected.id, "pos": selected.global_position, "rot": base,
		"label": "block rotation"})
	turn_target = (Quaternion(axis, angle) * base).normalized()
	turn_tween = selected.create_tween()
	turn_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	turn_tween.tween_property(selected, "quaternion", turn_target, TURN_TIME)
	turn_tween.finished.connect(_mark_dirty)


## A new cube with the same text, color, mark and rotation as `src`, on the
## same spot. Undo removes it.
func _copy_in_place(src: NoteScript) -> NoteScript:
	var n := _create_note(src.global_position, src.text, src.color)
	n.status = src.status
	n.quaternion = src.quaternion
	n.refresh()
	_push_undo({"type": "create", "id": n.id, "label": "block copy"})
	return n


## Ctrl+C: remembers the selected cube, and puts its text on the system clipboard.
func _copy_selected() -> void:
	clipboard = {"text": selected.text, "color": selected.color,
		"status": selected.status, "rot": selected.quaternion}
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(selected.text)


## Ctrl+X: copies the selected cube and deletes it (Ctrl+Z brings it back).
## Its links are remembered, so the next paste reconnects it to the same cubes.
func _cut_selected() -> void:
	var n := selected
	_copy_selected()
	var linked: Array[int] = []
	for l in links:
		if l[0] == n.id or l[1] == n.id:
			linked.append(l[1] if l[0] == n.id else l[0])
	clipboard["links_to"] = linked
	_delete_note(n, true)
	undo_stack[-1]["label"] = "block cut"


## Ctrl+V: places the copied cube where you're looking (like double-click does);
## it floats free if that's inside / too close to another cube. If something
## else was copied to the system clipboard since, a new cube with that text is
## pasted instead.
func _paste() -> void:
	var data := clipboard
	var outside := ""
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		outside = DisplayServer.clipboard_get()
	if outside.strip_edges() != "" and (data.is_empty() or outside != data["text"]):
		data = {"text": outside, "color": last_color, "status": "",
			"rot": Quaternion(Vector3.UP, rig.yaw)}
	if data.is_empty():
		return
	var n := _create_note(_point_in_front(_aim_pos()), data["text"], data["color"])
	n.status = data["status"]
	n.quaternion = data["rot"]
	n.refresh()
	# A cut cube gets its links back on its first paste (to cubes that still exist).
	for other_id in data.get("links_to", []):
		if notes.has(other_id):
			links.append([mini(n.id, other_id), maxi(n.id, other_id)])
	clipboard.erase("links_to")
	_push_create(n, "block paste")
	_select(n)


## Double-tap R: eases the selected cube back to its default rotation (upright,
## lined up with the floor grid). Its position stays; Ctrl+Z undoes it.
func _straighten_selected() -> void:
	if selected == null or selected.quaternion.is_equal_approx(Quaternion.IDENTITY):
		return
	_commit_move()  # close any R-rotation from the first tap
	if turn_tween and turn_tween.is_running() and turn_note == selected:
		turn_tween.kill()
	var record := _move_record(selected)
	record["label"] = "block rotation"
	_push_undo(record)
	turn_note = selected
	turn_target = Quaternion.IDENTITY
	turn_tween = selected.create_tween()
	turn_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	turn_tween.tween_property(selected, "quaternion", Quaternion.IDENTITY, TURN_TIME)
	turn_tween.finished.connect(_mark_dirty)


func _on_key(e: InputEventKey) -> void:
	match e.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			if selected:
				_delete_note(selected, true)
		KEY_ENTER, KEY_KP_ENTER:
			if selected:
				_open_editor(selected)
		KEY_R:
			var now := Time.get_ticks_msec() / 1000.0
			if now - last_r_press < DOUBLE_TAP_TIME:
				_straighten_selected()
				last_r_press = -1.0
			else:
				last_r_press = now
		KEY_LEFT:
			_turn_selected(camera.global_transform.basis.y, -PI * 0.5)
		KEY_RIGHT:
			_turn_selected(camera.global_transform.basis.y, PI * 0.5)
		KEY_UP:
			_turn_selected(camera.global_transform.basis.x, -PI * 0.5)
		KEY_DOWN:
			_turn_selected(camera.global_transform.basis.x, PI * 0.5)
		KEY_F:
			if selected:
				rig.focus(selected.global_position)
		KEY_G:
			guides.visible = not guides.visible
			grid.visible = guides.visible
		KEY_H, KEY_F1:
			help_panel.visible = not help_panel.visible
		KEY_S:
			if e.ctrl_pressed:
				_save()
		KEY_C:
			if e.ctrl_pressed and selected:
				_copy_selected()
		KEY_X:
			if e.ctrl_pressed and selected:
				_cut_selected()
		KEY_V:
			if e.ctrl_pressed:
				_paste()
		KEY_Z:
			if e.ctrl_pressed and e.shift_pressed:
				_redo()
			elif e.ctrl_pressed:
				_undo()
		KEY_Y:
			if e.ctrl_pressed:
				_redo()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			var i: int = e.keycode - KEY_1
			if selected and i < palette.size() and selected.color != palette[i]:
				var record := _edit_record(selected)
				record["label"] = "color change"
				_push_undo(record)
				_set_note_color(selected, palette[i])


# --- Picking & dragging -----------------------------------------------------

## Where clicks act: the crosshair while the mouse is captured, else the cursor.
func _aim_pos() -> Vector2:
	if _mouse_captured():
		return get_viewport().get_visible_rect().size * 0.5
	return get_viewport().get_mouse_position()


## Finds the nearest note (cube) under a screen position, by casting a ray
## against each cube's box. No physics engine needed.
func _pick(screen_pos: Vector2) -> NoteScript:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best: NoteScript = null
	var best_dist := INF
	for v in notes.values():
		var n: NoteScript = v
		var d := n.ray_distance(from, dir)
		if d < best_dist:
			best_dist = d
			best = n
	return best


## A point in front of the camera, at the depth of the orbit center.
func _point_in_front(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var plane := Plane(-camera.global_transform.basis.z, rig.global_position)
	var hit = plane.intersects_ray(from, dir)
	if hit != null:
		return hit
	return from + dir * rig.distance


func _begin_drag(n: NoteScript) -> void:
	dragging = n
	drag_moved = false
	move_start = _move_record(n)
	drag_local = camera.global_transform.basis.inverse() * (n.global_position - camera.global_position)


## Moves the dragged note along the line from the camera through it,
## so it stays at the same spot on screen while getting nearer or farther.
func _push_drag(amount: float) -> void:
	var dist := drag_local.length()
	var step := amount * maxf(1.0, dist * 0.1)
	# Don't pull the carried cube's corners into the camera.
	if dist + step < NoteScript.SIZE * 0.87 + CAMERA_RADIUS:
		return
	drag_local = drag_local.normalized() * (dist + step)


func _end_drag() -> void:
	var moved := _moving_note()
	if gizmo_axis >= 0:
		gizmo_axis = -1
		_mark_dirty()
	if dragging and drag_moved:
		_mark_dirty()
	dragging = null
	if moved and not snap_target.is_empty() and not Input.is_key_pressed(KEY_SHIFT):
		_ease_note(moved, snap_target["pos"], snap_target["rot"], SNAP_TIME)
	elif moved:
		_settle(moved)  # dropped inside / too close to another cube: float free
	snap_target = {}
	snap_ghost.visible = false
	if not Input.is_key_pressed(KEY_R):
		_commit_move()


# --- Snapping & neighbors ---------------------------------------------------

func _build_snap_ghost() -> void:
	snap_ghost_mat = StandardMaterial3D.new()
	snap_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snap_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snap_ghost_mat.no_depth_test = true  # visible even inside / behind other cubes
	var box := BoxMesh.new()
	box.size = Vector3.ONE * NoteScript.SIZE
	snap_ghost = MeshInstance3D.new()
	snap_ghost.mesh = box
	snap_ghost.material_override = snap_ghost_mat
	snap_ghost.visible = false
	add_child(snap_ghost)


## The cube currently being carried or dragged by an arrow, if any.
func _moving_note() -> NoteScript:
	if dragging:
		return dragging
	if gizmo_axis >= 0 and selected and is_instance_valid(selected):
		return selected
	return null


## Index (into NoteScript.FACES) of the face of cube `n` that point `p` lies beyond.
func _face_toward(n: NoteScript, p: Vector3) -> int:
	var local := n.global_transform.affine_inverse() * p
	var axis := local.abs().max_axis_index()
	var out := Vector3.ZERO
	out[axis] = signf(local[axis]) if local[axis] != 0.0 else 1.0
	for i in NoteScript.FACES.size():
		if (NoteScript.FACES[i][0] as Vector3).is_equal_approx(out):
			return i
	return 0


## Faces of `n` that have another cube sitting close against them.
func _blocked_faces(n: NoteScript) -> Array[bool]:
	var blocked: Array[bool] = []
	blocked.resize(NoteScript.FACES.size())
	blocked.fill(false)
	for v in notes.values():
		var m: NoteScript = v
		if m != n and m.global_position.distance_to(n.global_position) < NEIGHBOR_RANGE:
			blocked[_face_toward(n, m.global_position)] = true
	return blocked


## The nearest free slot against a face of another cube, within SNAP_DIST of
## where the moving cube `m` is now: {pos, rot}, or {} if there is none.
func _find_snap(m: NoteScript) -> Dictionary:
	var p := m.global_position
	var best: Dictionary = {}
	var best_dist := SNAP_DIST
	for v in notes.values():
		var n: NoteScript = v
		if n == m or n.global_position.distance_to(p) > PLUS_NEW_OFFSET + SNAP_DIST:
			continue
		var slot := n.global_position + _face_dir(n, _face_toward(n, p)) * PLUS_NEW_OFFSET
		var d := p.distance_to(slot)
		if d >= best_dist:
			continue
		var free := true
		for w in notes.values():
			if w != m and w != n and (w as NoteScript).global_position.distance_to(slot) < SPACING - 0.01:
				free = false
				break
		if free:
			best_dist = d
			best = {"pos": slot, "rot": n.quaternion}
	return best


## While a cube is being moved, shows a see-through ghost where it would snap.
func _update_snap() -> void:
	var m := _moving_note()
	snap_target = _find_snap(m) if m else {}
	snap_ghost.visible = not snap_target.is_empty() and not Input.is_key_pressed(KEY_SHIFT)
	if snap_ghost.visible:
		snap_ghost.global_transform = Transform3D(Basis(snap_target["rot"]), snap_target["pos"])
		snap_ghost_mat.albedo_color = Color(m.color, 0.35)


# --- Undo -------------------------------------------------------------------

func _move_record(n: NoteScript) -> Dictionary:
	return {"type": "move", "id": n.id, "pos": n.global_position, "rot": n.quaternion}


## Records a new action. A new action makes the undone steps unreachable,
## so the redo history is dropped, as in any editor.
func _push_undo(entry: Dictionary) -> void:
	_append_limited(undo_stack, entry)
	redo_stack.clear()


func _append_limited(stack: Array[Dictionary], entry: Dictionary) -> void:
	stack.append(entry)
	if stack.size() > UNDO_LIMIT:
		stack.pop_front()


## Ends the current move / rotation: if the cube actually changed, remember
## where it was so Ctrl+Z can put it back.
func _commit_move() -> void:
	if move_start.is_empty():
		return
	var n: NoteScript = notes.get(move_start["id"])
	if n and not n.global_position.is_equal_approx(move_start["pos"]):
		move_start["label"] = "block move"
		_push_undo(move_start)
	elif n and not n.quaternion.is_equal_approx(move_start["rot"]):
		move_start["label"] = "block rotation"
		_push_undo(move_start)
	move_start = {}


## Ctrl+Z: undoes the newest step, and makes it redoable.
func _undo() -> void:
	_commit_move()
	_step_history(undo_stack, redo_stack, "Undo")


## Ctrl+Y / Ctrl+Shift+Z: redoes the newest undone step.
func _redo() -> void:
	_commit_move()
	_step_history(redo_stack, undo_stack, "Redo")


## Takes the newest entry from `from`, applies it, and puts its opposite on
## `to`. Entries for cubes that no longer exist are skipped.
## `verb` ("Undo" / "Redo") is shown in the message along with the step's label.
func _step_history(from: Array[Dictionary], to: Array[Dictionary], verb: String) -> void:
	_finish_easing()
	while not from.is_empty():
		var entry: Dictionary = from.pop_back()
		var inverse := _apply_history(entry)
		if not inverse.is_empty():
			inverse["label"] = entry.get("label", "change")
			_append_limited(to, inverse)
			_toast("%s %s" % [verb, inverse["label"]])
			return
	_toast("Nothing to %s" % verb.to_lower())


## Applies one history entry and returns the entry that reverses it ({} if it
## no longer applies):
## - "delete" brings the deleted cube back; reversed by "create".
## - "create" removes the cube; reversed by "delete" (with all its data).
## - "move" eases the cube to the stored place / rotation; reversed by a
##   "move" back to where it is now.
func _apply_history(d: Dictionary) -> Dictionary:
	if d["type"] == "group":
		# Apply back to front; the reverse group undoes them back to front again.
		var inverses: Array[Dictionary] = []
		var entries: Array = d["entries"]
		for i in range(entries.size() - 1, -1, -1):
			var inv := _apply_history(entries[i])
			if not inv.is_empty():
				inverses.append(inv)
		return {"type": "group", "entries": inverses} if not inverses.is_empty() else {}
	if d["type"] == "delete":
		_restore_deleted(d)
		return {"type": "create", "id": d["id"]}
	var n: NoteScript = notes.get(d["id"])
	if n == null:
		return {}
	if d["type"] == "edit":
		var current := _edit_record(n)
		n.text = d["text"]
		n.color = d["color"]
		n.status = d["status"]
		n.refresh()
		_select(n)
		_mark_dirty()
		return current
	if d["type"] == "create":
		var record := _delete_record(n)
		_delete_note(n)
		return record
	if turn_tween and turn_tween.is_running() and turn_note == n:
		turn_tween.kill()
	var inverse := _move_record(n)
	_ease_note(n, d["pos"], d["rot"], UNDO_MOVE_TIME)
	_select(n)
	return inverse


## Eases cube `n` to a place and rotation, remembering it in `easing`.
func _ease_note(n: NoteScript, pos: Vector3, rot: Quaternion, time: float) -> void:
	var tween := n.create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(n, "global_position", pos, time)
	tween.tween_property(n, "quaternion", rot, time)
	tween.finished.connect(_mark_dirty)
	easing = easing.filter(func(e): return (e["tween"] as Tween).is_running())
	easing.append({"tween": tween, "note": n, "pos": pos, "rot": rot})


## Jumps any cube that's still easing to where it's headed, so the next undo /
## redo starts from (and records) the right place.
func _finish_easing() -> void:
	for e in easing:
		var tween: Tween = e["tween"]
		if tween.is_running() and is_instance_valid(e["note"]):
			tween.kill()
			e["note"].global_position = e["pos"]
			e["note"].quaternion = e["rot"]
			_mark_dirty()
	easing.clear()


# --- Notes & links ----------------------------------------------------------

func _create_note(pos: Vector3, text: String, color: Color, id: int = -1) -> NoteScript:
	if id < 0:
		id = next_id
	next_id = maxi(next_id, id + 1)
	var n: NoteScript = NoteScript.new()
	n.id = id
	n.text = text
	n.color = color
	notes_root.add_child(n)
	n.global_position = pos
	notes[id] = n
	_mark_dirty()
	return n


## Everything needed to bring a deleted note back, links included.
func _delete_record(n: NoteScript) -> Dictionary:
	return {
		"type": "delete",
		"id": n.id,
		"text": n.text,
		"color": n.color,
		"status": n.status,
		"rot": n.quaternion,
		"pos": n.global_position,
		"links": links.filter(func(l): return l[0] == n.id or l[1] == n.id),
	}


## With undoable, the note and its links are remembered for Ctrl+Z.
func _delete_note(n: NoteScript, undoable: bool = false) -> void:
	if undoable:
		var record := _delete_record(n)
		record["label"] = "block delete"
		_push_undo(record)
	links = links.filter(func(l): return l[0] != n.id and l[1] != n.id)
	notes.erase(n.id)
	if selected == n:
		selected = null
	if dragging == n:
		dragging = null
	if editing == n:
		editing = null
	n.queue_free()
	_mark_dirty()


## Brings a deleted note back, with its links to notes that still exist.
func _restore_deleted(d: Dictionary) -> void:
	var n := _create_note(d["pos"], d["text"], d["color"], d["id"])
	n.status = d["status"]
	n.quaternion = d["rot"]
	n.refresh()
	for l in d["links"]:
		if notes.has(l[0]) and notes.has(l[1]) and not links.has(l):
			links.append(l)
	_select(n)
	_mark_dirty()


func _select(n: NoteScript) -> void:
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
	selected = n
	if n:
		n.set_selected(true)


func _build_gizmo() -> void:
	gizmo = Node3D.new()
	gizmo.visible = false
	add_child(gizmo)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.04
	shaft.bottom_radius = 0.04
	shaft.height = GIZMO_SHAFT_END - GIZMO_START
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.12
	tip.height = GIZMO_TIP_END - GIZMO_SHAFT_END
	for k in GIZMO_AXES.size():
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true  # always drawn on top, like the editor's gizmos
		mat.render_priority = 4
		mat.albedo_color = GIZMO_COLORS[k]
		gizmo_mats.append(mat)
		for sgn: float in [1.0, -1.0]:
			# Cylinders point along +Y; turn each arrow onto its axis and side.
			var arrow := Node3D.new()
			if k == 0:
				arrow.rotation.z = -PI * 0.5 * sgn
			elif k == 1:
				arrow.rotation.x = 0.0 if sgn > 0.0 else PI
			else:
				arrow.rotation.x = PI * 0.5 * sgn
			for part in [[shaft, (GIZMO_START + GIZMO_SHAFT_END) * 0.5],
					[tip, (GIZMO_SHAFT_END + GIZMO_TIP_END) * 0.5]]:
				var mi := MeshInstance3D.new()
				mi.mesh = part[0]
				mi.material_override = mat
				mi.position.y = part[1]
				arrow.add_child(mi)
			gizmo.add_child(arrow)


## Shows the move arrows on the selected cube and highlights the one aimed at
## or being dragged.
func _update_gizmo() -> void:
	var shown := selected != null and is_instance_valid(selected) \
			and dragging == null and not editor_panel.visible and not paused
	gizmo.visible = shown
	if not shown:
		return
	gizmo.global_transform = Transform3D(selected.global_transform.basis.orthonormalized(),
		selected.global_position)
	var hot := gizmo_axis if gizmo_axis >= 0 else _pick_gizmo(_aim_pos())
	for k in gizmo_mats.size():
		gizmo_mats[k].albedo_color = GIZMO_COLORS[k].lightened(0.55) if k == hot else GIZMO_COLORS[k]


## World direction of arrow `k`: the selected cube's own axis.
func _gizmo_axis_dir(k: int) -> Vector3:
	return (selected.global_transform.basis * GIZMO_AXES[k]).normalized()


## Index of the arrow the aim ray passes closest to (within GIZMO_PICK), or -1.
func _pick_gizmo(screen_pos: Vector2) -> int:
	if selected == null or not is_instance_valid(selected) or editor_panel.visible:
		return -1
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var best := -1
	var best_dist := GIZMO_PICK
	for k in GIZMO_AXES.size():
		for sgn: float in [1.0, -1.0]:
			var axis := _gizmo_axis_dir(k) * sgn
			var a := selected.global_position + axis * GIZMO_START
			var b := selected.global_position + axis * GIZMO_TIP_END
			var pts := Geometry3D.get_closest_points_between_segments(a, b, from, to)
			var d := pts[0].distance_to(pts[1])
			if d < best_dist:
				best_dist = d
				best = k
	return best


## Moves the selected cube along the dragged arrow's axis by however far the
## mouse moved along that arrow's direction on screen.
func _drag_gizmo(relative: Vector2) -> void:
	if selected == null or not is_instance_valid(selected):
		gizmo_axis = -1
		return
	var axis := _gizmo_axis_dir(gizmo_axis)
	var p := selected.global_position
	var screen_axis := camera.unproject_position(p + axis) - camera.unproject_position(p)
	var pixels_per_unit := screen_axis.length()
	if pixels_per_unit < 4.0:
		return  # arrow points straight at the camera: no usable screen direction
	var amount := relative.dot(screen_axis / pixels_per_unit) / pixels_per_unit
	selected.global_position += axis * amount


## Shows the "+" buttons around the selected note (facing the camera like the
## notes do) and highlights the one under the crosshair.
func _update_plus_buttons() -> void:
	var shown := selected != null and is_instance_valid(selected) \
			and dragging == null and not editor_panel.visible and not paused
	var hovered := _pick_plus(_aim_pos()) if shown else -1
	var b := camera.global_transform.basis
	var blocked: Array = _blocked_faces(selected) if shown else []
	for i in plus_buttons.size():
		var mi := plus_buttons[i]
		mi.visible = shown and not blocked[i]
		if mi.visible:
			mi.global_transform = Transform3D(b, _plus_position(i))
			(mi.material_override as ShaderMaterial).set_shader_parameter(
				"hover", 1.0 if i == hovered else 0.0)


## World direction out of face `i` of cube `n`.
func _face_dir(n: NoteScript, i: int) -> Vector3:
	return n.global_transform.basis * (NoteScript.FACES[i][0] as Vector3)


## Each "+" floats just off the middle of one face of the selected cube.
func _plus_position(i: int) -> Vector3:
	return selected.global_position + _face_dir(selected, i) * (NoteScript.SIZE * 0.5 + PLUS_GAP)


## Index of the "+" button under a screen position, or -1. Buttons hidden
## behind the selected cube (on its far side) can't be clicked.
func _pick_plus(screen_pos: Vector2) -> int:
	if selected == null or not is_instance_valid(selected) or editor_panel.visible:
		return -1
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var forward := -camera.global_transform.basis.z
	var cube_dist := selected.ray_distance(from, dir)
	var best := -1
	var best_dist := INF
	var blocked := _blocked_faces(selected)
	for i in NoteScript.FACES.size():
		if blocked[i]:
			continue  # another cube already sits against this face
		var center := _plus_position(i)
		var hit = Plane(forward, center).intersects_ray(from, dir)
		if hit == null or (hit as Vector3).distance_to(center) > PLUS_RADIUS:
			continue
		var d := from.distance_to(hit)
		if d < best_dist and d < cube_dist:
			best_dist = d
			best = i
	return best


## Creates a note linked to `n`, directly next to the face of "+" button `i`,
## turned the same way, so the two cubes sit flush in a row.
func _add_note_beside(n: NoteScript, i: int) -> void:
	var pos := n.global_position + _face_dir(n, i) * PLUS_NEW_OFFSET
	var new_note := _create_note(pos, "", last_color)
	new_note.quaternion = n.quaternion  # same orientation as its neighbour
	_toggle_link(n, new_note)
	_push_create(new_note, "new block")
	_open_editor(new_note)


## Turns a new note upright, with a face toward the camera.
func _face_camera(n: NoteScript) -> void:
	n.rotation = Vector3(0.0, rig.yaw, 0.0)


## Records a newly created note as one undo step, and floats it free if it was
## placed inside or too close to another cube.
func _push_create(n: NoteScript, label: String) -> void:
	_push_undo({"type": "create", "id": n.id, "label": label})
	_settle(n)


## The nearest spot to `p` that's at least SPACING from every cube except `n`.
## Repeatedly steps straight out of whichever cubes are too close.
func _free_spot(n: NoteScript, p: Vector3) -> Vector3:
	for iteration in 30:
		var moved := false
		for v in notes.values():
			var m: NoteScript = v
			if m == n:
				continue
			var away := p - m.global_position
			var dist := away.length()
			if dist >= SPACING - 0.01:
				continue
			if dist < 0.01:
				away = camera.global_transform.basis.x  # exactly on top: slide sideways
			p = m.global_position + away.normalized() * SPACING
			moved = true
		if not moved:
			break
	return p


## If `n` is inside or too close to another cube, eases it to the nearest free spot.
func _settle(n: NoteScript) -> void:
	var target := _free_spot(n, n.global_position)
	if not target.is_equal_approx(n.global_position):
		_ease_note(n, target, n.quaternion, SETTLE_TIME)


func _toggle_link(a: NoteScript, b: NoteScript) -> void:
	var pair := [mini(a.id, b.id), maxi(a.id, b.id)]
	for i in links.size():
		if links[i][0] == pair[0] and links[i][1] == pair[1]:
			links.remove_at(i)
			_mark_dirty()
			return
	links.append(pair)
	_mark_dirty()


func _set_note_color(n: NoteScript, c: Color) -> void:
	n.color = c
	n.refresh()
	last_color = c
	_mark_dirty()


## First launch: a row of linked blocks, read left to right, low enough to clear the help panel.
## They sit exactly as far apart as snapping places cubes, so touching one doesn't make it jump.
func _create_welcome_notes() -> void:
	var x := -1.5 * PLUS_NEW_OFFSET
	var a := _create_note(Vector3(x, -2.4, 0),
		"Welcome to Mindblocks!\n\nEvery block is a note. Move the mouse to look around.", palette[0])
	var b := _create_note(Vector3(x + PLUS_NEW_OFFSET, -2.4, 0),
		"Double-click empty space to make a block.\n\nDouble-click a block to write on it.", palette[2])
	var c := _create_note(Vector3(x + 2 * PLUS_NEW_OFFSET, -2.4, 0),
		"Click a block to select it. Click a + to add a linked block, or drag an arrow to move it.", palette[3])
	var d := _create_note(Vector3(x + 3 * PLUS_NEW_OFFSET, -2.4, 0),
		"Esc frees the mouse.\n\nH shows all the controls.", palette[5])
	links = [[a.id, b.id], [b.id, c.id], [c.id, d.id]]


## Pause menu: swaps the Continue / New notespace buttons for the "are you sure?" step.
func _show_new_confirm(on: bool) -> void:
	pause_buttons.visible = not on
	new_confirm.visible = on


## Pause menu Exit: saves and quits.
func _exit() -> void:
	_save()
	get_tree().quit()


## Clears every block and link and starts over with the first-run blocks and
## the starting view. The old notespace is one undo step ("new notespace").
## Ids keep counting up, so undo can bring the old blocks back without clashes.
func _new_notespace() -> void:
	_end_drag()
	_commit_move()
	_finish_easing()
	if turn_tween and turn_tween.is_running():
		turn_tween.kill()
	_select(null)
	var entries: Array = []
	for n in notes.values():
		entries.append(_delete_record(n))
	for n in notes.values():
		_delete_note(n)
	links.clear()
	_create_welcome_notes()
	for n in notes.values():
		entries.append({"type": "create", "id": n.id})
	undo_stack.clear()
	_push_undo({"type": "group", "entries": entries, "label": "new notespace"})
	rig.reset()
	_save()
	_set_paused(false)


# --- Editor -----------------------------------------------------------------

func _open_editor(n: NoteScript) -> void:
	_end_drag()
	orbiting = false
	panning = false
	_select(n)
	editing = n
	edit_start = _edit_record(n)
	editor_text.text = n.text
	_sync_status_buttons()
	editor_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	editor_text.grab_focus()
	var last_line := editor_text.get_line_count() - 1
	editor_text.set_caret_line(last_line)
	editor_text.set_caret_column(editor_text.get_line(last_line).length())


func _close_editor() -> void:
	var n := editing
	editing = null
	if n and is_instance_valid(n):
		n.text = editor_text.text
		if n.text.strip_edges() == "":
			_delete_note(n)  # don't leave empty notes lying around
		else:
			n.refresh()
			_mark_dirty()
			_push_edit(n)
	edit_start = {}
	editor_text.release_focus()
	editor_panel.visible = false
	_capture_mouse()


## The cube's text, color and mark, as an undo "edit" entry.
func _edit_record(n: NoteScript) -> Dictionary:
	return {"type": "edit", "id": n.id, "text": n.text, "color": n.color, "status": n.status}


## After the editor closes: if the cube's text, color or mark changed, records
## how it was so Ctrl+Z can bring it back. A cube that was only just created
## is skipped: undoing its creation covers that.
func _push_edit(n: NoteScript) -> void:
	if edit_start.is_empty() or edit_start["id"] != n.id:
		return
	var top: Dictionary = undo_stack[-1] if not undo_stack.is_empty() else {}
	if top.get("type") == "create" and top.get("id") == n.id:
		return
	if n.text != edit_start["text"]:
		edit_start["label"] = "text edit"
	elif n.color != edit_start["color"]:
		edit_start["label"] = "color change"
	elif n.status != edit_start["status"]:
		edit_start["label"] = "mark change"
	else:
		return
	_push_undo(edit_start)


func _on_editor_text_changed() -> void:
	# Live preview on the card while typing.
	if editing and is_instance_valid(editing):
		editing.text = editor_text.text
		editing.refresh()


func _on_color_picked(c: Color) -> void:
	if editing and is_instance_valid(editing):
		_set_note_color(editing, c)


## Clicking the active status again clears it.
func _on_status_picked(s: String) -> void:
	if editing and is_instance_valid(editing):
		editing.status = "" if editing.status == s else s
		editing.refresh()
		_mark_dirty()
		_sync_status_buttons()


func _sync_status_buttons() -> void:
	var s := editing.status if editing else ""
	mark_done_btn.set_pressed_no_signal(s == "done")
	mark_failed_btn.set_pressed_no_signal(s == "failed")


func _on_editor_delete() -> void:
	var n := editing
	editing = null
	editor_text.release_focus()
	editor_panel.visible = false
	_capture_mouse()
	if n and is_instance_valid(n):
		_delete_note(n, true)


# --- Mouse capture & pause --------------------------------------------------

func _mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Drops and re-requests the grab, so a grab that silently failed gets another try.
func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_pause_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		pause_panel.accept_event()  # don't let the click also hit the 3D view
		_set_paused(false)


## Shows a short message top right. The newest goes at the bottom of the
## stack; older ones float up a row each time and fade, and every message
## fades out after TOAST_LIFE seconds.
func _toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	var style := _panel_style(Color(0, 0, 0, 0.6), 6)
	style.set_content_margin_all(8)
	l.add_theme_stylebox_override("normal", style)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.offset_left = -16.0
	l.offset_right = -16.0
	var base := TOAST_TOP + (TOAST_MAX - 1) * TOAST_ROW
	l.offset_top = base + 12.0
	l.modulate.a = 0.0
	toast_root.add_child(l)
	toasts.append(l)
	var life := l.create_tween()
	life.tween_property(l, "modulate:a", 1.0, 0.15)
	life.tween_interval(TOAST_LIFE)
	life.tween_property(l, "modulate:a", 0.0, 0.5)
	life.tween_callback(_drop_toast.bind(l))
	# Restack: row 0 (newest) at the base, each older one a row higher and fainter.
	for k in toasts.size():
		var t: Label = toasts[toasts.size() - 1 - k]
		var move := t.create_tween().set_parallel()
		move.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		move.tween_property(t, "offset_top", base - k * TOAST_ROW, 0.25)
		move.tween_property(t, "self_modulate:a", maxf(1.0 - k * 0.25, 0.0), 0.25)
		if k >= TOAST_MAX:
			move.chain().tween_callback(_drop_toast.bind(t))


func _drop_toast(l: Label) -> void:
	if is_instance_valid(l):
		toasts.erase(l)
		l.queue_free()


## Paused: cursor is free, the menu is up, and the 3D view ignores input.
func _set_paused(on: bool) -> void:
	paused = on
	pause_panel.visible = on
	_show_new_confirm(false)
	if on:
		_end_drag()
		orbiting = false
		panning = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_capture_mouse()


# --- Save / load ------------------------------------------------------------

func _mark_dirty() -> void:
	dirty = true
	dirty_timer = AUTOSAVE_DELAY


func _save() -> void:
	var note_list: Array = []
	for n in notes.values():
		note_list.append(n.to_dict())
	var data := {
		"version": 1,
		"next_id": next_id,
		"camera": rig.to_dict(),
		"notes": note_list,
		"links": links,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not save notes: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	dirty = false


## Copies the save from the old app name's folder, once, if there's none here yet.
func _migrate_old_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		return
	var old := OS.get_user_data_dir().get_base_dir().path_join(OLD_APP_NAME).path_join("notes.json")
	if not FileAccess.file_exists(old):
		return
	var err := DirAccess.copy_absolute(old, ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_warning("Could not copy notes from %s: %s" % [old, error_string(err)])


func _load() -> bool:
	_migrate_old_save()
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("notes.json is unreadable; starting fresh.")
		return false
	for d in data.get("notes", []):
		var p: Array = d.get("pos", [0, 0, 0])
		var n := _create_note(
			Vector3(float(p[0]), float(p[1]), float(p[2])),
			str(d.get("text", "")),
			Color(str(d.get("color", "ffe680"))),
			int(d.get("id", -1)))
		n.status = str(d.get("status", ""))
		var q: Array = d.get("rot", [])
		if q.size() == 4:
			n.quaternion = Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
		else:
			# Older saves had flat notes facing the camera: face the saved camera.
			var cam = data.get("camera")
			n.rotation.y = float(cam.get("yaw", 0.0)) if cam is Dictionary else 0.0
		n.refresh()
	for l in data.get("links", []):
		if l is Array and l.size() == 2:
			var a := int(l[0])
			var b := int(l[1])
			if notes.has(a) and notes.has(b):
				links.append([mini(a, b), maxi(a, b)])
	next_id = maxi(next_id, int(data.get("next_id", next_id)))
	if data.get("camera") is Dictionary:
		rig.from_dict(data["camera"])
	dirty = false
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and dirty:
		_save()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_panel \
			and not paused and not editor_panel.visible:
		_set_paused(true)  # alt-tabbed away: free the cursor
