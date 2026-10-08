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
const MIGRATED_PATH := "user://migrated_from_spatial_notes"
const AUTOSAVE_DELAY := 1.0
const BG_COLOR := Color(0.08, 0.09, 0.11)
## The sky: BG_COLOR with a sparse sprinkle of dim stars, scattered evenly in
## every direction. Two layers (small faint ones, fewer bigger ones); each grid cell
## of a layer holds at most one star, so they never clump.
## How many stars and how bright, for tweaking (1 and 0.35 are the defaults).
const SKY_STAR_AMOUNT := 1.0
const SKY_STAR_BRIGHTNESS := 0.35
const SKY_SHADER := """
shader_type sky;

uniform vec3 base_color : source_color;
uniform float star_amount = 1.0;  // scales how many cells hold a star
uniform float star_brightness = 0.35;

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

// density: cells across the sky; size: star radius in cells; chance: share of cells with a star.
float stars(vec3 dir, float density, float size, float chance) {
	vec3 cell = floor(dir * density);
	if (hash(cell + 7.13) > chance) {
		return 0.0;
	}
	vec3 star = cell + 0.25 + 0.5 * vec3(hash(cell), hash(cell + 1.7), hash(cell + 3.1));
	float d = length(normalize(star) - dir) * density;
	return (1.0 - smoothstep(size * 0.4, size, d)) * (0.35 + 0.65 * hash(cell + 5.3));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float s = (stars(dir, 110.0, 0.11, 0.07 * star_amount) * 0.6
			+ stars(dir, 45.0, 0.07, 0.06 * star_amount)) * star_brightness;
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.8), hash(floor(dir * 45.0) + 9.9));
	COLOR = base_color + tint * s;
}
"""
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
const STACK_TURN_TIME := 0.6  # an anchor's stack swings round more slowly, so its wobble stays gentle
const DOUBLE_TAP_TIME := 0.35  # seconds between two R presses that count as a double-tap
## Two quick clicks only make a double-click if they hit the same block, or both
## hit empty space with the aim turned less than this (radians) in between. With
## the mouse captured, the OS sees every click at the same spot, so it can't tell.
const DOUBLE_CLICK_ANGLE := 0.05
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
## The click played when two blocks get linked or a block snaps into place:
## a short, quickly fading tick made in code (no sound file needed).
const CLICK_HZ := 1700.0
const CLICK_LENGTH := 0.045
const CLICK_DECAY := 110.0  # per second
const CLICK_VOLUME_DB := -8.0
const UNDO_LIMIT := 50
## Undo / redo messages, top right: the newest sits at the bottom of the stack,
## older ones float up and fade; each disappears after TOAST_LIFE seconds.
const TOAST_TOP := 16.0
const TOAST_ROW := 40.0
const TOAST_MAX := 5
const TOAST_LIFE := 2.5
const UNDO_MOVE_TIME := 0.25
## All 2D UI (help, editor, menu, messages, crosshair) is laid out for a window
## this size and scaled with the window, so it takes up the same share of it at
## any size or pixel density. Godot draws the text at the scaled size, so it stays sharp.
const UI_DESIGN_SIZE := Vector2(1280, 760)
## In a narrow window the UI shrinks, but never below this much of the
## screen's own scale (2 on Retina), so text stays readable.
const UI_SCALE_MIN := 0.75
const UI_SCALE_MAX := 4.0
## AI, two ways. Break down a task (B) starts a new notespace: Claude splits a
## described task into groups of tasks and subtasks, laid out as blocks.
## Add with AI (Shift+B) sends Claude the current blocks and a request, and
## applies the changes it returns. The key comes from ANTHROPIC_API_KEY,
## or is typed into the panel once and kept in SETTINGS_PATH (never in notes.json).
const AI_URL := "https://api.anthropic.com/v1/messages"
const AI_MODEL := "claude-opus-5-5"
const SETTINGS_PATH := "user://settings.cfg"
const AI_TIMEOUT := 180.0
const AI_SYSTEM := """You break a big task down into blocks for a 3D note board.
Each block is a small cube with a few words on it, so keep every text short enough to fit on a cube face: at most 60 characters, a group title 1-4 words. No numbering or bullet characters.
Group related work together: 2-6 groups, each with a short title and 2-6 tasks, and each task with 0-4 concrete subtasks.
Order groups and tasks roughly in the order they'd be done. Write in the same language as the request."""
const AI_EDIT_SYSTEM := """You change a 3D note board where every note is a small cube with a few words on it.
You get the current blocks (id, text, status, color index, whether it's an anchor, and position as seen by the user: x to their right, y up, z toward them, so more negative z is farther away) and the links between them, then a request. Make only the changes the request asks for, but when someone seems stuck or asks to organise things, rearranging the board into meaningful clusters is welcome.
New blocks: give each a temp_id like "n1" and a parent: the id or temp_id of the most related block it belongs under (a task under its group's title block, a subtask under its task), or "" for a new top-level group. List parents before their children. Every new block is linked to its parent automatically, so don't also list those links.
Keep every text short enough to fit on a cube face: at most 60 characters, no numbering or bullet characters.
Colors are 0 yellow, 1 pink, 2 blue, 3 green, 4 orange, 5 purple, 6 white; use -1 for a new block to take its parent's color.
Moving things (the app works out exact positions and keeps blocks apart, so you only say where things go relative to each other):
- move: one block next to another block ("near" is that block's id), on the given side as the user sees it.
- move_stack: a whole stack (every block linked to the given block, directly or through others) moves together next to another block or stack ("near"), or with near "" to free space in front of the user. Use this to cluster related groups together or put unrelated ones apart.
- arrange: tidies a stack into a clean 3D mind map around its anchor (title) block, which stays where it is.
Only move what's needed, and never invent ids: use only ids from the board or your own temp_ids.
Use empty lists for kinds of change you don't need. summary: one short sentence on what you changed. Write in the same language as the request."""
## AI layouts grow like a 3D mind map, the way blocks look when arranged by
## hand: a group's tasks spread out around and below its title block, in all
## directions including depth, and each task's subtasks fan out the same way
## around it, continuing away from the title. Every new block goes FAN_DISTS
## from its parent, in the most open direction on a cone (FAN_TILTS from the
## outward direction), at least FAN_CLEAR from every other block; a bit of
## randomness keeps it from looking machine-made. Groups sit side by side,
## BD_GROUP_GAP apart.
const FAN_DISTS: Array[float] = [5.0, 6.5, 8.0]
const FAN_TILTS: Array[float] = [0.6, 1.0]  # radians from the outward direction
const FAN_STEPS := 12  # directions tried around the cone
const FAN_CLEAR := 3.4
const FAN_ROOM := 6.0  # more clearance than this doesn't make a spot any better
const FAN_JITTER := 0.5
const BD_GROUP_GAP := 5.0
const BD_MIN_DIST := 12.0
const BD_EASE_TIME := 0.6
## Add with AI: how far apart new top-level groups are kept from everything
## else, and how much changed blocks swell when they pulse.
const AI_CLUSTER_GAP := 10.0
## A moving anchor's stack follows on springs: stiffness (per link hop 1,
## loosened by FOLLOW_HOP_LOOSEN for each hop further), damping ratio (below
## 1 overshoots), tilt (radians per unit/s of speed, up to FOLLOW_MAX_TILT).
const FOLLOW_STIFFNESS := 120.0
const FOLLOW_DAMPING := 0.45
const FOLLOW_HOP_LOOSEN := 0.35
const FOLLOW_TILT := 0.02
const FOLLOW_MAX_TILT := 0.3
const FOLLOW_SUBSTEPS := 3
const AI_PULSE := 1.2
## Add with AI moves: sides Claude can name (as the user sees them), the gap
## kept around a moved stack, and how long blocks take to fly to their new place.
const AI_SIDES: Array[String] = ["left", "right", "above", "below", "front", "behind"]
const AI_STACK_GAP := 4.0
const AI_MOVE_TIME := 0.7
## Arrange around me: stacks go on one circle round the viewer at equal angles,
## the circle big enough for every stack to fit in view (ARRANGE_FILL of the
## field of view) but no smaller than ARRANGE_MIN_DIST, with neighbouring
## stacks at least ARRANGE_GAP apart. A stack this many times wider than
## it is deep is turned to show the viewer its full width.
const ARRANGE_MIN_DIST := 12.0
const ARRANGE_FILL := 0.7
const ARRANGE_GAP := 4.0
const ARRANGE_LONG := 1.3

## The first-run blocks: [title, [[block, [blocks under it]], ...]] per stack.
## "Ctrl" reads "Cmd" on macOS.
const WELCOME := [
	["Welcome to Mindblocks", [
		["Move the mouse to look around", []],
		["Fly with W A S D", ["Space or E: up, Q: down", "Hold Shift to fly much faster"]],
		["Esc: menu and a free mouse", ["The menu can start a new notespace"]],
		["H shows all the controls", []],
	]],
	["Blocks", [
		["Double-click empty space for a new block", ["Double-click a block to write on it"]],
		["Hold click on a block to carry it", ["Drag its colored arrows to slide it", "R + mouse or arrow keys turn it", "R R straightens it"]],
		["Click a block, then a + for a linked block", []],
		["1–7 colors it, Delete removes it", ["Mark it done or failed in the editor"]],
		["Ctrl+Z undo, Ctrl+Y redo", ["Ctrl+C / X / V: copy, cut, paste", "Alt + drag pulls out a copy"]],
	]],
	["Organise", [
		["Shift+click links two blocks", ["Linked blocks form a stack"]],
		["Drop a block near another to snap it", []],
		["Anchors have a thick dark frame", ["Moving an anchor moves its stack", "Turning it swings the stack round", "Toggle Anchor in the editor"]],
		["O arranges all stacks around you", []],
	]],
	["AI with Claude", [
		["B breaks a big task into blocks", ["It starts a new notespace"]],
		["Shift+B adds, changes or moves blocks", ["Try: organise this for me"]],
		["Needs an Anthropic API key", ["Paste it once when asked"]],
		["Ctrl+Z undoes any AI change", []],
	]],
]

const HELP_TEXT := """Mouse — look around · clicks act at the crosshair
Esc — pause and free the cursor · the pause menu has New notespace, Break down a task, Add with AI and Exit
Double-click empty space — new note · click a cube, then + on a face — new linked cube there
Double-click a note / Enter — edit it
Hold click on a note — carry it (scroll while carrying: nearer / farther)
Drag a colored arrow — move selected cube along that axis
Moving near another cube shows a ghost: let go to snap there (Shift = don't)
R + mouse — rotate selected cube · arrow keys — turn it 90° · R R — straighten it
Anchors only turn left / right, and their whole stack turns with them
Shift+click another note — link / unlink with selected
Anchor blocks (thick dark frame) carry every block linked to them when moved · toggle in the editor
1–7 — recolor selected · F — focus selected · Delete — delete
Alt + drag a cube — drag out a copy · Ctrl+C / Ctrl+X / Ctrl+V — copy / cut / paste where you look
Ctrl+Z — undo (blocks, moves, text edits…) · Ctrl+Y or Ctrl+Shift+Z — redo
Right-drag — orbit · Middle-drag or Shift+right-drag — pan
W A S D / Q E — fly (Shift = much faster) · scroll while orbiting — zoom
Space — fly up
G — floor guides on / off · O — arrange all stacks around you (also in the Esc menu)
B — break down a task with Claude into a new notespace · Shift+B — add, change or rearrange blocks with Claude
H — show / hide this help · saves automatically"""

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
## {type: "edit", id, text, color, status, anchor} (what a cube said / looked like) or
## {type: "links", links} (the whole link list, as it was).
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
## The previous left click: {id (block hit, or -1), dir (aim ray)}, or {} after
## a click that can't start a double-click.
var last_click: Dictionary = {}
## While an anchor is moved: {anchor, offsets: {block: offset from the anchor},
## tween (the anchor's ease after it's let go, if any)}. Every block linked to
## the anchor, directly or through others, keeps its offset.
var follow: Dictionary = {}
var click_player: AudioStreamPlayer
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
var anchor_btn: Button
var pause_panel: Control
var pause_buttons: Control  # Continue / New notespace
var new_confirm: Control  # "Start a new notespace?" with its two buttons
var crosshair: Control
var paused := false
## Whether the mouse was captured last frame. In a browser, Esc releases the
## pointer lock without the app seeing the key, so losing it opens the menu.
var was_captured := false
var ai_panel: PanelContainer
var ai_prompt: TextEdit
var ai_key_edit: LineEdit
var ai_status: Label
var ai_generate_btn: Button
var ai_title: Label
var ai_about: Label
var ai_buttons: Control  # Cancel / Generate
var ai_confirm: Control  # "This erases all current blocks" with its two buttons
## "breakdown" (new notespace) or "edit" (Add with AI); each keeps its own draft.
var ai_mode := "breakdown"
var ai_drafts: Dictionary = {}
var ai_http: HTTPRequest
var ai_busy := false


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
	_build_click()
	ai_http = HTTPRequest.new()
	ai_http.timeout = AI_TIMEOUT
	ai_http.request_completed.connect(_on_ai_response)
	add_child(ai_http)
	get_window().size_changed.connect(_update_ui_scale)
	_update_ui_scale()
	if not _load():
		_create_welcome_notes()
		_save()
	# Start paused: grabbing the mouse before the window has focus silently fails
	# on X11 / XWayland, so the first grab happens when Continue is clicked.
	_set_paused(true)
	# Open big: maximized, but still a normal window (title bar, taskbar).
	# Skipped when the game runs embedded in the editor's Game tab.
	if not Engine.is_embedded_in_editor():
		if not OS.has_feature("web"):  # in a browser the page decides the size
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _setup_environment() -> void:
	var env := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = Shader.new()
	sky_mat.shader.code = SKY_SHADER
	sky_mat.set_shader_parameter("base_color", BG_COLOR)
	sky_mat.set_shader_parameter("star_amount", SKY_STAR_AMOUNT)
	sky_mat.set_shader_parameter("star_brightness", SKY_STAR_BRIGHTNESS)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32  # the sky lights nothing, so keep its lighting cheap
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
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

	# Help overlay (top-left), hidden until H is pressed
	help_panel = PanelContainer.new()
	help_panel.position = Vector2(16, 16)
	help_panel.visible = false
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.55), 8))
	var help_label := Label.new()
	help_label.text = _shortcut_text(HELP_TEXT)
	help_label.add_theme_font_size_override("font_size", 14)
	help_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92))
	help_panel.add_child(help_label)
	layer.add_child(help_panel)

	# Always-on hint (bottom-left), styled like the undo messages
	var hint := Label.new()
	hint.text = "H to toggle help"
	hint.add_theme_font_size_override("font_size", 15)
	var hint_style := _panel_style(Color(0, 0, 0, 0.6), 6)
	hint_style.set_content_margin_all(8)
	hint.add_theme_stylebox_override("normal", hint_style)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = 16.0
	hint.offset_top = -16.0
	hint.offset_bottom = -16.0
	layer.add_child(hint)

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
	title.text = _shortcut_text("Edit note   (Ctrl+Enter or Esc to close)")
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
	anchor_btn = Button.new()
	anchor_btn.text = "Anchor"
	anchor_btn.toggle_mode = true
	anchor_btn.tooltip_text = "Moving an anchor moves every block linked to it"
	anchor_btn.pressed.connect(_on_anchor_toggled)
	row.add_child(anchor_btn)
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
	pause_panel.theme = _emoji_theme()
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
	continue_btn.text = "▶️  Continue"
	continue_btn.custom_minimum_size = Vector2(200, 40)
	continue_btn.pressed.connect(_set_paused.bind(false))
	var new_btn := Button.new()
	new_btn.text = "🆕  New notespace"
	new_btn.custom_minimum_size = Vector2(200, 40)
	new_btn.pressed.connect(_show_new_confirm.bind(true))
	var ai_btn := Button.new()
	ai_btn.text = "🧩  Break down a task"
	ai_btn.custom_minimum_size = Vector2(200, 40)
	ai_btn.pressed.connect(_open_ai_panel.bind("breakdown"))
	var ai_edit_btn := Button.new()
	ai_edit_btn.text = "✨  Add with AI"
	ai_edit_btn.custom_minimum_size = Vector2(200, 40)
	ai_edit_btn.pressed.connect(_open_ai_panel.bind("edit"))
	var arrange_btn := Button.new()
	arrange_btn.text = "🧭  Arrange notes around me"
	arrange_btn.custom_minimum_size = Vector2(200, 40)
	arrange_btn.pressed.connect(_arrange_around_me)
	var exit_btn := Button.new()
	exit_btn.text = "🚪  Exit"
	exit_btn.custom_minimum_size = Vector2(200, 40)
	exit_btn.pressed.connect(_exit)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	# Labels start with an emoji: left-aligned, so the emoji line up in a column.
	for b: Button in [continue_btn, new_btn, ai_btn, ai_edit_btn, arrange_btn, exit_btn]:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# In a browser: no system emoji font (they'd show as boxes), and quitting does nothing.
	if OS.has_feature("web"):
		for b: Button in [continue_btn, new_btn, ai_btn, ai_edit_btn, arrange_btn]:
			b.text = b.text.get_slice("  ", 1)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		exit_btn.visible = false
	buttons.add_child(continue_btn)
	buttons.add_child(new_btn)
	buttons.add_child(ai_btn)
	buttons.add_child(ai_edit_btn)
	buttons.add_child(arrange_btn)
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
	yes_btn.text = "🗑️  Delete and start new"
	yes_btn.custom_minimum_size = Vector2(0, 40)
	yes_btn.pressed.connect(_new_notespace)
	confirm_row.add_child(yes_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "↩️  Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(_show_new_confirm.bind(false))
	confirm_row.add_child(cancel_btn)
	if OS.has_feature("web"):
		yes_btn.text = yes_btn.text.get_slice("  ", 1)
		cancel_btn.text = cancel_btn.text.get_slice("  ", 1)
	confirm.add_child(confirm_row)
	new_confirm = confirm
	menu_box.add_child(confirm)

	_build_ai_panel(layer)


## AI panel (center), for both Break down a task and Add with AI: the request,
## the API key if there's none yet, a status line, and Generate. Breaking down
## over existing blocks asks first, in place of the buttons.
func _build_ai_panel(layer: CanvasLayer) -> void:
	ai_panel = PanelContainer.new()
	ai_panel.anchor_left = 0.5
	ai_panel.anchor_right = 0.5
	ai_panel.anchor_top = 0.5
	ai_panel.anchor_bottom = 0.5
	ai_panel.offset_left = -320
	ai_panel.offset_right = 320
	ai_panel.offset_top = -170
	ai_panel.offset_bottom = 170
	ai_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	ai_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.13, 0.16, 0.96), 10))
	ai_panel.visible = false
	layer.add_child(ai_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	ai_panel.add_child(vbox)

	ai_title = Label.new()
	vbox.add_child(ai_title)

	ai_about = Label.new()
	ai_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_about.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	vbox.add_child(ai_about)

	ai_prompt = TextEdit.new()
	ai_prompt.custom_minimum_size = Vector2(0, 130)
	ai_prompt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ai_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(ai_prompt)

	ai_key_edit = LineEdit.new()
	ai_key_edit.secret = true
	ai_key_edit.placeholder_text = ("Anthropic API key (sk-ant-…). Your key stays in this browser."
		if OS.has_feature("web") else "Anthropic API key (sk-ant-…), kept on this computer")
	vbox.add_child(ai_key_edit)

	ai_status = Label.new()
	ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.6))
	vbox.add_child(ai_status)

	var row := HBoxContainer.new()
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_close_ai_panel)
	row.add_child(cancel_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	ai_generate_btn = Button.new()
	ai_generate_btn.pressed.connect(_ai_generate)
	row.add_child(ai_generate_btn)
	ai_buttons = row
	vbox.add_child(row)

	var confirm := VBoxContainer.new()
	confirm.add_theme_constant_override("separation", 10)
	confirm.visible = false
	var question := Label.new()
	question.text = _shortcut_text("This erases all current blocks (Ctrl+Z brings them back). Continue?")
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm.add_child(question)
	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 10)
	var erase_btn := Button.new()
	erase_btn.text = "Erase and generate"
	erase_btn.pressed.connect(_ai_generate.bind(true))
	confirm_row.add_child(erase_btn)
	var keep_btn := Button.new()
	keep_btn.text = "Cancel"
	keep_btn.pressed.connect(_show_ai_confirm.bind(false))
	confirm_row.add_child(keep_btn)
	confirm.add_child(confirm_row)
	ai_confirm = confirm
	vbox.add_child(confirm)


## A theme whose font falls back to the system's color emoji font (Godot's
## built-in font has no emoji), for the pause menu's button icons.
func _emoji_theme() -> Theme:
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji"])
	var font: Font = ThemeDB.fallback_font.duplicate()
	font.fallbacks = [emoji]
	var theme := Theme.new()
	theme.default_font = font
	return theme


## Window size is in real pixels (so a Retina screen counts double), which makes
## this cover pixel density as well as window size.
func _update_ui_scale() -> void:
	var w := get_window()
	var s := Vector2(w.size) / UI_DESIGN_SIZE
	var lowest := UI_SCALE_MIN * DisplayServer.screen_get_scale(w.current_screen)
	w.content_scale_factor = clampf(minf(s.x, s.y), lowest, UI_SCALE_MAX)


## Shortcuts use Cmd instead of Ctrl on macOS (is_command_or_control_pressed()),
## so texts that name them say so there.
func _shortcut_text(t: String) -> String:
	return t.replace("Ctrl", "Cmd") if OS.has_feature("macos") else t


func _panel_style(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(12)
	return s


# --- Per frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if OS.has_feature("web"):
		var captured := _mouse_captured()
		if was_captured and not captured and not paused and not _panel_open():
			_set_paused(true)
		was_captured = captured
	_keep_camera_outside_notes()
	_update_depth_fx(delta)

	if dragging:
		var held := camera.global_position + camera.global_transform.basis * drag_local
		if not held.is_equal_approx(dragging.global_position):
			dragging.global_position = held
			drag_moved = true
	_update_follow()

	rig.input_blocked = _panel_open() or paused
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
	if ai_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var ak := event as InputEventKey
			if ak.keycode == KEY_ESCAPE:
				_close_ai_panel()
				get_viewport().set_input_as_handled()
			elif (ak.keycode == KEY_ENTER or ak.keycode == KEY_KP_ENTER) and ak.is_command_or_control_pressed():
				_ai_generate()
				get_viewport().set_input_as_handled()
		return
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
		if k.keycode == KEY_ESCAPE or (is_enter and k.is_command_or_control_pressed()):
			_close_editor()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if not editor_panel.get_global_rect().has_point(mb.position):
			_close_editor()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _panel_open() or paused:
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
					_start_follow(selected)
				gizmo_axis = axis
				last_click = {}
				return
			var plus := _pick_plus(aim)
			if plus >= 0:
				_add_note_beside(selected, plus)
				last_click = {}
				return
			var hit := _pick(aim)
			var dir := camera.project_ray_normal(aim)
			var same_target: bool = not last_click.is_empty() and last_click["id"] == (hit.id if hit else -1) \
					and (hit != null or dir.angle_to(last_click["dir"]) < DOUBLE_CLICK_ANGLE)
			last_click = {"id": hit.id if hit else -1, "dir": dir}
			if e.double_click and same_target:
				last_click = {}  # a third quick click starts over
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
				_click(1.0 if _linked(selected, hit) else 0.75)  # unlinking clicks lower
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
				elif orbiting:
					rig.zoom(0.9)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				if dragging:
					_push_drag(0.6)
				elif orbiting:
					rig.zoom(1.1)


## A dragged note is carried along by _process(), so it follows any of these.
## Turning and panning use screen_relative (real pixels), so their speed doesn't
## change with the UI scale; the gizmo works in UI coordinates like its arrows.
func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if gizmo_axis >= 0:
		_drag_gizmo(e.relative)
	elif orbiting:
		rig.orbit(e.screen_relative)
	elif panning:
		rig.pan(e.screen_relative)
	elif Input.is_key_pressed(KEY_R) and (dragging or selected):
		_rotate_note(dragging if dragging else selected, e.screen_relative)
	elif _mouse_captured():
		rig.look(e.screen_relative)


## Trackball-style: moving the mouse turns the cube around the camera's up
## and right axes, so it follows the mouse the way it looks on screen.
func _rotate_note(n: NoteScript, relative: Vector2) -> void:
	if move_start.is_empty():
		move_start = _move_record(n)
		if n.anchor and follow.is_empty():
			move_start["followers"] = _stack_records(n)
	if n.anchor:
		# Anchors only turn left / right, taking their stack with them on springs.
		if follow.is_empty() or follow["anchor"] != n:
			_start_follow(n, false)
		_turn_stack_by(n, Quaternion(Vector3.UP, relative.x * ROTATE_SPEED))
		_mark_dirty()
		return
	var b := camera.global_transform.basis
	var q := Quaternion(b.y, relative.x * ROTATE_SPEED) * Quaternion(b.x, relative.y * ROTATE_SPEED)
	n.quaternion = (q * n.quaternion).normalized()
	_mark_dirty()


## A quarter turn of the selected cube around a camera axis, eased. An anchor
## only turns left / right (around the world's up), and its stack turns with it.
func _turn_selected(axis: Vector3, angle: float) -> void:
	if selected == null:
		return
	if selected.anchor:
		if absf(axis.dot(camera.global_transform.basis.y)) > 0.5:  # left / right keys
			_ease_stack_turn(selected, Quaternion(Vector3.UP, angle), "stack rotation")
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
	if selected.anchor:
		# Turn the stack back by the anchor's heading; the anchor ends fully straight.
		var z := selected.global_transform.basis.z
		var heading := atan2(z.x, z.z)
		_ease_stack_turn(selected, Quaternion(Vector3.UP, -heading), "stack rotation", true)
		return
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
		KEY_B:
			_open_ai_panel("edit" if e.shift_pressed else "breakdown")
		KEY_O:
			_arrange_around_me()
		KEY_H, KEY_F1:
			help_panel.visible = not help_panel.visible
		KEY_S:
			if e.is_command_or_control_pressed():
				_save()
		KEY_C:
			if e.is_command_or_control_pressed() and selected:
				_copy_selected()
		KEY_X:
			if e.is_command_or_control_pressed() and selected:
				_cut_selected()
		KEY_V:
			if e.is_command_or_control_pressed():
				_paste()
		KEY_Z:
			if e.is_command_or_control_pressed() and e.shift_pressed:
				_redo()
			elif e.is_command_or_control_pressed():
				_undo()
		KEY_Y:
			if e.is_command_or_control_pressed():
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
	_start_follow(n)
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
	var snap := moved and not snap_target.is_empty() and not Input.is_key_pressed(KEY_SHIFT)
	if moved and not follow.is_empty() and follow["anchor"] == moved:
		# A whole stack: snap by the anchor, then shift everything clear of outside blocks.
		var target: Vector3 = snap_target["pos"] if snap else moved.global_position
		target += _stack_clearance(target)
		if not target.is_equal_approx(moved.global_position) or snap:
			follow["tween"] = _ease_note(moved, target,
				snap_target["rot"] if snap else moved.quaternion, SNAP_TIME if snap else SETTLE_TIME)
			if snap:
				(follow["tween"] as Tween).finished.connect(_click)
		# The stack keeps following until it has wobbled to rest (see _update_follow).
	elif snap:
		_ease_note(moved, snap_target["pos"], snap_target["rot"], SNAP_TIME).finished.connect(_click)
	elif moved:
		_settle(moved)  # dropped inside / too close to another cube: float free
	snap_target = {}
	snap_ghost.visible = false
	if not Input.is_key_pressed(KEY_R):
		_commit_move()


# --- Click sound ------------------------------------------------------------

## Synthesizes the click: a sine tick with a fast fade, as 16-bit mono PCM.
func _build_click() -> void:
	var rate := 44100
	var count := int(rate * CLICK_LENGTH)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / rate
		var v := sin(TAU * CLICK_HZ * t) * exp(-t * CLICK_DECAY)
		v *= minf(1.0, t * 2000.0)  # half a millisecond fade-in, so it doesn't pop
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	click_player = AudioStreamPlayer.new()
	click_player.stream = wav
	click_player.volume_db = CLICK_VOLUME_DB
	click_player.max_polyphony = 4  # quick clicks in a row don't cut each other off
	add_child(click_player)


## Plays the click, at `pitch` (1 = normal) with a slight random variation.
func _click(pitch: float = 1.0) -> void:
	click_player.pitch_scale = pitch * randf_range(0.95, 1.05)
	click_player.play()


# --- Anchors ----------------------------------------------------------------

## Every block linked to `n`, directly or through other blocks (not `n`
## itself), with how many links away from `n` it is.
func _stack_of(n: NoteScript) -> Dictionary:
	var neighbors := {}  # id -> linked ids
	for l in links:
		neighbors.get_or_add(l[0], []).append(l[1])
		neighbors.get_or_add(l[1], []).append(l[0])
	var hops := {n.id: 0}
	var queue: Array = [n.id]
	var stack := {}
	while not queue.is_empty():
		var id = queue.pop_front()
		for other in neighbors.get(id, []):
			if not hops.has(other) and notes.has(other):
				hops[other] = hops[id] + 1
				queue.append(other)
				stack[notes[other]] = hops[other]
	return stack


## If `n` is an anchor, the blocks linked to it start following it, and (with
## `record`) their places go into move_start so the move undoes as one step.
func _start_follow(n: NoteScript, record: bool = true) -> void:
	if not follow.is_empty():
		_finish_easing()  # a stack still easing from its last move lands first
	follow = {}
	if n == null or not n.anchor:
		return
	var stack := _stack_of(n)
	if stack.is_empty():
		return
	var offsets := {}
	var records: Array = []
	var springs := {}
	for m in stack:
		offsets[m] = m.global_position - n.global_position
		records.append(_move_record(m))
		springs[m] = {"vel": Vector3.ZERO, "rot": m.quaternion, "hops": stack[m]}
	follow = {"anchor": n, "offsets": offsets, "springs": springs}
	if record:
		move_start["followers"] = records


## Moves the stack after its anchor. Each block is pulled toward its place
## (its offset from the anchor) by a damped spring, so it lags, overshoots and
## wobbles a little, tilting with its speed; blocks more links away are looser.
## Once the anchor has been let go and has landed, and every block has come
## to rest, they're put exactly in place and the stack stops following.
## With `force`, everything lands at once (before undo / redo, or a new move).
func _update_follow(force: bool = false) -> void:
	if follow.is_empty():
		return
	var a: NoteScript = follow["anchor"]
	if not is_instance_valid(a) or not notes.has(a.id):
		follow = {}
		return
	var held := a == dragging or (gizmo_axis >= 0 and a == selected) \
			or (a == selected and Input.is_key_pressed(KEY_R))  # turning it with R + mouse
	var tween: Tween = follow.get("tween")
	var anchor_done := not held and (tween == null or not tween.is_running())
	var dt := minf(get_process_delta_time(), 0.05) / FOLLOW_SUBSTEPS
	var resting := true
	for m in follow["offsets"]:
		if not (is_instance_valid(m) and notes.has(m.id)):
			continue
		var target: Vector3 = a.global_position + follow["offsets"][m]
		var spring: Dictionary = follow["springs"][m]
		if force:
			m.global_position = target
			m.quaternion = spring["rot"]
			continue
		var k: float = FOLLOW_STIFFNESS / (1.0 + FOLLOW_HOP_LOOSEN * (spring["hops"] - 1))
		var c := 2.0 * FOLLOW_DAMPING * sqrt(k)
		var x: Vector3 = m.global_position
		var v: Vector3 = spring["vel"]
		for step in FOLLOW_SUBSTEPS:
			v += (k * (target - x) - c * v) * dt
			x += v * dt
		spring["vel"] = v
		m.global_position = x
		var tilt := minf(v.length() * FOLLOW_TILT, FOLLOW_MAX_TILT)
		var axis := Vector3.UP.cross(v)
		m.quaternion = (Quaternion(axis.normalized(), tilt) * spring["rot"]).normalized() \
				if axis.length() > 0.001 else spring["rot"]
		if x.distance_to(target) > 0.01 or v.length() > 0.05:
			resting = false
	_mark_dirty()
	if force or (anchor_done and resting):
		for m in follow["offsets"]:
			if is_instance_valid(m) and notes.has(m.id):
				m.global_position = a.global_position + follow["offsets"][m]
				m.quaternion = follow["springs"][m]["rot"]
		follow = {}


## Move records for every block in `n`'s stack (for an undo step).
func _stack_records(n: NoteScript) -> Array:
	var records: Array = []
	for m in _stack_of(n):
		records.append(_move_record(m))
	return records


## Turns anchor `n` by `q` (a turn around the world's up) and its stack with
## it, around the anchor's center: every block swings round and turns by the
## same amount, so the stack keeps its shape. While the stack is following
## the anchor on springs, their target places turn instead.
func _turn_stack_by(n: NoteScript, q: Quaternion, members: Array = []) -> void:
	var pivot := n.global_position
	n.quaternion = (q * n.quaternion).normalized()
	if not follow.is_empty() and follow["anchor"] == n:
		for m in follow["offsets"]:
			follow["offsets"][m] = q * follow["offsets"][m]
			follow["springs"][m]["rot"] = (q * follow["springs"][m]["rot"]).normalized()
		return
	if members.is_empty():
		members = _stack_of(n).keys()
	for m in members:
		if is_instance_valid(m) and notes.has(m.id):
			m.global_position = pivot + q * (m.global_position - pivot)
			m.quaternion = (q * m.quaternion).normalized()


## Eases anchor `n`'s stack through the turn `q` (one undo step, `label`).
## With `straighten`, the anchor itself ends at no rotation at all.
func _ease_stack_turn(n: NoteScript, q: Quaternion, label: String, straighten: bool = false) -> void:
	if turn_tween and turn_tween.is_running():
		turn_tween.custom_step(STACK_TURN_TIME)  # land a turn still running first
	var members: Array = _stack_of(n).keys()
	var entries: Array = [_move_record(n)]
	for m in members:
		entries.append(_move_record(m))
	_push_undo({"type": "group", "entries": entries, "label": label})
	var done := [Quaternion.IDENTITY]  # how much of the turn is applied so far
	var start_rot := n.quaternion
	turn_note = n
	_start_follow(n, false)  # the stack swings after the anchor on springs
	turn_tween = n.create_tween()
	turn_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	turn_tween.tween_method(func(t: float):
		if not is_instance_valid(n) or not notes.has(n.id):
			return
		var now := Quaternion.IDENTITY.slerp(q, t)
		_turn_stack_by(n, (now * done[0].inverse()).normalized(), members)
		done[0] = now
		if straighten:
			n.quaternion = start_rot.slerp(Quaternion.IDENTITY, t), 0.0, 1.0, STACK_TURN_TIME)
	if not follow.is_empty():
		follow["tween"] = turn_tween  # keep following until the turn is done
	turn_tween.finished.connect(func():
		if is_instance_valid(n) and notes.has(n.id):
			_settle_turned_stack(n)
		_mark_dirty())


## After a stack has turned: shifts it clear of outside blocks. If it's still
## swinging on springs, the anchor eases clear and the stack follows.
func _settle_turned_stack(n: NoteScript) -> void:
	if follow.is_empty() or follow["anchor"] != n:
		_unoverlap_stack(n)
		return
	var shift := _stack_clearance(n.global_position)
	if shift.length() > 0.001:
		follow["tween"] = _ease_note(n, n.global_position + shift, n.quaternion, SETTLE_TIME)


## If any block of `n`'s stack ended up too close to a block outside it,
## eases the whole stack clear.
func _unoverlap_stack(n: NoteScript) -> void:
	var members: Array[NoteScript] = [n]
	members.append_array(_stack_of(n).keys())
	var inside := {}
	for m in members:
		inside[m] = true
	var shift := Vector3.ZERO
	for iteration in 30:
		var moved := false
		for m in members:
			var p := m.global_position + shift
			for v in notes.values():
				if inside.has(v):
					continue
				var away := p - (v as NoteScript).global_position
				var dist := away.length()
				if dist >= SPACING - 0.01:
					continue
				if dist < 0.01:
					away = camera.global_transform.basis.x
				shift += away.normalized() * (SPACING - dist)
				moved = true
		if not moved:
			break
	if shift.length() > 0.001:
		for m in members:
			_ease_note(m, m.global_position + shift, m.quaternion, SETTLE_TIME)


func _following(n: NoteScript) -> bool:
	return not follow.is_empty() and follow["offsets"].has(n)


## How far to shift the stack (anchor at `anchor_pos`, the rest at their
## offsets) so none of its blocks end up too close to a block outside it.
func _stack_clearance(anchor_pos: Vector3) -> Vector3:
	var a: NoteScript = follow["anchor"]
	var members: Array[Vector3] = [Vector3.ZERO]
	for m in follow["offsets"]:
		members.append(follow["offsets"][m])
	var outside: Array[Vector3] = []
	for v in notes.values():
		if v != a and not follow["offsets"].has(v):
			outside.append((v as NoteScript).global_position)
	var shift := Vector3.ZERO
	for iteration in 30:
		var moved := false
		for off in members:
			var p: Vector3 = anchor_pos + shift + off
			for o in outside:
				var away := p - o
				var dist := away.length()
				if dist >= SPACING - 0.01:
					continue
				if dist < 0.01:
					away = camera.global_transform.basis.x
				shift += away.normalized() * (SPACING - dist)
				moved = true
		if not moved:
			break
	return shift


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
		if n == m or _following(n) or n.global_position.distance_to(p) > PLUS_NEW_OFFSET + SNAP_DIST:
			continue
		var slot := n.global_position + _face_dir(n, _face_toward(n, p)) * PLUS_NEW_OFFSET
		var d := p.distance_to(slot)
		if d >= best_dist:
			continue
		var free := true
		for w in notes.values():
			if w != m and w != n and not _following(w) \
					and (w as NoteScript).global_position.distance_to(slot) < SPACING - 0.01:
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
	var followers: Array = move_start.get("followers", [])
	move_start.erase("followers")
	if n and not followers.is_empty() and not n.global_position.is_equal_approx(move_start["pos"]):
		# An anchor carried its stack: one step puts every block back.
		_push_undo({"type": "group", "entries": [move_start] + followers, "label": "stack move"})
	elif n and not followers.is_empty() and not n.quaternion.is_equal_approx(move_start["rot"]):
		# An anchor turned its stack (R + mouse).
		_push_undo({"type": "group", "entries": [move_start] + followers, "label": "stack rotation"})
		_settle_turned_stack(n)
	elif n and not n.global_position.is_equal_approx(move_start["pos"]):
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
## - "links" puts the link list back (between cubes that exist); reversed by
##   "links" with the list as it is now.
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
	if d["type"] == "links":
		var current := {"type": "links", "links": links.duplicate(true)}
		links = d["links"].filter(func(l): return notes.has(l[0]) and notes.has(l[1]))
		_mark_dirty()
		return current
	var n: NoteScript = notes.get(d["id"])
	if n == null:
		return {}
	if d["type"] == "edit":
		var current := _edit_record(n)
		n.text = d["text"]
		n.color = d["color"]
		n.status = d["status"]
		n.anchor = d.get("anchor", false)
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
## TRANS_BACK overshoots a little before settling.
func _ease_note(n: NoteScript, pos: Vector3, rot: Quaternion, time: float,
		trans: Tween.TransitionType = Tween.TRANS_CUBIC) -> Tween:
	var tween := n.create_tween().set_parallel()
	tween.set_trans(trans).set_ease(Tween.EASE_OUT)
	tween.tween_property(n, "global_position", pos, time)
	tween.tween_property(n, "quaternion", rot, time)
	tween.finished.connect(_mark_dirty)
	easing = easing.filter(func(e): return (e["tween"] as Tween).is_running())
	easing.append({"tween": tween, "note": n, "pos": pos, "rot": rot})
	return tween


## Jumps any cube that's still easing to where it's headed, so the next undo /
## redo starts from (and records) the right place.
func _finish_easing() -> void:
	if turn_tween and turn_tween.is_running():
		turn_tween.custom_step(STACK_TURN_TIME)  # an eased turn (of a block or a stack) lands first
	for e in easing:
		var tween: Tween = e["tween"]
		if tween.is_running() and is_instance_valid(e["note"]):
			tween.kill()
			e["note"].global_position = e["pos"]
			e["note"].quaternion = e["rot"]
			_mark_dirty()
	easing.clear()
	_update_follow(true)  # a stack still moving lands too


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
		"anchor": n.anchor,
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
	n.anchor = d.get("anchor", false)
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
			and dragging == null and not _panel_open() and not paused
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
			and dragging == null and not _panel_open() and not paused
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
	_click()
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


## First launch (and New notespace): an overview of the app as four stacks,
## each an anchor title with its blocks fanned out below it (the same layout
## as an AI breakdown, so it looks the same every time), arranged round the
## starting view like Arrange notes around me, the first straight ahead.
func _create_welcome_notes() -> void:
	rig.reset()
	var groups: Array = []
	for g in WELCOME:
		var tasks: Array = []
		for t in g[1]:
			var subs: Array = []
			for sub in t[1]:
				subs.append(_shortcut_text(sub))
			tasks.append({"text": _shortcut_text(t[0]), "subtasks": subs})
		groups.append({"title": g[0], "tasks": tasks})
	_build_breakdown(groups, false)
	_finish_easing()
	var targets: Dictionary = _arrange_targets()["targets"]
	for n in targets:
		n.global_position = targets[n][0]
		n.quaternion = targets[n][1]
	_select(null)


## Pause menu: swaps the Continue / New notespace buttons for the "are you sure?" step.
func _show_new_confirm(on: bool) -> void:
	pause_buttons.visible = not on
	new_confirm.visible = on


## Every group of blocks connected by links (a lone block is a group of its own).
func _components() -> Array:
	var groups: Array = []
	var seen := {}
	var ids: Array = notes.keys()
	ids.sort()
	for id in ids:
		var n: NoteScript = notes[id]
		if seen.has(n):
			continue
		var group: Array[NoteScript] = [n]
		group.append_array(_stack_of(n).keys())
		for m in group:
			seen[m] = true
		groups.append(group)
	return groups


## Esc menu / O: puts every stack on one circle round the viewer at eye level,
## at equal angles (360° / number of stacks), the first straight ahead, in the
## order they're already in around the viewer. Each stack's middle sits on the
## circle, at eye height; a long stack is turned
## (around the vertical, keeping its shape) so its full width faces the viewer.
## The circle is big enough for every stack to be seen whole and for
## neighbours to stay ARRANGE_GAP apart. Doing it again without moving changes
## nothing. The camera stays put; one undo step puts everything back.
func _arrange_around_me() -> void:
	if paused:
		_set_paused(false)
	_end_drag()
	_commit_move()
	_finish_easing()
	if notes.is_empty():
		_toast("Nothing to arrange")
		return
	var plan := _arrange_targets()
	var targets: Dictionary = plan["targets"]
	var count: int = plan["count"]
	var entries: Array = []
	for m in targets:
		# Tiny differences (left over from arranging before) don't count as a move.
		if (targets[m][0] as Vector3).distance_to(m.global_position) > 0.01 \
				or (targets[m][1] as Quaternion).angle_to(m.quaternion) > 0.01:
			entries.append(_move_record(m))
			_ease_note(m, targets[m][0], targets[m][1], AI_MOVE_TIME, Tween.TRANS_BACK)
	if entries.is_empty():
		_toast("Already arranged")
		return
	_push_undo({"type": "group", "entries": entries, "label": "arrange around me"})
	_select(null)
	_toast(_shortcut_text("Arranged %d %s around you · Ctrl+Z undoes it"
		% [count, "stack" if count == 1 else "stacks"]))


## Where Arrange notes around me puts every block: {targets: {block: [place,
## rotation]}, count: number of stacks}. See _arrange_around_me().
func _arrange_targets() -> Dictionary:
	var eye := camera.global_position
	var flat := Basis(Vector3.UP, rig.yaw)
	var fwd := -flat.z
	var right := flat.x
	var vfov := deg_to_rad(camera.fov) * ARRANGE_FILL
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var hfov := 2.0 * atan(tan(deg_to_rad(camera.fov) * 0.5) * aspect) * ARRANGE_FILL
	var stacks: Array = []
	for group in _components():
		var mean := Vector3.ZERO
		for m in group:
			mean += m.global_position
		mean /= group.size()
		# The main direction the stack spreads in on the floor.
		var sxx := 0.0
		var szz := 0.0
		var sxz := 0.0
		var ylo := INF
		var yhi := -INF
		for m in group:
			var d: Vector3 = m.global_position - mean
			sxx += d.x * d.x
			szz += d.z * d.z
			sxz += d.x * d.z
			ylo = minf(ylo, m.global_position.y)
			yhi = maxf(yhi, m.global_position.y)
		var theta := 0.5 * atan2(2.0 * sxz, sxx - szz)
		var axis := Vector3(cos(theta), 0, sin(theta))
		var across := Vector3(-axis.z, 0, axis.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for m in group:
			var d: Vector3 = m.global_position - mean
			lo = lo.min(Vector2(d.dot(axis), d.dot(across)))
			hi = hi.max(Vector2(d.dot(axis), d.dot(across)))
		var long := hi.x - lo.x > (hi.y - lo.y + NoteScript.SIZE) * ARRANGE_LONG
		# The stack's middle (of its extent) is what goes on the circle.
		var center := mean + axis * (lo.x + hi.x) * 0.5 + across * (lo.y + hi.y) * 0.5
		center.y = (ylo + yhi) * 0.5
		var reach := NoteScript.SIZE  # farthest any block is from the middle, sideways
		for m in group:
			var o: Vector3 = m.global_position - center
			reach = maxf(reach, Vector2(o.x, o.z).length() + NoteScript.SIZE)
		var lowest_id: int = group[0].id
		for m in group:
			lowest_id = mini(lowest_id, m.id)
		var to := center - eye
		stacks.append({"group": group, "center": center, "axis": axis, "long": long, "reach": reach,
			"tall": (yhi - ylo) * 0.5 + NoteScript.SIZE, "id": lowest_id,
			"bearing": atan2(to.dot(right), to.dot(fwd))})
	var count := stacks.size()
	var step := TAU / count
	# Order: by angle round the viewer, starting from straight ahead (the
	# stack within half a step of straight ahead comes first), ties by id.
	for st in stacks:
		st["key"] = fposmod(st["bearing"] + step * 0.5, TAU)
	stacks.sort_custom(func(a, b):
		if not is_equal_approx(a["key"], b["key"]):
			return a["key"] < b["key"]
		return a["id"] < b["id"])
	# One radius: every stack fits in view, keeps its own blocks off the viewer,
	# and clears its neighbours by ARRANGE_GAP (chord between middles >= both reaches + gap).
	var radius := ARRANGE_MIN_DIST
	for k in count:
		var st: Dictionary = stacks[k]
		radius = maxf(radius, st["reach"] / tan(hfov * 0.5))
		radius = maxf(radius, st["tall"] / tan(vfov * 0.5))
		radius = maxf(radius, st["reach"] + ARRANGE_MIN_DIST * 0.5)
		if count > 1:
			var next: Dictionary = stacks[(k + 1) % count]
			radius = maxf(radius, (st["reach"] + next["reach"] + ARRANGE_GAP) / (2.0 * sin(step * 0.5)))
	var targets := {}  # block -> [place, rotation]
	for k in count:
		var st: Dictionary = stacks[k]
		var b := k * step
		var dir := fwd * cos(b) + right * sin(b)
		var tangent := right * cos(b) - fwd * sin(b)
		var place: Vector3 = eye + dir * radius
		var turn := 0.0
		if st["long"]:
			var axis: Vector3 = st["axis"]
			turn = atan2(axis.cross(tangent).y, axis.dot(tangent))
			if absf(turn) > PI * 0.5:
				turn -= signf(turn) * PI  # the shorter way: either end can face left
		var q := Quaternion(Vector3.UP, turn)
		for m in st["group"]:
			targets[m] = [place + q * (m.global_position - st["center"]), (q * m.quaternion).normalized()]
	return {"targets": targets, "count": count}


## Removes every block and link, and returns the undo entries that bring them back.
func _clear_space() -> Array:
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
	return entries


## Pause menu Exit: saves and quits.
func _exit() -> void:
	_save()
	get_tree().quit()


## Clears every block and link and starts over with the first-run blocks and
## the starting view. The old notespace is one undo step ("new notespace").
## Ids keep counting up, so undo can bring the old blocks back without clashes.
func _new_notespace() -> void:
	var entries := _clear_space()
	_create_welcome_notes()
	for n in notes.values():
		entries.append({"type": "create", "id": n.id})
	undo_stack.clear()
	_push_undo({"type": "group", "entries": entries, "label": "new notespace"})
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


## The cube's text, color, mark and anchor flag, as an undo "edit" entry.
func _edit_record(n: NoteScript) -> Dictionary:
	return {"type": "edit", "id": n.id, "text": n.text, "color": n.color, "status": n.status,
		"anchor": n.anchor}


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
	elif n.anchor != edit_start.get("anchor", false):
		edit_start["label"] = "anchor change"
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
	anchor_btn.set_pressed_no_signal(editing != null and editing.anchor)


func _on_anchor_toggled() -> void:
	if editing and is_instance_valid(editing):
		editing.anchor = not editing.anchor
		editing.refresh()
		_mark_dirty()
		_sync_status_buttons()


func _on_editor_delete() -> void:
	var n := editing
	editing = null
	editor_text.release_focus()
	editor_panel.visible = false
	_capture_mouse()
	if n and is_instance_valid(n):
		_delete_note(n, true)


# --- Task breakdown ---------------------------------------------------------

## The note editor or the breakdown panel is up: the 3D view ignores input.
func _panel_open() -> bool:
	return editor_panel.visible or ai_panel.visible


## The env var wins; otherwise the key typed in here earlier, if any.
func _ai_key() -> String:
	var k := OS.get_environment("ANTHROPIC_API_KEY").strip_edges()
	if k == "":
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			k = str(cfg.get_value("anthropic", "api_key", "")).strip_edges()
	return k


## Saves (or with "", forgets) the typed-in API key, keeping other settings.
func _store_ai_key(k: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # fine if it doesn't exist yet
	if k == "":
		if cfg.has_section_key("anthropic", "api_key"):
			cfg.erase_section_key("anthropic", "api_key")
	else:
		cfg.set_value("anthropic", "api_key", k)
	if cfg.save(SETTINGS_PATH) != OK:
		push_warning("Could not save %s" % SETTINGS_PATH)


## Opens the AI panel for "breakdown" (Break down a task) or "edit" (Add with AI).
func _open_ai_panel(mode: String) -> void:
	if paused:
		_set_paused(false)
	_end_drag()
	orbiting = false
	panning = false
	if mode != ai_mode and not ai_busy:
		ai_drafts[ai_mode] = ai_prompt.text
		ai_mode = mode
		ai_prompt.text = ai_drafts.get(mode, "")
	var breakdown := ai_mode == "breakdown"
	ai_title.text = _shortcut_text(("Break down a task" if breakdown else "Add with AI")
		+ "   (Ctrl+Enter to generate, Esc to close)")
	ai_about.text = ("Describe a big task. Claude splits it into groups of tasks and subtasks and lays them out as linked blocks in a new notespace."
		if breakdown else
		"Say what to add or change. Claude sees all your blocks and adds, rewrites, links, marks or removes blocks to match.")
	ai_prompt.placeholder_text = ("e.g. Launch a small online shop for my ceramics" if breakdown
		else "e.g. Add a group for marketing, and mark Set prices as done")
	ai_key_edit.visible = _ai_key() == ""
	if not ai_busy:
		ai_status.text = ""
		_set_ai_busy(false)  # sets the Generate button's text for this mode
	_show_ai_confirm(false)
	ai_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ai_prompt.grab_focus()


## Closing also drops a request that's still running.
func _close_ai_panel() -> void:
	if ai_busy:
		ai_http.cancel_request()
		_set_ai_busy(false)
	ai_prompt.release_focus()
	ai_key_edit.release_focus()
	ai_panel.visible = false
	_capture_mouse()


func _set_ai_busy(on: bool) -> void:
	ai_busy = on
	ai_generate_btn.disabled = on
	if on:
		ai_generate_btn.text = "Thinking…"
	else:
		ai_generate_btn.text = "Generate blocks" if ai_mode == "breakdown" else "Apply"


## Swaps the Cancel / Generate row for the "erase everything?" step.
func _show_ai_confirm(on: bool) -> void:
	ai_buttons.visible = not on
	ai_confirm.visible = on


## Generate / Ctrl+Enter. Breaking down over existing blocks asks first;
## `confirmed` is the answer. Nothing is erased until the answer arrives.
func _ai_generate(confirmed: bool = false) -> void:
	if ai_busy:
		return
	var request := ai_prompt.text.strip_edges()
	if request == "":
		ai_status.text = "Describe the task first." if ai_mode == "breakdown" else "Say what to add or change first."
		return
	if ai_key_edit.visible and ai_key_edit.text.strip_edges() != "":
		_store_ai_key(ai_key_edit.text.strip_edges())
		ai_key_edit.text = ""
	var key := _ai_key()
	if key == "":
		ai_status.text = "Paste an Anthropic API key first (or set ANTHROPIC_API_KEY)."
		return
	if ai_mode == "breakdown" and not notes.is_empty() and not confirmed:
		_show_ai_confirm(true)
		return
	_show_ai_confirm(false)
	var system := AI_SYSTEM
	var content := request
	var schema := _breakdown_schema()
	if ai_mode == "edit":
		system = AI_EDIT_SYSTEM
		content = "Current blocks:\n%s\n\nRequest: %s" % [JSON.stringify(_space_for_ai()), request]
		schema = _edit_schema()
	var body := {
		"model": AI_MODEL,
		"max_tokens": 16000,
		"system": system,
		"thinking": {"type": "adaptive"},
		"messages": [{"role": "user", "content": content}],
		"output_config": {
			"effort": "medium",
			"format": {"type": "json_schema", "schema": schema},
		},
		# If a safety check declines the request, the API retries it on its recommended fallback model.
		"fallbacks": "default",
	}
	var headers := [
		"content-type: application/json",
		"x-api-key: " + key,
		"anthropic-version: 2023-06-01",
		"anthropic-beta: server-side-fallback-2026-07-01",
	]
	if OS.has_feature("web"):
		# The API only answers a browser that says it means to call it directly (CORS).
		headers.append("anthropic-dangerous-direct-browser-access: true")
	var err := ai_http.request(AI_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		ai_status.text = "Couldn't start the request: %s" % error_string(err)
		return
	ai_status.text = "Asking Claude… this can take a little while."
	_set_ai_busy(true)
	_toast("Thinking…")


## A JSON schema object whose listed properties are all required, and nothing else allowed.
func _strict_object(props: Dictionary) -> Dictionary:
	return {"type": "object", "properties": props, "required": props.keys(),
		"additionalProperties": false}


func _breakdown_schema() -> Dictionary:
	var task := _strict_object({
		"text": {"type": "string"},
		"subtasks": {"type": "array", "items": {"type": "string"}},
	})
	var group := _strict_object({
		"title": {"type": "string"},
		"tasks": {"type": "array", "items": task},
	})
	return _strict_object({"groups": {"type": "array", "items": group}})


func _edit_schema() -> Dictionary:
	var pair := _strict_object({"from": {"type": "string"}, "to": {"type": "string"}})
	var placement := _strict_object({
		"id": {"type": "string"},
		"near": {"type": "string"},
		"side": {"type": "string", "enum": AI_SIDES},
	})
	return _strict_object({
		"summary": {"type": "string"},
		"add": {"type": "array", "items": _strict_object({
			"temp_id": {"type": "string"},
			"text": {"type": "string"},
			"parent": {"type": "string"},
			"color": {"type": "integer"},
		})},
		"edit": {"type": "array", "items": _strict_object({
			"id": {"type": "string"}, "text": {"type": "string"}})},
		"mark": {"type": "array", "items": _strict_object({
			"id": {"type": "string"},
			"state": {"type": "string", "enum": ["done", "failed", "none"]},
		})},
		"recolor": {"type": "array", "items": _strict_object({
			"id": {"type": "string"}, "color": {"type": "integer"}})},
		"link": {"type": "array", "items": pair},
		"unlink": {"type": "array", "items": pair},
		"remove": {"type": "array", "items": {"type": "string"}},
		"move": {"type": "array", "items": placement},
		"move_stack": {"type": "array", "items": placement},
		"arrange": {"type": "array", "items": {"type": "string"}},
	})


## The current blocks and links, as Claude sees them for Add with AI.
## Positions are from the user's point of view (level, facing where they look).
func _space_for_ai() -> Dictionary:
	var view := Basis(Vector3.UP, rig.yaw)
	var eye := camera.global_position
	var blocks: Array = []
	var ids: Array = notes.keys()
	ids.sort()
	for id in ids:
		var n: NoteScript = notes[id]
		var p := view.inverse() * (n.global_position - eye)
		blocks.append({"id": str(id), "text": n.text, "status": n.status if n.status != "" else "none",
			"color": palette.find(n.color), "anchor": n.anchor,
			"pos": [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]})
	var pairs: Array = []
	for l in links:
		pairs.append([str(l[0]), str(l[1])])
	return {"blocks": blocks, "links": pairs}


func _on_ai_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_set_ai_busy(false)
	if result != HTTPRequest.RESULT_SUCCESS:
		ai_status.text = "Couldn't reach the Anthropic API (%s)." % (
			"timed out" if result == HTTPRequest.RESULT_TIMEOUT else "network error %d" % result)
		_toast(ai_status.text)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		ai_status.text = "The API sent back something unreadable (HTTP %d)." % code
		return
	if code != 200:
		var msg := str(data.get("error", {}).get("message", "")) if data.get("error") is Dictionary else ""
		ai_status.text = "API error %d: %s" % [code, msg]
		_toast("API error %d" % code)
		if code == 401:
			# A bad saved key: forget it so the field comes back.
			_store_ai_key("")
			ai_key_edit.visible = _ai_key() == ""
		return
	var problem := _apply_ai_message(data)
	if problem != "":
		ai_status.text = problem
		_toast(problem)
		return
	ai_prompt.text = ""
	_close_ai_panel()


## Turns a successful Messages API response into blocks, for the current mode.
## Returns what went wrong, or "" once the changes are in.
func _apply_ai_message(data: Dictionary) -> String:
	var stop := str(data.get("stop_reason", ""))
	if stop == "refusal":
		return "Claude declined this one. Try describing it differently."
	if stop == "max_tokens":
		return "Claude's answer got too long. Try asking for less at once."
	var text := ""
	for block in data.get("content", []):
		if block is Dictionary and block.get("type") == "text":
			text = str(block.get("text", ""))  # thinking blocks are skipped; the last text block is the answer
	var json := JSON.new()  # unlike JSON.parse_string(), doesn't log an error for bad text
	var parsed = json.data if json.parse(text) == OK else null
	if not (parsed is Dictionary):
		return "Claude's answer couldn't be read. Try again."
	if ai_mode == "edit":
		return _apply_ai_edit(parsed)
	if not (parsed.get("groups") is Array) or parsed["groups"].is_empty():
		return "Claude's answer couldn't be read as blocks. Try again."
	# A new notespace: the old blocks go, as part of the same undo step.
	var view := rig.to_dict()
	var entries := _clear_space()
	rig.reset()
	var made := _build_breakdown(parsed["groups"])
	if made.is_empty():
		for e in entries:
			_restore_deleted(e)  # nothing usable came back: keep what was there
		_select(null)
		rig.from_dict(view)
		return "Claude's answer had no blocks in it. Try again."
	entries.append_array(made)
	_push_undo({"type": "group", "entries": entries, "label": "AI breakdown"})
	_save()
	_toast(_shortcut_text("Added %d blocks · Ctrl+Z brings the old ones back" % made.size()))
	return ""


## Lays the breakdown out in front of the camera, facing it, pushed back until
## it's clear of existing cubes, and turns the view level onto it. Each group
## is grown as a fan (see FAN_DISTS) around its title block, then the groups
## are set side by side. Returns the undo entries for the blocks it made.
func _build_breakdown(groups: Array, frame: bool = true) -> Array:
	# Each item: [local position, text, color, parent index]; local x is to the
	# right of the view, y up, z toward the camera.
	var items: Array = []
	var x := 0.0
	var gi := 0
	for g in groups.slice(0, 8):
		if not (g is Dictionary):
			continue
		var title := str(g.get("title", "")).strip_edges()
		var color := palette[gi % (palette.size() - 1)]  # every color but white
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(title) + gi
		var cluster: Array = [[Vector3.ZERO, title, color, -1]]
		var placed: Array[Vector3] = [Vector3.ZERO]
		var tasks: Array = []
		for t in (g.get("tasks", []) as Array).slice(0, 8):
			if t is Dictionary and str(t.get("text", "")).strip_edges() != "":
				var p := _fan_spot(Vector3.ZERO, Vector3.DOWN, placed, rng)
				placed.append(p)
				cluster.append([p, str(t["text"]).strip_edges(), color, 0])
				tasks.append([cluster.size() - 1, t])
		# Subtasks after all the tasks, so the tasks get the first pick of directions.
		for task in tasks:
			var tp: Vector3 = cluster[task[0]][0]
			var out := (tp.normalized() + Vector3.DOWN * 0.6).normalized()
			for sub in ((task[1] as Dictionary).get("subtasks", []) as Array).slice(0, 6):
				if str(sub).strip_edges() != "":
					var p := _fan_spot(tp, out, placed, rng)
					placed.append(p)
					cluster.append([p, str(sub).strip_edges(), color, task[0]])
		# Set this group to the right of the previous one.
		var lo := INF
		var hi := -INF
		for p in placed:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
		var base := items.size()
		for c in cluster:
			items.append([c[0] + Vector3(x - lo, 0, 0), c[1], c[2], c[3] + base if c[3] >= 0 else -1])
		x += hi - lo + NoteScript.SIZE + BD_GROUP_GAP
		gi += 1
	if items.is_empty():
		return []
	# Center the whole layout on the view.
	var box := AABB(items[0][0], Vector3.ZERO)
	for it in items:
		box = box.expand(it[0])
	for it in items:
		it[0] -= box.get_center()

	var flat := Basis(Vector3.UP, rig.yaw)
	var cam_pos := camera.global_position
	var dist := maxf(BD_MIN_DIST, maxf(box.size.x * 0.65, box.size.y * 1.2) + box.size.z * 0.5)
	var center := cam_pos
	for attempt in 40:
		center = cam_pos - flat.z * dist
		var clear := true
		for it in items:
			var p: Vector3 = center + flat * (it[0] as Vector3)
			for v in notes.values():
				if (v as NoteScript).global_position.distance_to(p) < SPACING:
					clear = false
					break
			if not clear:
				break
		if clear:
			break
		dist += 4.0

	var made: Array[NoteScript] = []
	var entries: Array = []
	var spots: Array[Vector3] = []
	for it in items:
		if str(it[1]) == "":
			made.append(null)
			continue
		var parent: int = it[3]
		var target: Vector3 = center + flat * (it[0] as Vector3)
		# Blocks grow out of their parent (which is still at its own start).
		var start := made[parent].global_position if parent >= 0 and made[parent] else target
		var n := _create_note(start, it[1], it[2])
		n.rotation = Vector3(0.0, rig.yaw, 0.0)
		n.anchor = parent < 0  # group titles carry their stack
		n.refresh()
		_ease_note(n, target, n.quaternion, BD_EASE_TIME)
		made.append(n)
		spots.append(target)
		entries.append({"type": "create", "id": n.id})
		if parent >= 0 and made[parent]:
			_toggle_link(made[parent], n)
	if frame:
		_frame_spots(spots)
	return entries


## Where a block hanging from a parent at `pp` goes: on a cone around `out`
## (the direction away from the parent's own parent, or down), FAN_DISTS
## away, in the spot with the most room to the `others`, nearer and straighter
## spots winning ties. Never closer than FAN_CLEAR to anything.
func _fan_spot(pp: Vector3, out: Vector3, others: Array[Vector3], rng: RandomNumberGenerator) -> Vector3:
	var a := out.cross(Vector3.FORWARD if absf(out.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var b := out.cross(a)
	var phase := rng.randf() * TAU
	var best := Vector3.ZERO
	var best_score := -INF
	for dist in FAN_DISTS:
		for tilt in FAN_TILTS:
			for k in FAN_STEPS:
				var az := phase + k * TAU / FAN_STEPS
				var p := pp + (out * cos(tilt) + (a * cos(az) + b * sin(az)) * sin(tilt)) * dist
				var room := INF
				for o in others:
					room = minf(room, o.distance_to(p))
				if room < FAN_CLEAR:
					continue
				var score := minf(room, FAN_ROOM) - dist * 0.3 - tilt * 0.5
				if score > best_score:
					best_score = score
					best = p
	if best_score == -INF:
		best = pp + out * FAN_DISTS[-1] * 1.5  # crowded: just go farther out
	var jittered := best + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * FAN_JITTER
	for o in others:
		if o.distance_to(jittered) < FAN_CLEAR:
			return best
	return jittered


## Add with AI: applies Claude's changes as one undo step. Ids that don't
## match a block are skipped. Returns what went wrong, or "".
func _apply_ai_edit(r: Dictionary) -> String:
	_end_drag()
	_commit_move()
	_finish_easing()
	var by_id := {}  # Claude's ids (existing block ids and new temp_ids) -> block
	for id in notes:
		by_id[str(id)] = notes[id]
	var entries: Array = [{"type": "links", "links": links.duplicate(true)}]
	var changed: Array[NoteScript] = []  # existing blocks that were edited, to pulse
	var counts := {"moved": 0, "arranged": 0, "added": 0, "edited": 0, "marked": 0, "recolored": 0,
		"linked": 0, "unlinked": 0, "removed": 0}
	var moved_from := {}  # block -> where it was before this edit

	for item in _ai_list(r, "edit"):
		var n: NoteScript = by_id.get(str(item.get("id", "")))
		var t := str(item.get("text", "")).strip_edges()
		if n and t != "" and t != n.text:
			entries.append(_edit_record(n))
			n.text = t
			n.refresh()
			_add_unique(changed, n)
			counts["edited"] += 1
	for item in _ai_list(r, "mark"):
		var n: NoteScript = by_id.get(str(item.get("id", "")))
		var state := str(item.get("state", ""))
		var st := "" if state == "none" else state
		if n and st in ["", "done", "failed"] and st != n.status:
			entries.append(_edit_record(n))
			n.status = st
			n.refresh()
			_add_unique(changed, n)
			counts["marked"] += 1
	for item in _ai_list(r, "recolor"):
		var n: NoteScript = by_id.get(str(item.get("id", "")))
		var ci := int(item.get("color", -1))
		if n and ci >= 0 and ci < palette.size() and palette[ci] != n.color:
			entries.append(_edit_record(n))
			n.color = palette[ci]
			n.refresh()
			_add_unique(changed, n)
			counts["recolored"] += 1

	# Moves: blocks jump to their new places now (so new blocks are placed
	# around them), and fly there from their old places at the end.
	for item in _ai_list(r, "move"):
		var n: NoteScript = by_id.get(str(item.get("id", "")))
		var near: NoteScript = by_id.get(str(item.get("near", "")))
		if n and near and n != near:
			_ai_move_stack([n], n, near, str(item.get("side", "")), FAN_CLEAR, FAN_DISTS[0], moved_from, entries)
	for item in _ai_list(r, "move_stack"):
		var n: NoteScript = by_id.get(str(item.get("id", "")))
		if n == null:
			continue
		var members: Array[NoteScript] = [n]
		members.append_array(_stack_of(n).keys())
		var near: NoteScript = by_id.get(str(item.get("near", "")))
		if near and members.has(near):
			continue  # can't move a stack next to itself
		_ai_move_stack(members, n, near, str(item.get("side", "")), AI_STACK_GAP, 6.0, moved_from, entries)
	for id in _ai_list(r, "arrange"):
		var n: NoteScript = by_id.get(str(id))
		if n and _ai_arrange(n, moved_from, entries):
			counts["arranged"] += 1

	# New blocks: placed (in order, parents first) next to their parent, or as a
	# new group in free space in front of the camera.
	var new_notes: Array[NoteScript] = []
	var grow_from := {}  # new block -> where it eases in from
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for item in _ai_list(r, "add"):
		var t := str(item.get("text", "")).strip_edges()
		var temp := str(item.get("temp_id", "")).strip_edges()
		if t == "" or (temp != "" and by_id.has(temp)):
			continue
		var parent: NoteScript = by_id.get(str(item.get("parent", "")))
		var ci := int(item.get("color", -1))
		var color := palette[ci] if ci >= 0 and ci < palette.size() else (parent.color if parent else last_color)
		var pos := _ai_child_spot(parent, rng) if parent else _ai_cluster_spot()
		var n := _create_note(pos, t, color)
		n.quaternion = parent.quaternion if parent else Quaternion(Vector3.UP, rig.yaw)
		n.anchor = parent == null  # a new group's title carries its stack
		n.refresh()
		if parent:
			_toggle_link(parent, n)
			grow_from[n] = parent.global_position
		if temp != "":
			by_id[temp] = n
		new_notes.append(n)
		entries.append({"type": "create", "id": n.id})
		counts["added"] += 1

	for item in _ai_list(r, "link"):
		var a: NoteScript = by_id.get(str(item.get("from", "")))
		var b: NoteScript = by_id.get(str(item.get("to", "")))
		if a and b and a != b and not _linked(a, b):
			_toggle_link(a, b)
			counts["linked"] += 1
	for item in _ai_list(r, "unlink"):
		var a: NoteScript = by_id.get(str(item.get("from", "")))
		var b: NoteScript = by_id.get(str(item.get("to", "")))
		if a and b and _linked(a, b):
			_toggle_link(a, b)
			counts["unlinked"] += 1
	var removed_spots: Array[Vector3] = []
	for id in _ai_list(r, "remove"):
		var n: NoteScript = by_id.get(str(id))
		if is_instance_valid(n) and notes.has(n.id):
			entries.append(_delete_record(n))
			removed_spots.append(n.global_position)
			changed.erase(n)
			new_notes.erase(n)
			_delete_note(n)
			counts["removed"] += 1

	for n in moved_from:
		if notes.has(n.id) and not n.global_position.is_equal_approx(moved_from[n]):
			counts["moved"] += 1
	var total := 0
	for k in counts:
		total += counts[k]
	if total == 0:
		var note := str(r.get("summary", "")).strip_edges()
		return "Claude didn't change anything." + (" " + note if note != "" else "")
	_push_undo({"type": "group", "entries": entries, "label": "AI edit"})

	# Show what happened: new blocks grow out of their parent, edited ones pulse,
	# and the view turns onto all of it.
	var spots: Array[Vector3] = removed_spots.duplicate()
	for n in moved_from:
		if notes.has(n.id) and not n.global_position.is_equal_approx(moved_from[n]):
			var target: Vector3 = n.global_position
			spots.append(target)
			n.global_position = moved_from[n]
			_ease_note(n, target, n.quaternion, AI_MOVE_TIME, Tween.TRANS_BACK)
	for n in new_notes:
		var target := n.global_position
		spots.append(target)
		if grow_from.has(n):
			n.global_position = grow_from[n]
		_ease_note(n, target, n.quaternion, BD_EASE_TIME)
	for n in changed:
		spots.append(n.global_position)
		_pulse(n)
	_frame_spots(spots)
	_mark_dirty()

	var summary := str(r.get("summary", "")).strip_edges()
	if summary != "":
		_toast(summary)
	var parts: Array[String] = []
	for k in counts:
		if counts[k] > 0:
			var noun := "" if k != "moved" else (" block" if counts[k] == 1 else " blocks")
			if k == "arranged":
				noun = " stack" if counts[k] == 1 else " stacks"
			parts.append("%s %d%s" % [k, counts[k], noun])
	var only_moves: bool = counts["moved"] == total - counts["arranged"]
	var line := "Moved blocks around (%d)" % counts["moved"] if only_moves and counts["moved"] > 0 \
			else ", ".join(parts).left(1).to_upper() + ", ".join(parts).substr(1)
	_toast(_shortcut_text(line + " · Ctrl+Z undoes it"))
	return ""


## Moves `members` rigidly (keeping their offsets from `lead`) so that `lead`
## sits on `side` of `near`, as the user sees it, starting `start_dist` away and
## going farther until every member is at least `gap` from every other block.
## With no `near`, the stack goes to free space in front of the user.
## Old places go into `moved_from` and `entries` (for the undo step).
func _ai_move_stack(members: Array[NoteScript], lead: NoteScript, near: NoteScript, side: String,
		gap: float, start_dist: float, moved_from: Dictionary, entries: Array) -> void:
	var offsets: Array[Vector3] = []
	var inside := {}
	for m in members:
		offsets.append(m.global_position - lead.global_position)
		inside[m] = true
	var flat := Basis(Vector3.UP, rig.yaw)
	var tries: Array[Vector3] = []
	if near:
		var dir := _side_dir(side if side in AI_SIDES else "right")
		for i in 40:
			tries.append(near.global_position + dir * (start_dist + i * 1.5))
	else:
		var base := camera.global_position - flat.z * BD_MIN_DIST
		for back in 10:
			for s in [0, 1, -1, 2, -2, 3, -3]:
				tries.append(base + flat.x * (s * AI_CLUSTER_GAP) - flat.z * (back * AI_CLUSTER_GAP))
	for p in tries:
		var clear := true
		for v in notes.values():
			if inside.has(v):
				continue
			for off in offsets:
				if (v as NoteScript).global_position.distance_to(p + off) < gap:
					clear = false
					break
			if not clear:
				break
		if clear:
			for k in members.size():
				_ai_place(members[k], p + offsets[k], moved_from, entries)
			return


## Lays a stack out again as a 3D mind map (like a breakdown) around its anchor,
## which stays put: the block itself if it's an anchor, else the nearest anchor
## linked to it, else the block. Returns whether anything moved.
func _ai_arrange(n: NoteScript, moved_from: Dictionary, entries: Array) -> bool:
	var stack := _stack_of(n)
	if stack.is_empty():
		return false
	var root := n
	if not n.anchor:
		var best := INF
		for m in stack:
			if m.anchor and stack[m] < best:
				best = stack[m]
				root = m
	var inside := {n: true}
	for m in stack:
		inside[m] = true
	# A tree from the root, breadth first: each block hangs from the block it was reached through.
	var neighbors := {}
	for l in links:
		neighbors.get_or_add(l[0], []).append(l[1])
		neighbors.get_or_add(l[1], []).append(l[0])
	var parent := {root: null}
	var order: Array[NoteScript] = []
	var queue: Array[NoteScript] = [root]
	while not queue.is_empty():
		var b: NoteScript = queue.pop_front()
		for other_id in neighbors.get(b.id, []):
			var o: NoteScript = notes.get(other_id)
			if o and inside.has(o) and not parent.has(o):
				parent[o] = b
				order.append(o)
				queue.append(o)
	var obstacles: Array[Vector3] = [root.global_position]
	for v in notes.values():
		if not inside.has(v):
			obstacles.append((v as NoteScript).global_position)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(root.text)
	var placed := {root: root.global_position}
	for b in order:
		var pb: NoteScript = parent[b]
		var out := Vector3.DOWN
		if parent[pb] != null:
			out = ((placed[pb] - placed[parent[pb]]).normalized() + Vector3.DOWN * 0.6).normalized()
		var p := _fan_spot(placed[pb], out, obstacles, rng)
		obstacles.append(p)
		placed[b] = p
	var any := false
	for b in order:
		if not (placed[b] as Vector3).is_equal_approx(b.global_position):
			_ai_place(b, placed[b], moved_from, entries)
			any = true
	return any


## Puts block `n` at `p` now, remembering where it was (once per edit).
func _ai_place(n: NoteScript, p: Vector3, moved_from: Dictionary, entries: Array) -> void:
	if not moved_from.has(n):
		moved_from[n] = n.global_position
		entries.append(_move_record(n))
	n.global_position = p


## A direction for a side as the user sees it (level, facing where they look).
func _side_dir(side: String) -> Vector3:
	var flat := Basis(Vector3.UP, rig.yaw)
	match side:
		"left": return -flat.x
		"right": return flat.x
		"above": return Vector3.UP
		"below": return Vector3.DOWN
		"front": return flat.z
		"behind": return -flat.z
	return flat.x


## r[key] if it's a list, else an empty one (so a malformed answer is just skipped).
func _ai_list(r: Dictionary, key: String) -> Array:
	return r[key] if r.get(key) is Array else []


func _add_unique(list: Array[NoteScript], n: NoteScript) -> void:
	if not list.has(n):
		list.append(n)


func _linked(a: NoteScript, b: NoteScript) -> bool:
	return links.has([mini(a.id, b.id), maxi(a.id, b.id)])


func _spot_free(p: Vector3) -> bool:
	for v in notes.values():
		if (v as NoteScript).global_position.distance_to(p) < SPACING - 0.01:
			return false
	return true


## Where a new block under `parent` goes: fanned out around it like the
## breakdown layout, away from the block it hangs from (its highest linked
## neighbor above it), or downward if there's none, and clear of every block.
func _ai_child_spot(parent: NoteScript, rng: RandomNumberGenerator) -> Vector3:
	var pp := parent.global_position
	var up_neighbor: NoteScript = null
	for l in links:
		if l[0] == parent.id or l[1] == parent.id:
			var other: NoteScript = notes.get(l[1] if l[0] == parent.id else l[0])
			if other and other.global_position.y > pp.y + 0.5 \
					and (up_neighbor == null or other.global_position.y > up_neighbor.global_position.y):
				up_neighbor = other
	var out := Vector3.DOWN
	if up_neighbor:
		out = ((pp - up_neighbor.global_position).normalized() + Vector3.DOWN * 0.6).normalized()
	var others: Array[Vector3] = []
	for v in notes.values():
		others.append((v as NoteScript).global_position)
	var p := _fan_spot(pp, out, others, rng)
	return p if _spot_free(p) else _free_spot(null, p)


## Where a new top-level group goes: in front of the camera, at least
## AI_CLUSTER_GAP from every block, trying spots side to side and then farther back.
func _ai_cluster_spot() -> Vector3:
	var flat := Basis(Vector3.UP, rig.yaw)
	var base := camera.global_position - flat.z * BD_MIN_DIST
	for back in 10:
		for side in [0, 1, -1, 2, -2, 3, -3]:
			var p: Vector3 = base + flat.x * (side * AI_CLUSTER_GAP) - flat.z * (back * AI_CLUSTER_GAP)
			var clear := true
			for v in notes.values():
				if (v as NoteScript).global_position.distance_to(p) < AI_CLUSTER_GAP:
					clear = false
					break
			if clear:
				return p
	return _free_spot(null, base)


## A quick swell and settle, to show a block was changed.
func _pulse(n: NoteScript) -> void:
	var tween := n.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(n, "scale", Vector3.ONE * AI_PULSE, 0.2)
	tween.tween_property(n, "scale", Vector3.ONE, 0.35)


## Turns the view level onto a set of points, far enough back to see them all.
func _frame_spots(spots: Array[Vector3]) -> void:
	if spots.is_empty():
		return
	var box := AABB(spots[0], Vector3.ZERO)
	for p in spots:
		box = box.expand(p)
	rig.frame(box.get_center(), maxf(BD_MIN_DIST, box.size.length() * 0.8 + NoteScript.SIZE))


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


## Copies the save from the old app name's folder, once, if there's none here
## yet. MIGRATED_PATH marks that this was tried, so a notespace removed later
## doesn't come back from the old folder.
func _migrate_old_save() -> void:
	if FileAccess.file_exists(MIGRATED_PATH):
		return
	var marker := FileAccess.open(MIGRATED_PATH, FileAccess.WRITE)
	if marker:
		marker.store_string("Notes from Spatial Notes were checked for (and copied if there was no save yet).\n")
		marker.close()
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
		n.anchor = bool(d.get("anchor", false))
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
			and not paused and not _panel_open():
		_set_paused(true)  # alt-tabbed away: free the cursor
